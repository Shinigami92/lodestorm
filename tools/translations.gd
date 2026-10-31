extends SceneTree
## Collects every player-facing text into the translation template (`locale/lodestorm.pot`) and
## brings each translation (`locale/<language>.po`, listed in the project settings) up to date:
## new texts are added untranslated, texts no longer used are dropped, translations are kept.
## Run it with `tools/translations.sh` after adding or changing texts.
##
## Texts are the English originals (English needs no translation file). They come from
## - scripts: `tr("Text")` and `tr("Text", "context")` with string literals,
## - scenes: the `text` of nodes (Label3D, ...), unless their auto translation is disabled,
## - resources: the player-facing texts of the resource types in `RESOURCE_TEXTS` (e.g. biomes,
##   weapons, upgrades, skills, what the crew says).

const TEMPLATE_PATH := "res://locale/lodestorm.pot"
const SOURCE_DIRS: Array[String] = ["res://game"]
## Node properties that hold player-facing text.
const TEXT_PROPERTIES: Array[StringName] = [&"text", &"placeholder_text", &"tooltip_text"]
## Resource types (script class names) with player-facing texts, and their text properties.
const RESOURCE_TEXTS: Dictionary[String, Array] = {
	"AlienStrain": [&"display_name"],
	"AlloyType": [&"display_name"],
	"CelestialBody": [&"display_name"],
	"ClearNestsGoal": [&"task"],
	"CrewReaction": [&"lines"],
	"Dialogue": [&"prompts"],
	"LocationBiome": [&"display_name"],
	"OreType": [&"display_name"],
	"Message": [&"lines"],
	"NpcProfile": [&"role", &"remarks", &"calls"],
	# Its lines are built into it.
	"OverheardTalk": [],
	# Its steps and topics are built into it.
	"Quest": [&"title"],
	"QuestStep": [&"text"],
	"RadioLine": [&"text", &"coop_text"],
	"ReachGoal": [&"place"],
	"RecoverFragmentsGoal": [&"task"],
	"Region": [&"display_name"],
	"Skill": [&"display_name", &"description"],
	"SkillCluster": [&"display_name"],
	# Only for the clusters built into it.
	"SkillTree": [],
	"StarSystem": [&"display_name"],
	"TalkLine": [&"text"],
	"Topic": [&"title", &"lines", &"guest_lines", &"away_lines"],
	"TourStop": [&"lines", &"empty_lines"],
	"Upgrade": [&"display_name", &"description"],
	"WeaponPart": [&"display_name", &"description"],
	# The name stays the same in every language.
	"WeaponType": [&"class_word", &"description"],
}
const TRANSLATIONS_SETTING := "internationalization/locale/translations"
## Separates the context from the text in entry keys (as in gettext's binary format).
const CONTEXT_SEPARATOR := "\u0004"


func _initialize() -> void:
	# Scenes load scripts that refer to autoloads (`Sfx`), which exist from the first frame on.
	await process_frame
	var entries: Array[Dictionary] = extract()
	_write(TEMPLATE_PATH, template(entries))
	print("%s: %d texts" % [TEMPLATE_PATH, entries.size()])
	for path: String in translation_paths():
		var existing: String = FileAccess.get_file_as_string(path)
		var merged: String = merge(entries, existing)
		_write(path, merged)
		var missing: int = untranslated(merged).size()
		print("%s: %d untranslated" % [path, missing])
	quit()


## Every text to translate, in a stable order: `{context, id, references}` (references: the files
## it appears in).
static func extract() -> Array[Dictionary]:
	var files: Array[String] = []
	for dir: String in SOURCE_DIRS:
		_collect_files(dir, files)
	files.sort()
	var entries: Array[Dictionary] = []
	var by_key: Dictionary[String, Dictionary] = {}
	for path: String in files:
		var found: Array[PackedStringArray] = []
		if path.ends_with(".gd"):
			found = _script_texts(path)
		elif path.ends_with(".tscn"):
			found = _scene_texts(path)
		elif path.ends_with(".tres"):
			found = _resource_texts(path)
		for text: PackedStringArray in found:
			var key: String = _key(text[0], text[1])
			if not by_key.has(key):
				by_key[key] = {&"context": text[0], &"id": text[1], &"references": []}
				entries.append(by_key[key])
			var references: Array = by_key[key][&"references"]
			var reference: String = path.trim_prefix("res://")
			if reference not in references:
				references.append(reference)
	return entries


