#!/bin/sh
# Renders the voice lines of every voiced NPC (see tools/voice/render.py): tools/voice.sh [npc id ...] [--prune] [--dry-run]
# Needs the voice ComfyUI running (VOICE_COMFYUI_URL), VOICE_PYTHON, a Python with numpy and soundfile, and
# GODOT4_EDITOR (the game lists the lines).
set -e
cd "$(dirname "$0")/.."
if [ -z "$VOICE_PYTHON" ]; then
	echo "Set VOICE_PYTHON to a Python with numpy and soundfile (see docs/technical/voice.md)" >&2
	exit 1
fi
PYTHONUTF8=1 exec "$VOICE_PYTHON" tools/voice/render.py "$@"
