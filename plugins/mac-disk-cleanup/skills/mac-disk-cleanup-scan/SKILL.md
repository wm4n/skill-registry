---
name: mac-disk-cleanup-scan
description: Use when a Mac is low on disk space or the user wants to find space-consuming junk — caches, logs, temp files, trash, large or old files, node_modules, npm/pip/gradle/cargo caches, Docker data, Xcode DerivedData/Archives, iOS backups, Time Machine local snapshots (macOS only). Triggers include "Mac 空間不足", "清理 Mac", "找出佔空間的檔案 / cache / 暫存檔", "disk full on Mac", "what's eating my disk".
---

# mac-disk-cleanup-scan

## Overview

Read-only scan of the macOS locations that commonly waste disk space, turned
into a ranked, risk-labeled report. **The skill only finds — it never deletes.**
Cleanup is always the user's decision; provide copy-paste commands, never run them.

**Core principle:** the bundled `scripts/scan.sh` gathers *facts* (paths + sizes,
strictly read-only). This SKILL.md supplies the *judgment* (risk level) and the
*presentation* (the report + cleanup commands).

## When to Use

- Mac reports low disk space, or the user asks what is taking up space.
- User wants caches / temp / large / old files surfaced before cleaning.

**When NOT to use:** non-macOS systems; when the user wants files actually deleted
(this skill reports only — hand them the commands and let them decide).

## How to Run

Run the bundled script (never modifies anything):

```bash
bash scripts/scan.sh                      # scan everything, TSV output
bash scripts/scan.sh --categories dev     # only developer caches
bash scripts/scan.sh --min-size 1G        # raise large-file threshold
bash scripts/scan.sh --format summary     # human totals per category
bash scripts/scan.sh --help               # all flags
```

Groups: `user`, `dev`, `files`, `system`. Flags: `--categories`, `--min-size`
(default 500M), `--old-days` (default 180), `--home`, `--format`. See `--help`.

A full scan traverses `$HOME` for large/old files and `node_modules`; on big home
directories it can take a minute. Suggest `--min-size 1G` or `--categories` to narrow.

## Output Contract

TSV, one finding per line, after a `# READ-ONLY ...` header:

```
category_id <TAB> path <TAB> size_bytes <TAB> human_size <TAB> item_count
```

Categories are designed so no emitted path is nested inside another — a plain sum
of `size_bytes` is a correct grand total. Everything under `~/Library/Caches`
(including pip and Homebrew caches) is reported as `user-cache`; dev/browser
categories only cover paths outside `~/Library/Caches`.

## Risk & Cleanup Reference

Legend: ✅ usually safe · ⚠️ confirm first · ⛔ do not delete

| category_id | 中文名稱 | 風險 | 建議清理指令 |
|---|---|---|---|
| `user-cache` | 使用者快取 `~/Library/Caches`（含 pip/Homebrew 子項） | ✅ | `rm -rf ~/Library/Caches/*`；pip：`pip cache purge`；Homebrew：`brew cleanup -s` |
| `user-logs` | 使用者日誌 `~/Library/Logs` | ✅ | `rm -rf ~/Library/Logs/*` |
| `browser-cache` | 瀏覽器快取（Chrome/Firefox/Edge/Brave） | ✅ | 刪對應 Cache 目錄，或用瀏覽器內建「清除快取」 |
| `dev-node-modules` | 專案 `node_modules` | ✅ | 逐專案 `rm -rf node_modules`（需要時重裝） |
| `dev-pkg-cache` | 套件快取（npm/yarn/pnpm/maven/go） | ✅ | `npm cache clean --force`、`go clean -modcache` 等 |
| `dev-docker` | Docker 容器資料 | ⚠️ | `docker system prune`（會刪未用 image/volume，先確認） |
| `dev-xcode-derived` | Xcode DerivedData | ✅ | `rm -rf ~/Library/Developer/Xcode/DerivedData/*`（會重建） |
| `dev-xcode-archives` | Xcode Archives | ⚠️ | 發佈打包，刪了無法重新上傳同版本 |
| `dev-ios-devicesupport` | iOS DeviceSupport | ⚠️ | 連舊裝置時會重建，可刪舊版本 |
| `dev-gradle-cargo` | Gradle / Cargo 快取 | ✅ | `rm -rf ~/.gradle/caches`、`cargo cache -a`（僅 caches） |
| `large-file` | 大檔案（≥ 門檻、近期用過） | ⚠️ | 人工判斷，可能是你重要的檔案 |
| `old-file` | 大且長期未存取的檔案 | ⚠️ | 人工判斷，通常是遺忘的下載/素材 |
| `sys-tmp` | 系統暫存 `/private/var/folders`、`/private/tmp` | ⚠️ | 系統管理，重開機自清，勿手動刪 |
| `trash` | 垃圾桶 `~/.Trash` | ✅ | 清空垃圾桶，或 `rm -rf ~/.Trash/*` |
| `ios-backup` | iOS 裝置備份 | ⛔ | 手機備份，刪了無法還原，先確認已不需要 |
| `tm-localsnapshots` | Time Machine 本機快照 | ⚠️ | `tmutil thinlocalsnapshots / 999999999999 4` |

## Composing the Report

Read the TSV, then produce Markdown:

1. **Opening statement (required):** 「本次為唯讀掃描，未刪除或修改任何檔案。」
2. **Overview:** grand total (sum of `size_bytes`, dedup by path) as 「可能可釋放約 XX GB」, plus a per-category subtotal line.
3. **Details by group** (`user` / `dev` / `files` / `system`): within each, sort rows by `size_bytes` descending; show the risk badge (✅/⚠️/⛔ from the table), the path, and `human_size`.
4. **Cleanup commands:** per category, give the copy-paste command from the table, prefixed with 「以下由你自行決定執行，skill 不代為刪除」.

## Common Mistakes

- **Running any delete command.** Never. Report and hand over commands only.
- **Double-counting.** Sum `size_bytes` per unique path; the categories are already non-nested, so don't also add parent directories.
- **Empty `~/Library` results.** Likely the terminal lacks Full Disk Access — tell the user to grant it in 系統設定 › 隱私權與安全性 › 完整磁碟取用權, then rescan.
- **Treating ⚠️/⛔ as safe.** `large-file`, `old-file`, `dev-xcode-archives`, `ios-backup` need human judgment; surface them, don't imply they're disposable.
