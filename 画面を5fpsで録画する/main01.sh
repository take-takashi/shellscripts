#!/bin/env zsh

# shellcheck disable=SC1090
source ~/.zshrc

proc=$(ffmpeg -hide_banner \
  -f avfoundation \
  -list_devices true \
  -i "" 2>&1 | \
  awk '/AVFoundation video devices:/ {flag=1; next} /AVFoundation audio devices:/ {flag=0} flag' | \
  sed 's/^\[AVFoundation indev @ [^]]*\] //')

# プレフィックス行を追加してテキストとして出力
printf "result:\n%s\n" "$proc"