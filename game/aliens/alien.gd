class_name Alien
extends CharacterBody3D
## Alien: one body of the hive, of a strain (`strain`: its values and attacks; the swarmer's body is
## assets/aliens/swarmer/swarmer.glb). Waits until a living player outside the ship comes within
## `strain.detection_range`, then chases the nearest one and attacks it with the first of its
## attacks that is ready and in range (`AlienAttack`: a wind-up as the telegraph, the attack,
## standing still afterwards). A player gets away by running farther than `strain.chase_range` or
## by going aboard; aliens don't hunt players inside the ship. Where there is a navigation mesh it
## walks around obstacles along it and steers around other aliens; elsewhere it goes straight. Some
## strains keep away from their target (`strain.keep_away`: spitters back off), burrowers travel
## under the ground (`strain.burrows`: out of reach, only a `BurrowRipple` shows) and come up to
## attack, tenders mend the aliens around them (`strain.mend`: see `MendLinks`), darters fly
## (`strain.flight_height`: see `AlienFlight`), stalkers hide (`strain.cloak`: see
## `AlienCloaking`) and back off after each attack (`strain.retreat_time`), and the Ravager roams
## the location (`strain.roams`, `route`) and shakes the ground (`strain.tremor`: see
## `AlienTremor`). A gravity well (Nadir's) pulls it in and holds it (see `AlienStatus.hold`), a
## punch (Clout's) throws it (`thrown`). A shrieker's scream speeds up the aliens near it and
## calls for help (`called_for_help`, answered by the nearest nest); in the hive's frenzy all of
## them are faster (see `status`). While a scream boosts it or a tender's link holds it, it's a
## little bigger and outlined in the hive's yellow-green.
## Its role (set from its strain by the nest) says what it goes for: guards stay by their nest
## (within `strain.leash` of where they hatched, walking back when a player gets away) and go for
## a player who hits it from any distance (`AlienStatus.defending`), hunters go
## for the nearest player outside however far away and never give up because of distance, and
## raiders go for the nearest miner that still works, however far away, biting only a player who
## stands in their way; without a working miner they walk back and guard. It grows out of the
## ground when it appears. Hits (`take_hit`) lose
## its armor's share, flash it white, spray ichor (sparks off armor), push it back and fill its
## stagger meter; past the strain's threshold it rears up, staggered, and its attack is broken off.
## At zero health it stops, collapses, sinks into the ground and disappears. Its legs step on
## their own (`AlienLegs`), the body plays the model's clips (`AlienAnimator`) and is posed on top
## of them (`AlienPose`). Its eyes and glands (the model's `Eyes` and `Glands`) flare during a
## wind-up. Its sounds (chitter, telegraphs, strikes, hits, death) come from `AlienSounds`.

## Emitted when health reaches zero.
signal died
## Emitted for every hit it takes, with the damage that got through and whether it hit armor.
signal hit_taken(hit: Hit, dealt: float, armored: bool)
## Emitted when it calls the hive for help at `at` (a shrieker's scream: emitted by
## `AlienScream`): the nest nearest to it answers with a pack, boosted `boost` times for `seconds`.
@warning_ignore("unused_signal")
signal called_for_help(at: Vector3, boost: float, seconds: float)
## Emitted when an attack's wind-up starts (its telegraph), and when it acts after it.
signal winding_up(attack: AlienAttack)
signal acting(attack: AlienAttack)
## Emitted when it hits `victim` (a player or a miner) with a strike.
signal struck(victim: Node3D)

## Guards wait until a player comes close, hunters go for players and raiders for miners.
enum Role { GUARD, HUNTER, RAIDER }
## What it's doing with its attack: the telegraph, the attack itself, standing still afterwards.
enum AttackPhase { NONE, WIND_UP, ACT, RECOVER }

const GROUP: StringName = &"aliens"

## The hive's yellow-green: eyes, glands, nests, ichor and acid (no ore uses it).
const COLOR_GLOW := Color(0.9, 1.0, 0.2)

