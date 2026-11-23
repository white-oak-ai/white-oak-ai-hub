#!/usr/bin/env bash
# Check the file mode git records for every shell script. Scripts are run directly,
# so they must be executable (100755). Files starting with "_" are libraries that
# are only sourced, so they must not be (100644).
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
fail=0
while read -r mode _ _ path; do
  if [[ "$(basename "$path")" == _* ]]; then
    want=100644; fix="-x"
  else
    want=100755; fix="+x"
  fi
  if [[ "$mode" != "$want" ]]; then
    echo "✗ $path is $mode, should be $want. Fix: git update-index --chmod=$fix $path"
    fail=1
  fi
done < <(git ls-files -s -- '*.sh')

(( fail )) || echo "✓ all shell scripts have the right mode"
exit $fail
