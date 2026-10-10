#!/bin/sh
# Import the project, then run the GUT unit tests headless (config: .gutconfig.json).
# Extra arguments go to GUT, e.g. -gselect=test_foo.gd
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"

# Import check: a fresh checkout has no import cache or global class list yet, and broken
# assets (e.g. LFS pointers instead of files) only show up as errors in the output
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
"$GODOT4_EDITOR" --headless --import 2>&1 | tee "$log"
if grep -q "ERROR" "$log"; then
	echo "Import failed: see errors above" >&2
	exit 1
fi

"$GODOT4_EDITOR" --headless -s addons/gut/gut_cmdln.gd "$@"