## Share of a hit's damage that always gets through armor.
const MIN_DAMAGE_SHARE: float = 0.25
## Seconds a full stagger meter takes to drain.
const STAGGER_DRAIN_TIME: float = 1.0
## How fast a push fades (per second).
const PUSH_DECAY: float = 8.0
## How much brighter the eyes glow when fully crouched for an attack, and while it's faster than
## its strain (a scream's boost, the hive's frenzy).
const EYE_FLARE: float = 4.0
const EYE_FLARE_FAST: float = 0.8
## A leap ends early when it moves slower than this share of its speed (it ran into something).
const LUNGE_STALL: float = 0.3
## Burrowers dig in only for targets farther away than this (m); closer, they fight up top.
const DIG_DISTANCE: float = 3.0
## How deep a burrower's body sinks under the ground (m).
const BURROW_DEPTH: float = 1.2
## Without a target, guards walk back once they're this far from where they hatched (m).
const HOME_RADIUS: float = 1.5
## A roaming alien heads for its route's next point once it's this close to the one it walked to
## (m).
const ROAM_ARRIVE: float = 4.0
## Seconds a flier takes to drop to the ground when it dies.
const FALL_TIME: float = 0.4
## The rim light is weaker than on players and machines: the alien's many thin, curved parts
## would glow all over.
const RIM_STRENGTH: float = 0.45
## While boosted or mended (see `AlienStatus.is_buffed`): how much bigger it gets, how fast it
## grows and shrinks back (per second), and its outline's strength.
const BUFFED_SCALE: float = 1.15
const BUFFED_GROW_SPEED: float = 6.0
const BUFFED_RIM_STRENGTH: float = 1.6
## A hit flash covers the model in white.
const COLOR_FLASH := Color(1.0, 1.0, 1.0, 0.85)
## Seconds a hit flash lasts.
const FLASH_DURATION: float = 0.1
## Seconds the body takes to grow out of the ground when the alien appears.
const HATCH_DURATION: float = 0.4
## Faster than this (m/s), it faces where it goes; slower, where it wants to go.
const FACE_VELOCITY_MIN: float = 1.0
## Under the ground it doesn't move on where the ground rises more than this (m): a rock or a cliff.
const UNDERGROUND_CLIMB: float = 0.6
## Slower than this (m/s) on the ground, it stands: it doesn't move at all.
const STAND_SPEED: float = 0.01
## Its model counts as on screen this far (m) beyond its body, so its shadow and legs reaching
## into the view still move.
const SCREEN_MARGIN: float = 1.5
## Seconds the body lies on the ground after dying (the "Die" clip takes 1 s).
const COLLAPSE_DURATION: float = 1.2
## Seconds it then takes to sink into the ground.
const SINK_DURATION: float = 0.5
## How far it sinks, in m.
const SINK_DEPTH: float = 0.6
## Seconds from death until the alien is gone.
const DEATH_DURATION: float = COLLAPSE_DURATION + SINK_DURATION

## Whether aliens think (the debug overlay switches it): off, every alien stands where it is,
## without a target or an attack (one under way is broken off, burrowers come up), but can still be
## hit, pushed, staggered and killed.
static var ai_on: bool = true
## Whether aliens off screen stop their legs and clips (see `_on_screen_changed`). Without a display
## (headless: tests, a server) nothing is ever on screen, so it's off there.
static var culls_off_screen: bool = DisplayServer.get_name() != "headless"
## Shared by all aliens (see `RIM_STRENGTH`).
static var _rim: ShaderMaterial
static var _buffed_rim: ShaderMaterial

## Set by `AlienStrain.spawn`.
@export var strain: AlienStrain
## Hunters and raiders go for their target however far away and never let it get away by distance.
@export var role := Role.GUARD
## Where it hatched (global): guards (and raiders without a miner) stay near it. Set when it enters
## the tree.
var home := Vector3.INF
## Where it roams without a target (global points, `strain.roams`), set before it enters the tree.
var route: Array[Vector3] = []

## How much stronger than its strain it is (more health, more damage): bodies farther in have
## stronger aliens (see `MissionSettings.alien_health_at`). Set before it enters the tree.
var health_factor: float = 1.0
var damage_factor: float = 1.0
## A scream's boost, the hive's frenzy and a tender's link on it.
var status := AlienStatus.new()
## Where an attack under way wants it to face (horizontal; zero: at its target), e.g. a charge's
## line.
var attack_facing := Vector3.ZERO
## Current health, from 0 to `max_health()`.
var health: float
## Dead aliens don't move or attack; they disappear after `DEATH_DURATION`.
var dead: bool = false
## The player or miner being chased, or null.
var target: Node3D
## The ground hazards it stands in (slick ice).
var ground_contact := GroundContact.new()
## How full the stagger meter is (see `AlienStrain.stagger_threshold`).
var stagger: float = 0.0
## Whether the leap under way hit already (see `AlienPounce`), and whether it ended because it
## ran into something.
var lunge_hit: bool = false
var lunge_stalled: bool = false
## Whether it's under the ground (burrowers): it can't be hit and doesn't block anyone.
var underground: bool = false
## How it flies (fliers only, see `strain.flight_height`).
var flight := AlienFlight.new()
## Its flight from a punch (see `AlienThrow`).
var thrown := AlienThrow.new()
## Its see-through body (stalkers), and the ground shaking around it (the Ravager), or null.
var cloaking: AlienCloaking
var tremor: AlienTremor

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## The attack under way and its phase, and the seconds the phase has run.
var _attack: AlienAttack
## Whether the attack's clip moves the legs right now (see `AlienAttack.clip_lead`).
var _clip_legs: bool = false
var _phase := AttackPhase.NONE
var _phase_time: float = 0.0
## Seconds until each attack can start again.
var _cooldowns: Dictionary[AlienAttack, float] = {}
## Seconds of stagger left.
var _staggered: float = 0.0
## The push of the last hits (m/s), fading, and how much of it the velocity holds.
var _push := Vector3.ZERO
var _push_applied := Vector3.ZERO
## The leap under way: where it goes, how far, and the velocity the attack asks for this tick.
var _lunge_direction := Vector3.ZERO
var _lunge_length: float = 0.0
var _lunge_velocity := Vector3.ZERO
var _flash_left: float = 0.0
## Seconds since a burrower came up.
var _surfaced_for: float = 0.0
## Seconds it still backs off after an attack (`strain.retreat_time`).
var _retreat_left: float = 0.0
## The route's point it walks to, or -1.
var _route_index: int = -1
## Which way it circles its target (`strain.circles`): 1 or -1.
var _circle_side: float = 1.0 if randf() < 0.5 else -1.0
var _dig_tween: Tween
var _ripple: BurrowRipple
## Laid over the model: the hit flash, and the rim light as its next pass.
var _overlay := StandardMaterial3D.new()
## The eyes' and glands' own materials, flaring during a wind-up, and their usual energy.
var _glows: Array[BaseMaterial3D] = []
var _glow_energies: Array[float] = []
var _hatch_tween: Tween
var _legs := AlienLegs.new()
var _pose := AlienPose.new()
var _pathing: AlienPathing
var _screen := VisibleOnScreenNotifier3D.new()

