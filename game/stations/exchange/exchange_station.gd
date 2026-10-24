class_name ExchangeStation
extends Station
## The ore exchange on the depot master's counter at Waypost Ostra (greybox until the station's art
## pass; the rules are `OreExchange`): two square steel hoppers side by side, the left one taking
## ore in, the right one giving it out, each with a plate in front saying which and the ore picked.
## `interact` in front of the counter opens it as a station with the hoppers as its two parts; the
## card (`ExchangeCard`) shows both: what goes in (any ore the user's hold has three of) and what
## comes out (a common or mid ore it ever had, not the one going in), `tab_prev`/`tab_next` (or the
## card's arrows) picking the ore of the selected hopper, and how much comes out (its buttons
## `COUNT_BUTTONS`, or `zoom_out`/`zoom_in` by one; from 1 up to what the hold pays for), then
## "Exchange", paid at once from the user's own hold. On a trade each hopper glows in its ore's
## color for a moment, with a clatter of ore.

## What the card's buttons add to the amount (the number shows between the minus and the plus
## ones).
const COUNT_BUTTONS: Array[int] = [-10, -5, -1, 1, 5, 10]
## Where the hoppers stand on the counter (its middle at x 0, its front at z `COUNTER_FRONT`), in
## m.
const IN_X: float = -1.5
const OUT_X: float = 1.0
const COUNTER_TOP: float = 1.1
const COUNTER_FRONT: float = 0.45
## How high over the hoppers the card floats, in m (clear of their rims).
const CARD_HEIGHT: float = 1.8
## The hopper: its base, the funnel's height and its half widths at the bottom and the top, in m.
const BASE_SIZE := Vector3(0.6, 0.14, 0.6)
const FUNNEL_HEIGHT: float = 0.5
const FUNNEL_BOTTOM: float = 0.2
const FUNNEL_TOP: float = 0.42
const METAL_COLOR := Color(0.32, 0.31, 0.29)
const PLATE_COLOR := Color(0.85, 0.92, 1.0)
## How brightly the ore glows in a hopper: picked, and flaring up on a trade (fading in
## `FLASH_TIME` s).
const GLOW: float = 0.6
const FLASH: float = 4.0
const FLASH_TIME: float = 1.2
const TRADE_SOUND: Sound = preload("res://assets/audio/sfx/stations/exchange.tres")

## The ore going in and the one coming out (null: none to pick).
var ore_in: OreType
var ore_out: OreType
## How much comes out, as the card shows it (see `get_count`).
var count: int = 1

var _in := StationPart.new()
var _out := StationPart.new()
var _glows: Dictionary[StationPart, StandardMaterial3D] = {}
var _plates: Dictionary[StationPart, Label3D] = {}
## Seconds since the last trade, for the hoppers' flare.
var _since_trade: float = FLASH_TIME


func _ready() -> void:
	_build()
	super()
	_update_look()


func _process(delta: float) -> void:
	super(delta)
	_since_trade += delta
	_update_look()


func get_parts() -> Array[StationPart]:
	return [_in, _out]


## The hopper taking ore in.
func get_in_hopper() -> StationPart:
	return _in


## The hopper giving ore out.
func get_out_hopper() -> StationPart:
	return _out


## The hold the card pays from: the user's, else the viewer's (empty without one).
func get_hold() -> PlayerHold:
	var player: Player = user if user else viewer()
	return player.hold if player else PlayerHold.new()


## How much comes out: `count`, at most what the hold pays for (at least 1).
func get_count() -> int:
	return clampi(count, 1, get_max_count())


## The most the card offers: what the hold pays for with the ore going in (at least 1).
func get_max_count() -> int:
	return maxi(OreExchange.affordable(ore_in, get_hold()), 1)


## Whether the user can trade what the card shows now.
func can_trade() -> bool:
	return user != null and OreExchange.can_trade(ore_in, ore_out, get_count(), user.hold)


## Trades what the card shows, paid from the user's hold. Returns whether it did.
func trade() -> bool:
	if not can_trade():
		return false
	if not OreExchange.trade(ore_in, ore_out, get_count(), user.hold):
		return false
	_since_trade = 0.0
	Sfx.play_at(TRADE_SOUND, global_position + Vector3(0.0, COUNTER_TOP, 0.0))
	# The amount stays for the next trade (`get_count` caps it at what's left).
	_pick_valid()
	refresh()
	return true


## Picks the previous (-1) or next (1) ore of `hopper` (the selected one by default), commonest
## first, skipping the other hopper's ore.
func step_ore(step_by: int, hopper: StationPart = null) -> void:
	var which: StationPart = hopper if hopper else selected
	var hold: PlayerHold = get_hold()
	if which == _in:
		ore_in = _step(OreExchange.ores_in(hold), ore_in, ore_out, step_by)
	elif which == _out:
		ore_out = _step(OreExchange.ores_out(hold), ore_out, ore_in, step_by)
	refresh()


## Shows `step_by` more coming out (fewer when negative), from 1 up to `get_max_count`.
func step_count(step_by: int) -> void:
	count = clampi(get_count() + step_by, 1, get_max_count())
	refresh()


func _cycle(step_by: int) -> void:
	step_ore(step_by)


## `zoom_out`/`zoom_in` (-/+, the wheel, the triggers) take one off or add one.
func _shortcut(event: InputEvent) -> bool:
	for action: StringName in [&"zoom_in", &"zoom_out"] as Array[StringName]:
		if InputMap.has_action(action) and event.is_action_pressed(action, true):
			step_count(1 if action == &"zoom_in" else -1)
			return true
	return false


