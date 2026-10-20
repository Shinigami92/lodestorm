class_name LobDelivery
extends WeaponDelivery
## Lobs a shot in an arc (Tremor, see `LobbedShot`) that blasts where it lands (see `Blast`): on
## the locked alien or nest, else at the spot the mouse cursor points at, else (the stick, a VR
## hand) `stick_reach` m along the aim; never farther than `reach`. The arc rises with the
## distance, so it clears rocks and cliffs; under a ceiling (aboard the ship, the shooting range) it
## stays flat enough to pass beneath it. A `LandingRing` on the weapon shows where it lands.
## All values TBD (playtest).

## How high the landing spot is looked for above the holder's feet without a spot to aim at (m),
## as high as the cursor finds the ground (so a deck above doesn't catch it).
const GROUND_CEILING: float = PlayerAim.CURSOR_CEILING
## How far the arc's top stays below a ceiling (m), and the flattest arc under one (m).
const CEILING_MARGIN: float = 0.5
const MIN_CEILING_ARC: float = 0.2

## Farthest landing spot (horizontally, m).
@export var reach: float = 22.0
## How far along the aim it lands without a spot to aim at (m).
@export var stick_reach: float = 12.0
## How fast it travels over the ground (m/s), and its shortest flight (s).
@export var speed: float = 16.0
@export var min_flight_time: float = 0.5
## How high the arc rises above the line from the muzzle to the landing spot, per m of distance,
## and at least (m).
@export var arc_per_meter: float = 0.45
@export var min_arc: float = 1.5
## The blast's radius at MK1 (m), larger with the MK level of the weapon's blast.
@export var blast_radius: float = 3.5
## What flies (a `LobbedShot`).
@export var shot_scene: PackedScene

@export_group("Sounds")
## The blast.
@export var blast_sound: Sound


func attack(weapon: Weapon) -> void:
	var holder: CollisionObject3D = weapon.holder
	var shot := shot_scene.instantiate() as LobbedShot
	var muzzle: Vector3 = weapon.get_muzzle().global_position
	var landing: Vector3 = landing_point(weapon)
	var distance: float = Vector2(landing.x - muzzle.x, landing.z - muzzle.z).length()
	shot.start = muzzle
	shot.landing = landing
	shot.flight_time = maxf(distance / speed, min_flight_time)
	shot.arc_height = arc_under_ceiling(
		weapon, muzzle, landing, maxf(distance * arc_per_meter, min_arc)
	)
	shot.hit = weapon.make_hit(landing - muzzle, landing)
	shot.blast_radius = blast_radius_of(weapon)
	shot.blast_sound = blast_sound
	shot.exclude = [holder.get_rid()]
	_prepare(shot, weapon)
	holder.get_parent().add_child(shot)
	shot.global_position = muzzle
	shot.reset_physics_interpolation()


## `arc` (m above the line from `start` to `landing`), lowered so its top stays under a ceiling
## above the middle of the flight, if there's one.
func arc_under_ceiling(weapon: Weapon, start: Vector3, landing: Vector3, arc: float) -> float:
	var middle: Vector3 = start.lerp(landing, 0.5)
	var space: PhysicsDirectSpaceState3D = weapon.holder.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		middle, middle + Vector3.UP * (arc + CEILING_MARGIN), PhysicsLayers.WORLD
	)
	query.exclude = [weapon.holder.get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty() or (result["collider"] is Player or result["collider"] is Alien):
		return arc
	var room: float = (result["position"] as Vector3).y - middle.y - CEILING_MARGIN
	return clampf(room, MIN_CEILING_ARC, arc)


## The radius of `weapon`'s blast with its MK level (m).
func blast_radius_of(weapon: Weapon) -> float:
	return blast_radius * weapon.multiplier(WeaponPart.Stat.BLAST)


## The radius of the ring showing where `weapon`'s shot lands: its blast's.
func ring_radius(weapon: Weapon) -> float:
	return blast_radius_of(weapon)


## Where `weapon`'s next shot lands (global): at the locked target, else the spot the holder
## points at, else `stick_reach` m along the aim; at most `reach` m away (on the ground there).
func landing_point(weapon: Weapon) -> Vector3:
	var from: Vector3 = weapon.holder.global_position
	var spot: Vector3 = from + weapon.aim_direction * stick_reach
	var exact: bool = true
	if PlayerAim.is_lockable(weapon.aim_target):
		spot = weapon.aim_target.global_position
	elif weapon.aim_point.is_finite():
		spot = weapon.aim_point
	else:
		exact = false
	var offset := Vector3(spot.x - from.x, 0.0, spot.z - from.z)
	if offset.length() > reach:
		offset = offset.normalized() * reach
		exact = false
	if exact:
		return spot
	return ground_at(weapon, from + offset)


## The ground (or a rock's top) at `spot`'s place, up to `GROUND_CEILING` m above the holder's
## feet; `spot` at the holder's height if there's none.
func ground_at(weapon: Weapon, spot: Vector3) -> Vector3:
	var holder: CollisionObject3D = weapon.holder
	var top := Vector3(spot.x, holder.global_position.y + GROUND_CEILING, spot.z)
	var space: PhysicsDirectSpaceState3D = holder.get_world_3d().direct_space_state
	var skip: Array[RID] = [holder.get_rid()]
	for _i: int in 8:
		var query := PhysicsRayQueryParameters3D.create(
			top, top + Vector3.DOWN * (GROUND_CEILING * 5.0), PhysicsLayers.WORLD
		)
		query.exclude = skip
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			break
		var collider: Object = result["collider"]
		if collider is Player or collider is Alien or collider is Miner:
			skip.append((collider as CollisionObject3D).get_rid())
			continue
		return result["position"]
	return Vector3(spot.x, holder.global_position.y, spot.z)


## Sets up `shot` of `weapon` further before it flies (a charge's own values).
func _prepare(_shot: LobbedShot, _weapon: Weapon) -> void:
	pass
