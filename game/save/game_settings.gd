class_name GameSettings
extends RefCounted
## The player's settings, kept apart from the progress (`SaveGame`) in `settings.cfg` next to the
## save, so resetting keeps them. So far the language: the system's until one is picked.

const FILE: String = "settings.cfg"


## Where the settings are kept, or empty when saving is off (`SaveGame.directory`).
static func path() -> String:
	return SaveGame.directory.path_join(FILE) if SaveGame.directory else ""


## Applies the saved settings. A language forced on the command line (`--language`, anything
## but the system's) wins over the saved one.
static func load_settings() -> void:
	if not path():
		return
	var language: String = saved_language()
	var forced: bool = TranslationServer.get_locale() != OS.get_locale()
	if language and not forced:
		TranslationServer.set_locale(language)


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
	if not path():
		return
	var config := ConfigFile.new()
	config.load(path())
	config.set_value("general", "language", code)
	DirAccess.make_dir_recursive_absolute(SaveGame.directory)
	if config.save(path()) != OK:
		push_error("Settings: can't write %s" % path())
