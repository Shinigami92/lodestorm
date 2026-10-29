class_name CraftedMiner
extends Resource
## One of a player's crafted miners (see `MinerFleet`): built in the ship and kept. It lives in its
## cradle in the miners' room (`number`, 1–6, on its plate as "M-01"), has its own MK levels
## (`upgrades`: drill, tank, hose, plating, see `PARTS`) and goes along on the next run unless the
## player leaves it aboard (`going_along`). While it's built, `build` runs on the wall clock. During
## a run `out` says it stands on the planet, and the health it had when it was picked up comes
## along to its next spot (`health`) until the run ends.

## Its parts, the upgrades on the maintenance pad.
const PARTS: Array[Upgrade] = [
	preload("res://game/progression/upgrades/miner_drill.tres"),
	preload("res://game/progression/upgrades/miner_tank.tres"),
	preload("res://game/progression/upgrades/miner_hose.tres"),
	preload("res://game/progression/upgrades/miner_plating.tres"),
]

## Its cradle, 1–`MinerFleet.SLOTS`.
var number: int = 1
## Its own MK levels and the ones under way.
var upgrades := Upgrades.new()
## Whether it goes along on the next run.
var going_along: bool = true
## Building it on the wall clock (level 1), or null once it's built.
var build: TimedJob
## Whether it stands on the planet right now.
var out: bool = false
## Its health when it was picked up during this run, or -1: undamaged.
var health: float = -1.0


func _init(cradle: int = 1, building: TimedJob = null) -> void:
	number = cradle
	build = building
	upgrades.changed.connect(emit_changed)


## Whether it's built (not under way).
func is_built() -> bool:
	return build == null


## Its number plate, e.g. "M-01".
func plate() -> String:
	return plate_of(number)


## Whether a level of one of its parts is under way.
func is_upgrading() -> bool:
	return not upgrades.jobs.is_empty()


## The number plate of cradle `cradle`, e.g. "M-01".
static func plate_of(cradle: int) -> String:
	return "M-%02d" % cradle


## What's saved: its number, whether it goes along, its parts' levels (`Upgrades.save_data`) and,
## while it's built, its build (`TimedJob.save_data`).
func save_data() -> Dictionary:
	var saved: Dictionary = {
		"number": number, "along": going_along, "upgrades": upgrades.save_data()
	}
	if build:
		saved["build"] = build.save_data()
	return saved


## A miner in the cradle and with the build a save has (`save_data`), or null when they don't
## read; the rest is `load_data`'s.
static func from_data(saved: Variant) -> CraftedMiner:
	var data: Dictionary = saved if saved is Dictionary else {}
	var cradle: float = SaveData.number(data.get("number"), 0.0)
	var building: TimedJob = TimedJob.from_data(data["build"]) if data.has("build") else null
	if cradle < 1.0 or cradle > MinerFleet.SLOTS or (data.has("build") and not building):
		return null
	return CraftedMiner.new(roundi(cradle), building)


## Reads whether it goes along and its parts' levels from what a save has (`save_data`). Returns
## whether all of it read.
func load_data(saved: Dictionary) -> bool:
	var along: Variant = saved.get("along", true)
	going_along = along is bool and along
	var complete: bool = upgrades.load_data(saved.get("upgrades"), PARTS)
	return complete and (along is bool or SaveData.skipped("miner along", along))
