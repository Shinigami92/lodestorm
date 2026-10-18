#!/bin/sh
# Rewrite tests/timings.txt, the seconds each test script takes, which tools/test.sh balances the
# scripts by. From GUT JUnit reports: a directory of them (TEST_REPORTS=<dir> tools/test.sh), or
# the reports a CI run uploaded, by its run ID or, without an argument, the latest successful CI
# run on main (needs the GitHub CLI, gh). CI's numbers fit CI's runners best.
set -eu
cd "$(dirname "$0")/.."
export LC_ALL=C

source="${1:-}"
if [ -z "$source" ]; then
	source="$(gh run list --workflow ci.yml --branch main --status success --limit 1 \
		--json databaseId --jq '.[0].databaseId')"
fi
if [ -d "$source" ]; then
	reports="$source"
else
	reports="$(mktemp -d)"
	trap 'rm -rf "$reports"' EXIT
	echo "Downloading the test reports of CI run $source..."
	gh run download "$source" --pattern 'test-reports-*' --dir "$reports"
fi

# A <testsuite> per script; GUT leaves out the time of before_all and after_all
timings="$(find "$reports" -name '*.xml' -exec cat {} + |
	sed -n 's/.*<testsuite name="\([^"]*\)".* time="\([0-9.]*\)".*/\2 \1/p' |
	awk '{ printf "%.1f %s\n", $1, $2 }' | sort -k1,1nr -k2,2)"
if [ -z "$timings" ]; then
	echo "No test reports in $source" >&2
	exit 1
fi
{
	echo "# Seconds each test script takes in a run of tools/test.sh, which balances the scripts by"
	echo "# them. Written by tools/timings.sh."
	echo "$timings"
} >tests/timings.txt
echo "Wrote tests/timings.txt ($(echo "$timings" | wc -l | tr -d ' ') scripts)"
