#!/usr/bin/env bash
# self-evolution 紀錄檢查 + Codex 鏡像同步
#
#   evolution.sh check        驗證紀錄一致性、回報 REVIEW_DUE，並同步 Codex 區塊
#   evolution.sh sync-codex   只同步 Codex 區塊
#
# exit 0：沒有 ERROR（可能仍有 REVIEW_DUE）；exit 1：有 ERROR；exit 2：用法錯誤
# 相容 macOS 內建 bash 3.2 與 BSD/GNU date（不用關聯陣列）。

set -uo pipefail

EVO="${EVOLUTION_HOME:-$HOME/.claude/evolution}"
CLAUDE_MD="${EVOLUTION_CLAUDE_MD:-$HOME/.claude/CLAUDE.md}"
CODEX_MD="${EVOLUTION_CODEX_MD:-$HOME/.codex/AGENTS.md}"
CAP="${EVOLUTION_CAP:-20}"
STALE_DAYS="${EVOLUTION_STALE_DAYS:-60}"
TODAY="${EVOLUTION_TODAY:-$(date +%Y-%m-%d)}"
CODEX_LIMIT=32768

START_MARK='<!-- self-evolution:start -->'
END_MARK='<!-- self-evolution:end -->'

errors=0
review_due=0

err() { echo "ERROR $*"; errors=$((errors + 1)); }
due() { echo "REVIEW_DUE $*"; review_due=1; }

to_epoch() {
  date -j -f %Y-%m-%d "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}

# CLAUDE.md 教訓區塊的內容（不含標題），到下一個 `## ` 標題為止
block_body() {
  [ -f "$CLAUDE_MD" ] || return 0
  awk '/^## Self-Evolution 教訓/ { inb = 1; next } inb && /^## / { inb = 0 } inb' "$CLAUDE_MD"
}

# INDEX 中某個 lessons 路徑的狀態（active/scoped/enforced/repeated/archived）
index_status() {
  awk -v p="$1" 'index($0, p) && match($0, /^- \[[a-z-]+\]/) {
    print substr($0, 4, RLENGTH - 4); exit
  }' "$EVO/INDEX.md"
}

field_value() { # $1=file $2=欄位名，印出「- 欄位：」之後的內容
  awk -v f="- $2：" 'index($0, f) == 1 { print substr($0, length(f) + 1); exit }' "$1"
}

