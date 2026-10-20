class_name GameSettings
extends RefCounted
## The player's settings, kept apart from the progress (`SaveGame`) in `settings.cfg` next to the
## save, so resetting keeps them: the language (the system's until one is picked), the suit
## ring's size and "Always show", and the sound volumes per bus.

const FILE: String = "settings.cfg"

## The suit ring's sizes, as a factor of its radius (small, medium, large). TBD (playtest).
const RING_SCALES: Array[float] = [0.8, 1.0, 1.25]
const RING_MEDIUM: int = 1

## The suit ring's size (an index into `RING_SCALES`).
static var ring_size: int = RING_MEDIUM
## Whether the suit ring's arcs stay lit instead of dimming when nothing changes.
static var ring_always_show: bool = false
## The volume of each bus that has been changed (0..1, by bus name, see `Sfx.BUSES`); the others
## are at full volume.
static var volumes: Dictionary[StringName, float] = {}


## Where the settings are kept, or empty when saving is off (`SaveGame.directory`).
static func path() -> String:
	return SaveGame.directory.path_join(FILE) if SaveGame.directory else ""


## Applies the saved settings (the defaults without any). A language forced on the command line
## (`--language`, anything but the system's) wins over the saved one.
static func load_settings() -> void:
	ring_size = RING_MEDIUM
	ring_always_show = false
	volumes.clear()
	var config := ConfigFile.new()
	if not path() or config.load(path()) != OK:
		return
	var size: Variant = config.get_value("suit_ring", "size", RING_MEDIUM)
	if size is int and size >= 0 and size < RING_SCALES.size():
		ring_size = size
	var always: Variant = config.get_value("suit_ring", "always_show", false)
	ring_always_show = always is bool and always
	if config.has_section("volume"):
		for bus: String in config.get_section_keys("volume"):
			var saved: Variant = config.get_value("volume", bus)
			if saved is float or saved is int:
				var level: float = saved
				volumes[StringName(bus)] = clampf(level, 0.0, 1.0)
	var language: String = saved_language()
	var forced: bool = TranslationServer.get_locale() != OS.get_locale()
	if language and not forced:
		TranslationServer.set_locale(language)


## The suit ring's radius factor for its size setting.
static func ring_scale() -> float:
	return RING_SCALES[clampi(ring_size, 0, RING_SCALES.size() - 1)]


## Sets the suit ring's size (an index into `RING_SCALES`) and saves it.
static func set_ring_size(size: int) -> void:
	ring_size = clampi(size, 0, RING_SCALES.size() - 1)
	_save("suit_ring", "size", ring_size)


## Sets whether the suit ring always shows and saves it.
static func set_ring_always_show(always: bool) -> void:
	ring_always_show = always
	_save("suit_ring", "always_show", always)


## The volume of `bus` (0..1).
static func volume(bus: StringName) -> float:
	return volumes.get(bus, 1.0)


## Sets the volume of `bus` (0..1) and saves it.
static func set_volume(bus: StringName, level: float) -> void:
	volumes[bus] = clampf(level, 0.0, 1.0)
	_save("volume", bus, volumes[bus])


## The language picked at the settings terminal, or empty when none was (or it's unknown).
static func saved_language() -> String:
	var config := ConfigFile.new()
	if not path() or config.load(path()) != OK:
		return ""
	var language: Variant = config.get_value("general", "language", "")
	return language if language is String and language in SettingsList.languages() else ""


## Switches the game's texts to `code` and saves it.
static func set_language(code: String) -> void:
	TranslationServer.set_locale(code)
	_save("general", "language", code)


## Writes one setting into the file, keeping the others.
static func _save(section: String, key: String, value: Variant) -> void:
	if not path():
		return
	var config := ConfigFile.new()
	config.load(path())
	config.set_value(section, key, value)
	DirAccess.make_dir_recursive_absolute(SaveGame.directory)
	if config.save(path()) != OK:
		push_error("Settings: can't write %s" % path())
