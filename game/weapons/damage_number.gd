class_name DamageNumber
extends Label3D
## The damage of a hit, floating up from the alien or nest and fading (the damage readout skill).
## Hits on the same one within `MERGE_TIME` add up into one number (Brask's pellets).

const META: StringName = &"damage_number"
## How long a number shows (s), how far it rises (m), and how long it takes more hits.
const LIFETIME: float = 0.8
const RISE: float = 0.6
const MERGE_TIME: float = 0.12
const COLOR := Color(1.0, 0.92, 0.75)

## The damage shown.
var amount: float = 0.0

var _age: float = 0.0
var _start: Vector3


func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = false
	pixel_size = 0.011
	font_size = 72
	outline_size = 16
	modulate = COLOR
	outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	render_priority = WorldPanel.ON_TOP_PRIORITY
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var t: float = _age / LIFETIME
	global_position = _start + Vector3.UP * RISE * (1.0 - (1.0 - t) * (1.0 - t))
	modulate.a = 1.0 - t * t


## Adds `damage` to the number shown.
func add(damage: float) -> void:
	amount += damage
	text = str(roundi(amount))


## Whether it still takes more hits.
func is_fresh() -> bool:
	return _age < MERGE_TIME


## Shows `damage` on `target` (an alien or a destructible) if `attacker` is a player with the
## damage readout skill. Returns the number shown, or null (also for no damage).
static func show_hit(attacker: Node, target: Node3D, damage: float) -> DamageNumber:
	var player := attacker as Player
	if (
		not player
		or damage <= 0.0
		or not player.skills.has(Skill.Effect.DAMAGE_READOUT)
		or not target.is_inside_tree()
	):
		return null
	# The last number may be gone already (it frees itself): check before typing it.
	var last: Variant = target.get_meta(META) if target.has_meta(META) else null
	if is_instance_valid(last):
		var shown := last as DamageNumber
		if shown and shown.is_fresh():
			shown.add(damage)
			return shown
	var number := DamageNumber.new()
	number.add(damage)
	target.get_parent().add_child(number)
	number._start = PlayerAim.aim_point(target) + Vector3.UP * 0.5
	number.global_position = number._start
	target.set_meta(META, number)
	return number
