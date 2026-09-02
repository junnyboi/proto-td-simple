#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-godot}
temporary_base=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "$temporary_base/proto-td-isolation-regression.XXXXXX")

cleanup() {
  if [[ "$work_dir" == "$temporary_base"/proto-td-isolation-regression.* ]]; then
    rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT INT TERM

case "$(uname -s)" in
  Darwin)
    production_dir="$HOME/Library/Application Support/Godot/app_userdata/Game template - TD"
    ;;
  Linux)
    production_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Game template - TD"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    production_dir="${APPDATA:?APPDATA is required}/Godot/app_userdata/Game template - TD"
    ;;
  *)
    echo "unsupported platform for production-save fingerprint: $(uname -s)" >&2
    exit 69
    ;;
esac

fingerprint_production_slot() {
  local path
  for path in \
    "$production_dir/campaign_v1.json" \
    "$production_dir/campaign_v1.bak" \
    "$production_dir/campaign_v1.tmp" \
    "$production_dir/campaign_v1.invalid" \
    "$production_dir/campaign_v1.bak.invalid" \
    "$production_dir/campaign_v1.tmp.invalid"; do
    if [[ ! -e "$path" ]]; then
      printf 'missing|%s\n' "$path"
      continue
    fi
    cksum "$path"
    case "$(uname -s)" in
      Darwin) stat -f '%N|%m|%z|%i' "$path" ;;
      *) stat -c '%n|%Y|%s|%i' "$path" ;;
    esac
  done
}

before=$(fingerprint_production_slot)

set +e
"$GODOT_BIN" --headless --path "$ROOT" --log-file "$work_dir/raw.log" \
  --script res://tests/test_user_data_isolation_test.gd \
  > "$work_dir/raw.stdout" 2>&1
raw_exit=$?
set -e

if [[ "$raw_exit" -eq 0 ]]; then
  echo "raw test did not fail closed" >&2
  cat "$work_dir/raw.stdout" >&2
  exit 1
fi
grep -q 'TEST_USER_DATA_ISOLATION_REQUIRED' "$work_dir/raw.log"
if rg -q 'TEST_USER_DATA_ISOLATION_OK' "$work_dir/raw.log" "$work_dir/raw.stdout"; then
  echo "raw test body ran despite the isolation guard" >&2
  exit 1
fi

after_raw=$(fingerprint_production_slot)
if [[ "$before" != "$after_raw" ]]; then
  echo "raw test guard changed the production campaign slot" >&2
  diff -u <(printf '%s\n' "$before") <(printf '%s\n' "$after_raw") >&2 || true
  exit 1
fi

GODOT_BIN="$GODOT_BIN" \
PROTO_TD_TEST_ARTIFACT_DIR="$work_dir/isolated-artifacts" \
  "$ROOT/tools/run_godot_test.sh" tests/test_user_data_isolation_test.gd \
  > "$work_dir/isolated.stdout" 2>&1
grep -q 'TEST_USER_DATA_ISOLATION_OK' "$work_dir/isolated-artifacts/godot.log"

GODOT_BIN="$GODOT_BIN" \
PROTO_TD_TEST_ARTIFACT_DIR="$work_dir/parallel-a" \
  "$ROOT/tools/run_godot_test.sh" tests/test_user_data_isolation_test.gd \
  > "$work_dir/parallel-a.stdout" 2>&1 &
parallel_a_pid=$!
GODOT_BIN="$GODOT_BIN" \
PROTO_TD_TEST_ARTIFACT_DIR="$work_dir/parallel-b" \
  "$ROOT/tools/run_godot_test.sh" tests/test_user_data_isolation_test.gd \
  > "$work_dir/parallel-b.stdout" 2>&1 &
parallel_b_pid=$!
wait "$parallel_a_pid"
wait "$parallel_b_pid"
parallel_a_dir=$(sed -n 's/^TEST_USER_DATA_ISOLATION_OK user_dir=//p' "$work_dir/parallel-a/godot.log")
parallel_b_dir=$(sed -n 's/^TEST_USER_DATA_ISOLATION_OK user_dir=//p' "$work_dir/parallel-b/godot.log")
if [[ -z "$parallel_a_dir" || -z "$parallel_b_dir" || "$parallel_a_dir" == "$parallel_b_dir" ]]; then
  echo "parallel tests did not receive distinct user-data directories" >&2
  exit 1
fi

after_isolated=$(fingerprint_production_slot)
if [[ "$before" != "$after_isolated" ]]; then
  echo "isolated test changed the production campaign slot" >&2
  diff -u <(printf '%s\n' "$before") <(printf '%s\n' "$after_isolated") >&2 || true
  exit 1
fi

printf '%s\n' 'TEST_USER_DATA_ISOLATION_REGRESSION_OK'
