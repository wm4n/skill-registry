#!/usr/bin/env bash
#
# scan.sh — READ-ONLY macOS disk-cleanup scanner.
#
# Finds space-consuming caches, dev caches, large/old files, temp & trash.
# It NEVER deletes or modifies anything: only du / find / stat / ls / df /
# tmutil-list are used. There is no rm, mv, or output redirection to files.
#
# Output: TSV, one finding per line, 5 columns:
#   category_id <TAB> path <TAB> size_bytes <TAB> human_size <TAB> item_count
# A leading "# READ-ONLY ..." header line describes the run.
#
# Grand total is NOT printed; the caller sums size_bytes (dedup by path).
# Categories are designed so no emitted path is nested inside another,
# so a plain sum of size_bytes is correct.

set -o pipefail

# ---------------------------------------------------------------------------
# Defaults & argument parsing
# ---------------------------------------------------------------------------
HOME_DIR="$HOME"
MIN="500M"          # large/old file threshold (find -size syntax: 500M, 1G, ...)
OLD_DAYS=180        # a file not accessed in this many days counts as "old"
FORMAT="tsv"        # tsv | summary
REQ=""              # space-separated requested groups/ids; empty = all

usage() {
  cat <<'EOF'
Usage: scan.sh [options]

Options:
  --categories LIST   Comma-separated groups or ids to scan (default: all).
                      Groups: user, dev, files, system
                      Ids:    user-cache, user-logs, browser-cache,
                              dev-node-modules, dev-pkg-cache, dev-docker,
                              dev-xcode-derived, dev-xcode-archives,
                              dev-ios-devicesupport, dev-gradle-cargo,
                              large-file, old-file,
                              sys-tmp, trash, ios-backup, tm-localsnapshots
  --min-size SIZE     Large-file threshold (find -size form). Default: 500M
  --old-days N        A file unused for N days is "old". Default: 180
  --home PATH         Override HOME (for testing). Default: $HOME
  --format FMT        tsv (machine, default) or summary (human totals)
  -h, --help          Show this help

READ-ONLY: this script never deletes or modifies any file.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --categories) REQ=$(printf '%s' "$2" | tr ',' ' '); shift 2;;
    --min-size)   MIN="$2"; shift 2;;
    --old-days)   OLD_DAYS="$2"; shift 2;;
    --home)       HOME_DIR="$2"; shift 2;;
    --format)     FORMAT="$2"; shift 2;;
    -h|--help)    usage; exit 0;;
    *) printf 'scan.sh: unknown option: %s\n' "$1" >&2; usage >&2; exit 2;;
  esac
done

# Light validation (bad values just yield no rows, but fail loud on obvious typos)
case "$MIN" in
  *[!0-9kKmMgGtTpP]*) printf 'scan.sh: invalid --min-size: %s\n' "$MIN" >&2; exit 2;;
esac
case "$OLD_DAYS" in
  ''|*[!0-9]*) printf 'scan.sh: invalid --old-days: %s\n' "$OLD_DAYS" >&2; exit 2;;
esac

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
ROWS=()

# bytes -> human readable (1024 base)
human() {
  awk -v b="$1" 'BEGIN{
    split("B KB MB GB TB PB", u, " "); i=1;
    while (b>=1024 && i<6){ b/=1024; i++ }
    if (i==1) printf("%d %s", b, u[i]); else printf("%.1f %s", b, u[i]);
  }'
}

group_of() {
  case "$1" in
    user-*|browser-cache) echo user;;
    dev-*)                echo dev;;
    large-file|old-file)  echo files;;
    sys-tmp|trash|ios-backup|tm-localsnapshots) echo system;;
    *) echo "";;
  esac
}

# want <category_id> : true if requested (or if nothing requested = all)
want() {
  [ -z "$REQ" ] && return 0
  local grp; grp=$(group_of "$1")
  case " $REQ " in
    *" $1 "*)   return 0;;
    *" $grp "*) return 0;;
  esac
  return 1
}

