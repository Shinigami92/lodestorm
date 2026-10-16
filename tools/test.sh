#!/bin/sh
# Import the project, then run the GUT unit tests headless (config: .gutconfig.json).
# Godot runs with a fixed frame rate (the physics tick rate), so simulated time doesn't wait for the
# wall clock: waiting for seconds or physics frames only takes as long as computing the frames.
# Without arguments, the test scripts are split round-robin over TEST_JOBS Godot processes
# (default 4) running in parallel; each one's output is printed once all are done.
# Extra arguments go to GUT in a single process instead, e.g. -gselect=test_foo.gd
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"

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

tools/import.sh

if [ $# -gt 0 ]; then
	gut "$@"
	exit
fi

jobs="${TEST_JOBS:-4}"
logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT
scripts="$(grep -rl --include='test_*.gd' '^extends GutTest' tests | sort)"

echo "Running the tests in $jobs processes..."
processes=""
i=0
while [ "$i" -lt "$jobs" ]; do
	# -gdir= drops the config's test directory, so only the -gtest scripts run
	selected="$(echo "$scripts" | awk -v n="$jobs" -v i="$i" \
		'NR % n == i { printf "%sres://%s", sep, $0; sep = "," }')"
	gut -gdir= -gtest="$selected" >"$logs/$i.log" 2>&1 &
	processes="$processes $!"
	i=$((i + 1))
done

status=0
i=0
for pid in $processes; do
	i=$((i + 1))
	if wait "$pid"; then
		group "Tests $i/$jobs: passed"
		cat "$logs/$((i - 1)).log"
		group_end
	else
		# Left expanded, so the failure is visible right away
		echo "=== Tests $i/$jobs: FAILED"
		cat "$logs/$((i - 1)).log"
		status=1
	fi
done
exit $status
