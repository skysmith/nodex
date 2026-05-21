#!/usr/bin/env bash
set -euo pipefail

resolve_script_dir() {
  local source="${BASH_SOURCE[0]}"
  while [[ -L "$source" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    local target
    target="$(readlink "$source")"
    if [[ "$target" == /* ]]; then
      source="$target"
    else
      source="$dir/$target"
    fi
  done
  cd -P "$(dirname "$source")" && pwd
}

ROOT="$(resolve_script_dir)"
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="${BINDIR:-$PREFIX/bin}"

mkdir -p "$BINDIR"
swift build --package-path "$ROOT" -c release

ln -sfn "$ROOT/bin/nodex" "$BINDIR/nodex"
ln -sfn "$ROOT/bin/nodex-motion" "$BINDIR/nodex-motion"

cat <<EOF
Installed Nodex:
  $BINDIR/nodex
  $BINDIR/nodex-motion

Add this to your shell profile if needed:
  export PATH="$BINDIR:\$PATH"

Try:
  nodex doctor
  nodex-motion ask "Should I keep going?" --motion-only
EOF
