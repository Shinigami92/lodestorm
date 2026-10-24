class_name Story
extends Resource
## What has happened in the story so far, as flags: a topic heard to the end at an NPC (its id),
## later quest steps and crew joining. It's the host's (the ship's), saved with the ship; what
## one player has seen for themselves (a hint) is theirs instead (`PlayerHints`).
## Flags are saved by name, so a name never changes once it's in a release. A name is lowercase
## parts joined by dots, the first saying whose it is (`is_valid_flag`):
## - `<npc>.<topic>`: a topic heard, `<npc>` the `NpcProfile.id` (`quartermaster.ammo`);
## - `quest.<quest>.<step>`: a quest step done, `quest.<quest>` the quest itself;
## - `reward.<quest>`: a quest's reward handed out;
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


## Sets `flag` (once; it stays set). A name outside the scheme (`is_valid_flag`) is refused with
## an error: it's a mistake in the content.
func set_flag(flag: StringName) -> void:
	if flags.has(flag):
		return
	if not is_valid_flag(flag):
		push_error('Story: "%s" isn\'t a flag name (scope.name, see Story)' % flag)
		return
	flags[flag] = true
	emit_changed()
	GameEvents.bus.story_flag_set.emit(flag)


## Whether `flag` follows the naming scheme (see the class description).
static func is_valid_flag(flag: StringName) -> bool:
	if not _flag_regex:
		_flag_regex = RegEx.create_from_string(FLAG_PATTERN)
	return _flag_regex.search(String(flag)) != null
