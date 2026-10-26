#!/bin/sh

set -eu

asset_root=${1:-after-dark-css}

# README.md is also a version sentinel: the previously pinned 2014 checkout
# used README.markdown and lacks later responsive fixes.

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
    path="$asset_root/all/$saver.html"
    if [ ! -f "$path" ]; then
        echo "error: Missing screen saver asset: $path" >&2
        echo "Run: git submodule update --init --recursive" >&2
        exit 1
    fi
done

for path in \
    "$asset_root/README.md" \
    "$asset_root/all/base.css" \
    "$asset_root/fonts/ChicagoFLF.ttf" \
    "$asset_root/img/favicon.png" \
    "$asset_root/img/bubbles_50.png" \
    "$asset_root/img/fish-angel.png" \
    "$asset_root/img/fish-butterfly.png" \
    "$asset_root/img/fish-flounder.png" \
    "$asset_root/img/fish-guppy.png" \
    "$asset_root/img/fish-jelly.png" \
    "$asset_root/img/fish-minnow.png" \
    "$asset_root/img/fish-red.png" \
    "$asset_root/img/fish-seahorse.png" \
    "$asset_root/img/fish-striped.png" \
    "$asset_root/img/globe_240.jpg" \
    "$asset_root/img/logo.png" \
    "$asset_root/img/macos-desktop.png" \
    "$asset_root/img/rain-tile-distant.png" \
    "$asset_root/img/rain-tile-mid.png" \
    "$asset_root/img/rain-tile-near.png" \
    "$asset_root/img/seafloor.jpg" \
    "$asset_root/img/spotlight_bg.png" \
    "$asset_root/img/stars1.png" \
    "$asset_root/img/stars2.png" \
    "$asset_root/img/stars3.png" \
    "$asset_root/img/stars4.png" \
    "$asset_root/img/toast1.gif" \
    "$asset_root/img/toaster-sprite.gif"
do
    if [ ! -f "$path" ]; then
        echo "error: Missing referenced screen saver asset: $path" >&2
        echo "Run: git submodule update --init --recursive" >&2
        exit 1
    fi
done
