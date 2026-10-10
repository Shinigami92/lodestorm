#!/bin/sh
# Run the GUT unit tests headless (config: .gutconfig.json). Extra arguments go to GUT, e.g. -gselect=test_foo.gd
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"

# A fresh checkout has no import cache or global class list yet
"$GODOT4_EDITOR" --headless --import
"$GODOT4_EDITOR" --headless -s addons/gut/gut_cmdln.gd "$@"
