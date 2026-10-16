#!/bin/sh
# Check formatting and lint: GDScript (gdformat, gdlint) and Python (ruff), or only one of them:
#   tools/lint.sh [gdscript|python]
# Excluded directories are set in gdformatrc / gdlintrc; ruff (ruff.toml) skips what git ignores.
set -u
cd "$(dirname "$0")/.."

status=0
lint_gdscript() {
	gdformat --check . || status=1
	gdlint . || status=1
}
lint_python() {
	ruff format --check . || status=1
	ruff check . || status=1
	# Generated scenes must match their generator
	python game/ship/hull_build.py --check || status=1
}

case "${1:-all}" in
all)
	lint_gdscript
	lint_python
	;;
gdscript) lint_gdscript ;;
python) lint_python ;;
*)
	echo "usage: tools/lint.sh [gdscript|python]" >&2
	exit 2
	;;
esac
exit $status
