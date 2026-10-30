#!/bin/sh
# Lists the voice lines without a recording and the recordings without a line (see tools/voice/status.py):
# tools/voice_status.sh [npc id ...] [--prune] [--unvoiced]
# Needs only Python's standard library and GODOT4_EDITOR (the game lists the lines), no GPU; --prune deletes
# the stale recordings.
set -e
cd "$(dirname "$0")/.."
PYTHONUTF8=1 exec python tools/voice/status.py "$@"
