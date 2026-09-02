#!/usr/bin/env bash
set -euo pipefail

production_root="${PRODUCTION_ROOT:-/home/ubuntu/webdev-static-assets/proto-td-act2}"
repository_root="${REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
master_root="$production_root/music-masters"
out_root="$repository_root/assets/music/lunaris/act2"
mkdir -p "$out_root"

loopify() {
  local id="$1" target_lufs="$2" crossfade="${3:-4.0}" post_gain="${4:-0.0}"
  local input="$master_root/${id}.master.wav"
  local output="$out_root/${id}.ogg"
  local duration body_end
  duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input")
  body_end=$(printf '%s-%s\n' "$duration" "$crossfade" | bc)
  ffmpeg -hide_banner -loglevel error -y -i "$input" \
    -filter_complex "[0:a]loudnorm=I=${target_lufs}:LRA=9:TP=-2,aresample=48000,asplit=3[headsrc][bodysrc][tailsrc];[headsrc]atrim=start=0:end=${crossfade},asetpts=PTS-STARTPTS[head];[bodysrc]atrim=start=${crossfade}:end=${body_end},asetpts=PTS-STARTPTS[body];[tailsrc]atrim=start=${body_end}:end=${duration},asetpts=PTS-STARTPTS[tail];[tail][head]acrossfade=d=${crossfade}:c1=tri:c2=tri[wrap];[body][wrap]concat=n=2:v=0:a=1,volume=${post_gain}dB,alimiter=limit=0.794:level=false[out]" \
    -map "[out]" -ar 48000 -ac 2 -c:a libvorbis -q:a 5 "$output"
}

loopify s09_return_path -21.0
loopify s10_covenant_orchard -21.0

printf '%s\n' 'Act II runtime score:'
for output in "$out_root"/*.ogg; do
  printf '%s\t' "$output"
  ffprobe -v error -show_entries stream=codec_name,sample_rate,channels -show_entries format=duration,size -of compact=p=0:nk=1 "$output"
done
