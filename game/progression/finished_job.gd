class_name FinishedJob
extends RefCounted
## A job that finished (see `FinishedJobs`): an upgrade level, a skill rank, a crafted miner built,
## a level of one of its parts or a furnace batch.

## What finished: an `Upgrade`, a `Skill` or an `AlloyType`; null: a crafted miner built.
var item: Resource
## The MK level or rank it reached, or a batch's bars.
var level: int = 0
## The crafted miner it belongs to (its cradle number, `CraftedMiner.number`); 0: none.
var miner: int = 0
## When it was seen finishing, in Unix seconds.
var at: float = 0.0


func _init(what: Resource = null, to_level: int = 0, of_miner: int = 0, when: float = 0.0) -> void:
	item = what
	level = to_level
	miner = of_miner
	at = when


## What's saved: the item (by its UID, empty for a miner built), the level, the miner and when.
func save_data() -> Dictionary:
	return {
		"item": SaveData.uid_of(item) if item else "",
		"level": level,
		"miner": miner,
		"at": at,
	}


## A finished job from what a save has (`save_data`), or null when it doesn't read.
static func from_data(saved: Variant) -> FinishedJob:
	if not saved is Dictionary:
		return null
	var data: Dictionary = saved
	var saved_item: Variant = data.get("item", "")
	var what: Resource = null
	if not (saved_item is String and (saved_item as String).is_empty()):
		for kind: Script in [Upgrade, Skill, AlloyType]:
			what = what if what else SaveData.load_uid(saved_item, kind)
		if not what:
			return null
	var to_level: float = SaveData.number(data.get("level"), -1.0)
	var of_miner: float = SaveData.number(data.get("miner"), 0.0)
	var when: float = SaveData.number(data.get("at"), NAN)
	if to_level < 0.0 or of_miner < 0.0 or is_nan(when) or (not what and of_miner < 1.0):
		return null
	return FinishedJob.new(what, roundi(to_level), roundi(of_miner), when)
