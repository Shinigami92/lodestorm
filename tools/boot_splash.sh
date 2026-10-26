#!/bin/sh
# Render the boot splash (assets/ui/boot/boot_splash.png) from the boot screen. Needs a window
# (headless runs don't render); it closes by itself.
set -eu
cd "$(dirname "$0")/.."
: "${GODOT4_EDITOR:?set GODOT4_EDITOR to the Godot executable}"

"$GODOT4_EDITOR" --path . -s tools/boot_splash.gd
