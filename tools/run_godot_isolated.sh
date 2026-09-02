#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-godot}
KEEP_TEST_USER_DATA=${PROTO_TD_KEEP_TEST_USER_DATA:-0}

if (($# == 0)); then
  echo "usage: tools/run_godot_isolated.sh <godot arguments...>" >&2
  exit 64
fi

for argument in "$@"; do
  if [[ "$argument" == "--path" || "$argument" == --path=* ]]; then
    echo "run_godot_isolated.sh owns --path; remove it from the supplied arguments" >&2
    exit 64
  fi
done

temporary_base=${TMPDIR:-/tmp}
run_root=$(mktemp -d "$temporary_base/proto-td-test.XXXXXX")
run_token=$(basename "$run_root")-$$
run_id=${run_token//[^a-zA-Z0-9._-]/-}
custom_user_dir_name="GameTemplateTDTests-$run_id"
project_root="$run_root/project"
xdg_data_root="$run_root/xdg-data"
artifact_root=${PROTO_TD_TEST_ARTIFACT_DIR:-"$ROOT/build/test-runs/$run_id"}
log_file=${PROTO_TD_TEST_LOG_FILE:-"$artifact_root/godot.log"}

mkdir -p "$project_root" "$xdg_data_root" "$artifact_root" "$project_root/build"

while IFS= read -r entry; do
  base=${entry##*/}
  case "$base" in
    .git|build|project.godot)
      continue
      ;;
  esac
  ln -s "$entry" "$project_root/$base"
done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -print)

awk -v custom_name="$custom_user_dir_name" '
  /^config\/use_custom_user_dir=/ { next }
  /^config\/custom_user_dir_name=/ { next }
  /^config\/name=/ {
    print
    print "config/use_custom_user_dir=true"
    print "config/custom_user_dir_name=\"" custom_name "\""
    next
  }
  { print }
' "$ROOT/project.godot" > "$project_root/project.godot"

case "$(uname -s)" in
  Darwin)
    isolated_user_dir="$HOME/Library/Application Support/$custom_user_dir_name"
    ;;
  Linux)
    isolated_user_dir="$xdg_data_root/$custom_user_dir_name"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    isolated_user_dir="${APPDATA:?APPDATA is required}/$custom_user_dir_name"
    ;;
  *)
    echo "unsupported platform for isolated Godot user data: $(uname -s)" >&2
    exit 69
    ;;
esac

cleanup() {
  if [[ "$KEEP_TEST_USER_DATA" == "1" ]]; then
    echo "preserved isolated test project: $run_root" >&2
    echo "preserved isolated user data: $isolated_user_dir" >&2
    return
  fi
  if [[ "$run_root" == "$temporary_base"/proto-td-test.* ]]; then
    rm -rf -- "$run_root"
  fi
  case "$isolated_user_dir" in
    */GameTemplateTDTests-proto-td-test.*)
      rm -rf -- "$isolated_user_dir"
      ;;
    *)
      echo "refusing to clean unexpected test user-data path: $isolated_user_dir" >&2
      ;;
  esac
}
trap cleanup EXIT INT TERM

export PROTO_TD_TEST_ISOLATED=1
export PROTO_TD_TEST_RUN_ID="$run_id"
export XDG_DATA_HOME="$xdg_data_root"

"$GODOT_BIN" --path "$project_root" --log-file "$log_file" "$@"
