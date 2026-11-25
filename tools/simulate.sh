#!/usr/bin/env bash
# Simula a economia sem interface e imprime CSV em stdout.
# Uso: tools/simulate.sh [--steps=600] [--every=10] [--plan=generator,collector,...]
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/bin/godot}"
mkdir -p tests/output
touch tests/output/.gdignore

timeout 300 "$GODOT" --headless --path . --import >tests/output/import.log 2>&1
# O banner do Godot vai para stdout e não é CSV; --quiet também silenciaria o print.
set +e
timeout 300 "$GODOT" --headless --path . --script res://tools/simulate.gd -- "$@" | grep -v "^Godot Engine v"
exit "${PIPESTATUS[0]}"