# directory size in bytes (du -k reports 1024-byte blocks); 0/empty -> skip
dir_bytes() { du -sk -x "$1" 2>/dev/null | awk 'NR==1{print $1*1024; exit}'; }
child_count() { find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '; }

emit_dir() {
  local cat="$1" p="$2" b c
  [ -e "$p" ] || return 0
  b=$(dir_bytes "$p"); [ -z "$b" ] && return 0
  [ "$b" -gt 0 ] 2>/dev/null || return 0
  c=$(child_count "$p")
  ROWS+=("$(printf '%s\t%s\t%s\t%s\t%s' "$cat" "$p" "$b" "$(human "$b")" "$c")")
}

emit_children() {
  local cat="$1" d="$2" child
  [ -d "$d" ] || return 0
  while IFS= read -r child; do
    [ -n "$child" ] && emit_dir "$cat" "$child"
  done < <(find "$d" -mindepth 1 -maxdepth 1 2>/dev/null)
}

emit_file() {
  local cat="$1" f="$2" b
  [ -f "$f" ] || return 0
  b=$(stat -f %z "$f" 2>/dev/null); [ -z "$b" ] && return 0
  [ "$b" -gt 0 ] 2>/dev/null || return 0
  ROWS+=("$(printf '%s\t%s\t%s\t%s\t1' "$cat" "$f" "$b" "$(human "$b")")")
}

# ---------------------------------------------------------------------------
# Scanners (each gated by `want`)
# ---------------------------------------------------------------------------

# user group -----------------------------------------------------------------
# user-cache owns EVERYTHING under ~/Library/Caches (incl. pip, Homebrew,
# Safari HTTP cache). Dev/browser categories only cover paths OUTSIDE Caches,
# so no path is ever counted twice.
scan_user_cache() { want user-cache && emit_children user-cache "$HOME_DIR/Library/Caches"; }
scan_user_logs()  { want user-logs  && emit_dir      user-logs  "$HOME_DIR/Library/Logs"; }

scan_browser() {
  want browser-cache || return 0
  local g
  for g in \
    "$HOME_DIR/Library/Application Support/Google/Chrome/Default/Cache" \
    "$HOME_DIR/Library/Application Support/Google/Chrome/Default/Code Cache" \
    "$HOME_DIR/Library/Application Support/Google/Chrome/Default/GPUCache" \
    "$HOME_DIR/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage" \
    "$HOME_DIR/Library/Application Support/Microsoft Edge/Default/Cache" \
    "$HOME_DIR/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache" ; do
    emit_dir browser-cache "$g"
  done
  for g in "$HOME_DIR/Library/Application Support/Firefox/Profiles/"*/cache2; do
    [ -e "$g" ] && emit_dir browser-cache "$g"
  done
}

# dev group ------------------------------------------------------------------
scan_dev_node() {
  want dev-node-modules || return 0
  local d
  # Prune cache roots already counted whole by other categories, so a
  # node_modules nested inside them (e.g. ~/.npm/_npx/*/node_modules) is not
  # double-counted. Then prune at each node_modules so nested ones don't recount.
  while IFS= read -r -d '' d; do
    emit_dir dev-node-modules "$d"
  done < <(find "$HOME_DIR" -type d \( \
      -path "$HOME_DIR/Library" \
      -o -path "$HOME_DIR/.npm" \
      -o -path "$HOME_DIR/.yarn" \
      -o -path "$HOME_DIR/.pnpm-store" \
      -o -path "$HOME_DIR/.gradle" \
      -o -path "$HOME_DIR/.cargo" \
      -o -path "$HOME_DIR/.m2" \
      -o -path "$HOME_DIR/go" \
      -o -path "$HOME_DIR/.cache" \
      -o -path "$HOME_DIR/.Trash" \
    \) -prune -o -type d -name node_modules -prune -print0 2>/dev/null)
}

scan_dev_pkg() {
  want dev-pkg-cache || return 0
  emit_dir dev-pkg-cache "$HOME_DIR/.npm"
  emit_dir dev-pkg-cache "$HOME_DIR/.yarn"
  emit_dir dev-pkg-cache "$HOME_DIR/.pnpm-store"
  emit_dir dev-pkg-cache "$HOME_DIR/Library/pnpm"
  emit_dir dev-pkg-cache "$HOME_DIR/.m2/repository"
  emit_dir dev-pkg-cache "$HOME_DIR/go/pkg/mod"
}

scan_dev_docker() {
  want dev-docker || return 0
  emit_dir dev-docker "$HOME_DIR/Library/Containers/com.docker.docker/Data"
}

scan_dev_xcode() {
  want dev-xcode-derived && \
    emit_children dev-xcode-derived "$HOME_DIR/Library/Developer/Xcode/DerivedData"
  want dev-xcode-archives && \
    emit_dir dev-xcode-archives "$HOME_DIR/Library/Developer/Xcode/Archives"
  want dev-ios-devicesupport && \
    emit_children dev-ios-devicesupport "$HOME_DIR/Library/Developer/Xcode/iOS DeviceSupport"
}

scan_dev_gradle_cargo() {
  want dev-gradle-cargo || return 0
  emit_dir dev-gradle-cargo "$HOME_DIR/.gradle/caches"
  emit_dir dev-gradle-cargo "$HOME_DIR/.cargo/registry"
}

# files group ----------------------------------------------------------------
# Single traversal: find files >= MIN, then split large (recently used) vs
# old (not accessed in OLD_DAYS) by atime. ~/Library and known dev-cache roots
# are pruned so these never double-count the categories above.
scan_files() {
  want large-file || want old-file || return 0
  local cutoff f atime cat
  cutoff=$(date -v-"${OLD_DAYS}"d +%s 2>/dev/null); [ -z "$cutoff" ] && cutoff=0
  while IFS= read -r -d '' f; do
    atime=$(stat -f %a "$f" 2>/dev/null); [ -z "$atime" ] && continue
    if [ "$atime" -le "$cutoff" ]; then cat="old-file"; else cat="large-file"; fi
    want "$cat" || continue
    emit_file "$cat" "$f"
  done < <(find "$HOME_DIR" -type d \( \
      -path "$HOME_DIR/Library" \
      -o -name node_modules \
      -o -path "$HOME_DIR/.Trash" \
      -o -path "$HOME_DIR/.npm" \
      -o -path "$HOME_DIR/.yarn" \
      -o -path "$HOME_DIR/.pnpm-store" \
      -o -path "$HOME_DIR/.gradle" \
      -o -path "$HOME_DIR/.cargo" \
      -o -path "$HOME_DIR/.m2" \
      -o -path "$HOME_DIR/.cache" \
      -o -path "$HOME_DIR/go" \
    \) -prune -o -type f -size +"${MIN}" -print0 2>/dev/null)
}

# system group ---------------------------------------------------------------
scan_system() {
  want sys-tmp && { emit_dir sys-tmp "/private/var/folders"; emit_dir sys-tmp "/private/tmp"; }
  want trash   && emit_dir trash "$HOME_DIR/.Trash"
  want ios-backup && \
    emit_children ios-backup "$HOME_DIR/Library/Application Support/MobileSync/Backup"
  if want tm-localsnapshots && command -v tmutil >/dev/null 2>&1; then
    local n
    n=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple.TimeMachine')
    [ "$n" -gt 0 ] 2>/dev/null && \
      ROWS+=("$(printf '%s\t%s\t%s\t%s\t%s' \
        "tm-localsnapshots" "/ (APFS local snapshots)" "0" "n/a (use tmutil)" "$n")")
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
scan_user_cache
scan_user_logs
scan_browser
scan_dev_node
scan_dev_pkg
scan_dev_docker
scan_dev_xcode
scan_dev_gradle_cargo
scan_files
scan_system

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
printf '# READ-ONLY scan | home=%s | min-size=%s | old-days=%s | format=%s\n' \
  "$HOME_DIR" "$MIN" "$OLD_DAYS" "$FORMAT"

if [ "${#ROWS[@]}" -eq 0 ]; then
  echo "# (no matching items found)"
  exit 0
fi

case "$FORMAT" in
  tsv)
    printf '%s\n' "${ROWS[@]}"
    ;;
  summary)
    printf '%s\n' "${ROWS[@]}" \
      | awk -F'\t' 'NF>=3{b[$1]+=$3;c[$1]++;t+=$3;ti+=1}
                    END{for(k in b)printf "%d\t%s\t%d\n",b[k],k,c[k];
                        printf "%d\t%s\t%d\n",t,"TOTAL",ti}' \
      | sort -rn \
      | awk -F'\t' 'function human(x, u,i){split("B KB MB GB TB PB",u," ");i=1;
                       while(x>=1024&&i<6){x/=1024;i++}
                       return (i==1)?sprintf("%d %s",x,u[i]):sprintf("%.1f %s",x,u[i])}
                    {printf "%-22s %12s  (%s items)\n", $2, human($1), $3}'
    ;;
  *)
    printf 'scan.sh: invalid --format: %s\n' "$FORMAT" >&2; exit 2;;
esac