@onready var _body: Node3D = $Body
@onready var _model: Node3D = $Body/Model
@onready var _animator: AlienAnimator = $Animator
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	assert(strain != null, "Alien without a strain: hatch it with AlienStrain.spawn")
	if home == Vector3.INF:
		home = global_position
	add_to_group(GROUP)
	health = max_health()
	_animator.run_speed = strain.move_speed
	_animator.setup(_model)
	_legs.step_distance *= strain.stride
	_legs.step_distance_per_speed *= strain.stride
	_legs.step_height *= strain.stride
	(_model.find_child("Skeleton3D", true, false) as Skeleton3D).add_child(_legs)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if not _rim:
		_rim = preload("res://assets/shaders/rim_light.tres").duplicate() as ShaderMaterial
		_rim.set_shader_parameter(&"strength", RIM_STRENGTH)
		_buffed_rim = _rim.duplicate() as ShaderMaterial
		_buffed_rim.set_shader_parameter(&"color", COLOR_GLOW)
		_buffed_rim.set_shader_parameter(&"strength", BUFFED_RIM_STRENGTH)
	_overlay.next_pass = _rim
	# Seen behind cliffs too, as a red silhouette.
	var creature := _model.find_child("Creature", true, false) as GeometryInstance3D
	creature.material_overlay = OccludedSilhouette.overlay(OccludedSilhouette.ALIEN_COLOR, _overlay)
	OccludedSilhouette.mark_visible(_model)
	RenderLayers.put(_model, RenderLayers.CHARACTERS)
	for part: String in ["Eyes", "Glands"]:
		var glowing := _model.find_child(part, true, false) as MeshInstance3D
		if glowing and glowing.mesh.surface_get_material(0) is BaseMaterial3D:
			var glow := glowing.mesh.surface_get_material(0).duplicate() as BaseMaterial3D
			_glows.append(glow)
			_glow_energies.append(glow.emission_energy_multiplier)
			glowing.material_override = glow
	if strain.burrows:
		_ripple = BurrowRipple.new()
		add_child(_ripple)
	if strain.mend:
		var links := MendLinks.new()
		links.mend = strain.mend
		add_child(links)
	if strain.cloak:
		cloaking = AlienCloaking.new()
		cloaking.cloak = strain.cloak
		add_child(cloaking)
	if strain.tremor > 0.0:
		tremor = AlienTremor.new()
		tremor.strength = strain.tremor
		add_child(tremor)
		_legs.stepped.connect(tremor.thump)
	if strain.flies():
		add_to_group(AlienFlight.GROUP)
	_watch_screen(creature)
	_update_look()
	_body.scale = Vector3.ONE * 0.01
	_hatch_tween = create_tween()
	_hatch_tween.tween_property(_body, ^"scale", Vector3.ONE, HATCH_DURATION)
	# The feet spread out while it grows: put them where they belong at full size.
	_hatch_tween.tween_callback(_legs.plant_all)
	_pathing = AlienPathing.new(self, _agent)
	_agent.velocity_computed.connect(_on_velocity_computed)
	var sounds := AlienSounds.new()
	sounds.name = "Sounds"
	sounds.alien = self
	add_child(sounds)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_count_down(delta)
	if _held() and _attack and _attack.moves():
		_end_attack()
	if not ai_on:
		_stand_still()
	elif _phase == AttackPhase.NONE:
		_update_target()
		if strain.burrows:
			_update_burrow()

	var wanted := Vector3.ZERO
	var lunging: bool = false
	var facing := Vector3.ZERO
	if _staggered > 0.0 or not ai_on:
		pass
	elif _phase != AttackPhase.NONE:
		_lunge_velocity = Vector3.ZERO
		_process_attack(delta)
		lunging = _lunge_velocity != Vector3.ZERO
		if lunging:
			facing = _lunge_direction
		elif attack_facing != Vector3.ZERO:
			facing = attack_facing
		else:
			facing = _offset_to(target)
		if _attack and _attack.on_the_move and is_instance_valid(target):
			wanted = _chase(_offset_to(target).length())
	elif _held():
		# In a gravity well: it doesn't walk, only attacks that don't move it.
		if is_instance_valid(target):
			facing = _offset_to(target)
			_start_attack(facing.length())
	elif target and _retreat_left > 0.0:
		wanted = _pathing.direction_away_from(target)
		facing = _offset_to(target)
	elif not target and strain.roams and not route.is_empty():
		wanted = _roam()
	elif not target and strain.leash > 0.0 and role != Role.HUNTER:
		# Back to where it hatched.
		var back: Vector3 = home - global_position
		if Vector2(back.x, back.z).length() > HOME_RADIUS:
			wanted = _pathing.direction_to(home)
	elif target:
		var offset: Vector3 = _offset_to(target)
		var distance: float = offset.length()
		if not _start_attack(distance):
			wanted = _chase(distance)
		facing = offset
	# Face where it actually goes (avoidance and acceleration bend the path), or the target when
	# it stands.
	if not lunging and _phase == AttackPhase.NONE and not _held():
		var moving := Vector3(velocity.x, 0.0, velocity.z)
		if moving.length() >= FACE_VELOCITY_MIN:
			facing = moving
		elif wanted != Vector3.ZERO:
			facing = wanted
	if facing != Vector3.ZERO and _staggered == 0.0:
		_turn_to(facing, delta)

	var horizontal: Vector3
	if thrown.is_flying():
		horizontal = thrown.step(self, delta)
	elif lunging:
		horizontal = _lunge_velocity
	elif _held():
		horizontal = status.pull
	else:
		horizontal = Vector3(velocity.x, 0.0, velocity.z) - _push_applied
		horizontal = horizontal.move_toward(
			wanted * strain.move_speed * status.speed() * ground_contact.speed(),
			strain.acceleration * ground_contact.grip() * delta
		)
	horizontal += _push
	_push_applied = _push
	_push *= exp(-PUSH_DECAY * delta)
	if underground:
		_move_underground(horizontal, delta)
		return
	if strain.flies():
		velocity = flight.velocity(self, horizontal)
		move_and_slide()
		return
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	# Avoidance only runs with a navigation mesh while it walks (not in a leap or a well's pull); it
	# answers with `velocity_computed`.
	var avoiding: bool = (
		AlienPathing.has_navigation(self) and not lunging and not _held() and not thrown.is_flying()
	)
	if _agent.avoidance_enabled != avoiding:
		_agent.avoidance_enabled = avoiding
	if avoiding:
		_agent.max_speed = strain.move_speed * status.speed() + _push.length()
		_agent.velocity = horizontal
	else:
		_on_velocity_computed(horizontal)
		thrown.check_impact(self)


