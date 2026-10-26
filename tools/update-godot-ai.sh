#!/bin/sh
# Replace addons/godot_ai/ with the editor plugin matching the godot-ai server pinned in .mcp.json
# (tests/project/test_addon_versions.gd checks they match). Downloads the plugin from the GitHub
# release, checks it against the release manifest's SHA-256 and stages the change in Git (removed
# files included). The godot-ai-plugin workflow runs it on Renovate's godot-ai branch.
set -eu
cd "$(dirname "$0")/.."

version="$(sed -n 's/.*"godot-ai==\([^"]*\)".*/\1/p' .mcp.json)"
if [ -z "$version" ]; then
	echo "godot-ai is not pinned in .mcp.json" >&2
	exit 1
fi
if grep -q "^version=\"$version\"$" addons/godot_ai/plugin.cfg; then
	echo "addons/godot_ai/ is already at $version"
	exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
release="https://github.com/hi-godot/godot-ai/releases/download/v$version"
echo "Downloading the godot-ai plugin $version..."
curl -fsSL -o "$work/plugin.zip" "$release/godot-ai-v4-plugin.zip"
curl -fsSL -o "$work/manifest.json" "$release/godot-ai-v4-plugin.manifest.json"

expected="$(sed -n 's/.*"asset":{[^}]*"sha256":"\([0-9a-f]*\)".*/\1/p' "$work/manifest.json")"
if command -v sha256sum >/dev/null; then
	actual="$(sha256sum "$work/plugin.zip" | cut -d ' ' -f 1)"
else
	actual="$(shasum -a 256 "$work/plugin.zip" | cut -d ' ' -f 1)"
fi
if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
	echo "The plugin's SHA-256 $actual doesn't match the manifest's '$expected'" >&2
	exit 1
fi

unzip -q "$work/plugin.zip" -d "$work/plugin"
if ! grep -q "^version=\"$version\"$" "$work/plugin/addons/godot_ai/plugin.cfg"; then
	echo "The release's plugin.cfg is not version $version" >&2
	exit 1
fi
git rm -rq addons/godot_ai
mv "$work/plugin/addons/godot_ai" addons/godot_ai
git add addons/godot_ai
echo "addons/godot_ai/ updated to $version"
