#!/bin/sh
# Rewrite tests/timings.txt, the seconds each test script takes, which tools/test.sh balances the
# scripts by. From GUT JUnit reports: directories of them (TEST_REPORTS=<dir> tools/test.sh), or
# the reports CI runs uploaded, by their run IDs, or, without an argument, the latest three
# successful CI runs on main (needs the GitHub CLI, gh). CI's numbers fit CI's runners best.
# A script's time is its mean over the runs it's in: one run's times swing a lot with what shares
# its runner. Scripts that no longer exist are left out.
set -eu
cd "$(dirname "$0")/.."
export LC_ALL=C

if [ "$#" -eq 0 ]; then
	# One run ID per word
	set -- $(gh run list --workflow ci.yml --branch main --status success --limit 3 \
		--json databaseId --jq '.[].databaseId')
fi
downloads="$(mktemp -d)"
trap 'rm -rf "$downloads"' EXIT
reports=""
for source in "$@"; do
	if [ -d "$source" ]; then
		reports="$reports $source"
	else
		echo "Downloading the test reports of CI run $source..."
		gh run download "$source" --pattern 'test-reports-*' --dir "$downloads/$source"
		reports="$reports $downloads/$source"
	fi
done

# A <testsuite> per script; GUT leaves out the time of before_all and after_all
# (unquoted: one directory per word)
timings="$(find $reports -name '*.xml' -exec cat {} + |
	sed -n 's/.*<testsuite name="\([^"]*\)".* time="\([0-9.]*\)".*/\2 \1/p' |
	awk '{ sum[$2] += $1; runs[$2]++ } END { for (s in sum) printf "%.1f %s\n", sum[s] / runs[s], s }' |
	while read -r seconds script; do
		if [ -f "$script" ]; then echo "$seconds $script"; fi
	done | sort -k1,1nr -k2,2)"
if [ -z "$timings" ]; then
	echo "No test reports in $*" >&2
	exit 1
fi
{
	echo "# Seconds each test script takes in a run of tools/test.sh, which balances the scripts by"
	echo "# them (the mean over $# runs). Written by tools/timings.sh."
	echo "$timings"
} >tests/timings.txt
echo "Wrote tests/timings.txt ($(echo "$timings" | wc -l | tr -d ' ') scripts, $# runs)"
