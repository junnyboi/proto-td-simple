#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary_base=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "$temporary_base/proto-td-pack-staging.XXXXXX")

cleanup() {
  if [[ "$work_dir" == "$temporary_base"/proto-td-pack-staging.* ]]; then
    rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT INT TERM

out="$work_dir/content-packs"
GODOT_RUNNER="${GODOT_RUNNER:-$ROOT/tools/run_godot_isolated.sh}" \
  "$ROOT/tools/stage_web_content_packs.sh" "$out" \
  > "$work_dir/staging.stdout"

grep -q 'Staged 3 verified operator Web content packs' "$work_dir/staging.stdout"
manifest="$out/manifest.tsv"
[[ -f "$manifest" ]]
[[ "$(head -n 1 "$manifest")" == $'key\tfile\tbytes\tsha256\tresources' ]]
[[ "$(tail -n +2 "$manifest" | wc -l | tr -d ' ')" -eq 3 ]]

file_size() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f %z "$1"
  else
    stat -c %s "$1"
  fi
}

file_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

seen='|'
while IFS=$'\t' read -r key file bytes sha resources; do
  case "$key" in
    operator-gunner|operator-mage-apprentice|operator-swordmaster) ;;
    *)
      printf 'Unexpected staged pack key: %s\n' "$key" >&2
      exit 1
      ;;
  esac
  if [[ "$seen" == *"|$key|"* ]]; then
    printf 'Duplicate staged pack key: %s\n' "$key" >&2
    exit 1
  fi
  seen="${seen}${key}|"
  [[ "$file" == "$key.pck" ]]
  [[ "$resources" -eq 8 ]]
  [[ "$bytes" -gt 0 ]]
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]]
  pack="$out/$file"
  [[ -s "$pack" ]]
  [[ "$(file_size "$pack")" -eq "$bytes" ]]
  [[ "$(file_sha256 "$pack")" == "$sha" ]]
done < <(tail -n +2 "$manifest")

for key in operator-gunner operator-mage-apprentice operator-swordmaster; do
  [[ "$seen" == *"|$key|"* ]]
done

printf '%s\n' 'WEB_CONTENT_PACK_STAGING_TEST_OK'
