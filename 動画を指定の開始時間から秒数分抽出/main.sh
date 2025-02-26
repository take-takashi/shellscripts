#!/bin/env zsh

# shellcheck disable=SC1090
source ~/.zshrc

# 引数 =======================================================
# $1 = ファイルパス
# $2 = 開始時間（HH:MM:SS）
# $3 = 秒数（S）

# ファイル引数の分解
readonly FILE="$1"
readonly DIR="${FILE%/*}"
readonly BASE="${FILE##*/}"
readonly EXT="${FILE##*.}"
readonly STEM="${FILE%.*}"
echo -e "F=${FILE}\nD=${DIR}\nB=${BASE}\nE=${EXT}\nS=${STEM}"

# MAIN =======================================================
# 処理概要
# - タイムコードを取得を試みる
# - 抽出開始秒数から最も近いキーフレームを取得
# - 抽出開始予定のキーフレームの秒数分、タイムコードを進める
# - 動画をカットする際にタイムコードを付与する（あれば）

# 抽出開始の時刻をファイル名に利用できる文字列へ変換
CUT_TIME="$2"
SEC="$3"
FILE_TIME=$(echo "$CUT_TIME" | sed 's/:/h/;s/:/m/;s/$/s/')
OUTPUT=${STEM}-${FILE_TIME}-${SEC}s.${EXT}


##############################################################
# ffprobeでFPSを取得し、整数に四捨五入して返す関数
# Globals:
# Arguments:
#   $1: ファイルパス
# Outputs:
#   FPS（整数）
##############################################################
fn_get_fps() {
  local file="$1"
  local fps_raw;
  fps_raw=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=r_frame_rate \
    -of default=nw=1:nk=1 "$file")
  local fps_float
  if [[ "$fps_raw" == *"/"* ]]; then
    local num; num=$(echo "$fps_raw" | cut -d'/' -f1)
    local denom; denom=$(echo "$fps_raw" | cut -d'/' -f2)
    fps_float=$(echo "scale=4; $num / $denom" | bc -l)
  else
    fps_float="$fps_raw"
  fi
  # 四捨五入して整数に変換
  local fps_int; fps_int=$(printf "%.0f" "$fps_float")
  echo "${fps_int}"
}
FRAMERATE=$(fn_get_fps "$FILE")
echo "Using frame rate: ${FRAMERATE} fps"


##############################################################
# HH:MM:SS:FF形式の文字列を秒に変換する関数
# Globals:
# Arguments:
#   $1: 時刻（HH:MM:SS:FF形式も文字列）
#   $2: FPS
# Outputs:
#   FPS（整数）
##############################################################
fn_time2sec() {
  local time="$1"
  local fps="$2"

  IFS=":;" read -r hh mm ss ff <<< "$time"

  if [ -z "$ff" ]; then
    ff=0
  fi
  local total
  total=$(echo "$hh*3600 + $mm*60 + $ss + $ff/$fps" | bc -l)

  echo "${total}"
}
CUT_TIME_SEC=$(fn_time2sec "$CUT_TIME" "$FRAMERATE")
echo "カット開始時刻（秒）: ${CUT_TIME_SEC}"


##############################################################
# 秒数（小数）をタイムコード(HH:MM:SS:FF)形式に変換する関数
# Globals:
# Arguments:
#   $1: 秒数
#   $2: FPS（整数）
# Outputs:
#   タイムコード（HH:MM:SS.sss）
##############################################################
fn_sec2time() {
  local sec="$1"
  local fps="$2"
  local hh
  hh=$(echo "$sec/3600" | bc -l | awk '{print int($1)}')
  local rem
  rem=$(echo "$sec - ($hh * 3600)" | bc -l)
  local mm
  mm=$(echo "$rem/60" | bc -l | awk '{print int($1)}')
  rem=$(echo "$rem - ($mm * 60)" | bc -l)
  local ss
  ss=$(echo "$rem" | bc -l | awk '{print int($1)}')
  local ff
  ff=$(echo "$sec - ($hh*3600 + $mm*60 + $ss)" | bc -l)
  local subsec
  subsec=$(echo "$ff * $fps" | bc -l | awk '{print int($1)}')
  printf "%02d:%02d:%02d.%03d" "$hh" "$mm" "$ss" "$subsec"
}


