#!/bin/sh
# Run a screenshot probe: a script extending tests/support/probe.gd that sets up a scene, plays it
# and saves screenshots (see tools/probe.gd and docs/technical/pitfalls.md, Screenshot probes).
#   tools/probe.sh [--headless] [--seconds N] <probe.gd> [probe arguments...]
# Screenshots go to $PROBE_OUT (default tmp/probe/); $PROBE_SCREEN picks the monitor of the window.
# The probe ends itself, or after N seconds (default 120) with exit code 124; the probe's own
# arguments reach it as `args`.
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"

headless=""
seconds=120
while [ $# -gt 0 ]; do
	case "$1" in
	--headless) headless="--headless" ;;
	--seconds)
		seconds="$2"
		shift
		;;
	*) break ;;
	esac
	shift
done
if [ $# -lt 1 ]; then
	echo "usage: tools/probe.sh [--headless] [--seconds N] <probe.gd> [probe arguments...]" >&2
	exit 2
fi
probe="$1"
shift
case "$probe" in
res://*) ;;
*) probe="res://${probe#./}" ;;
esac
out="${PROBE_OUT:-tmp/probe}"
mkdir -p "$out"

set -- --probe="$probe" --out="$out" --seconds="$seconds" "$@"
if [ -n "${PROBE_SCREEN:-}" ]; then
	set -- --screen "$PROBE_SCREEN" -- "$@"
else
	set -- -- "$@"
fi
# The loader's own watchdog ends a probe that stops waiting; timeout (where there is one) also
# ends one stuck in a loop, a little later.
if command -v timeout > /dev/null 2>&1; then
	exec timeout "$((seconds + 30))" "$GODOT4_EDITOR" $headless --path . -s tools/probe.gd "$@"
fi
exec "$GODOT4_EDITOR" $headless --path . -s tools/probe.gd "$@"
