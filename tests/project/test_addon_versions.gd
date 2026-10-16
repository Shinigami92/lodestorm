extends GutTest


## The godot-ai MCP server pinned in `.mcp.json` must match the editor plugin in `addons/godot_ai/`.
func test_godot_ai_server_matches_plugin() -> void:
	var mcp: String = FileAccess.get_file_as_string("res://.mcp.json")
	var server: RegExMatch = RegEx.create_from_string('godot-ai==([^"]+)').search(mcp)
	if server == null:
		fail_test("godot-ai is not pinned in .mcp.json")
		return
	var plugin: ConfigFile = ConfigFile.new()
	assert_eq(plugin.load("res://addons/godot_ai/plugin.cfg"), OK)
	var plugin_version: String = plugin.get_value("plugin", "version", "")
	assert_eq(plugin_version, server.get_string(1))
