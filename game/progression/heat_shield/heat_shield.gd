class_name HeatShield
extends Resource
## The ship's heat shield around the drive core (see docs/design/missions.md, Opening planets): MK1
## is the bare core; every further MK level is a plate (`plates`) that opens the next planet
## inwards, so the ship reaches every body whose tier is at most its MK level (`reaches`). The next
## plate is paid in ore, bit by bit: while it's the ship's `project`, every haul pays into it first
## (see `Ship.store_haul`), and the host can pay what's missing from their own hold any time
## (`Ship.pay_shield`). It's installed as soon as it's paid (at once, not timed). Every plate also
## raises the highest MK level of the upgrades (`upgrade_cap`). It's the host's (the ship's), saved
## with the ship.

## Emitted when the MK level changes (a plate installed, a save loaded): other bodies are in reach.
signal level_changed(mk: int)

const PLATES: ShieldPlates = preload("res://game/progression/heat_shield/plates.tres")
## Paid amounts this close to a cost count as paid (ore amounts are fractional).
const PAID_TOLERANCE: float = 0.001

## The plates from MK2 on, in order.
var plates: Array[ShieldPlate] = PLATES.plates
## The installed MK level (1: the bare core).
var mk: int = 1
## Whether the next plate is the ship's project: hauls pay into it before they're stored.
var project: bool = false
## What's paid into the next plate so far, in units per ore type.
var paid: Dictionary[OreType, float] = {}


## The highest MK level.
func max_mk() -> int:
	return plates.size() + 1


## The plate that brings MK `level`, or null (MK1 is the bare core).
func plate_for(level: int) -> ShieldPlate:
	return plates[level - 2] if level >= 2 and level <= max_mk() else null


## The plate to install next, or null when every plate is installed.
func next_plate() -> ShieldPlate:
	return plate_for(mk + 1)


## The highest MK level upgrades can be bought up to: that of the bodies it reaches (their tier is
## at most `mk`, see `CelestialBody.max_mk`), MK3 with the bare core, MK8 with every plate.
func upgrade_cap() -> int:
	return mk + CelestialBody.MK_ABOVE_TIER


## Whether the ship can fly to `body` with the installed plates (its tier is at most `mk`).
func reaches(body: CelestialBody) -> bool:
	return body != null and body.tier <= mk


## What the next plate still needs, in units per ore type (empty once every plate is installed).
func missing() -> Dictionary[OreType, float]:
	var still: Dictionary[OreType, float] = {}
	var plate: ShieldPlate = next_plate()
	if plate:
		for ore_type: OreType in plate.cost:
			var paid_so_far: float = paid.get(ore_type, 0.0)
			var left: float = plate.cost[ore_type] - paid_so_far
			if left > PAID_TOLERANCE:
				still[ore_type] = left
	return still


## Makes the next plate the ship's project. Returns whether it did (not when it already is, or
## every plate is installed).
func set_project() -> bool:
	if project or not next_plate():
		return false
	project = true
	emit_changed()
	return true


## Pays what the next plate still needs out of `available` (units per ore type), as far as it
## goes, and installs the plate once it's paid. Returns what it took.
func take_from(available: Dictionary[OreType, float]) -> Dictionary[OreType, float]:
	var taken: Dictionary[OreType, float] = {}
	var still: Dictionary[OreType, float] = missing()
	for ore_type: OreType in still:
		var offered: float = available.get(ore_type, 0.0)
		var amount: float = minf(offered, still[ore_type])
		if amount > 0.0:
			var paid_so_far: float = paid.get(ore_type, 0.0)
			paid[ore_type] = paid_so_far + amount
			taken[ore_type] = amount
	if taken.is_empty():
		return taken
	if missing().is_empty():
		_install()
	else:
		emit_changed()
	return taken


## Installs the next plate without paying (debug overlay). Returns whether it did.
func install_next() -> bool:
	if not next_plate():
		return false
	_install()
	return true


## Sets the state from a save: MK `level` (clamped to the plates there are), whether the next
## plate is the project and what's paid into it (only what it costs).
func restore(level: int, is_project: bool, paid_so_far: Dictionary[OreType, float]) -> void:
	var before: int = mk
	mk = clampi(level, 1, max_mk())
	paid.clear()
	var plate: ShieldPlate = next_plate()
	project = is_project and plate != null
	if plate:
		for ore_type: OreType in paid_so_far:
			if ore_type in plate.cost:
				paid[ore_type] = minf(paid_so_far[ore_type], plate.cost[ore_type])
		# A plate paid in full is installed.
		if not paid.is_empty() and missing().is_empty():
			mk += 1
			paid.clear()
			project = false
	emit_changed()
	if mk != before:
		level_changed.emit(mk)


## What's saved: the MK level, whether the next plate is the project and what's paid into it.
func save_data() -> Dictionary:
	return {"mk": mk, "project": project, "paid": SaveData.numbers_by_uid(paid)}


## Reads what a save has (`save_data`) through `restore`, a level out of range clamped. Returns
## whether all of it read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	if not saved is Dictionary:
		return SaveData.skipped("heat shield", saved)
	var data: Dictionary = saved
	var complete: bool = true
	var level: float = SaveData.number(data.get("mk"), 0.0)
	if level < 1.0 or level > max_mk():
		complete = SaveData.skipped("heat shield level", data.get("mk"))
	var paid_so_far: Dictionary[OreType, float] = {}
	var saved_paid: Variant = data.get("paid", {})
	if saved_paid is Dictionary:
		var entries: Dictionary = saved_paid
		var read: Dictionary = SaveData.load_numbers(entries, OreType, 0.0, "heat shield payment")
		complete = complete and read.size() == entries.size()
		for ore_type: OreType in read:
			var amount: float = read[ore_type]
			paid_so_far[ore_type] = amount
	else:
		complete = SaveData.skipped("heat shield payment", saved_paid)
	var is_project: Variant = data.get("project", false)
	if not is_project is bool:
		complete = SaveData.skipped("heat shield project", is_project)
	var next_is_project: bool = is_project is bool and is_project
	restore(roundi(clampf(level, 1.0, max_mk())), next_is_project, paid_so_far)
	return complete


func _install() -> void:
	mk += 1
	paid.clear()
	project = false
	emit_changed()
	level_changed.emit(mk)
	GameEvents.bus.heat_shield_raised.emit(mk)
