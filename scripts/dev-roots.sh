#!/usr/bin/env bash
# Where the hub is and which folders it searches for your other repos — `just forge dev-roots`,
# `just forge dev-root-exact <dir> [-]`.
# Depth: scripts/README.md#dev-rootssh

set -euo pipefail
source "$(dirname "$0")/env.sh"

MANIFEST=elections.json

show() {
  local src=manifest r d n
  if [[ -n ${FORGE_DEV_ROOT:-} ]]; then
    src='$FORGE_DEV_ROOT'
  elif [[ $(jq -r '(.devRoots // []) | length' "$MANIFEST") == 0 ]]; then
    src=default
  fi
  printf 'hub       %s\n' "$ROOT"
  while IFS= read -r r; do
    if [[ -d $r ]]; then
      n=0
      for d in "$r"/*/; do
        if [[ -e $d/.git ]]; then n=$((n + 1)); fi
      done
      printf 'dev root  %s  (git repos: %s, from %s)\n' "$r" "$n" "$src"
    else
      printf 'dev root  %s  (not on this machine, from %s)\n' "$r" "$src"
    fi
  done < <(forge_dev_roots)
}

if [[ $# -eq 0 ]]; then
  show
  exit 0
fi
if [[ $# -gt 2 || ($# -eq 2 && $2 != -) ]]; then
  echo "usage: dev-roots.sh            print the hub and the dev roots" >&2
  echo "       dev-roots.sh <dir>      add a folder that holds repos" >&2
  echo "       dev-roots.sh <dir> -    remove it" >&2
  exit 2
fi

# The stored form: `~/…` for a folder under the home directory, so the same manifest
# works on a machine with another user name; an absolute path otherwise.
dir=${1%/}
case $dir in
  "~") dir=$HOME ;;
  "~/"*) dir=$HOME/${dir#"~/"} ;;
esac
if [[ -d $dir ]]; then
  dir=$(cd "$dir" && pwd)
elif [[ ${2:-} != - ]]; then
  echo "no folder at $dir" >&2
  exit 1
fi
case $dir in
  "$HOME") stored="~" ;;
  "$HOME"/*) stored="~/${dir#"$HOME"/}" ;;
  *)
    stored=$dir
    # Git Bash: bun reads the manifest as a Windows program, so store `D:/…`, not `/d/…`.
    if command -v cygpath >/dev/null 2>&1; then stored=$(cygpath -m "$dir"); fi
    ;;
esac

listed=$(jq -r --arg s "$stored" '(.devRoots // []) | index($s) != null' "$MANIFEST")
mkdir -p scratch
tmp=scratch/elections.json.tmp

if [[ ${2:-} == - ]]; then
  if [[ $listed != true ]]; then
    echo "$stored is not in the manifest's devRoots" >&2
    show >&2
    exit 1
  fi
  jq --arg s "$stored" '.devRoots -= [$s] | if .devRoots == [] then del(.devRoots) else . end' "$MANIFEST" >"$tmp"
  mv "$tmp" "$MANIFEST"
  echo "removed dev root $stored"
elif [[ $listed == true ]]; then
  echo "$stored is already a dev root"
else
  # The first folder added by hand must not drop the default the person was using.
  seed='[]'
  if [[ $(jq -r '(.devRoots // []) | length' "$MANIFEST") == 0 && -d $HOME/dev && $stored != "~/dev" ]]; then
    seed='["~/dev"]'
  fi
  jq --arg s "$stored" --argjson seed "$seed" '.devRoots = ((.devRoots // $seed) + [$s])' "$MANIFEST" >"$tmp"
  mv "$tmp" "$MANIFEST"
  echo "added dev root $stored"
fi

if [[ -n ${FORGE_DEV_ROOT:-} ]]; then
  echo "note: FORGE_DEV_ROOT is set in this shell and replaces the manifest's list while it is" >&2
fi
bun run "$ENGINE/scripts/render.ts" >/dev/null
show
