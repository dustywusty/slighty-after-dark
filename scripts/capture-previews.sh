#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
workspace=$(CDPATH= cd -- "$script_directory/.." && pwd)
asset_root=${1:-"$workspace/after-dark-css"}
output_directory=${2:-"$workspace/docs/previews"}
width=${SAD_PREVIEW_WIDTH:-1024}
height=${SAD_PREVIEW_HEIGHT:-768}
frames_per_second=${SAD_PREVIEW_FPS:-25}

ffmpeg=${FFMPEG:-$(command -v ffmpeg || true)}
if [ -z "$ffmpeg" ]; then
    echo "error: ffmpeg is required to encode preview GIFs" >&2
    exit 1
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/slightly-after-dark-previews.XXXXXX")
trap '/bin/rm -rf "$temporary_directory"' EXIT INT TERM
frames_directory="$temporary_directory/frames"
gifs_directory="$temporary_directory/gifs"
/bin/mkdir -p "$frames_directory" "$gifs_directory"

xcrun swift "$script_directory/capture-previews.swift" \
    "$asset_root" \
    "$frames_directory" \
    "$width" \
    "$height" \
    "$frames_per_second"

for saver in \
    flying-toasters \
    fish \
    globe \
    hard-rain \
    bouncing-ball \
    warp \
    messages \
    messages2 \
    fade-out \
    logo \
    rainstorm \
    spotlight
do
    raw_gif="$temporary_directory/$saver.gif"
    final_gif="$gifs_directory/$saver.gif"
    "$ffmpeg" \
        -hide_banner \
        -loglevel error \
        -y \
        -framerate "$frames_per_second" \
        -i "$frames_directory/$saver/%04d.png" \
        -filter_complex \
        "[0:v]split[a][b];[a]palettegen=max_colors=128:reserve_transparent=0:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
        -loop 0 \
        "$raw_gif"

    if command -v gifsicle >/dev/null 2>&1; then
        gifsicle --optimize=3 --colors 128 "$raw_gif" -o "$final_gif"
    else
        /bin/mv "$raw_gif" "$final_gif"
    fi
    echo "Encoded $saver.gif"
done

/bin/mkdir -p "$output_directory"
for gif in "$gifs_directory"/*.gif
do
    /usr/bin/ditto "$gif" "$output_directory/$(basename "$gif")"
done

echo "Wrote previews to $output_directory"
/usr/bin/du -ch "$output_directory"/*.gif | tail -1
