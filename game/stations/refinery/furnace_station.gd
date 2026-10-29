class_name FurnaceStation
extends Station
## One of the refinery's furnaces in the cargo bay (greybox until the cargo bay's art pass): a squat
## steel block on a plinth with a flue going up to the pipes from the silos, its door facing the
## camera. The ship has up to four (`Furnaces`, unlocked one by one); this one is `slot`. A locked
## one stands cold and open, its burner pulled out (sold before the ship was bought): its door swung
## open, an empty port with capped lines below it; an unlocked one has a lit lamp over its door.
## It shows the batch (`AlloyBatch`) of the player using it, else the viewer's (see
## `Ship.get_viewing_player`): while one runs, its door glows in the alloy's color, filling from
## the bottom with the batch's progress, a light flickers in front of it and it roars; the plate
## below the door names the alloy and the bars done. `interact` at it opens it as a station with
## the door as its one part (the directions move on to the cargo bay's other stations, its `room`);
## the card (`FurnaceCard`) picks the recipe (`tab_prev`/`tab_next`, by tier) and the number of
## bars (its buttons `BAR_BUTTONS`, or `zoom_out`/`zoom_in` by one; from 1 up to what the hold pays
## for), shows the cost against the hold and the time it takes, and starts it (paid at once); a
## running batch's card shows its progress and the time left and stops it (pressed twice: the bars
## done stay, the ore of the others goes back to the hold). Nothing starts or stops while a
## mission is underway.

## What the card's buttons add to the number of bars (the number shows between the minus and the
## plus ones).
const BAR_BUTTONS: Array[int] = [-10, -5, -1, 1, 5, 10]
const CATALOG: AlloyCatalog = preload("res://game/refinery/all_alloys.tres")
const WIDTH: float = 1.2
const DEPTH: float = 1.1
const HEIGHT: float = 2.3
const PLINTH_HEIGHT: float = 0.18
## The door's window on the front: its size and the height of its bottom edge, in m.
const DOOR_SIZE := Vector2(0.72, 0.95)
const DOOR_BOTTOM: float = 0.55
## Where the flue ends (the refinery's pipes run there), in m above the floor.
const FLUE_TOP: float = 3.6
const FLUE_RADIUS: float = 0.16
const METAL_COLOR := Color(0.3, 0.29, 0.28)
const COLD_COLOR := Color(0.13, 0.13, 0.14)
const TRIM_COLOR := Color(0.16, 0.16, 0.17)
const LAMP_COLOR := Color(1.0, 0.6, 0.2)
## How far a cold furnace's door hangs open, in degrees.
const DOOR_OPEN_ANGLE: float = 115.0
## The burner's port below the door: its radius and the height of its middle, in m.
const PORT_RADIUS: float = 0.17
const PORT_HEIGHT: float = 0.36
## Light in front of a running furnace's door: its energy and how much it flickers.
const LIGHT_ENERGY: float = 1.6
const FLICKER: float = 0.35
const IGNITE_SOUND: Sound = preload("res://assets/audio/sfx/refinery/furnace_ignite.tres")
const ROAR_SOUND: Sound = preload("res://assets/audio/sfx/refinery/furnace_roar.tres")
const STOP_SOUND: Sound = preload("res://assets/audio/sfx/refinery/furnace_stop.tres")

## Which of the ship's furnaces it is (0: the first unlocked).
@export var slot: int = 0

## The recipe the card shows for starting.
var recipe: AlloyType
## The number of bars the card shows for starting (see `get_bars`).
var bars: int = 1

## "Stop" acts on the second press (for the batch shown).
var stop_press := ConfirmPress.new()
var _door := StationPart.new()
var _fill := MeshInstance3D.new()
var _fill_pivot := Node3D.new()
var _lamp := MeshInstance3D.new()
## The swung-open door and the empty burner port, shown while it's locked.
var _cold := Node3D.new()
var _glass := MeshInstance3D.new()
var _light := OmniLight3D.new()
var _plate := Label3D.new()
var _body_material := StandardMaterial3D.new()
var _lamp_material := StandardMaterial3D.new()
var _roar: AudioStreamPlayer3D
## The alloy glowing in the door right now (null: none).
var _glowing: AlloyType