func _process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _ripple:
		_ripple.active = underground and not dead
		var moving: float = 0.5 if Vector2(velocity.x, velocity.z).length() > 0.5 else 0.0
		_ripple.strength = 1.0 if is_winding_up() else moving
	_animator.speed = 0.0 if dead else Vector2(velocity.x, velocity.z).length()
	var buffed: bool = status.is_buffed() and not dead
	var size: float = BUFFED_SCALE if buffed else 1.0
	_model.scale = _model.scale.lerp(Vector3.ONE * size, 1.0 - exp(-BUFFED_GROW_SPEED * delta))
	var rim: ShaderMaterial = _buffed_rim if buffed else _rim
	if cloaking and cloaking.is_cloaked():
		rim = null
	if _overlay.next_pass != rim:
		_overlay.next_pass = rim
	if not dead:
		# Keeps the scale: it grows while hatching.
		var pose: Transform3D = _pose.update(delta)
		_body.position = pose.origin
		_body.quaternion = pose.basis.get_rotation_quaternion()
	_update_look()


## Hits `victim` (a player or a miner) for `amount` (scaled by `damage_factor`) and plays the
## strike.
func strike(victim: Node3D, amount: float) -> void:
	if not is_instance_valid(victim):
		return
	if cloaking and cloaking.ambush:
		amount = maxf(amount, strain.cloak.ambush_damage)
		cloaking.ambush = false
	hurt(victim, amount * damage_factor, global_position, self)
	play_attack()
	struck.emit(victim)


