class_name Keywords
extends RefCounted
## Names in spoken lines (speech bubbles and radio calls, not cards) stand out in their own color:
## people, the star and its planets, moons, stations and regions, the weapons, ores and alloys,
## read from where they're defined, so a renamed one stays highlighted. Alien strains aren't among
## them: their names are common words (German "Heiler", "Wächter"). A name is matched as a whole
## word in the language shown, also with a German genitive "s" ("Gaulms Monde").

## The color names show in, apart from the text's pale blue and the frame's cyan.
const COLOR := Color(1.0, 0.85, 0.5)
const STAR_SYSTEM: String = "res://game/world/star_system.tres"
const ARSENAL: String = "res://game/weapons/all_weapons.tres"
## Where the people are (`NpcProfile`s, also in subfolders; those without a name are skipped).
const PEOPLE: String = "res://game/npcs"

## Matches any name in `_locale`, built the first time it's needed in that language.
static var _pattern: RegEx
static var _locale: String = ""


## `text` (already translated) as BBCode for a `RichTextLabel`, every name in `COLOR`.
static func highlight(text: String) -> String:
	var pattern: RegEx = _current_pattern()
	var result: String = ""
	var from: int = 0
	for found: RegExMatch in pattern.search_all(text):
		result += _escaped(text.substr(from, found.get_start() - from))
		result += "[color=#%s]%s[/color]" % [COLOR.to_html(false), found.get_string()]
		from = found.get_end()
	return result + _escaped(text.substr(from))


## Every name, as defined (in English).
static func names() -> PackedStringArray:
	var found: PackedStringArray = []
	var system := load(STAR_SYSTEM) as StarSystem
	found.append(system.display_name)
	for body: CelestialBody in system.bodies:
		found.append(body.display_name)
		for region: Region in body.regions:
			found.append(region.display_name)
	var arsenal := load(ARSENAL) as Arsenal
	for weapon_type: WeaponType in arsenal.weapons + arsenal.blueprints:
		found.append(weapon_type.display_name)
	for ore: OreType in OreCatalog.all().ores:
		found.append(ore.display_name)
	for alloy: AlloyType in AlloyCatalog.all().alloys:
		found.append(alloy.display_name)
	for profile: NpcProfile in _people(PEOPLE):
		found.append(profile.display_name)
	var unique: PackedStringArray = []
	for name: String in found:
		if not name.is_empty() and not unique.has(name):
			unique.append(name)
	return unique


static func _current_pattern() -> RegEx:
	var locale: String = TranslationServer.get_locale()
	if _pattern and locale == _locale:
		return _pattern
	var shown: Array[String] = []
	for name: String in names():
		shown.append(_regex_escaped(TranslationServer.translate(name)))
	# Longest first, so a name inside a longer one doesn't cut it short.
	shown.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	_pattern = RegEx.create_from_string("\\b(?:%s)s?\\b" % "|".join(shown))
	_locale = locale
	return _pattern


## Every named profile in `directory` and its subfolders.
static func _people(directory: String) -> Array[NpcProfile]:
	var people: Array[NpcProfile] = []
	for entry: String in ResourceLoader.list_directory(directory):
		var path: String = directory.path_join(entry)
		if entry.ends_with("/"):
			people.append_array(_people(path.trim_suffix("/")))
		elif entry.ends_with(".tres"):
			var profile := load(path) as NpcProfile
			if profile and not profile.display_name.is_empty():
				people.append(profile)
	return people


static func _regex_escaped(text: String) -> String:
	var escaped: String = ""
	for character: String in text:
		escaped += "\\" + character if character in "\\^$.|?*+()[]{}" else character
	return escaped


## `text` with its brackets kept from being read as BBCode.
static func _escaped(text: String) -> String:
	return text.replace("[", "[lb]")
