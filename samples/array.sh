#!/bin/env zsh

##############################################################
# 配列を初期化して定義する
# Globals:
# Arguments:
#   None
# Outputs:
#   None
##############################################################
fn_try_array01() {
  local array=(1 2 3 4 5)
  echo "array count: ${#array[@]}"
}
ARRAY01=$(fn_try_array01)
echo "array01: ${ARRAY01}"


##############################################################
# 文字列を配列に変換する
# Globals:
# Arguments:
#   None
# Outputs:
#   None
##############################################################
fn_try_array02() {

  local str="a b c d e"

  # 以下の方法だとzshでも文字列から配列に格納できる
  local array
  IFS=' ' read -r -A array <<< "${str}"
  local i
  for i in ${array}; do
    echo "i: ${i}"
  done
}
echo "array02: $(fn_try_array02)"

exit 0