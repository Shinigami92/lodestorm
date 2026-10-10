#!/bin/sh
# Check formatting and lint all GDScript; excluded directories are set in gdformatrc / gdlintrc.
set -u
cd "$(dirname "$0")/.."

status=0
gdformat --check . || status=1
gdlint . || status=1
exit $status
