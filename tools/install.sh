#!/usr/bin/env bash
# Symlinks each addon in addons/ into WoW's Interface/AddOns directory.
# Usage: tools/install.sh "/path/to/World of Warcraft/_retail_"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <path-to-_retail_-or-Interface/AddOns>" >&2
    exit 1
fi

if [[ -d "$TARGET/Interface/AddOns" ]]; then
    ADDONS_DIR="$TARGET/Interface/AddOns"
elif [[ "$(basename "$TARGET")" == "AddOns" && -d "$TARGET" ]]; then
    ADDONS_DIR="$TARGET"
elif [[ -d "$TARGET/AddOns" ]]; then
    ADDONS_DIR="$TARGET/AddOns"
else
    echo "error: could not locate an AddOns directory under '$TARGET'" >&2
    exit 1
fi

for dir in "$ROOT"/addons/*/; do
    name="$(basename "$dir")"
    ln -sfn "$dir" "$ADDONS_DIR/$name"
    echo "linked $name -> $ADDONS_DIR/$name"
done
