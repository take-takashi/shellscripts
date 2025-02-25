#!/bin/env bash

################################################################################
# Cleanup files from the backup directory.
# Globals:
# Arguments:
#   None
# Outputs:
#   None
################################################################################
fn_try_array01() {
  local array=(1 2 3 4 5)
  echo "array count: ${#array[@]}"
}
ARRAY01=$(fn_try_array01)
echo "array01: ${ARRAY01}"

exit 0