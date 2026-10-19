class_name AlienTremor
extends Node
## The ground shaking around a huge alien (the Ravager, `AlienStrain.tremor`; a child of its
## `Alien`): each of its steps (`thump`) shakes the view of players within `REACH` m, the more the
## closer they are, and throws up dust at the foot; its slam thumps harder. So it's heard before
## it's seen. Values TBD (playtest).

## Players farther away than this feel nothing (horizontally, m).
const REACH: float = 40.0
## Seconds a thump's shake takes to fade.
const FADE: float = 0.35

## How strongly the view shakes at its feet for a thump of 1 (m).
var strength: float = 0.1

## The thump fading now (1: a step).
var _thump: float = 0.0
var _alien: Alien


func _ready() -> void:
	_alien = get_parent() as Alien


func _process(delta: float) -> void:
	_thump = maxf(_thump - delta / FADE, 0.0)
	if _thump == 0.0 or _alien.dead:
		return
	for rig: IsoCameraRig in get_tree().get_nodes_in_group(IsoCameraRig.GROUP):
		if is_instance_valid(rig.target):
			rig.tremble(strength * _thump * felt_at(rig.target.global_position))


## A thump at `at` (global): a foot landing (1), a slam (more).
func thump(at: Vector3, amount: float = 1.0) -> void:
	_thump = maxf(_thump, amount)
	if _alien.is_inside_tree():
		DustPuff.spawn(_alien.get_parent(), at, sqrt(amount))


## How much of a thump is felt at `point` (global): 1 at its feet, 0 from `REACH` on.
func felt_at(point: Vector3) -> float:
	var offset: Vector3 = point - _alien.global_position
	var near: float = clampf(1.0 - Vector2(offset.x, offset.z).length() / REACH, 0.0, 1.0)
	return near * near