func _init() -> void:
	super()
	locks_while_underway = true


func _ready() -> void:
	_build()
	super()
	recipe = CATALOG.alloys[0]
	_update_look()


func _process(delta: float) -> void:
	super(delta)
	_update_look()
	# The batch, the hold and the mission change meanwhile.
	if user:
		refresh()


func get_parts() -> Array[StationPart]:
	return [_door]


## Whether the ship has unlocked it.
func is_unlocked() -> bool:
	return ship != null and ship.furnaces.is_unlocked(slot)


## The shown player's batch in it, or null.
func get_batch() -> AlloyBatch:
	var player: Player = viewer()
	return player.refining.get_batch(slot) if player else null


## The number of bars the card shows: `bars`, at most what the user's hold pays for (at least 1).
func get_bars() -> int:
	return clampi(bars, 1, get_max_bars())


## The most bars the card offers: what the user's hold pays for of the recipe shown (at least 1).
func get_max_bars() -> int:
	return maxi(recipe.affordable(user.hold), 1) if user and recipe else 1


## Whether the user can start the recipe shown now.
func can_start() -> bool:
	return (
		user != null
		and is_unlocked()
		and not is_locked()
		and recipe != null
		and recipe.is_known(user.hold)
		and user.refining.can_start(slot, recipe, get_bars(), user.hold)
	)


## Starts the bars shown of the recipe shown, paid from the user's hold. Returns whether it did.
func start() -> bool:
	if not can_start():
		return false
	if not user.refining.start(slot, recipe, get_bars(), user.hold, _now()):
		return false
	Sfx.play_at(IGNITE_SOUND, _door.global_position)
	refresh()
	return true


## Whether the user's batch in it can be stopped now.
func can_stop() -> bool:
	return user != null and not is_locked() and user.refining.get_batch(slot) != null


## Whether "Stop" was pressed once and waits for the second press.
func is_stop_armed() -> bool:
	return stop_press.is_armed(get_batch())


## Stops the user's batch on the second press (`stop_press`); the first only arms it.
## Returns whether it stopped.
func stop() -> bool:
	if not can_stop():
		return false
	if not stop_press.press(user.refining.get_batch(slot)):
		refresh()
		return false
	user.refining.stop(slot, user.hold, _now())
	Sfx.play_at(STOP_SOUND, _door.global_position)
	refresh()
	return true


## Shows the previous (-1) or next (1) recipe, by tier.
func step_recipe(step_by: int) -> void:
	var alloys: Array[AlloyType] = CATALOG.alloys
	recipe = alloys[posmod(alloys.find(recipe) + step_by, alloys.size())]
	stop_press.reset()
	refresh()


## Shows `step_by` bars more (fewer when negative), from 1 up to `get_max_bars`.
func step_bars(step_by: int) -> void:
	bars = clampi(get_bars() + step_by, 1, get_max_bars())
	refresh()


## The current wall clock time, in Unix seconds.
static func _now() -> float:
	return Time.get_unix_time_from_system()


func _cycle(step_by: int) -> void:
	if is_unlocked() and not get_batch():
		step_recipe(step_by)


## `zoom_out`/`zoom_in` (-/+, the wheel, the triggers) take one bar off or add one.
func _shortcut(event: InputEvent) -> bool:
	if not is_unlocked() or get_batch():
		return false
	for action: StringName in [&"zoom_in", &"zoom_out"] as Array[StringName]:
		if InputMap.has_action(action) and event.is_action_pressed(action, true):
			step_bars(1 if action == &"zoom_in" else -1)
			return true
	return false


func _opened() -> void:
	stop_press.reset()
	# Start on a recipe the player knows.
	if recipe and not recipe.is_known(user.hold):
		for alloy: AlloyType in CATALOG.alloys:
			if alloy.is_known(user.hold):
				recipe = alloy
				break
	super()


