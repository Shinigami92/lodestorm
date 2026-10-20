@abstract class_name WeaponStream
extends Node3D
## What a continuous weapon shows while it fires (a child named `Stream` of its scene): Scald's
## flame (`FlameJet`), a beam (`WeaponBeam`). Every attack keeps it on a moment longer (`fire`),
## so it stays on while the trigger is held and goes out right after; its `loop_sound` plays
## meanwhile, at the weapon. Teammates see it too.

## Attacks' worth of time it stays on after one.
const LINGER: float = 1.6

## Plays while it's on.
@export var loop_sound: Sound

## Where the last attack ended (a beam's end, a flame's reach), in world space.
var end := Vector3.ZERO

var _on_for: float = 0.0
var _was_on: bool = false

@onready var weapon: Weapon = owner as Weapon


func _process(delta: float) -> void:
	_on_for = maxf(_on_for - delta, 0.0)
	var on: bool = is_on()
	if on != _was_on:
		if on:
			weapon.hold_loop(loop_sound, 1.0)
		else:
			weapon.stop_loop()
		_was_on = on
	_show(on, delta)


## Turns it on (or keeps it on) after an attack ending at `at`.
func fire(at: Vector3) -> void:
	end = at
	_on_for = LINGER / weapon.attack_rate()


## Whether it's on: an attack a moment ago, and the weapon shows.
func is_on() -> bool:
	return _on_for > 0.0 and is_visible_in_tree()


## Shows it on or off, every frame.
@abstract func _show(on: bool, delta: float) -> void
