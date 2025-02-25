#!/bin/env bash

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
SEC=$(fn_time2sec "00:00:01:00" "60")
echo "SEC: ${SEC}"


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
echo "変換後の抽出開始時刻: $(fn_sec2time "10.010" "60")"