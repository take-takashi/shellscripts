#!/bin/env zsh

# shellcheck disable=SC1090
source ~/.zshrc

# shwordsplit オプションを有効化（zshのみ）
# setopt shwordsplit

# 引数 =========================================================================
# $1 = ファイルパス
# $2 = 何GBごとに分割するか（例：4.8 とすると4.8GB）

INPUT="$1"
SPLIT_SIZE="$2"

# 引数の分解
readonly FILE="$1"
readonly DIR="${FILE%/*}"
readonly BASE="${FILE##*/}"
readonly EXT="${FILE##*.}"
readonly STEM="${FILE%.*}"
echo -e "file=${FILE}\ndir=${DIR}\nbase=${BASE}\next=${EXT}\nstem=${STEM}"

################################################################################
# 動画ファイルのタイムコードを取得する関数
# Globals:
# Arguments:
#   $1: ファイルパス
# Outputs:
#   タイムコード（例：12:28:33;42）
################################################################################
fn_get_timecode() {
  local file="$1"
  # ffprobeで元のタイムコードを取得
  local timecode
  timecode=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream_tags=timecode -of default=nw=1:nk=1 "${file}")
  echo "${timecode}"
}
TIMECODE=$(fn_get_timecode "$INPUT")
echo "元のタイムコード: ${TIMECODE}"


################################################################################
# HH:MM:SS:FF形式の文字列を秒に変換する関数
# Globals:
# Arguments:
#   $1: 時刻（HH:MM:SS:FF形式も文字列）
#   $2: FPS
# Outputs:
#   FPS（整数）
################################################################################
fn_time2sec() {

  local old_ifs=$IFS
  IFS=":;" read -r hour minute second frame <<< "$1"

  if [ -z "$frame" ]; then
    frame=0
  fi
  local total
  total=$(echo "$hour*3600 + $minute*60 + $second + $frame/$FRAMERATE" | bc -l)
  IFS=$old_ifs
  echo "${total}"
}


################################################################################
# 秒数（浮動小数点）をタイムコード(HH:MM:SS:FF)形式に変換する関数
# Globals:
# Arguments:
#   $1: ファイルパス
#   $2: FPS（整数）
# Outputs:
#   タイムコード（HH:MM:SS:FF）
################################################################################
fn_sec2time() {
  local total="$1"
  local fps; fps="$2"
  local hours; hours=$(echo "$total/3600" | bc -l | awk '{print int($1)}')
  local rem; rem=$(echo "$total - ($hours * 3600)" | bc -l)
  local minutes; minutes=$(echo "$rem/60" | bc -l | awk '{print int($1)}')
  rem=$(echo "$rem - ($minutes * 60)" | bc -l)
  local seconds; seconds=$(echo "$rem" | bc -l | awk '{print int($1)}')
  local fractional
  fractional=$(echo "$total - ($hours*3600 + $minutes*60 + $seconds)" | bc -l)
  local subsec
  subsec=$(echo "$fractional * $fps" | bc -l | awk '{print int($1)}')
  printf "%02d:%02d:%02d.%03d" "$hours" "$minutes" "$seconds" "$subsec"
}


################################################################################
# 指定した動画ファイルの平均ビットレートを取得
# ffprobeでビットレート情報を取得できればその値を返す
# 取得できなければ、ファイルサイズと再生時間から計算する
# Globals:
# Arguments:
#   $1: ファイルパス
# Outputs:
#   ビットレートbps（ビット毎秒）
################################################################################
fn_get_avg_bitrate() {
  local file="$1"

  # ファイル存在チェック -------------------------------------------------------
  if [ ! -f "$file" ]; then
    echo "Error: File not found: $file" >&2
    return 1
  fi

  # ffprobeで全体のビットレートを取得（映像、音声などすべてのストリームを含む）
  local bitrate; bitrate=$(ffprobe -v error -show_entries format=bit_rate \
    -of default=noprint_wrappers=1:nokey=1 "$file")
  # ビットレート情報が取得できなかった場合、計算に切り替え
  if [ -z "$bitrate" ]; then
    echo "Bitrate info not found, calculating using file size and duration." >&2

    # ffprobeで再生時間を取得
    local duration; duration=$(ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "$file")
    if [ -z "$duration" ] || [ "$duration" = "0" ]; then
      echo "Error: Unable to determine duration for file: $file" >&2
      return 1
    fi
    # wc -c でファイルサイズ（バイト単位）を取得
    local size; size=$(wc -c < "$file")
    # 平均ビットレートの計算： (ファイルサイズ[バイト] × 8) / 再生時間[秒]
    bitrate=$(echo "scale=0; ($size * 8) / $duration" | bc)
  fi

  echo "${bitrate}"
}
AVG_BITRATE=$(fn_get_avg_bitrate "$INPUT")
echo "平均ビットレート: ${AVG_BITRATE} bps"


