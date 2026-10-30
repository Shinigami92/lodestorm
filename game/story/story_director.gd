class_name StoryDirector
extends Resource
## Picks what's new in the story between runs (see docs/design/story.md, Between missions): on
## every return (coming back aboard after a run, won or lost, or docking at a station) it puts out
## the best `Beat` it can (`direct`): the highest `priority` among those whose conditions hold,
## that fit the return and the place, while fewer than `MOST_WAITING` wait and none waits for the
## same NPC. What it needs to know for the conditions besides the story, the quests and the heat
## shield (runs, ores found, regions visited, falls) it counts itself. It's the host's (the
## ship's), saved with the ship. Quests stay their own system.

## Emitted when a beat is put out (its flag is set by then).
signal beat_put_out(beat: Beat)

const CATALOG: BeatCatalog = preload("res://game/story/beats.tres")
## The most beats waiting at once. TBD (playtest).
const MOST_WAITING: int = 2

## Every beat there is.
var catalog: BeatCatalog = CATALOG
## The story its flags go into (the ship's).
var story := Story.new()
## The ship's quests (for quest steps).
var quests := QuestLog.new()
## The ship's heat shield (for the act and the plate paid).
var heat_shield := HeatShield.new()
## How many beats it puts out on each return: the one setting for "something new on every return"
## (0: none). TBD (playtest).
var per_return: int = 1
## The runs ended so far, won or lost.
var runs: int = 0
## Per beat put out (its id): `runs` when it last was.
var put_out: Dictionary[StringName, int] = {}
## `runs` when the last beat was put out.
var last_beat: int = 0
## The ores brought aboard so far, in the order found.
var ores_found: Array[OreType] = []
## The regions runs went to so far (their `Region.id`), in the order first visited.
var regions_visited: Array[StringName] = []
## How often players fell in the run just ended, while its return is directed (0 otherwise).
var falls: int = 0

var _run_falls: int = 0


## The act the story is in: one per planet, ending when the heat shield's next plate is installed
## (the installed MK level).
func act() -> int:
	return heat_shield.mk


## Runs ended since `beat` was last put out (since the start when it never was); null: since any
## beat.
func runs_since(beat: Beat = null) -> int:
	if not beat:
		return runs - last_beat
	var since: int = put_out.get(beat.id, 0)
	return runs - since


## Whether `beat` was put out and waits until its `done_when` flag is set.
func is_waiting(beat: Beat) -> bool:
	return (
		not beat.repeats
		and not beat.done_when.is_empty()
		and story.is_set(beat.flag())
		and not story.is_set(beat.done_when)
	)


## The beats put out that wait, in catalog order.
func waiting() -> Array[Beat]:
	var found: Array[Beat] = []
	for beat: Beat in catalog.beats:
		if is_waiting(beat):
			found.append(beat)
	return found


## Whether `beat` could be put out on a return of kind `on` at the body `body` (its id): not put
## out yet (or it `repeats`), it fits the return, its conditions hold and nobody it's carried by
## waits for another beat.
func is_ready(beat: Beat, on: Beat.Returns, body: StringName) -> bool:
	if story.is_set(beat.flag()) and not beat.repeats:
		return false
	if not beat.fits(on, body) or not beat.holds(self):
		return false
	if beat.npc.is_empty():
		return true
	return not waiting().any(func(other: Beat) -> bool: return other.npc == beat.npc)


## Notes a run starting in `region` (visited from now on).
func start_run(region: Region) -> void:
	_run_falls = 0
	if region and region.id not in regions_visited:
		regions_visited.append(region.id)
		emit_changed()


## Notes a player falling during the run.
func count_fall() -> void:
	_run_falls += 1


## Notes `ore` brought aboard (found from now on).
func find_ore(ore: OreType) -> void:
	if ore and ore not in ores_found:
		ores_found.append(ore)
		emit_changed()


## A run ended with the ship at the body `body` (its id): counts it and directs the return.
## Returns the beats put out.
func end_run(body: StringName) -> Array[Beat]:
	runs += 1
	falls = _run_falls
	_run_falls = 0
	var beats: Array[Beat] = direct(Beat.Returns.RUN, body)
	falls = 0
	emit_changed()
	return beats


## The ship docked at the station `station` (its id): directs the return. Returns the beats put
## out.
func dock(station: StringName) -> Array[Beat]:
	return direct(Beat.Returns.DOCKING, station)


## Puts out up to `per_return` beats for a return of kind `on` at the body `body` (its id), the
## best first, while fewer than `MOST_WAITING` wait. Returns them.
func direct(on: Beat.Returns, body: StringName) -> Array[Beat]:
	var beats: Array[Beat] = []
	for _i: int in per_return:
		if waiting().size() >= MOST_WAITING:
			break
		var best: Beat = null
		for beat: Beat in catalog.beats:
			if (not best or beat.priority > best.priority) and is_ready(beat, on, body):
				best = beat
		if not best:
			break
		_put_out(best)
		beats.append(best)
	return beats


## What's saved: the runs, the beats put out, the ores found and the regions visited.
func save_data() -> Dictionary:
	var saved_beats: Dictionary = {}
	for id: StringName in put_out:
		saved_beats[String(id)] = put_out[id]
	return {
		"runs": runs,
		"last_beat": last_beat,
		"put_out": saved_beats,
		"ores": SaveData.uids_of(ores_found),
		"regions": regions_visited.map(func(id: StringName) -> String: return String(id)),
	}


## Reads what a save has (`save_data`), without beats no longer in the `catalog` and ores or
## regions that don't read. Returns whether all of it read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	if not saved is Dictionary:
		return SaveData.skipped("story director", saved)
	var data: Dictionary = saved
	var complete: bool = true
	runs = maxi(int(SaveData.number(data.get("runs", 0), 0.0)), 0)
	last_beat = clampi(int(SaveData.number(data.get("last_beat", 0), 0.0)), 0, runs)
	put_out.clear()
	var saved_beats: Variant = data.get("put_out", {})
	for id: Variant in saved_beats if saved_beats is Dictionary else {}:
		var when: float = SaveData.number((saved_beats as Dictionary)[id], -1.0)
		if id is String and catalog.find(StringName(id as String)) and when >= 0.0:
			put_out[StringName(id as String)] = mini(int(when), runs)
		else:
			complete = SaveData.skipped("beat", id)
	var saved_ores: Variant = data.get("ores", [])
	ores_found.assign(
		SaveData.load_uids(saved_ores as Array, OreType, "ore found") if saved_ores is Array else []
	)
	complete = (
		saved_ores is Array and (saved_ores as Array).size() == ores_found.size() and complete
	)
	regions_visited.clear()
	var saved_regions: Variant = data.get("regions", [])
	for id: Variant in saved_regions if saved_regions is Array else []:
		if id is String and not (id as String).is_empty():
			regions_visited.append(StringName(id as String))
		else:
			complete = SaveData.skipped("region visited", id)
	emit_changed()
	return complete


func _put_out(beat: Beat) -> void:
	story.set_flag(beat.flag())
	put_out[beat.id] = runs
	last_beat = runs
	emit_changed()
	beat_put_out.emit(beat)
