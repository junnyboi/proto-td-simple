#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
OUT="${2:-/tmp/proto-td-advanced-live-quality}"
GODOT_BIN=${GODOT_BIN:-godot}
rm -rf "$OUT"
mkdir -p "$OUT/live" "$OUT/closeup" "$OUT/metrics"
classes=(
  gunner mage_apprentice swordmaster
)

ADVANCED_COMPRESSION_FULL=1 ADVANCED_COMPRESSION_REPORT="$OUT/metrics/compression-metrics.json" \
  GODOT_BIN="$GODOT_BIN" GODOT_SILENCE_ROOT_WARNING=1 \
  PROTO_TD_TEST_ARTIFACT_DIR="$OUT/metrics/user-data" timeout 360s \
  "$ROOT/tools/run_godot_isolated.sh" --headless \
    --script res://tests/advanced_operator_compression_quality_test.gd \
    > "$OUT/metrics/compression-quality.log" 2>&1
grep -q 'ADVANCED_OPERATOR_COMPRESSION_QUALITY_OK' "$OUT/metrics/compression-quality.log"

for class_id in "${classes[@]}"; do
  xvfb-run -a -s '-screen 0 1920x1080x24' env GODOT_BIN="$GODOT_BIN" \
    GODOT_SILENCE_ROOT_WARNING=1 \
    PROTO_TD_TEST_ARTIFACT_DIR="$OUT/closeup/${class_id}-user-data" \
    "$ROOT/tools/run_godot_isolated.sh" --audio-driver Dummy \
      --script test/advanced_operator_visual_harness.gd \
      -- --class "$class_id" --output "$OUT/closeup/${class_id}.png" \
      > "$OUT/closeup/${class_id}.log" 2>&1
  grep -q 'ADVANCED_OPERATOR_VISUAL_CAPTURE_OK' "$OUT/closeup/${class_id}.log"

  prefix="$OUT/live/${class_id}-landscape"
  xvfb-run -a -s '-screen 0 1920x1080x24' env GODOT_BIN="$GODOT_BIN" \
    GODOT_SILENCE_ROOT_WARNING=1 \
    PROTO_TD_TEST_ARTIFACT_DIR="$OUT/live/${class_id}-landscape-user-data" \
    "$ROOT/tools/run_godot_isolated.sh" --audio-driver Dummy \
      --script test/advanced_operator_live_quality_harness.gd \
      -- --class "$class_id" --output-prefix "$prefix" --width 1920 --height 1080 \
      > "$prefix.log" 2>&1
  grep -q 'ADVANCED_OPERATOR_LIVE_QUALITY_OK' "$prefix.log"

  for gender in female male; do
    prefix="$OUT/live/${class_id}-portrait-${gender}"
    xvfb-run -a -s '-screen 0 720x1280x24' env GODOT_BIN="$GODOT_BIN" \
      GODOT_SILENCE_ROOT_WARNING=1 \
      PROTO_TD_TEST_ARTIFACT_DIR="$OUT/live/${class_id}-portrait-${gender}-user-data" \
      "$ROOT/tools/run_godot_isolated.sh" --audio-driver Dummy \
        --script test/advanced_operator_live_quality_harness.gd \
        -- --class "$class_id" --gender "$gender" --output-prefix "$prefix" --width 720 --height 1280 \
        > "$prefix.log" 2>&1
    grep -q 'ADVANCED_OPERATOR_LIVE_QUALITY_OK' "$prefix.log"
  done
done

if grep -RInE 'SCRIPT ERROR|Parse Error|Parser Error|Invalid call|Assertion failed|FATAL|CRASH|ERROR:' "$OUT" --include='*.log'; then
  exit 1
fi
printf 'ADVANCED_OPERATOR_LIVE_QUALITY_MATRIX_OK output=%s classes=%d images=%d\n' \
  "$OUT" "${#classes[@]}" "$(find "$OUT" -type f -name '*.png' | wc -l)"