func _opened() -> void:
	count = 1
	_pick_valid()
	super()


## Keeps the ores picked valid for the hold: going in the one it has most of (unless the one
## picked can still go in), coming out the commonest other one (unless the one picked still can).
func _pick_valid() -> void:
	var hold: PlayerHold = get_hold()
	if not OreExchange.can_put_in(ore_in, hold):
		ore_in = null
		for ore: OreType in OreExchange.ores_in(hold):
			if not ore_in or hold.amount(ore) > hold.amount(ore_in):
				ore_in = ore
	if not OreExchange.can_take_out(ore_out, hold) or ore_out == ore_in:
		ore_out = _step(OreExchange.ores_out(hold), null, ore_in, 1)


## The ore after `current` in `ores` by `step_by` (wrapping around), never `other`; null when
## there's none.
static func _step(ores: Array[OreType], current: OreType, other: OreType, step_by: int) -> OreType:
	ores.erase(other)
	if ores.is_empty():
		return null
	var index: int = ores.find(current)
	if index < 0:
		return ores[0] if step_by > 0 else ores[-1]
	return ores[posmod(index + step_by, ores.size())]


## The hoppers' glow and plates for the ores picked (shown to everyone while someone uses it).
func _update_look() -> void:
	var flare: float = maxf(1.0 - _since_trade / FLASH_TIME, 0.0)
	for hopper: StationPart in [_in, _out] as Array[StationPart]:
		var ore: OreType = (ore_in if hopper == _in else ore_out) if user else null
		var glow: StandardMaterial3D = _glows[hopper]
		glow.emission_enabled = ore != null
		if ore:
			glow.albedo_color = ore.color * 0.4
			glow.emission = ore.color
			glow.emission_energy_multiplier = GLOW + (FLASH - GLOW) * flare
		else:
			glow.albedo_color = Color(0.05, 0.05, 0.05)
		var heading: String = tr("In") if hopper == _in else tr("Out")
		var text: String = heading.to_upper()
		if ore:
			text += "\n" + ore.get_display_name().to_upper()
		_plates[hopper].text = text


## The greybox hoppers on the counter, their plates and glow, the parts.
func _build() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = METAL_COLOR
	metal.metallic = 0.45
	metal.roughness = 0.5
	# The funnel is open at the top: its inside shows.
	var funnel_metal := metal.duplicate() as StandardMaterial3D
	funnel_metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	for hopper: StationPart in [_in, _out] as Array[StationPart]:
		var x: float = IN_X if hopper == _in else OUT_X
		hopper.name = "HopperIn" if hopper == _in else "HopperOut"
		hopper.position = Vector3(x, COUNTER_TOP, 0.0)
		hopper.pick_radius = 0.6
		# Either hopper's card floats in the same place, over the counter between them.
		hopper.card_offset = Vector2((IN_X + OUT_X) * 0.5 - x, CARD_HEIGHT)
		add_child(hopper)
		var shell := Node3D.new()
		shell.name = "Shell"
		hopper.add_child(shell)
		hopper.outline = shell
		var base := MeshInstance3D.new()
		var base_mesh := BoxMesh.new()
		base_mesh.size = BASE_SIZE
		base_mesh.material = metal
		base.mesh = base_mesh
		base.position.y = BASE_SIZE.y * 0.5
		shell.add_child(base)
		# A square funnel: a four-sided cylinder turned to stand square to the counter.
		var funnel := MeshInstance3D.new()
		var funnel_mesh := CylinderMesh.new()
		funnel_mesh.radial_segments = 4
		funnel_mesh.rings = 1
		funnel_mesh.cap_top = false
		funnel_mesh.bottom_radius = FUNNEL_BOTTOM * sqrt(2.0)
		funnel_mesh.top_radius = FUNNEL_TOP * sqrt(2.0)
		funnel_mesh.height = FUNNEL_HEIGHT
		funnel_mesh.material = funnel_metal
		funnel.mesh = funnel_mesh
		funnel.rotation.y = PI * 0.25
		funnel.position.y = BASE_SIZE.y + FUNNEL_HEIGHT * 0.5
		shell.add_child(funnel)
		# The ore inside, a little below the rim (glowing in its color).
		var glow := StandardMaterial3D.new()
		glow.roughness = 0.8
		var ore := MeshInstance3D.new()
		ore.name = "Ore"
		var ore_mesh := BoxMesh.new()
		var inside: float = lerpf(FUNNEL_BOTTOM, FUNNEL_TOP, 0.75) * 2.0
		ore_mesh.size = Vector3(inside, 0.02, inside)
		ore_mesh.material = glow
		ore.mesh = ore_mesh
		ore.position.y = BASE_SIZE.y + FUNNEL_HEIGHT * 0.75
		ore.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hopper.add_child(ore)
		_glows[hopper] = glow
		# The plate on the counter's front below it.
		var plate := Label3D.new()
		plate.name = "Plate"
		plate.pixel_size = 0.12 / 64.0
		plate.font_size = 64
		plate.outline_size = 12
		plate.modulate = PLATE_COLOR
		plate.position = Vector3(0.0, -0.3, COUNTER_FRONT + 0.01)
		plate.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		# Translated in `_update_look`; ore names by `ItemType.get_display_name`.
		plate.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		plate.layers = RenderLayers.EFFECTS
		hopper.add_child(plate)
		_plates[hopper] = plate