## Plays the model's attack clip once.
func play_attack() -> void:
	_animator.attack()


## Hurts `victim` (a player or a miner) by `amount`, coming from `from` (for a player's hit marks).
## A blow of an `attacker` (`heavy`: a charge, a slam) may be stopped by a player's shield; shots
## and acid aren't blows (shots stop at a shield's field on their way, see `ShieldField`).
static func hurt(
	victim: Node3D,
	amount: float,
	from: Vector3 = Vector3.INF,
	attacker: Alien = null,
	heavy: bool = false
) -> void:
	if victim is Player:
		(victim as Player).take_damage(amount, from, attacker, heavy)
	elif victim is Miner:
		(victim as Miner).take_damage(amount)


## Health of the unhurt alien.
func max_health() -> float:
	return strain.max_health * health_factor


## Where shots aim at: the middle of its body.
func get_aim_point() -> Vector3:
	return _collision.global_position


## How close it has to come to `node` for an attack reaching `reach` (horizontally, center to
## center): a miner's body radius is added.
func reach_to(node: Node3D, reach: float) -> float:
	return reach + ((node as Miner).body_radius if node is Miner else 0.0)


func horizontal_distance(node: Node3D) -> float:
	return _offset_to(node).length()


## Whether it's winding up, attacking or recovering from an attack.
func is_attacking() -> bool:
	return _phase != AttackPhase.NONE


## Whether shots, swings and the target lock can reach it: alive and not under the ground.
func is_hittable() -> bool:
	return not dead and not underground and is_inside_tree()


## Whether it's winding up for an attack (its telegraph).
func is_winding_up() -> bool:
	return _phase == AttackPhase.WIND_UP


func is_staggered() -> bool:
	return _staggered > 0.0


## Starts a leap of `length` m along `direction` (horizontal), arcing `height` m (see
## `AlienPounce`); `running`, it runs on its legs instead (a charge, see `AlienCharge`).
func lunge(direction: Vector3, length: float, height: float, running: bool = false) -> void:
	_lunge_direction = direction
	_lunge_length = length
	lunge_hit = false
	lunge_stalled = false
	_pose.leap_height = height
	_pose.leap = 0.0
	# In a leap, the legs hang in the clip's pose in the air.
	_legs.active = running


## Goes on with the leap at `speed`, `travelled` m into it. Returns whether it's over (its length
## reached, or it ran into something: `lunge_stalled`).
func lunge_step(speed: float, travelled: float) -> bool:
	_pose.leap = clampf(travelled / _lunge_length, 0.0, 1.0) if _lunge_length > 0.0 else 1.0
	if travelled >= _lunge_length:
		return true
	var real := get_real_velocity()
	if travelled > 0.0 and Vector2(real.x, real.z).length() < speed * LUNGE_STALL:
		lunge_stalled = true
		return true
	_lunge_velocity = _lunge_direction * speed
	return false


## Digs in under the ground (burrowers): it sinks, can't be hit and travels on as a ripple.
func dig_in() -> void:
	if underground or dead:
		return
	underground = true
	_end_attack()
	_collision.set_deferred(&"disabled", true)
	_agent.avoidance_enabled = false
	_legs.active = false
	_sink_to(BURROW_DEPTH, _hide_model)


## Comes up from under the ground where it is (burrowers).
func surface() -> void:
	if not underground:
		return
	underground = false
	_surfaced_for = 0.0
	_collision.set_deferred(&"disabled", false)
	_model.visible = true
	_legs.plant_all()
	_legs.active = true
	_sink_to(0.0)


## Takes `hit`: armor takes its share (on the armored side), it flashes, sprays, is pushed back (or
## thrown, see `thrown`) and its stagger fills. Returns the damage that got through.
func take_hit(hit: Hit) -> float:
	if dead or underground or hit.damage <= 0.0:
		return 0.0
	var armor: float = _armor_against(hit.direction)
	var armored: bool = armor > 0.0
	var dealt: float = hit.damage
	if armored:
		dealt = maxf(hit.damage - armor, hit.damage * MIN_DAMAGE_SHARE)
	_push += hit.direction * hit.push * strain.knockback
	if hit.slow < 1.0:
		status.slow(hit.slow, hit.slow_time)
	if hit.spray and is_inside_tree():
		HitSpray.spawn(get_parent(), hit.point, hit.direction, armored)
	_pose.jolt()
	if _staggered == 0.0:
		var on_plates: bool = strain.armor > 0.0 and _on_armor(hit.direction)
		stagger += hit.stagger * (strain.armored_stagger if on_plates else 1.0)
		if stagger >= strain.stagger_threshold:
			_stagger()
	hit_taken.emit(hit, dealt, armored)
	take_damage(dealt)
	if hit.throw and not dead:
		thrown.start(self, hit)
	return dealt


