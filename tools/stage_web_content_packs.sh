#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-${ROOT}/build/web/content-packs}"
GODOT_RUNNER="${GODOT_RUNNER:-${ROOT}/tools/run_godot_isolated.sh}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
find "$OUT" -maxdepth 1 -type f \( -name '*.pck' -o -name '*.zip' -o -name 'manifest.tsv' \) -delete

manifest="$OUT/manifest.tsv"
printf 'key\tfile\tbytes\tsha256\tresources\n' > "$manifest"

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

stage_pack() {
  local key="$1"
  local expected_count="$2"
  shift 2
  local target="$OUT/${key}.pck"
  local -a files=("$@")
  if [[ "${#files[@]}" -ne "$expected_count" ]]; then
    printf 'Expected %d resources for %s, found %d\n' "$expected_count" "$key" "${#files[@]}" >&2
    exit 1
  fi
  local -a resource_paths=()
  local file
  for file in "${files[@]}"; do
    resource_paths+=("res://${file}")
  done
  local output
  output="$(
    GODOT_SILENCE_ROOT_WARNING=1 "$GODOT_RUNNER" --headless --audio-driver Dummy \
      --script res://tools/build_web_content_pack.gd -- \
      "$target" "${resource_paths[@]}"
  )"
  printf '%s\n' "$output" | grep -q "CONTENT_PACK_BUILD_OK|$target|resources=$expected_count"
  local bytes sha
  bytes="$(file_size "$target")"
  sha="$(file_sha256 "$target")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$key" "$(basename "$target")" "$bytes" "$sha" "$expected_count" >> "$manifest"
}

classes=(
  gunner mage_apprentice swordmaster
)
operator_resources=(
  female/attack_ne.webp
  female/attack_nw.webp
  female/idle_ne.webp
  female/idle_nw.webp
  male/attack_ne.webp
  male/attack_nw.webp
  male/idle_ne.webp
  male/idle_nw.webp
)
for class_id in "${classes[@]}"; do
  class_files=()
  for relative_path in "${operator_resources[@]}"; do
    class_file="assets/sprites/operators/animated/${class_id}/${relative_path}"
    if [[ ! -f "$ROOT/$class_file" ]]; then
      printf 'Missing required resource for operator-%s: %s\n' "$class_id" "$class_file" >&2
      exit 1
    fi
    class_files+=("$class_file")
  done
  actual_count="$(
    find "$ROOT/assets/sprites/operators/animated/${class_id}" \
      -mindepth 2 -maxdepth 2 -type f -name '*.webp' -print \
      | wc -l \
      | tr -d '[:space:]'
  )"
  if [[ "$actual_count" -ne "${#operator_resources[@]}" ]]; then
    printf 'Expected exactly %d retained resources for operator-%s, found %d\n' \
      "${#operator_resources[@]}" "$class_id" "$actual_count" >&2
    exit 1
  fi
  key="operator-${class_id//_/-}"
  stage_pack "$key" "${#operator_resources[@]}" "${class_files[@]}"
done

[[ "$(tail -n +2 "$manifest" | wc -l)" -eq 3 ]]
printf 'Staged 3 verified operator Web content packs in %s\n' "$OUT"
