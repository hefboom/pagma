#!/usr/bin/env bash
# Onboard a repo-targeted scope, interactively — `just forge discover [query]`.
# Depth: scripts/README.md#discoversh

set -euo pipefail
source "$(dirname "$0")/env.sh"

if ! { : <"/dev/tty"; } 2>/dev/null; then
  echo "discover.sh needs a terminal — it opens an fzf picker." >&2
  echo "non-interactive: bash scripts/discover-core.sh <repo>" >&2
  exit 2
fi

roots=$(forge_dev_roots)
shown=$(tr '\n' ' ' <<<"$roots")

dotfiles_root=$(cd .. && pwd)

# A folder name found in two roots is listed once: the first root wins, as in forge_repo_dir.
candidates=$(
  seen=$'\n'
  while IFS= read -r dev_root; do
  for d in "$dev_root"/*/; do
    [[ -e "$d/.git" ]] || continue
    repo=$(basename "$d")
    case $seen in *$'\n'"$repo"$'\n'*) continue ;; esac
    seen+=$repo$'\n'
    root=$(jq -r --arg r "$repo" '.harnesses["claude-code"].roots[$r] // empty' elections.json)
    link=$d.claude/skills
    if [[ -z "$root" ]]; then
      printf '%s\t(new)\n' "$repo"
    elif [[ ! -e "$link" && ! -L "$link" ]]; then
      printf '%s\t(declared, unlinked)\n' "$repo"
    elif [[ -L "$link" && $(readlink "$link") == "$dotfiles_root/$root" ]]; then
      printf '%s\t(linked)\n' "$repo"
    else
      printf '%s\t(mislinked — link.sh will refuse with the fix)\n' "$repo"
    fi
  done
  done <<<"$roots"
)

if [[ -z "$candidates" ]]; then
  echo "nothing to discover — no git repos under ${shown}(add a folder: just forge dev-root-exact <dir>)"
  exit 0
fi

pick=$(fzf \
  --prompt='discover> ' \
  --layout=reverse \
  --query "${1:-}" --select-1 \
  --header "git repos under ${shown}— pick to declare + link" <<<"$candidates") || true
[[ -z "$pick" ]] && {
  echo "aborted — no changes"
  exit 0
}

exec bash "$ENGINE/scripts/discover-core.sh" "${pick%%$'\t'*}"
