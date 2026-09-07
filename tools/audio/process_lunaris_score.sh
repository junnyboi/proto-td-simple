#!/usr/bin/env bash
set -euo pipefail

prod="${PRODUCTION_ROOT:-/home/ubuntu/projects/proto-td-1515240c/audio-production-2026-08-25}"
repo="${REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
music_out="$repo/assets/template/bundled/music/lunaris"
sfx_out="$repo/assets/template/bundled/sfx/ui"
mkdir -p "$music_out" "$sfx_out"

loopify() {
  local input="$1" offset="$2" duration="$3" crossfade="$4" gain="$5" output="$6"
  local body_end tail_start
  body_end=$(printf '%s-%s\n' "$duration" "$crossfade" | bc)
  tail_start="$body_end"
  ffmpeg -hide_banner -loglevel error -y -ss "$offset" -t "$duration" -i "$input" \
    -filter_complex "[0:a]aresample=48000,volume=${gain}dB,asplit=3[headsrc][bodysrc][tailsrc];[headsrc]atrim=start=0:end=${crossfade},asetpts=PTS-STARTPTS[head];[bodysrc]atrim=start=${crossfade}:end=${body_end},asetpts=PTS-STARTPTS[body];[tailsrc]atrim=start=${tail_start}:end=${duration},asetpts=PTS-STARTPTS[tail];[tail][head]acrossfade=d=${crossfade}:c1=tri:c2=tri[wrap];[body][wrap]concat=n=2:v=0:a=1,alimiter=limit=0.794[out]" \
    -map "[out]" -c:a libvorbis -q:a 5 "$output"
}

stinger() {
  local input="$1" offset="$2" duration="$3" gain="$4" output="$5"
  local fade_start
  fade_start=$(printf '%s-%s\n' "$duration" "0.20" | bc)
  ffmpeg -hide_banner -loglevel error -y -ss "$offset" -t "$duration" -i "$input" \
    -af "aresample=48000,volume=${gain}dB,afade=t=out:st=${fade_start}:d=0.20,alimiter=limit=0.708:level=false" \
    -c:a libvorbis -q:a 5 "$output"
}

loopify "$prod/music/master/lunaris_staging_archive_command.wav" 0 144.0 3.428571 -10.2 \
  "$music_out/lunaris_staging_archive_command.ogg"
for row in "low 0 -6.3" "medium 52 -7.6" "high 104 -9.0"; do
  read -r state offset gain <<<"$row"
  loopify "$prod/music/master/lunaris_battle_orbit_early.wav" "$offset" 52.0 2.0 "$gain" \
    "$music_out/lunaris_battle_orbit_early_${state}.ogg"
done
for row in "low 0 -5.1" "medium 52 -8.5" "high 104 -9.2"; do
  read -r state offset gain <<<"$row"
  loopify "$prod/music/master/lunaris_battle_air_raid.wav" "$offset" 49.523810 1.904762 "$gain" \
    "$music_out/lunaris_battle_air_raid_${state}.ogg"
done
for row in "low 0 -4.7" "medium 52 -7.1" "high 104 -9.3"; do
  read -r state offset gain <<<"$row"
  loopify "$prod/music/master/lunaris_battle_gravity_lattice.wav" "$offset" 50.322581 1.935484 "$gain" \
    "$music_out/lunaris_battle_gravity_lattice_${state}.ogg"
done
loopify "$prod/music/master/lunaris_boss_gatecrasher.wav" 12 150.0 3.0 -7.6 \
  "$music_out/lunaris_boss_gatecrasher.ogg"
stinger "$prod/music/master/lunaris_result_resolutions.wav" 0 8.0 -0.5 \
  "$music_out/lunaris_result_victory.ogg"
stinger "$prod/music/master/lunaris_result_resolutions.wav" 31.75 8.0 -8.2 \
  "$music_out/lunaris_result_defeat.ogg"

for id in ui_click ui_back menu_open menu_close ui_confirm; do
  ffmpeg -hide_banner -loglevel error -y -i "$prod/sfx/carriers/${id}_carrier.mp4" -t 3 \
    -af "loudnorm=I=-18:LRA=7:TP=-1.5,aresample=48000,afade=t=out:st=2.85:d=0.15" \
    -c:a pcm_s16le "$sfx_out/${id}.wav"
done

ffmpeg -hide_banner -loglevel error -y -ss 1.0 -i "$prod/sfx/carriers/ui_hover_carrier.mp4" \
  -t 1.75 -vn \
  -af "aresample=48000,loudnorm=I=-28:LRA=4:TP=-9,afade=t=in:st=0:d=0.01,afade=t=out:st=1.55:d=0.20" \
  -ar 48000 -ac 2 -c:a pcm_s16le "$sfx_out/ui_hover.wav"

printf '%s\n' 'Runtime audio derivatives created:'
find "$music_out" "$sfx_out" -maxdepth 1 -type f \( -name '*.ogg' -o -name '*.wav' \) -printf '%p %s bytes\n' | sort
