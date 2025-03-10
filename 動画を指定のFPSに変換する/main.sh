#!/bin/env zsh

# shellcheck disable=SC1090
source ~/.zshrc

# 引数 =======================================================
# $1 = ファイルパス
# $2 = FPS（数字）

# ファイル引数の分解
readonly FILE="$1"
readonly DIR="${FILE%/*}"
readonly BASE="${FILE##*/}"
readonly EXT="${FILE##*.}"
readonly STEM="${FILE%.*}"
echo -e "F=${FILE}\nD=${DIR}\nB=${BASE}\nE=${EXT}\nS=${STEM}"

# MAIN =======================================================

ffmpeg -i "${FILE}" -r "${2}" \
  -c:v h264_videotoolbox \
  "${STEM}-fps${2}.${EXT}"