## The translation files listed in the project settings.
static func translation_paths() -> PackedStringArray:
	var paths: PackedStringArray = ProjectSettings.get_setting(TRANSLATIONS_SETTING, [])
	var po_paths: PackedStringArray = []
	for path: String in paths:
		if path.ends_with(".po"):
			po_paths.append(path)
	return po_paths


## The template's content for `entries`.
static func template(entries: Array[Dictionary]) -> String:
	var header: String = "Content-Type: text/plain; charset=UTF-8\n"
	return _format(entries, header, {})


## `existing` (a translation file's content) updated to `entries`, keeping its header and
## translations.
static func merge(entries: Array[Dictionary], existing: String) -> String:
	var translations: Dictionary[String, String] = parse(existing)
	var header: String = translations.get(_key("", ""), "")
	return _format(entries, header, translations)


## A PO file's translations by entry key (context + separator + text; the header has key "").
static func parse(content: String) -> Dictionary[String, String]:
	var translations: Dictionary[String, String] = {}
	var fields: Dictionary[String, String] = {}
	var field: String = ""
	for raw_line: String in content.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("#"):
			continue
		if line.is_empty():
			_add_entry(fields, translations)
			fields = {}
			field = ""
			continue
		var space: int = line.find(" ")
		if not line.begins_with('"') and space > 0:
			field = line.substr(0, space)
			if field == "msgctxt" or (field == "msgid" and fields.has("msgstr")):
				_add_entry(fields, translations)
				fields = {}
			line = line.substr(space + 1)
		var value: String = fields.get(field, "")
		fields[field] = value + _unquote(line)
	_add_entry(fields, translations)
	return translations


## The texts in `content` (a translation file) without a translation.
static func untranslated(content: String) -> PackedStringArray:
	var missing: PackedStringArray = []
	var translations: Dictionary[String, String] = parse(content)
	for key: String in translations:
		if not key.is_empty() and translations[key].is_empty():
			missing.append(key.get_slice(CONTEXT_SEPARATOR, 1))
	return missing


static func _format(
	entries: Array[Dictionary], header: String, translations: Dictionary[String, String]
) -> String:
	var lines: PackedStringArray = ['msgid ""', 'msgstr ""']
	for header_line: String in header.split("\n", false):
		lines.append(_quote(header_line + "\n"))
	for entry: Dictionary in entries:
		var context: String = entry[&"context"]
		var id: String = entry[&"id"]
		lines.append("")
		var references: Array = entry[&"references"]
		for reference: String in references:
			lines.append("#: " + reference)
		if not context.is_empty():
			lines.append("msgctxt " + _quote(context))
		lines.append("msgid " + _quote(id))
		var translation: String = translations.get(_key(context, id), "")
		lines.append("msgstr " + _quote(translation))
	return "\n".join(lines) + "\n"


static func _add_entry(fields: Dictionary[String, String], translations: Dictionary) -> void:
	if fields.has("msgid"):
		var context: String = fields.get("msgctxt", "")
		var translation: String = fields.get("msgstr", "")
		translations[_key(context, fields["msgid"])] = translation


static func _key(context: String, id: String) -> String:
	return context + CONTEXT_SEPARATOR + id if not context.is_empty() or not id.is_empty() else ""


static func _quote(text: String) -> String:
	var escaped: String = text.replace("\\", "\\\\").replace('"', '\\"')
	return '"%s"' % escaped.replace("\n", "\\n").replace("\t", "\\t")


static func _unquote(text: String) -> String:
	return text.trim_prefix('"').trim_suffix('"').c_unescape()


