class_name OreArrival
extends Node3D
## Ore arriving (a child of the player, above its head; see docs/design/ui.md): while a hose
## delivers, a line with each arriving ore's badge and its amount ("+180") shows above the player
## from its first whole unit, counting up; once the ore stops coming (slower than `SETTLE_RATE` for
## `SETTLE_TIME`), it rises and fades over `RISE_TIME`. A slow trickle (a miner filling while the
## player stands by) shows once it adds up to `MIN_AMOUNT`; one that stops before that, or that a
## hose starts over, is forgotten (it doesn't join the next miner's line). Several ores share one
## line. The line is a card (`ItemBadge`s and labels)
## rendered in a SubViewport onto a sprite facing the camera, drawn over everything like the
## damage numbers.

## A trickle shows once it reaches this many units. TBD (playtest).
const MIN_AMOUNT: float = 10.0
## Units per second from which ore comes from a hose (it shows at once); slower is a trickle.
## TBD (playtest).
const SETTLE_RATE: float = 5.0
## Seconds the ore comes slower than `SETTLE_RATE` until a delivery counts as done and rises, or
## doesn't come at all until a trickle not shown yet is forgotten.
const SETTLE_TIME: float = 0.4
## How long a finished delivery rises (s) and how far (m).
const RISE_TIME: float = 2.0
const RISE: float = 0.7
## The card's height in pixels and the sprite's size of a pixel (m): about as tall as the ship's
## countdown.
const LINE_HEIGHT: int = 64
const PIXEL_SIZE: float = 0.008
const FONT_SIZE: int = 52
const OUTLINE_SIZE: int = 14

## The delivery shown (or still forming), per ore.
var amounts: Dictionary[OreType, float] = {}
## Whether the shown delivery is done and rises.
var rising: bool = false

## Ore arriving while the last delivery rises: the next one.
var _next: Dictionary[OreType, float] = {}
## Whether a hose delivered to the delivery forming (`_next` while rising, else `amounts`).
var _streamed: bool = false
## Ore arrived since the last physics step.
var _step: Dictionary[OreType, float] = {}
## Seconds the ore came slower than `SETTLE_RATE`, and seconds none came.
var _slow: float = 0.0
var _idle: float = 0.0
var _age: float = 0.0
var _viewport := SubViewport.new()
var _row := HBoxContainer.new()
var _sprite := Sprite3D.new()
## The amount label per ore shown.
var _labels: Dictionary[OreType, Label] = {}
var _start: Vector3

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	_start = position
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_row.add_theme_constant_override(&"separation", 18)
	_row.resized.connect(_fit)
	_viewport.add_child(_row)
	add_child(_viewport)
	_sprite.texture = _viewport.get_texture()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.no_depth_test = true
	_sprite.shaded = false
	_sprite.pixel_size = PIXEL_SIZE
	_sprite.render_priority = WorldPanel.ON_TOP_PRIORITY
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sprite)
	_player.cargo_added.connect(_on_cargo_added)
	_player.died.connect(clear)
	_show(false)


## Ore arrives in physics steps (the hoses): measured per step, a hose is told from a trickle at
## once.
func _physics_process(delta: float) -> void:
	var arrived: float = _total(_step)
	var hose: bool = arrived >= SETTLE_RATE * delta
	_slow = 0.0 if hose else _slow + delta
	_idle = 0.0 if arrived > 0.0 else _idle + delta
	var batch: Dictionary[OreType, float] = _next if rising else amounts
	if not _shows(batch) and (hose or _idle >= SETTLE_TIME):
		# A trickle not shown yet: not part of a hose starting, and forgotten once it stopped.
		batch.clear()
	_streamed = _streamed or hose
	for ore_type: OreType in _step:
		batch[ore_type] = batch.get(ore_type, 0.0) + _step[ore_type]
	_step.clear()


func _process(delta: float) -> void:
	if rising:
		_age += delta
		if _age >= RISE_TIME or (_shows(_next) and _has_whole(_next)):
			_begin(_next)
	elif _shows(amounts) and _slow >= SETTLE_TIME:
		rising = true
		_age = 0.0
		# The next delivery forms in `_next`.
		_streamed = false
	var shown: bool = (rising or _shows(amounts)) and _has_whole(amounts)
	_show(shown)
	if not shown:
		return
	_update_labels()
	var t: float = clampf(_age / RISE_TIME, 0.0, 1.0) if rising else 0.0
	position = _start + Vector3.UP * RISE * (1.0 - (1.0 - t) * (1.0 - t))
	_sprite.modulate.a = 1.0 - t * t


## Forgets what arrived (the player died and dropped it).
func clear() -> void:
	_begin({})
	_step.clear()
	_streamed = false
	_slow = 0.0
	_idle = 0.0


## The text shown for `ore_type`, or "" when it isn't in the line.
func shown_text(ore_type: OreType) -> String:
	return _labels[ore_type].text if ore_type in _labels and _sprite.visible else ""


func _on_cargo_added(ore_type: OreType, amount: float) -> void:
	_step[ore_type] = _step.get(ore_type, 0.0) + amount


## Starts showing `batch` as the delivery (empty: nothing); `_streamed` stays its own.
func _begin(batch: Dictionary[OreType, float]) -> void:
	amounts = batch.duplicate()
	_next = {}
	rising = false
	_age = 0.0
	position = _start
	for node: Node in _row.get_children():
		_row.remove_child(node)
		node.queue_free()
	_labels.clear()


func _update_labels() -> void:
	for ore_type: OreType in amounts:
		if ore_type not in _labels:
			if amounts[ore_type] < 1.0:
				# No "+0".
				continue
			_add_item(ore_type)
		_labels[ore_type].text = "+%d" % floori(amounts[ore_type])


func _add_item(ore_type: OreType) -> void:
	var item := HBoxContainer.new()
	item.add_theme_constant_override(&"separation", 6)
	var badge := ItemBadge.new(ore_type, false)
	item.add_child(badge)
	var label := Label.new()
	# Numbers only: nothing to translate.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.add_theme_constant_override(&"outline_size", OUTLINE_SIZE)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_color_override(&"font_color", ore_type.color.lerp(Color.WHITE, 0.35))
	item.add_child(label)
	_row.add_child(item)
	# The badge's icon as tall as the digits.
	for child: Node in badge.get_children():
		var icon := child as TextureRect
		if icon:
			icon.custom_minimum_size = Vector2.ONE * LINE_HEIGHT * 0.8
	_labels[ore_type] = label


## Sizes the viewport to the line.
func _fit() -> void:
	var size := Vector2i(ceili(_row.size.x), LINE_HEIGHT)
	_row.position = Vector2.ZERO
	_row.size = Vector2(_row.size.x, LINE_HEIGHT)
	_viewport.size = Vector2i(maxi(size.x, 1), size.y)


func _show(shown: bool) -> void:
	_sprite.visible = shown
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	)


## Whether the delivery forming, `batch`, shows: a hose delivered to it, or it adds up.
func _shows(batch: Dictionary[OreType, float]) -> bool:
	return _streamed or _total(batch) >= MIN_AMOUNT


static func _has_whole(batch: Dictionary[OreType, float]) -> bool:
	for ore_type: OreType in batch:
		if batch[ore_type] >= 1.0:
			return true
	return false


static func _total(batch: Dictionary[OreType, float]) -> float:
	var total: float = 0.0
	for ore_type: OreType in batch:
		total += batch[ore_type]
	return total
