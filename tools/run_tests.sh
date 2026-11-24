#!/usr/bin/env bash
# Executa todos os testes headless do NEXUS.
# Uso: tools/run_tests.sh [--filter=texto]
# Código de saída: 0 = todos passaram; 1 = falha; 2 = erro de ambiente/import.
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/bin/godot}"
OUT_DIR="tests/output"
mkdir -p "$OUT_DIR"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Godot não encontrado em '$GODOT'. Defina GODOT=/caminho/para/godot." >&2
	exit 2
fi

# Um checkout novo não tem .godot/; sem importar, class_name e assets não resolvem.
if ! timeout 300 "$GODOT" --headless --path . --import >"$OUT_DIR/import.log" 2>&1; then
	echo "Falha ao importar o projeto. Veja $OUT_DIR/import.log" >&2
	exit 2
fi

set +e
timeout 300 "$GODOT" --headless --path . --script res://tests/runner.gd -- "$@" \
	2>"$OUT_DIR/tests.err"
status=$?
set -e

if grep -nE "SCRIPT ERROR|^ERROR:" "$OUT_DIR/tests.err" >/dev/null; then
	echo "" >&2
	echo "Erros registrados durante os testes ($OUT_DIR/tests.err):" >&2
	grep -nE -A2 "SCRIPT ERROR|^ERROR:" "$OUT_DIR/tests.err" >&2 || true
	[ "$status" -eq 0 ] && status=1
fi

if [ "$status" -eq 124 ]; then
	echo "Tempo esgotado: algum teste travou." >&2
fi
exit "$status"
