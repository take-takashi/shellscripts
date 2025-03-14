#!/bin/env zsh

# shellcheck disable=SC1090
source ~/.zshrc

FILE="$1"
DEVICE="$2"

ffmpeg -hide_banner \
  -f avfoundation \
  -capture_cursor 1 \
  -capture_mouse_clicks 1 \
  -i "${DEVICE}" \
  -c:v h264_videotoolbox \
  -r 10 \
  -y "${FILE}"