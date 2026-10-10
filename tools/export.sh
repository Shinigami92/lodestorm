#!/bin/sh
# Import the project, then export a release build of each preset in export_presets.cfg
# to its export path (under builds/, gitignored). Export templates for the pinned Godot
# version must be installed.
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"

tools/import.sh

# Each preset section lists name= before export_path=
sed -n -e 's/^name="\(.*\)"$/\1/p' -e 's/^export_path="\(.*\)"$/\1/p' export_presets.cfg |
	while read -r name && read -r path; do
		echo "Exporting $name to $path"
		mkdir -p "$(dirname "$path")"
		"$GODOT4_EDITOR" --headless --export-release "$name" "$path"
		if [ ! -f "$path" ]; then
			echo "Export of $name failed: $path missing" >&2
			exit 1
		fi
	done