################################################################################
# mp4動画の再生時間（秒）を取得する関数
# Globals:
# Arguments:
#   $1: ファイルパス
# Outputs:
#   再生時間（秒）
################################################################################
fn_get_duration() {
  local file="$1"

  # ファイルの存在チェック -----------------------------------------------------
  if [ ! -f "$file" ]; then
    echo "Error: ファイルが存在しません: $file" >&2
    return 1
  fi

  # ffprobeを用いて再生時間を取得
  local duration; duration=$(ffprobe -v error -select_streams v:0 \
    -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \
    "$file")

  if [ -z "$duration" ]; then
    echo "Error: 再生時間を取得できませんでした: $file" >&2
    return 1
  fi

  echo "${duration}"
}
DURATION=$(fn_get_duration "$INPUT")
echo "再生時間: ${DURATION} 秒"


################################################################################
# 動画を指定したGB数ごとに分割するための秒数を求める関数
# Globals:
# Arguments:
#   $1: 平均ビットレート (bps)
#   $2: 動画の総再生時間 (秒、少数可)
#   $3: 分割したいサイズ (GB、少数可)
# Outputs:
#   分割すべき秒数をスペース区切りの文字列で出力する
################################################################################
fn_get_split_points() {
  local bitrate="$1"
  local duration="$2"
  local split_gb="$3"

  # 分割サイズ（GB）をバイトに変換し、ビットに換算（awkで少数計算）
  local target_bits
  target_bits=$(awk -v \
    gb="$split_gb" 'BEGIN { printf "%.0f", gb * 1024 * 1024 * 1024 * 8 }')

  # セグメントごとの秒数を計算（浮動小数点数として計算、6桁の小数として出力）
  local seg
  seg=$(awk -v tb="$target_bits" \
    -v bitrate="$bitrate" 'BEGIN { printf "%.6f", tb / bitrate }')

  # segが0以下の場合は空文字を返す
  if [ "$(echo "$seg <= 0" | bc -l)" -eq 1 ]; then
    echo ""
    return
  fi

  # awkを用いて、durationまでの各分割時刻を計算
  local splits
  splits=$(awk -v seg="$seg" -v duration="$duration" 'BEGIN {
    t = seg;
    s = "";
    while (t < duration) {
      s = s sprintf("%.6f", t) " ";
      t += seg;
    }
    sub(/[ \t]+$/, "", s);
    print s;
  }')

  echo "${splits}"
}
SPLIT_POINTS=$(fn_get_split_points "$AVG_BITRATE" "$DURATION" "$SPLIT_SIZE")
echo "分割秒数: $SPLIT_POINTS"