## Stops it for `seconds`, its attack broken off (a stagger; a charge into a wall).
func stagger_for(seconds: float) -> void:
	stagger = 0.0
	_staggered = maxf(_staggered, seconds)
	_pose.stagger(seconds)
	_end_attack()


## Loses `amount` health, past its armor (burning ground, the debug overlay); dies at zero.
func take_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_flash_left = FLASH_DURATION
	if health == 0.0:
		_die()


## Whether `player` can be hunted: alive and not aboard a ship.
static func is_prey(tree: SceneTree, player: Player) -> bool:
	if player.dead:
		return false
	for ship: Ship in tree.get_nodes_in_group(Ship.GROUP):
		if ship.is_aboard(player):
			return false
	return true


## How much the living aliens count towards the cap (see `AlienStrain.cap_share`).
static func living_load(tree: SceneTree) -> float:
	var total: float = 0.0
	for alien: Alien in tree.get_nodes_in_group(GROUP):
		total += alien.strain.cap_share
	return total


## Keeps chasing the target while it's in `strain.chase_range` (with a leash: while it's within
## `strain.leash` of home), otherwise picks the nearest prey in `strain.detection_range`.
## Hunters keep their prey and pick it from any distance. Raiders keep their miner until it
## breaks and pick the nearest working one from any distance, turning on a player only while one
## stands in reach; without a working miner they act like guards. Guards defending their nest go
## for its attacker first.
func _update_target() -> void:
	if role == Role.GUARD and _defends():
		return
	if role == Role.RAIDER and _update_miner_target():
		var in_way: Player = _player_in_reach()
		if in_way:
			target = in_way
		return
	if is_instance_valid(target) and target is Player and is_prey(get_tree(), target as Player):
		if role == Role.HUNTER or _keeps_chasing(target):
			return
	target = null
	var nearest_distance: float = INF if role == Role.HUNTER else strain.detection_range
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if not is_prey(get_tree(), player):
			continue
		var distance: float = horizontal_distance(player)
		if distance <= nearest_distance and (role == Role.HUNTER or _within_leash(player)):
			target = player
			nearest_distance = distance


## Whether it defends its nest (`status.defending`): the attacker is prey and within its leash,
## then it's the target. Otherwise it forgets them.
func _defends() -> bool:
	if not is_instance_valid(status.defending):
		status.defending = null
		return false
	var attacker := status.defending as Player
	if attacker and is_prey(get_tree(), attacker) and _within_leash(attacker):
		target = attacker
		return true
	status.defending = null
	return false


## Whether a guard (or a raider without a miner) keeps chasing `node`: within its chase range,
## and with a leash, not too far from home.
func _keeps_chasing(node: Node3D) -> bool:
	return horizontal_distance(node) <= strain.chase_range and _within_leash(node)


## Whether `node` is within `strain.leash` of home (always without a leash).
func _within_leash(node: Node3D) -> bool:
	if strain.leash <= 0.0:
		return true
	var offset: Vector3 = node.global_position - home
	return Vector2(offset.x, offset.z).length() <= strain.leash


## A living player outside within reach of its closest attack (in a raider's way), or null.
func _player_in_reach() -> Player:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if is_prey(get_tree(), player) and horizontal_distance(player) <= strain.reach():
			return player
	return null


## Keeps the target miner while it works, otherwise picks the nearest working one. Returns
## whether there is one.
func _update_miner_target() -> bool:
	if is_instance_valid(target) and target is Miner and not (target as Miner).broken:
		return true
	target = null
	var nearest_distance: float = INF
	for miner: Miner in get_tree().get_nodes_in_group(Miner.GROUP):
		var distance: float = horizontal_distance(miner)
		if not miner.broken and distance <= nearest_distance:
			target = miner
			nearest_distance = distance
	return target != null


## Starts the first attack that is ready and has the target in range. Returns whether one started.
func _start_attack(distance: float) -> bool:
	for attack: AlienAttack in strain.attacks:
		if _cooldowns.get(attack, 0.0) > 0.0 or (attack.moves() and _held()):
			continue
		if not attack.can_start(self, target, distance):
			continue
		_attack = attack
		_cooldowns[attack] = attack.cooldown
		_phase = AttackPhase.WIND_UP
		_phase_time = 0.0
		if cloaking:
			cloaking.reveal(true)
		attack.prepare(self)
		winding_up.emit(attack)
		_process_attack(0.0)
		return true
	return false


