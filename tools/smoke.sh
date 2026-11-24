#!/usr/bin/env bash
# Executa a cena principal headless por N frames e procura erros no log.
# Uso: tools/smoke.sh [frames]   (padrão: 300)
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/bin/godot}"
FRAMES="${1:-300}"
OUT_DIR="tests/output"
mkdir -p "$OUT_DIR"

timeout 300 "$GODOT" --headless --path . --import >"$OUT_DIR/import.log" 2>&1
timeout 300 "$GODOT" --headless --path . --quit-after "$FRAMES" >"$OUT_DIR/smoke.log" 2>&1

# O código de saída fica 0 mesmo com erros de script; por isso o grep.
if grep -nE "SCRIPT ERROR|^ERROR:" "$OUT_DIR/smoke.log"; then
	echo "Smoke test falhou. Veja $OUT_DIR/smoke.log" >&2
	exit 1
fi
echo "Smoke test ok ($FRAMES frames, sem erros)."