################################################################################
# ffprobeでFPSを取得し、整数に四捨五入して返す関数
# Globals:
# Arguments:
#   $1: ファイルパス
# Outputs:
#   FPS（整数）
################################################################################
fn_get_fps() {
  local file="$1"
  local fps_raw; fps_raw=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$file")
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
FRAMERATE=$(fn_get_fps "$INPUT")
echo "Using frame rate: ${FRAMERATE} fps"


################################################################################
# 指定の時間から近いキーフレーム数を返す関数
# Globals:
# Arguments:
#   $1: ファイルパス
#   $2: シークしたい時刻（秒）
#   $3 = シーク開始から何秒前からキーフレームを探すか（秒）：デフォルトは10秒
# Outputs:
#   シークしたい時刻以下で最大のキーフレームのタイムスタンプ（秒）
################################################################################
fn_get_seek_keyframe() {
  setopt localoptions
  setopt shwordsplit
  local file="$1"
  local desired_sec="$2"
  local before_sec="${3:-10}"
  local read_sec; read_sec=$(echo "$before_sec * 2" | bc -l)
  local start_sec; start_sec=$(echo "$desired_sec - $before_sec" | bc -l)
  local keyframes

  keyframes=$(ffprobe -v error -i "$file"\
    -skip_frame nokey \
    -read_intervals "${start_sec}%+${read_sec}" \
    -select_streams v:0 \
    -show_frames -show_entries frame=pts_time -of compact=p=0:nk=1)

  # 指定時刻以下の最大のタイムスタンプ（シーク時に選ばれるキーフレーム）を求める
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


# タイムコードが存在する場合、オフセットを計算して分割後の動画に付与する
if [ "${TIMECODE}" != "" ]; then
  # タイムコードが空でない場合の処理
  # タイムコードを秒に変換
  TIMECODE_SEC=$(fn_time2sec "${TIMECODE}" "${FRAMERATE}")
  echo "元のタイムコードを秒に変換: ${TIMECODE_SEC} 秒"
fi

################################################################################
# MAIN
################################################################################
# 分割秒数ごとに一番近いキーフレームに変換する
# ${(z)SPLIT_POINTS} でスペース区切りの変数を配列に変換
SPLIT_KEYFRAMES=(0) # 配列（最初のINDEXに0秒を入れる）
# shellcheck disable=SC2296
for split_point in ${(z)SPLIT_POINTS}; do
  echo "分割秒数: $split_point"
  keyframe=$(fn_get_seek_keyframe "${INPUT}" "${split_point}")
  echo "最も近いキーフレームのタイムスタンプ: $keyframe 秒へ変換"
  echo "---"
  SPLIT_KEYFRAMES+=("${keyframe}")
done

# 分割キーフレームを使って動画を分割する
for ((i=1; i <= ${#SPLIT_KEYFRAMES[@]}; i++))
do
  start_time="${SPLIT_KEYFRAMES[i]}"
  end_time="${SPLIT_KEYFRAMES[i+1]}"

  output="${STEM}-part${i}.${EXT}"
  echo "分割${i}: ${start_time}秒 から ${end_time}秒 まで (${duration}秒)"
  echo "出力: ${output}"

  # タイムコードが存在する場合、オフセットを計算
    if [ -n "${TIMECODE_SEC}" ]; then
      timecode_add=$(echo "${start_time} + ${TIMECODE_SEC}" | bc)
      added_timecode=$(fn_sec2time "${timecode_add}" "${FRAMERATE}")
      echo "オフセットを加算: ${start_time} 秒"
    fi

  # end_timeが考慮して分割するかどうか
  if [ -n "$end_time" ]; then
    # end_timeが取得できた場合
    duration=$(echo "${end_time} - ${start_time}" | bc)
    echo "duration: ${duration}"

    # タイムコードを考慮して分割するかどうか
    if [ -n "${TIMECODE_SEC}" ]; then
      ffmpeg -ss "${start_time}" -i "${INPUT}" \
        -t "${duration}" -reset_timestamps 1 \
        -timecode "${added_timecode}" -c copy "${output}"
    else
      ffmpeg -ss "${start_time}" -i "${INPUT}" \
        -t "${duration}" -reset_timestamps 1 -c copy "${output}"
    fi

  # end_timeが取得できなかった場合は最後まで分割
  else
    # タイムコードを考慮して分割するかどうか
    if [ -n "${TIMECODE_SEC}" ]; then
      ffmpeg -ss "${start_time}" -i "${INPUT}" \
        -reset_timestamps 1 -timecode "${added_timecode}" -c copy "${output}"
    else
      ffmpeg -ss "${start_time}" -i "${INPUT}" \
        -reset_timestamps 1 -c copy "${output}"
    fi
  fi
done

echo "終了"

exit 0