## Runs the attack under way for `delta` seconds: the wind-up (crouching), the attack, the
## recovery.
func _process_attack(delta: float) -> void:
	_phase_time += delta
	if _phase == AttackPhase.WIND_UP:
		if not is_instance_valid(target):
			_end_attack()
			return
		if _attack.clip_lead > 0.0:
			if not _clip_legs and _phase_time >= _attack.wind_up - _attack.clip_lead:
				play_attack()
				_clip_legs = true
				_legs.active = false
		else:
			_pose.crouch = 1.0
		if _phase_time < _attack.wind_up:
			return
		_pose.crouch = 0.0
		_phase = AttackPhase.ACT
		_phase_time = 0.0
		acting.emit(_attack)
		_attack.begin(self)
	if _phase == AttackPhase.ACT:
		if not _attack.act(self, _phase_time):
			return
		_land()
		_phase = AttackPhase.RECOVER
		_phase_time = 0.0
	if _phase == AttackPhase.RECOVER and _phase_time >= _attack.recovery:
		_end_attack()


## Breaks off or ends the attack under way.
func _end_attack() -> void:
	if _phase == AttackPhase.ACT:
		_land()
	if _clip_legs:
		_clip_legs = false
		if _phase != AttackPhase.RECOVER:
			_animator.stop_attack()
		if not underground and not dead:
			_legs.plant_all()
			_legs.active = true
	if _attack:
		_attack.finish(self)
		if not dead:
			_retreat_left = strain.retreat_time
	if cloaking:
		cloaking.ambush = false
	_attack = null
	_phase = AttackPhase.NONE
	_phase_time = 0.0
	_pose.crouch = 0.0
	attack_facing = Vector3.ZERO


## Ends a leap, if one is under way: back on its feet.
func _land() -> void:
	_lunge_velocity = Vector3.ZERO
	_pose.leap = 0.0
	if not _legs.active and not _clip_legs:
		# It lands on its feet, without sliding on.
		velocity = Vector3(0.0, velocity.y, 0.0)
		_legs.plant_all()
		_legs.active = true


## Horizontal direction it goes for its target, `distance` m away, when it doesn't attack: away
## while closer than `strain.keep_away`, towards it out of reach of its attacks, around it in
## between if it circles (`strain.circles`), otherwise nowhere.
func _chase(distance: float) -> Vector3:
	if strain.keep_away > 0.0 and distance < strain.keep_away:
		return _pathing.direction_away_from(target)
	if distance > reach_to(target, strain.reach(underground)):
		return _pathing.direction_to(target.global_position)
	if strain.circles and distance > 0.01:
		return _offset_to(target).normalized().cross(Vector3.UP) * _circle_side
	return Vector3.ZERO


## Horizontal direction along its route: to the point it walks to, and once there to another one,
## picked at random.
func _roam() -> Vector3:
	var arrived: bool = false
	if _route_index >= 0:
		var offset: Vector3 = route[_route_index] - global_position
		arrived = Vector2(offset.x, offset.z).length() < ROAM_ARRIVE
	if _route_index < 0 or arrived:
		var next: int = randi() % route.size()
		if route.size() > 1 and next == _route_index:
			next = (next + 1) % route.size()
		_route_index = next
	return _pathing.direction_to(route[_route_index])


## Without its AI (`ai_on`): no target, the attack under way broken off, up from under the ground.
func _stand_still() -> void:
	target = null
	if _phase != AttackPhase.NONE:
		_end_attack()
	if underground:
		surface()


## Burrowers dig in for a target farther away once they've been up for `strain.surface_time`, and
## come up without one.
func _update_burrow() -> void:
	if underground:
		if not is_instance_valid(target):
			surface()
	elif is_instance_valid(target) and _surfaced_for >= strain.surface_time and not _held():
		if horizontal_distance(target) > reach_to(target, DIG_DISTANCE):
			dig_in()


## Moves it under the ground at `horizontal` (m/s), along the ground's surface: nothing blocks it
## there, but it doesn't move on under rocks and cliffs.
func _move_underground(horizontal: Vector3, delta: float) -> void:
	velocity = horizontal
	var next: Vector3 = global_position + horizontal * delta
	var ground: float = AlienFlight.ground_below(self, next, UNDERGROUND_CLIMB, BURROW_DEPTH * 2.0)
	if ground == -INF:
		# Under a rock or a cliff, or beyond the ground's edge: it stays.
		velocity = Vector3.ZERO
		return
	next.y = ground
	global_position = next


func _sink_to(depth: float, then: Callable = Callable()) -> void:
	if _dig_tween:
		_dig_tween.kill()
	_dig_tween = create_tween()
	_dig_tween.tween_property(_pose, ^"sink", depth, strain.dig_time)
	if then.is_valid():
		_dig_tween.tween_callback(then)


func _hide_model() -> void:
	_model.visible = false


## Whether a gravity well holds it (see `AlienStatus.hold`).
func _held() -> bool:
	return strain.held_by_wells and status.is_held()


func _stagger() -> void:
	stagger_for(strain.stagger_time)