static func _collect_files(dir: String, files: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd") or file.ends_with(".tscn") or file.ends_with(".tres"):
			files.append(dir.path_join(file))
	for sub_dir: String in DirAccess.get_directories_at(dir):
		_collect_files(dir.path_join(sub_dir), files)


## `[context, text]` of every `tr()` call with string literals in the script at `path`.
static func _script_texts(path: String) -> Array[PackedStringArray]:
	var string: String = '"((?:[^"\\\\]|\\\\.)*)"'
	var tr_call := RegEx.create_from_string(
		"(?<![\\w])tr\\(\\s*%s\\s*(?:,\\s*%s\\s*)?\\)" % [string, string]
	)
	var texts: Array[PackedStringArray] = []
	for found: RegExMatch in tr_call.search_all(FileAccess.get_file_as_string(path)):
		texts.append(
			PackedStringArray([found.get_string(2).c_unescape(), found.get_string(1).c_unescape()])
		)
	return texts


## `[context, text]` of every translated text property in the scene at `path` (an empty context:
## scenes have none).
static func _scene_texts(path: String) -> Array[PackedStringArray]:
	var scene := load(path) as PackedScene
	var state: SceneState = scene.get_state()
	var disabled: Dictionary[NodePath, bool] = {}
	var texts: Array[PackedStringArray] = []
	for node: int in state.get_node_count():
		var node_path: NodePath = state.get_node_path(node)
		var parent_path: NodePath = state.get_node_path(node, true)
		var mode: int = Node.AUTO_TRANSLATE_MODE_INHERIT
		for property: int in state.get_node_property_count(node):
			var name: StringName = state.get_node_property_name(node, property)
			if name == &"auto_translate_mode":
				mode = state.get_node_property_value(node, property)
		var is_disabled: bool = (
			mode == Node.AUTO_TRANSLATE_MODE_DISABLED
			or (mode == Node.AUTO_TRANSLATE_MODE_INHERIT and disabled.get(parent_path, false))
		)
		disabled[node_path] = is_disabled
		if is_disabled:
			continue
		for property: int in state.get_node_property_count(node):
			var name: StringName = state.get_node_property_name(node, property)
			var value: Variant = state.get_node_property_value(node, property)
			if name in TEXT_PROPERTIES and value is String and not (value as String).is_empty():
				texts.append(PackedStringArray(["", value]))
	return texts


## `[context, text]` of the player-facing texts of the resource at `path`, if its type has any
## (`RESOURCE_TEXTS`), and of the resources built into it (e.g. a star system's bodies and regions).
static func _resource_texts(path: String) -> Array[PackedStringArray]:
	var texts: Array[PackedStringArray] = []
	# The header names the script class: no need to load every resource.
	var header: String = FileAccess.open(path, FileAccess.READ).get_line()
	for type: String in RESOURCE_TEXTS:
		if header.contains('script_class="%s"' % type):
			_collect_resource_texts(load(path), texts, [])
			break
	return texts


## Adds the texts of `resource` and of the resources built into it (sub-resources of the same file)
## to `texts`.
static func _collect_resource_texts(
	resource: Resource, texts: Array[PackedStringArray], visited: Array[Resource]
) -> void:
	if not resource or resource in visited:
		return
	visited.append(resource)
	var script := resource.get_script() as Script
	var type: String = String(script.get_global_name()) if script else ""
	for property: StringName in RESOURCE_TEXTS.get(type, []):
		var value: Variant = resource.get(property)
		# A text, or a list of them (e.g. a topic's lines).
		var values: Array = value if value is Array else [value]
		for text: Variant in values:
			if text is String and not (text as String).is_empty():
				texts.append(PackedStringArray(["", text]))
	for info: Dictionary in resource.get_property_list():
		var usage: int = info["usage"]
		if not usage & PROPERTY_USAGE_STORAGE:
			continue
		var value: Variant = resource.get(info["name"] as StringName)
		var children: Array = value if value is Array else [value]
		for child: Variant in children:
			if not child is Resource:
				continue
			var sub: Resource = child
			# Only resources built into the file; others are collected from their own files.
			if sub.resource_path.is_empty() or sub.resource_path.contains("::"):
				_collect_resource_texts(sub, texts, visited)


static func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
