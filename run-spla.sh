#!/bin/bash
# Usage: bash run-spla.sh <spla tests dir>   (e.g. ~/spla/build-debug/tests)
TESTS=${1:-$HOME/spla/build-debug/tests}
BACKEND=${VENTUS_BACKEND:-spike}
WORK=$(mktemp -d)
cd "$WORK" || exit 1
for t in "$TESTS"/test_*; do
  [ -x "$t" ] || continue
  echo "===== $(basename "$t")"
  VENTUS_BACKEND=$BACKEND timeout --foreground 3600 "$t" < /dev/null 2>&1 \
    | grep -E "^\[ *(OK|PASSED|FAILED) *\]"
  rm -f ./*.log
done
rm -rf "$WORK"
