#!/bin/sh
# Collect all player-facing texts into locale/lodestorm.pot and update every translation
# (locale/<language>.po): new texts are added untranslated, unused ones dropped.
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"

"$GODOT4_EDITOR" --headless -s tools/translations.gd