## The glow, the light, the lamp, the plate and the roar for the shown batch.
func _update_look() -> void:
	var unlocked: bool = is_unlocked()
	_cold.visible = not unlocked
	_glass.visible = unlocked
	_body_material.albedo_color = METAL_COLOR if unlocked else COLD_COLOR
	_lamp_material.emission_enabled = unlocked
	_lamp_material.albedo_color = LAMP_COLOR if unlocked else TRIM_COLOR
	var batch: AlloyBatch = get_batch() if unlocked else null
	var alloy: AlloyType = batch.alloy if batch else null
	if alloy != _glowing:
		_glowing = alloy
		_fill.material_override = alloy.get_glow_material() if alloy else null
		_light.light_color = alloy.color if alloy else LAMP_COLOR
	var level: float = batch.progress(_now()) if batch else 0.0
	_fill.visible = batch != null
	_fill_pivot.scale = Vector3(1.0, maxf(level, 0.02), 1.0)
	_light.visible = batch != null
	if batch:
		# Two slow sines (under 3 per s, photosensitivity), each furnace out of step.
		var time: float = Time.get_ticks_msec() / 1000.0 + slot * 1.7
		var flicker: float = 0.5 + 0.25 * (sin(time * 11.0) + sin(time * 17.3))
		_light.light_energy = LIGHT_ENERGY * (1.0 - FLICKER * flicker)
		_plate.text = "%s\n%d / %d" % [alloy.get_display_name().to_upper(), batch.done, batch.bars]
	else:
		_plate.text = ""
	if batch and not _roar:
		_roar = Sfx.play_loop_at(ROAR_SOUND, _door)
	elif not batch and _roar:
		Sfx.stop_loop(_roar)
		_roar = null


## The greybox furnace: plinth, body, door frame and window, lamp, flue, plate, collision, and the
## door as its part.
func _build() -> void:
	_body_material.metallic = 0.35
	_body_material.roughness = 0.55
	var trim := StandardMaterial3D.new()
	trim.albedo_color = TRIM_COLOR
	trim.metallic = 0.3
	trim.roughness = 0.6
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.03, 0.025, 0.02)
	glass.roughness = 0.1
	_lamp_material.emission = LAMP_COLOR
	_lamp_material.emission_energy_multiplier = 2.0

	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)
	_box(
		shell,
		Vector3(WIDTH + 0.16, PLINTH_HEIGHT, DEPTH + 0.16),
		Vector3(0.0, PLINTH_HEIGHT * 0.5, 0.0),
		trim
	)
	var body_height: float = HEIGHT - PLINTH_HEIGHT
	_box(
		shell,
		Vector3(WIDTH, body_height, DEPTH),
		Vector3(0.0, PLINTH_HEIGHT + body_height * 0.5, 0.0),
		_body_material
	)
	# A heavier band around the top, like a hood.
	_box(shell, Vector3(WIDTH + 0.08, 0.22, DEPTH + 0.08), Vector3(0.0, HEIGHT - 0.11, 0.0), trim)
	var flue := MeshInstance3D.new()
	var flue_mesh := CylinderMesh.new()
	flue_mesh.top_radius = FLUE_RADIUS
	flue_mesh.bottom_radius = FLUE_RADIUS * 1.3
	flue_mesh.height = FLUE_TOP - HEIGHT
	flue_mesh.radial_segments = 12
	flue_mesh.rings = 1
	flue_mesh.material = trim
	flue.mesh = flue_mesh
	flue.position = Vector3(0.0, (HEIGHT + FLUE_TOP) * 0.5, -DEPTH * 0.2)
	shell.add_child(flue)

	# The door on the front: a frame, dark glass and the glow behind it.
	var front: float = DEPTH * 0.5
	var door_middle: float = DOOR_BOTTOM + DOOR_SIZE.y * 0.5
	_box(
		shell,
		Vector3(DOOR_SIZE.x + 0.14, DOOR_SIZE.y + 0.14, 0.06),
		Vector3(0.0, door_middle, front + 0.03),
		trim
	)
	_glass.name = "Glass"
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(DOOR_SIZE.x, DOOR_SIZE.y, 0.01)
	glass_mesh.material = glass
	_glass.mesh = glass_mesh
	_glass.position = Vector3(0.0, door_middle, front + 0.065)
	shell.add_child(_glass)
	_build_cold(shell, trim, front, door_middle)
	_fill_pivot.name = "Fill"
	_fill.name = "Level"
	_fill_pivot.position = Vector3(0.0, DOOR_BOTTOM, front + 0.075)
	add_child(_fill_pivot)
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(DOOR_SIZE.x - 0.04, DOOR_SIZE.y, 0.01)
	_fill.mesh = fill_mesh
	_fill.position.y = DOOR_SIZE.y * 0.5
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill_pivot.add_child(_fill)

	_lamp.name = "Lamp"
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.06
	lamp_mesh.height = 0.12
	lamp_mesh.material = _lamp_material
	_lamp.mesh = lamp_mesh
	_lamp.position = Vector3(0.0, DOOR_BOTTOM + DOOR_SIZE.y + 0.22, front + 0.04)
	shell.add_child(_lamp)

	_light.name = "Glow"
	_light.position = Vector3(0.0, door_middle, front + 0.6)
	_light.omni_range = 3.0
	_light.shadow_enabled = false
	add_child(_light)

	_plate.name = "Plate"
	_plate.pixel_size = 0.16 / 64.0
	_plate.font_size = 64
	_plate.outline_size = 12
	_plate.modulate = Color(0.85, 0.92, 1.0)
	_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_plate.position = Vector3(0.0, DOOR_BOTTOM - 0.12, front + 0.3)
	_plate.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# Names and numbers: the name is translated by `ItemType.get_display_name`.
	_plate.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_plate.layers = RenderLayers.EFFECTS
	add_child(_plate)

	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH + 0.16, HEIGHT, DEPTH + 0.16)
	shape.shape = box
	shape.position.y = HEIGHT * 0.5
	body.add_child(shape)
	add_child(body)

	_door.name = "Door"
	_door.outline = shell
	_door.position = Vector3(0.0, door_middle, front)
	_door.pick_radius = 0.9
	_door.card_offset = Vector2(1.75, 0.45)
	add_child(_door)


