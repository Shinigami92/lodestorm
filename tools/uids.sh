#!/bin/sh
# Give every scene and resource its own UID and every reference in them the target's UID, as the
# editor does when it saves them (see tools/uids.gd). Run it after writing or patching .tscn/.tres
# files without the editor; tests/project/test_resource_uids.gd checks it.
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"

"$GODOT4_EDITOR" --headless -s tools/uids.gd