func _count_down(delta: float) -> void:
	for attack: AlienAttack in _cooldowns:
		_cooldowns[attack] = maxf(_cooldowns[attack] - delta, 0.0)
	_staggered = maxf(_staggered - delta, 0.0)
	_retreat_left = maxf(_retreat_left - delta, 0.0)
	_pathing.tick(delta)
	status.tick(delta)
	if not underground:
		_surfaced_for += delta
	stagger = maxf(stagger - strain.stagger_threshold / STAGGER_DRAIN_TIME * delta, 0.0)


## The armor a hit travelling along `direction` meets: its strain's on the armored side, and a
## tender's on every side.
func _armor_against(direction: Vector3) -> float:
	var armor: float = status.bonus_armor
	if strain.armor > 0.0 and _on_armor(direction):
		armor += strain.armor
	return armor


## Whether a hit travelling along `direction` lands on the armored side.
func _on_armor(direction: Vector3) -> bool:
	if strain.armor_arc >= 360.0 or direction == Vector3.ZERO:
		return true
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	return (-direction).angle_to(forward) <= deg_to_rad(strain.armor_arc) * 0.5


func _turn_to(facing: Vector3, delta: float) -> void:
	var target_yaw: float = atan2(-facing.x, -facing.z)
	# In world space: aliens live under turned nodes (the location, nests).
	var yaw: float = lerp_angle(
		global_rotation.y, target_yaw, 1.0 - exp(-strain.turn_speed * delta)
	)
	global_basis = Basis(Vector3.UP, yaw)


## Horizontal offset to `node`, or zero without one.
func _offset_to(node: Node3D) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.ZERO
	var offset: Vector3 = node.global_position - global_position
	offset.y = 0.0
	return offset


## Off screen, its legs and clips stop (see `_on_screen_changed`): `creature` is its body's mesh,
## whose box (grown by `SCREEN_MARGIN`) counts.
func _watch_screen(creature: GeometryInstance3D) -> void:
	var box: AABB = creature.get_aabb()
	box = (global_transform.affine_inverse() * creature.global_transform) * box
	_screen.aabb = box.grow(SCREEN_MARGIN)
	_screen.screen_entered.connect(_on_screen_changed)
	_screen.screen_exited.connect(_on_screen_changed)
	add_child(_screen)
	_on_screen_changed()


## Off screen nobody sees its legs step, its clips play or its pose and glow change (`_process`):
## all of them stop, which saves much of an alien's cost. Not for the Ravager: its steps shake the
## ground (see `AlienTremor`).
func _on_screen_changed() -> void:
	var shown: bool = _screen.is_on_screen() or tremor != null or not culls_off_screen
	_animator.active = shown
	_legs.culled = not shown
	set_process(shown)


func _update_look() -> void:
	var shade := Color(0.0, 0.0, 0.0, 0.0)
	if _flash_left > 0.0:
		shade = COLOR_FLASH
	# Only on a change: every change updates the material on the renderer.
	if _overlay.albedo_color != shade:
		_overlay.albedo_color = shade
	var fast: float = EYE_FLARE_FAST if status.is_fast() else 0.0
	# A clip that is the telegraph (rearing up, swelling) brightens them over its wind-up.
	var winding: float = _pose.crouched()
	if _phase == AttackPhase.WIND_UP and _attack.clip_lead > 0.0 and _attack.wind_up > 0.0:
		winding = maxf(winding, _phase_time / _attack.wind_up)
	var flare: float = 1.0 + fast + EYE_FLARE * winding
	for i: int in _glows.size():
		if _glows[i].emission_energy_multiplier != _glow_energies[i] * flare:
			_glows[i].emission_energy_multiplier = _glow_energies[i] * flare


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if dead:
		return
	velocity = Vector3(safe_velocity.x, velocity.y, safe_velocity.z)
	# Standing on the ground there's nothing to move (it saves the physics engine's queries).
	if is_on_floor() and velocity.length_squared() < STAND_SPEED * STAND_SPEED:
		velocity = Vector3.ZERO
		return
	move_and_slide()


func _die() -> void:
	dead = true
	target = null
	_end_attack()
	for attack: AlienAttack in strain.attacks:
		attack.on_death(self)
	if _dig_tween:
		_dig_tween.kill()
	underground = false
	_pose.sink = 0.0
	_model.visible = true
	remove_from_group(GROUP)
	remove_from_group(AlienFlight.GROUP)
	velocity = Vector3.ZERO
	_agent.avoidance_enabled = false
	_collision.set_deferred(&"disabled", true)
	died.emit()
	_hatch_tween.kill()
	_body.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	_animator.dead = true
	_legs.active = false
	if strain.flies():
		var ground: float = AlienFlight.ground_below(self, global_position)
		if ground > -INF:
			var fall: Tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			fall.tween_property(self, ^"global_position:y", ground, FALL_TIME)
	var tween: Tween = create_tween()
	tween.tween_interval(COLLAPSE_DURATION)
	tween.tween_property(_body, ^"position:y", -SINK_DEPTH, SINK_DURATION)
	tween.tween_callback(queue_free)
