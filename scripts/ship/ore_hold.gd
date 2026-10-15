class_name OreHold
extends Station
## The ship's hold in the cargo bay (greybox until the cargo bay's art pass): a tank per ore of the
## game (`OreTank`, from `OreCatalog`), in fixed spots ordered by rarity, filled with what the hold
## has. The common and mid ores stand in tall tanks along the back wall, the commonest near the
## ramp; the signature ores in small tanks along the front, low enough not to hide the bay. The lane
## between them, from the ramp to the lower deck and the lift, stays clear (at least `LANE_WIDTH`).
## Ores never brought aboard show as dark "?" tanks.
## As a station (at its console), the tanks are its parts and the camera follows the selected one;
## its card shows the ore's name, how much the hold has and where it's found.

const CATALOG: OreCatalog = preload("res://scenes/mining/ores/all_ores.tres")
## Tank size per band: radius, height (m) and the units it shows as full (TBD (playtest)).
const TANKS: Dictionary[OreType.Band, Vector3] = {
	OreType.Band.COMMON: Vector3(0.55, 4.0, 3000.0),
	OreType.Band.MID: Vector3(0.45, 3.0, 1500.0),
	OreType.Band.SIGNATURE: Vector3(0.32, 1.6, 600.0),
}
## Distance between neighboring tanks' centers along a bank, in m.
const SPACING: float = 1.4
## Clear width (m) the lane between the banks keeps (four players side by side, VR comfort).
const LANE_WIDTH: float = 4.0

## Where the banks start (their first tank, the commonest) and the direction they run, in the
## hold's space (its origin on the cargo bay's floor).
@export var back_bank_start: Vector3 = Vector3(7.45, 0.0, -12.6)
@export var front_bank_start: Vector3 = Vector3(6.2, 0.0, 12.2)
@export var bank_direction: Vector3 = Vector3.LEFT

## The mission (for where ores are found); found in the scene tree when not set.
var mission: Mission

var _tanks: Dictionary[OreType, OreTank] = {}


func _ready() -> void:
	_build_tanks()
	super()


func _process(delta: float) -> void:
	super(delta)
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission


## Shows `amount` units of `ore_type` in its tank; `found`: it was ever brought aboard.
func show_amount(ore_type: OreType, amount: float, found: bool) -> void:
	var tank: OreTank = _tanks.get(ore_type)
	if tank:
		tank.show_amount(amount, found)
	if user and selected == tank:
		refresh()


## The tank of `ore_type`, or null.
func get_tank(ore_type: OreType) -> OreTank:
	return _tanks.get(ore_type)


## The open regions where `ore_type` is found.
func regions_with(ore_type: OreType) -> Array[Region]:
	var found_in: Array[Region] = []
	var system: StarSystem = mission.settings.system if mission and mission.settings else null
	if system:
		for region: Region in system.open_regions():
			if ore_type in system.ores_of(region):
				found_in.append(region)
	return found_in


## The camera follows the selected tank (the card beside it).
func get_view_center() -> Vector3:
	if not selected:
		return super()
	var camera: Camera3D = get_viewport().get_camera_3d()
	var right: Vector3 = camera.global_basis.x if camera else Vector3.RIGHT
	return selected.global_position + right * selected.card_offset.x * 0.5


func _cycle(step_by: int) -> void:
	var parts: Array[StationPart] = get_parts()
	if parts.is_empty():
		return
	var index: int = parts.find(selected)
	select(parts[posmod(index + step_by, parts.size())])


## A tank per ore: the biome ores (common, then mid) along the back, the signature ores along the
## front, each bank commonest first.
func _build_tanks() -> void:
	var back: int = 0
	var front: int = 0
	for ore_type: OreType in OreCatalog.sorted(CATALOG.ores):
		var size: Vector3 = TANKS[ore_type.band]
		var tank := OreTank.new()
		tank.setup(ore_type, size.x, size.y, size.z)
		var spot: Vector3
		if ore_type.band == OreType.Band.SIGNATURE:
			spot = front_bank_start + bank_direction * SPACING * front
			front += 1
		else:
			spot = back_bank_start + bank_direction * SPACING * back
			back += 1
		tank.position = spot + Vector3.UP * size.y * 0.5
		add_child(tank)
		_tanks[ore_type] = tank
