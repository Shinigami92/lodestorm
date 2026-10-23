#!/bin/sh
# Import the project, then run the GUT unit tests headless (config: .gutconfig.json).
# Godot runs with a fixed frame rate (the physics tick rate), so simulated time doesn't wait for the
# wall clock: waiting for seconds or physics frames only takes as long as computing the frames.
# Without arguments, the test scripts are spread over TEST_JOBS Godot processes (default 4)
# running in parallel; each one's output is printed once all are done. TEST_SHARD=k/n runs only
# the k-th of n shares (CI runs the shares on separate runners). The scripts are balanced by their
# durations in tests/timings.txt, longest first (tools/timings.sh rewrites it). TEST_REPORTS=<dir>
# keeps each process's GUT JUnit report there (relative to the project).
# Extra arguments go to GUT in a single process instead, e.g. -gselect=test_foo.gd
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"
export LC_ALL=C

gut() {
	"$GODOT4_EDITOR" --headless --fixed-fps 60 -s addons/gut/gut_cmdln.gd "$@"
}

# Collapsible sections in the GitHub Actions log
group() {
	if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::group::$1"; else echo "=== $1"; fi
}
group_end() {
	if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::endgroup::"; fi
}

jobs="${TEST_JOBS:-4}"
shard="${TEST_SHARD:-1/1}"
shard_index="${shard%%/*}"
shard_count="${shard#*/}"
case "$jobs-$shard_index-$shard_count" in
*[!0-9-]* | -* | *--* | *-) shard_index=0 ;;
esac
if [ "$shard_index" -lt 1 ] || [ "$shard_index" -gt "$shard_count" ] || [ "$jobs" -lt 1 ]; then
	echo "TEST_JOBS must be a positive number and TEST_SHARD k/n with 1 <= k <= n" >&2
	exit 2
fi
timings=tests/timings.txt

tools/import.sh

if [ $# -gt 0 ]; then
	gut "$@"
	exit
fi

logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT
# The scripts GUT runs from .gutconfig.json: every test_*.gd under tests/, whatever it extends
scripts="$(find tests -name 'test_*.gd' | sort)"

# Longest first, each to the process with the least work so far, over the processes of all shards
# (scripts missing from the timings count as 10 s). Prints "<process> <script>".
balance() {
	{
		if [ -f "$timings" ]; then grep -v '^#' "$timings"; fi
		echo "$scripts" | sed 's/^/? /'
	} | awk '$1 != "?" { seconds[$2] = $1; next } { print ($2 in seconds ? seconds[$2] : 10), $2 }' |
		sort -k1,1nr -k2,2 |
		awk -v n="$1" '{
			best = 0
			for (i = 1; i < n; i++) if (load[i] < load[best]) best = i
			load[best] += $1
			print best, $2
		}'
}
assigned="$(balance $((jobs * shard_count)))"

if [ "$shard_count" -gt 1 ]; then
	echo "Running shard $shard of the tests in $jobs processes..."
else
	echo "Running the tests in $jobs processes..."
fi
processes=""
i=0
while [ "$i" -lt "$jobs" ]; do
	process=$(((shard_index - 1) * jobs + i))
	selected="$(echo "$assigned" | awk -v p="$process" \
		'$1 == p { printf "%sres://%s", sep, $2; sep = "," }')"
	if [ -n "$selected" ]; then
		# -gdir= drops the config's test directory, so only the -gtest scripts run
		gut -gdir= -gtest="$selected" -gjunit_xml_file="$logs/$i.xml" >"$logs/$i.log" 2>&1 &
		processes="$processes $i:$!"
	fi
	i=$((i + 1))
done

status=0
for entry in $processes; do
	i="${entry%%:*}"
	if wait "${entry#*:}"; then
		group "Tests $((i + 1))/$jobs: passed"
		cat "$logs/$i.log"
		group_end
	else
		# Left expanded, so the failure is visible right away
		echo "=== Tests $((i + 1))/$jobs: FAILED"
		cat "$logs/$i.log"
		status=1
	fi
done

if [ -n "${TEST_REPORTS:-}" ]; then
	mkdir -p "$TEST_REPORTS"
	for report in "$logs"/*.xml; do
		if [ -f "$report" ]; then cp "$report" "$TEST_REPORTS/shard$shard_index-$(basename "$report")"; fi
	done
fi
exit $status
