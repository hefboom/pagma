#!/usr/bin/env bash
# Sourced by every forge script, never run: resolves where the engine is and where the
# hub is, then cds to the manifest dir so `elections.json`, `skills/`, `kegs/`
# and `scratch/` resolve as bare relative paths.
#
#   ENGINE  the dir holding this scripts/ tree and the justfile — call siblings via "$ENGINE/scripts/<x>"
#   ROOT    the hub: $FORGE_ROOT if set, else the nearest ancestor of ENGINE holding forge/elections.json
#   FORGE   $ROOT/forge — the manifest, the cellars, scratch; the cwd from here on
#
# The engine owns no paths: ROOT plus the manifest own all of them.

ENGINE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -n ${FORGE_ROOT:-} ]]; then
  ROOT=$(cd "$FORGE_ROOT" && pwd)
else
  ROOT=$ENGINE
  until [[ -f $ROOT/forge/elections.json ]]; do
    if [[ $ROOT == / ]]; then
      echo "forge: no ancestor of $ENGINE holds forge/elections.json — set FORGE_ROOT to the hub" >&2
      exit 1
    fi
    ROOT=$(dirname "$ROOT")
  done
fi
FORGE=$ROOT/forge
[[ -f $FORGE/elections.json ]] || { echo "forge: $FORGE/elections.json not found (FORGE_ROOT=$ROOT)" >&2; exit 1; }
cd "$FORGE"

# The dev roots: the folders that hold the person's other repos, one per line.
# $FORGE_DEV_ROOT, when set, is the only one. Otherwise the manifest's `devRoots` list
# (a leading ~ is the home directory). Otherwise ~/dev. render.ts devRoots() is the same.
forge_dev_roots() {
  if [[ -n ${FORGE_DEV_ROOT:-} ]]; then
    printf '%s\n' "$FORGE_DEV_ROOT"
    return 0
  fi
  local listed r
  listed=$(jq -r '(.devRoots // [])[]' "$FORGE/elections.json")
  if [[ -z $listed ]]; then
    printf '%s\n' "$HOME/dev"
    return 0
  fi
  while IFS= read -r r; do
    case $r in
      "~") r=$HOME ;;
      "~/"*) r=$HOME/${r#"~/"} ;;
    esac
    printf '%s\n' "$r"
  done <<<"$listed"
}

# One repo's directory, by folder name: the first dev root that holds it. Fails when none does.
forge_repo_dir() {
  local r
  while IFS= read -r r; do
    if [[ -d $r/$1 ]]; then
      printf '%s\n' "$r/$1"
      return 0
    fi
  done < <(forge_dev_roots)
  return 1
}

# The refusal every repo verb prints when forge_repo_dir fails.
forge_no_repo() {
  echo "no repo named \"$1\" in the dev roots:" >&2
  forge_dev_roots | sed 's/^/  /' >&2
  echo "add the folder it lives in: just forge dev-root-exact <dir>" >&2
}
