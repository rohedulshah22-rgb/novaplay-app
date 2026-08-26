#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p assets/icons
rsvg-convert -w 1024 -h 1024 assets/icons/app_icon.svg -o assets/icons/app_icon.png
rsvg-convert -w 1024 -h 1024 assets/icons/play_foreground.svg -o assets/icons/play_foreground.png