##############################################################
# 動画ファイルのタイムコードを取得する関数
# Globals:
# Arguments:
#   $1: ファイルパス
# Outputs:
#   タイムコード（例：12:28:33;42）
##############################################################
fn_get_timecode() {
  local file="$1"
  # ffprobeで元のタイムコードを取得
  local timecode
  timecode=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream_tags=timecode \
    -of default=nw=1:nk=1 "${file}")
  echo "${timecode}"
}
TIMECODE=$(fn_get_timecode "$FILE")
echo "元のタイムコード: ${TIMECODE}"

# タイムコードが取得できれば、秒数に変換
if [ "${TIMECODE}" != "" ]; then
  TIMECODE_SEC=$(fn_time2sec "$TIMECODE" "$FRAMERATE")
  echo "元のタイムコード（秒）: ${TIMECODE_SEC}"
fi

##############################################################
# 指定の時間から近いキーフレーム数を返す関数
# Globals:
# Arguments:
#   $1: ファイルパス
#   $2: シークしたい時刻（秒）
#   $3: シーク開始から何秒前からキーフレームを探すか（秒）
#       デフォルトは10秒
# Outputs:
#   シークしたい時刻で最大キーフレームのタイムスタンプ（秒）
##############################################################
fn_get_seek_keyframe() {
  setopt localoptions
  setopt shwordsplit
  local file="$1"
  local desired_sec="$2"
  local before_sec="${3:-10}"
  local read_sec
  read_sec=$(echo "$before_sec * 2" | bc -l)
  local start_sec
  start_sec=$(echo "$desired_sec - $before_sec" | bc -l)
  local keyframes

  keyframes=$(ffprobe -v error -i "$file"\
    -skip_frame nokey \
    -read_intervals "${start_sec}%+${read_sec}" \
    -select_streams v:0 \
    -show_frames -show_entries \
    frame=pts_time -of compact=p=0:nk=1)

  # 指定時刻以下の最大のタイムスタンプを求める
  local selected_frame=0
  local OLD_IFS=$IFS
  IFS=$'\n'
  local t
  for t in $keyframes; do
    # t が desired_sec 以下なら更新
    if (( $(echo "$t <= ${desired_sec}" | bc -l) )); then
      selected_frame=$t
    else
      break
    fi
  done
  IFS=$OLD_IFS

  echo "${selected_frame}"
}
CUT_FRAME_SEC=$(fn_get_seek_keyframe "$FILE" "$CUT_TIME_SEC")

# タイムコードが取得できていれば、カット開始時刻を進める
if [ "${TIMECODE_SEC}" != "" ]; then
  ADDED_TIMECODE_SEC=$(echo "$CUT_FRAME_SEC + $TIMECODE_SEC" \
  | bc -l)
  echo "加算したタイムコード（秒）: ${ADDED_TIMECODE_SEC}"
  ADDED_TIMECODE=$( \
    fn_sec2time "${ADDED_TIMECODE_SEC}" "${FRAMERATE}")
  echo "加算したタイムコード（HH:MM:SS）: ${ADDED_TIMECODE}"
fi

# タイムコードの有無でコマンドを変更
if [ "${ADDED_TIMECODE}" != "" ]; then
  ffmpeg -ss "${CUT_FRAME_SEC}" -i "${FILE}" \
  -t "${SEC}" -reset_timestamps 1 \
  -timecode "${ADDED_TIMECODE}" \
  -c copy "${OUTPUT}"
else
  ffmpeg -ss "${CUT_FRAME_SEC}" -i "${FILE}" \
  -t "${SEC}" -reset_timestamps 1 \
  -c copy "${OUTPUT}"
fi

echo "終了"

exit 0