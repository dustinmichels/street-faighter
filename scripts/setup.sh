#!/usr/bin/env bash
# Prompt for the itch.io API key and save it to mise.local.toml (git-ignored).
set -euo pipefail
file=mise.local.toml
echo "Paste your itch.io API key from https://itch.io/user/settings/api-keys (input is hidden)."
read -rsp "BUTLER_API_KEY: " key
echo
[[ -n "$key" ]] || { echo "no key entered; $file unchanged" >&2; exit 1; }
[[ -f "$file" ]] || printf '# Local, untracked overrides (git-ignored). Created by `mise run setup`.\n[env]\n' > "$file"
printf '%s' "$key" | mise set --file "$file" --stdin BUTLER_API_KEY
echo "Saved BUTLER_API_KEY to $file"
