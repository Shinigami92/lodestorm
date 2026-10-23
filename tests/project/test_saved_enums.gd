extends GutTest
## Exported enums are saved as numbers in scenes and resources (a biome's area kinds, a map part's
## markers, a strain's role, ...), so a value inserted before others or removed would silently
## change what those files mean. Their values are pinned in `saved_enums.cfg`: a new value goes at
## the end of its enum and into the file.

const PINNED: String = "res://tests/project/saved_enums.cfg"


func test_saved_enum_values_stay() -> void:
	var pinned := ConfigFile.new()
	assert_eq(pinned.load(PINNED), OK, PINNED)
	var enums: Dictionary[String, Dictionary] = _saved_enums()
	assert_gt(enums.size(), 0, "no exported enums found")
	for enum_name: String in enums:
		if not pinned.has_section(enum_name):
			fail_test("%s is exported: pin its values in %s" % [enum_name, PINNED])
			continue
		var values: Dictionary = enums[enum_name]
		for key: String in values:
			var value: int = values[key]
			var was: int = pinned.get_value(enum_name, key, -1)
			assert_eq(
				value, was, "%s.%s (a new value goes at the end, and here)" % [enum_name, key]
			)
		for key: String in pinned.get_section_keys(enum_name):
			assert_has(values, key, "%s.%s was removed" % [enum_name, key])
	for enum_name: String in pinned.get_sections():
		assert_has(enums, enum_name, "no longer exported: remove it from %s" % PINNED)


## Every enum some project class exports (also as a typed array), by its name ("Class.Enum").
func _saved_enums() -> Dictionary[String, Dictionary]:
	var all: Dictionary[String, Dictionary] = {}
	var scripts: Array[Script] = []
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var path: String = entry["path"]
		if path.begins_with("res://addons/"):
			continue
		var script: Script = load(path)
		scripts.append(script)
		_collect_enums(script, entry["class"] as String, all)
	var saved: Dictionary[String, Dictionary] = {}
	for script: Script in scripts:
		for property: Dictionary in script.get_script_property_list():
			var usage: int = property["usage"]
			if not (usage & PROPERTY_USAGE_STORAGE):
				continue
			var hint_string: String = property["hint_string"]
			if usage & PROPERTY_USAGE_CLASS_IS_ENUM != 0:
				var enum_name: String = property["class_name"]
				if all.has(enum_name):
					saved[enum_name] = all[enum_name]
			elif property["type"] == TYPE_ARRAY and property["hint"] == PROPERTY_HINT_TYPE_STRING:
				# A typed array of an enum names only its values: "2/2:Ore Pocket:3,Nest Hollow:4"
				var prefix: String = "%d/%d:" % [TYPE_INT, PROPERTY_HINT_ENUM]
				if hint_string.begins_with(prefix):
					var values: String = hint_string.substr(prefix.length())
					for enum_name: String in all:
						if _hint(all[enum_name]) == values:
							saved[enum_name] = all[enum_name]
	return saved


func _collect_enums(script: Script, prefix: String, into: Dictionary[String, Dictionary]) -> void:
	var constants: Dictionary = script.get_script_constant_map()
	for key: String in constants:
		var constant: Variant = constants[key]
		if constant is Dictionary and _is_enum(constant as Dictionary):
			into[prefix + "." + key] = constant
		elif constant is GDScript and (constant as GDScript).resource_path.is_empty():
			_collect_enums(constant as Script, prefix + "." + key, into)


static func _is_enum(constants: Dictionary) -> bool:
	if constants.is_empty():
		return false
	for key: Variant in constants:
		if not ((key is String or key is StringName) and constants[key] is int):
			return false
	return true


## An enum's values as an exported array's hint lists them.
static func _hint(values: Dictionary) -> String:
	var pairs: PackedStringArray = []
	for key: String in values:
		pairs.append("%s:%d" % [key.capitalize(), values[key]])
	return ",".join(pairs)
