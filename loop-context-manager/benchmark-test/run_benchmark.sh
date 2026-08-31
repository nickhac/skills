#!/usr/bin/env bash
# run_benchmark.sh
# Runs the loop-context-manager A/B benchmark.
# Usage: bash run_benchmark.sh [target_dir]
# Default target_dir: ~/vault/principles/  (pass your own as first arg)
#
# Requires:
#   - hermes CLI on PATH
#   - Python 3
#   - ~/.hermes/state.db (Hermes session DB, or set HERMES_DB env var)
#   - loop-context-manager skill installed

set -euo pipefail

TARGET_DIR="${1:-${HOME}/vault/principles/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_FILE="$SCRIPT_DIR/task_prompt.txt"
MEASURE="$SCRIPT_DIR/token_measure.py"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_DIR="/tmp/lcm_bench_${TIMESTAMP}"
mkdir -p "$OUT_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "loop-context-manager A/B Benchmark"
echo "Target dir:  $TARGET_DIR"
echo "Output dir:  $OUT_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Substitute target dir into task prompt
TASK=$(sed "s|~/vault/principles/|${TARGET_DIR}|g" "$TASK_FILE")

echo ""
echo "▶ Run 1: WITH loop-context-manager"
hermes chat --skills loop-context-manager -q "$TASK" 2>&1 | tee "$OUT_DIR/run_with_skill.log"
SESSION_WITH=$(grep -oP '(?<=hermes --resume )\S+' "$OUT_DIR/run_with_skill.log" | tail -1)
echo "$SESSION_WITH" > "$OUT_DIR/session_with_skill.txt"
echo "  Session: $SESSION_WITH"
python3 "$MEASURE" "$SESSION_WITH" "WITH_SKILL" | tee "$OUT_DIR/tokens_with_skill.txt"

echo ""
echo "▶ Run 2: WITHOUT loop-context-manager"
hermes chat -q "$TASK" 2>&1 | tee "$OUT_DIR/run_no_skill.log"
SESSION_WITHOUT=$(grep -oP '(?<=hermes --resume )\S+' "$OUT_DIR/run_no_skill.log" | tail -1)
echo "$SESSION_WITHOUT" > "$OUT_DIR/session_no_skill.txt"
echo "  Session: $SESSION_WITHOUT"
python3 "$MEASURE" "$SESSION_WITHOUT" "NO_SKILL" | tee "$OUT_DIR/tokens_no_skill.txt"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "RESULTS SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "WITH skill:"
grep -E "API calls|Output tokens|Cache read|cost" "$OUT_DIR/tokens_with_skill.txt" || true
echo ""
echo "WITHOUT skill:"
grep -E "API calls|Output tokens|Cache read|cost" "$OUT_DIR/tokens_no_skill.txt" || true
echo ""
echo "Full results in: $OUT_DIR"
echo "Session IDs:"
echo "  With:    $SESSION_WITH"
echo "  Without: $SESSION_WITHOUT"