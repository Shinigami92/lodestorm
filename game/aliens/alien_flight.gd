class_name AlienFlight
extends RefCounted
## How a flying alien moves (darters, `AlienStrain.flight_height`): it keeps its height above the
## ground, looking a little ahead so it rises over cliffs and rock before it gets there, and never
## sinks below its target's ground (over a gap it flies on level). It goes straight for its target
## (no paths) and keeps a little apart from other fliers. While it dives (`low`) it flies at its
## strain's `dive_height`, low enough for every weapon; up at its flight height only shots locked
## on it reach it (they fly at the alien, see `PlayerAim`). Values TBD (playtest).

## The living fliers.
const GROUP: StringName = &"flying_aliens"
## How far ahead it looks for rising ground (seconds at its speed).
const LOOK_AHEAD: float = 0.6
## Rays for the ground start this high above it and reach this far below (m).
const RAY_UP: float = 30.0
const RAY_DOWN: float = 60.0
## How fast it closes the gap to its height (per second), and its fastest climb or drop (m/s).
const HEIGHT_GAIN: float = 6.0
const MAX_CLIMB: float = 10.0
## Fliers closer than this keep apart (m), pushed up to this fast when they touch (m/s).
const SEPARATION: float = 1.6
const SEPARATION_PUSH: float = 3.0

## Whether it dives: it flies at its strain's `dive_height` (set by `AlienDive`).
var low: bool = false


## The velocity for `alien` this physics step, moving at `horizontal` (m/s).
func velocity(alien: Alien, horizontal: Vector3) -> Vector3:
	horizontal += _separation(alien)
	var height: float = alien.strain.dive_height if low else alien.strain.flight_height
	var ground: float = maxf(
		ground_below(alien, alien.global_position),
		ground_below(alien, alien.global_position + horizontal * LOOK_AHEAD)
	)
	if is_instance_valid(alien.target):
		ground = maxf(ground, alien.target.global_position.y)
	var climb: float = 0.0
	if ground > -INF:
		climb = clampf(
			(ground + height - alien.global_position.y) * HEIGHT_GAIN, -MAX_CLIMB, MAX_CLIMB
		)
	return Vector3(horizontal.x, climb, horizontal.z)


## The height of the ground under `point` (the highest static surface along a vertical ray from `up`
## above it to `down` below), or -INF when there is none. Players and aliens are skipped.
static func ground_below(
	alien: Alien, point: Vector3, up: float = RAY_UP, down: float = RAY_DOWN
) -> float:
	if not alien.is_inside_tree():
		return -INF
	var space: PhysicsDirectSpaceState3D = alien.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * up, point + Vector3.DOWN * down, PhysicsLayers.WORLD
	)
	var skipped: Array[RID] = [alien.get_rid()]
	query.exclude = skipped
	for attempt: int in 4:
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return -INF
		if hit["collider"] is CharacterBody3D:
			skipped.append(hit["rid"] as RID)
			query.exclude = skipped
			continue
		return (hit["position"] as Vector3).y
	return -INF


## A push away from the other fliers close to it (horizontal, m/s).
func _separation(alien: Alien) -> Vector3:
	var push := Vector3.ZERO
	for node: Node in alien.get_tree().get_nodes_in_group(GROUP):
		var other := node as Alien
		if other == alien:
			continue
		var away: Vector3 = alien.global_position - other.global_position
		away.y = 0.0
		var distance: float = away.length()
		if distance < SEPARATION and distance > 0.001:
			push += away / distance * SEPARATION_PUSH * (1.0 - distance / SEPARATION)
	return push
