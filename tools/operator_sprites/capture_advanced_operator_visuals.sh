#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
OUTPUT="${2:-/tmp/proto-td-advanced-operator-visuals}"
GODOT_BIN=${GODOT_BIN:-godot}
mkdir -p "$OUTPUT"
classes=(
  gunner mage_apprentice swordmaster
)
for class_id in "${classes[@]}"; do
	  xvfb-run -a -s '-screen 0 1920x1080x24' env \
	    GODOT_BIN="$GODOT_BIN" GODOT_SILENCE_ROOT_WARNING=1 \
	    PROTO_TD_TEST_ARTIFACT_DIR="$OUTPUT/${class_id}-user-data" \
	    "$REPOSITORY/tools/run_godot_isolated.sh" --audio-driver Dummy \
    --script test/advanced_operator_visual_harness.gd \
    -- --class "$class_id" --output "$OUTPUT/${class_id}.png" \
    > "$OUTPUT/${class_id}.log" 2>&1
  grep -q 'ADVANCED_OPERATOR_VISUAL_CAPTURE_OK' "$OUTPUT/${class_id}.log"
done
printf 'ADVANCED_OPERATOR_VISUAL_MATRIX_OK output=%s classes=%d\n' "$OUTPUT" "${#classes[@]}"
