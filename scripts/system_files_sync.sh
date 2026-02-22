#!/usr/bin/env bash
set -euo pipefail

repo_root="/home/vind-admin/codex-relay"
dest="$repo_root/System_files"
list="$repo_root/System_files_list.txt"
log="$repo_root/logs/system_files_sync.log"
md_file="$repo_root/system_relay.md"

mkdir -p "$dest" "$(dirname "$log")"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

echo "[$(ts)] sync start" >> "$log"

rsync -rlptD --relative --ignore-missing-args   --files-from="$list" / "$dest" >> "$log" 2>&1

cd "$repo_root"

git add System_files/ System_files_list.txt >> "$log" 2>&1 || true
if git diff --cached --quiet; then
  echo "[$(ts)] no changes" >> "$log"
  exit 0
fi

change_summary="$(git diff --cached --name-status | sed 's/^/- /')"
timestamp="$(date '+%Y-%m-%d %H:%M')"

if ! grep -q '^\#\# Auto Sync Log' "$md_file" 2>/dev/null; then
  printf '\n## Auto Sync Log\n' >> "$md_file"
fi
printf '**%s**\n%s\n' "$timestamp" "$change_summary" >> "$md_file"

git add "$md_file" >> "$log" 2>&1 || true
git -c user.name='auto-sync' -c user.email='auto-sync@local'   commit -m "Auto-sync: ${timestamp}" >> "$log" 2>&1

tag_name="sync-$(date '+%Y%m%d-%H%M')"
git tag -a "$tag_name" -m "Auto-sync changes:\n${change_summary}" >> "$log" 2>&1

echo "[$(ts)] sync complete" >> "$log"
