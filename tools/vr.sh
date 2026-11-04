#!/bin/sh
# Run the game in VR from the source (OpenXR on: the active OpenXR runtime, e.g. SteamVR, starts
# with it; see docs/technical/vr.md). Extra arguments go to Godot.
#   tools/vr.sh [godot arguments...]
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"

exec "$GODOT4_EDITOR" --path . --xr-mode on "$@"
