#!/bin/sh
# Import the project, then run the GUT unit tests headless (config: .gutconfig.json).
# Extra arguments go to GUT, e.g. -gselect=test_foo.gd
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"

tools/import.sh
"$GODOT4_EDITOR" --headless -s addons/gut/gut_cmdln.gd "$@"