## A locked furnace's open door and empty burner port: the door's panel hinged at the window's
## left edge and swung open, the window a dark hole, and below it the port the burner came out of,
## its two lines cut and capped.
func _build_cold(shell: Node3D, trim: Material, front: float, door_middle: float) -> void:
	_cold.name = "Cold"
	shell.add_child(_cold)
	var hole := StandardMaterial3D.new()
	hole.albedo_color = Color(0.01, 0.01, 0.01)
	hole.roughness = 1.0
	_box(
		_cold,
		Vector3(DOOR_SIZE.x, DOOR_SIZE.y, 0.01),
		Vector3(0.0, door_middle, front + 0.062),
		hole
	)
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	hinge.position = Vector3(-DOOR_SIZE.x * 0.5 - 0.07, door_middle, front + 0.09)
	hinge.rotation.y = deg_to_rad(-DOOR_OPEN_ANGLE)
	_cold.add_child(hinge)
	var panel := Vector3(DOOR_SIZE.x + 0.12, DOOR_SIZE.y + 0.12, 0.06)
	_box(hinge, panel, Vector3(panel.x * 0.5, 0.0, 0.0), trim)
	var port := MeshInstance3D.new()
	port.name = "Port"
	var port_mesh := CylinderMesh.new()
	port_mesh.top_radius = PORT_RADIUS
	port_mesh.bottom_radius = PORT_RADIUS
	port_mesh.height = 0.02
	port_mesh.radial_segments = 16
	port_mesh.rings = 1
	port_mesh.material = hole
	port.mesh = port_mesh
	port.rotation.x = PI * 0.5
	port.position = Vector3(0.0, PORT_HEIGHT, front + 0.005)
	_cold.add_child(port)
	for side: float in [-1.0, 1.0]:
		var line := MeshInstance3D.new()
		var line_mesh := CylinderMesh.new()
		line_mesh.top_radius = 0.025
		line_mesh.bottom_radius = 0.025
		line_mesh.height = 0.12
		line_mesh.radial_segments = 8
		line_mesh.rings = 1
		line_mesh.material = trim
		line.mesh = line_mesh
		line.rotation.x = PI * 0.5
		line.position = Vector3(side * (PORT_RADIUS + 0.09), PORT_HEIGHT, front + 0.06)
		_cold.add_child(line)


func _box(parent: Node3D, box_size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	parent.add_child(instance)
