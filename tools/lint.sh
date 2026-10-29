#!/bin/sh
# Check formatting and lint: GDScript (gdformat, gdlint) and Python (ruff), or only one of them:
#   tools/lint.sh [gdscript|python]
# Excluded directories are set in gdformatrc / gdlintrc; ruff (ruff.toml) skips what git ignores.
# The last line names every check that failed ("lint: FAILED (gdformat, ruff check)") or says
# "lint: passed"; the exit code is non-zero when one failed.
set -u
cd "$(dirname "$0")/.."

failed=""
# Runs a check (its name, then the command) and remembers it when it fails.
check() {
	name="$1"
	shift
	"$@" || failed="${failed:+$failed, }$name"
}
lint_gdscript() {
	check gdformat gdformat --check .
	check gdlint gdlint .
}
lint_python() {
	check "ruff format" ruff format --check .
	check "ruff check" ruff check .
	# Generated scenes must match their generator
	check hull_build python game/ship/hull_build.py --check
	check ostra_build python game/space_station/ostra/ostra_build.py --check
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
if [ -n "$failed" ]; then
	echo "lint: FAILED ($failed)"
	exit 1
fi
echo "lint: passed"