check() {
  local entries count dups line path file st cited ep now age

  if [ ! -f "$EVO/INDEX.md" ]; then
    err "NO_INDEX $EVO/INDEX.md 不存在（首次執行請依 SKILL.md 建立）"
    return
  fi

  entries=$(block_body | grep -E '^- \[E[0-9]+\]' || true)
  if [ -z "$entries" ]; then
    count=0
  else
    count=$(printf '%s\n' "$entries" | wc -l | tr -d ' ')
  fi

  if [ "$count" -gt "$CAP" ]; then
    err "CAP_EXCEEDED 常駐條目 $count/$CAP"
    due "常駐條目超過上限 $CAP"
  fi

  dups=$(printf '%s\n' "$entries" | grep -oE '^- \[E[0-9]+\]' | grep -oE 'E[0-9]+' | sort | uniq -d | tr '\n' ' ')
  [ -n "${dups// /}" ] && err "DUP_ID 重複編號：$dups"

  now=$(to_epoch "$TODAY")

  # 常駐條目：連結存在、lessons 檔存在、最後引用沒過期
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id=$(printf '%s' "$line" | grep -oE '^- \[E[0-9]+\]' | tr -d '[]- ')
    path=$(printf '%s' "$line" | grep -oE 'evolution/lessons/[^ ）)]+\.md' | head -1)
    if [ -z "$path" ]; then
      err "NO_LINK [$id] 條目沒有 evolution/lessons/… 連結"
      continue
    fi
    file="$EVO/${path#evolution/}"
    if [ ! -f "$file" ]; then
      err "MISSING_LESSON [$id] $path 不存在"
      continue
    fi
    cited=$(field_value "$file" "最後引用" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    if [ -z "$cited" ]; then
      err "NO_LAST_CITED [$id] $path 缺「- 最後引用：YYYY-MM-DD」"
      continue
    fi
    ep=$(to_epoch "$cited")
    if [ -n "$ep" ] && [ -n "$now" ]; then
      age=$(((now - ep) / 86400))
      [ "$age" -gt "$STALE_DAYS" ] && due "STALE [$id] 已 $age 天未引用（${path}）"
    fi
  done <<EOF
$entries
EOF

  # INDEX 指到的 lessons 檔都存在
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    [ -f "$EVO/$path" ] || err "INDEX_DANGLING INDEX 指向不存在的 $path"
  done <<EOF
$(grep -oE 'lessons/[^ ]+\.md' "$EVO/INDEX.md" | sort -u)
EOF

  # 每個 lessons 檔都在 INDEX；非封存者要有「強制方式」
  for file in "$EVO"/lessons/*.md; do
    [ -f "$file" ] || continue
    path="lessons/$(basename "$file")"
    st=$(index_status "$path")
    if [ -z "$st" ]; then
      err "UNINDEXED $path 不在 INDEX.md"
      continue
    fi
    [ "$st" = "archived" ] && continue
    [ -z "$(field_value "$file" "強制方式")" ] && due "NO_ENFORCEMENT $path 缺「- 強制方式：」"
  done

  echo "SUMMARY 常駐條目 $count/${CAP}，ERROR ${errors}，REVIEW_DUE $([ "$review_due" -eq 1 ] && echo yes || echo no)"
}

sync_codex() {
  local dir rest body size
  dir=$(dirname "$CODEX_MD")
  if [ ! -d "$dir" ]; then
    echo "SKIP_CODEX $dir 不存在（未安裝 Codex）"
    return 0
  fi

  rest=""
  if [ -f "$CODEX_MD" ]; then
    rest=$(awk -v s="$START_MARK" -v e="$END_MARK" '
      $0 == s { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip' "$CODEX_MD")
  fi

  # 去掉區塊頭尾空行，lessons 連結改成絕對路徑
  body=$(block_body | awk 'NF { started = 1 } started' | sed 's#詳: evolution/#詳: ~/.claude/evolution/#g')

  {
    if [ -n "$rest" ]; then
      printf '%s\n\n' "$rest"
    fi
    echo "$START_MARK"
    echo '## Self-Evolution 教訓（由 self-evolution 檢查腳本從 ~/.claude/CLAUDE.md 產生，勿手改）'
    echo
    [ -n "$body" ] && printf '%s\n' "$body"
    echo '- 改檔前，讀 repo 的 `.claude/rules/**/*.md` 與 `~/.claude/rules/**/*.md` 中，frontmatter 沒有 `paths`、或 `paths` glob 符合要改之檔案的規則檔，並照做。'
    echo "$END_MARK"
  } >"$CODEX_MD.tmp.$$"

  # 用 cat 寫回，若 AGENTS.md 是 symlink 會寫到目標檔而不是把 symlink 換掉
  cat "$CODEX_MD.tmp.$$" >"$CODEX_MD"
  rm -f "$CODEX_MD.tmp.$$"

  size=$(wc -c <"$CODEX_MD" | tr -d ' ')
  echo "SYNCED_CODEX ${CODEX_MD}（$size bytes）"
  if [ "$size" -gt "$CODEX_LIMIT" ]; then
    echo "WARN_CODEX_SIZE 超過 Codex 預設 project_doc_max_bytes ${CODEX_LIMIT}，後段可能被截掉"
  fi
}

case "${1:-}" in
  check)
    check
    sync_codex
    [ "$errors" -eq 0 ] || exit 1
    ;;
  sync-codex)
    sync_codex
    ;;
  *)
    echo "用法：$0 check|sync-codex" >&2
    exit 2
    ;;
esac
