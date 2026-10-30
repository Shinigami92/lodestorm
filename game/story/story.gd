class_name Story
extends Resource
## What has happened in the story so far, as flags: a topic heard to the end at an NPC (its id),
## later quest steps and crew joining. It's the host's (the ship's), saved with the ship; what
## one player has seen for themselves (a hint) is theirs instead (`PlayerHints`).
## Flags are saved by name, so a name never changes once it's in a release. A name is lowercase
## parts joined by dots, the first saying whose it is (`is_valid_flag`):
## - `<npc>.<topic>`: a topic heard, `<npc>` the `NpcProfile.id` (`quartermaster.ammo`);
## - `quest.<quest>.<step>`: a quest step handed in (its rewards with it), `quest.<quest>` the
##   quest's last one (see `Quest`);
## - `beat.<beat>`: a beat put out by the story director (see `Beat`);
## - `message.<message>`: a message heard to the end (see `Message`);
## - `crew.<npc>.joined`: a crew member aboard;
## - `event.<event>`: something that happens once per game (`CrewReactions`), e.g.
##   `event.first_death`, `event.landed.<body>`.

## What a flag's name looks like: two or more parts of lowercase letters, digits and `_`, joined
## by dots.
const FLAG_PATTERN: String = "^[a-z0-9_]+(\\.[a-z0-9_]+)+$"

static var _flag_regex: RegEx

## The flags set so far (the value is always true).
@export var flags: Dictionary[StringName, bool] = {}


## Whether `flag` is set.
func is_set(flag: StringName) -> bool:
	return flags.has(flag)


## Whether every flag in `required` is set (true when it's empty).
func is_set_all(required: Array[StringName]) -> bool:
	return required.all(is_set)


## Sets `flag` (once; it stays set, except a request's: see `clear_flag`). A name outside the
## scheme (`is_valid_flag`) is refused with an error: it's a mistake in the content.
func set_flag(flag: StringName) -> void:
	if flags.has(flag):
		return
	if not is_valid_flag(flag):
		push_error('Story: "%s" isn\'t a flag name (scope.name, see Story)' % flag)
		return
	flags[flag] = true
	emit_changed()
	GameEvents.bus.story_flag_set.emit(flag)


## Clears `flag`: only a request's flags, once it's handed in, so it's offered again (see
## `QuestLog`); every other flag stays set.
func clear_flag(flag: StringName) -> void:
	if flags.erase(flag):
		emit_changed()


## Whether `flag` follows the naming scheme (see the class description).
static func is_valid_flag(flag: StringName) -> bool:
	if not _flag_regex:
		_flag_regex = RegEx.create_from_string(FLAG_PATTERN)
	return _flag_regex.search(String(flag)) != null


## What's saved: the flags, sorted.
func save_data() -> Array:
	var saved: Array = []
	for flag: StringName in flags:
		saved.append(String(flag))
	saved.sort()
	return saved


## Reads the flags a save has (`save_data`). Returns whether all of them read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	if not saved is Array:
		return SaveData.skipped("story", saved)
	var complete: bool = true
	for flag: Variant in saved as Array:
		if flag is String and is_valid_flag(StringName(flag as String)):
			flags[StringName(flag as String)] = true
		else:
			complete = SaveData.skipped("story flag", flag)
	emit_changed()
	return complete
