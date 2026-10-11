#!/bin/sh
# Run a Blender Python script headless, e.g. an asset's build or bake script:
#   tools/blender.sh assets/miners/source/miner_glow_build.py final
# Arguments after the script are passed to it (after Blender's "--").
set -eu
cd "$(dirname "$0")/.."
: "${BLENDER:?set BLENDER to the Blender executable}"
script="$1"
shift
exec "$BLENDER" --background --factory-startup --python "$script" -- "$@"
