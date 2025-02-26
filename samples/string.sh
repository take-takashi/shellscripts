#!/bin/env zsh

fn_try_HHMMSSFF() {
  local time="$1"

  IFS=":;" read -r hh mm ss ff <<< "$time"

  if [ -z "$ff" ]; then
    ff=0
  fi

  local total
  total=$(echo "$hh*3600 + $mm*60 + $ss + $ff" | bc -l)

  echo "${total}"
}
echo "fn_try_HHMMSSFF: $(fn_try_HHMMSSFF '01:02:03:04')"

exit 0