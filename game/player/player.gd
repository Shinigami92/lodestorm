class_name Player
extends CharacterBody3D
## Twin-stick player: moves relative to the camera and faces where it aims (`aim`: the mouse
## cursor on the ground, the right stick or else the movement direction; aliens there get locked
## on), and attacks there with the equipped weapon while `attack` is held. Places the miners of
## its `fleet` (one per open cradle of the ship per run, its crafted ones first) on the nearest
## free ore node in range with `place_miner` (the one it chose with `miner_prev`/`miner_next`, shown
## there as a preview, see `picker`), picks miners up again with `interact`, both taking a few
## seconds while it stays near the miner (`handling`), and carries the ore that miners' hoses
## move to it (`cargo`), shown in canisters on its back and as a badge rising above it
## (`OreArrival`). An arrow on the suit ring's edge points back to the ship (`ShipPointer`). Uses
## the nearest interactable in range (buttons, terminals, ...) with `interact`. While it uses a 3D
## menu (`menu`), it stands still and only the menu gets its input. Its health (`vitals`) shows on
## the suit ring around its feet (`SuitRing`, with the ammo, the spare magazines and the dash) and
## the suit light; at zero health the player dies, drops everything carried and lies still until
## `respawn`, or, while its vitals have a bleed-out, goes `down` first: it lies still keeping what
## it carries, ignored by aliens, until it gets up (`PlayerVitals.get_up`) or dies.
## Owns the weapons in its `arsenal` and carries the ones in its `loadout` (picked in the armory);
## its `arms` hold, switch and reload the equipped one and hand teammates ammo. Its `upgrades`
## (bought at the upgrade stations) raise its weapons' parts (damage, capacity, ...) and its armor
## (`armor_upgrade`: more health, shown by pips on the helmet); each crafted miner has its own.
## Its own `hold` keeps the ore brought back over all runs (every haul goes to every player in the
## session) and pays for its gear; its `refining` are its batches in the refinery's furnaces. Its
## `skills` (learned at the skill graph) add health, regeneration, the dash (`suit_dash`, its
## cooldown shown on the suit ring), more spare magazines, reloading at full speed,
## careful reloads, the ore scanner's arrow (`OreScanner`), the damage readout (`DamageNumber`),
## the rescue drone (`rescue_drone`), the hardened canister (part of the cargo safe on death, see
## `PlayerCargo.secure`), rebuilding spares (see `PlayerArms`) and the miner radar (`MinerRadar`).
## The suit model (Body/Model) is animated by `PlayerAnimator` (holding the weapon as its type
## says, swinging it with its melee attacks); the weapon, the cargo rack and the hose port follow
## its markers (WeaponGrip in the right hand, ShieldGrip on the left forearm for a shield, the
## others on the backpack).
## While the mouse is over a 2D control (developer tools), it neither aims nor attacks with it.
## `pause` with no menu open shows its pause panel (`pause_panel`).
## Each player has a `number` (1–4) and its color; only the `local` one (the one this machine plays
## and its camera follows) reads the input (`input`), teammates' rings show only their health. Its
## `sounds`
## play its hits, death and dash, and the local player's are where the game is heard from.

## Emitted when health changes (damage, healing).
signal health_changed(health: float)
## Emitted when it dies (see `PlayerVitals.died`).
signal died

const GROUP: StringName = &"players"
## The players' colors by number (1 orange, 2 sky blue, 3 yellow, 4 reddish purple), always shown
## with the number, so color is never the only cue (see docs/design/art.md, Art direction).
const COLORS: Array[Color] = [
	Color(0.95, 0.55, 0.15), Color(0.35, 0.7, 0.95), Color(0.95, 0.85, 0.25), Color(0.8, 0.4, 0.65)
]
const PAUSE_PANEL_PATH: String = "res://game/player/pause/pause_panel.tscn"

## Where the armor's MK pips sit, in the model's rest pose: on top of the helmet, left of its fin
## (the isometric camera always sees it), following this bone.
const ARMOR_PIPS_POSITION := Vector3(0.075, 1.805, 0.0)
const ARMOR_PIPS_BONE: StringName = &"Head"

@export var settings: PlayerSettings
## The weapons the player owns; a new player starts with these. Each player gets its own copy.
@export var arsenal: Arsenal
## The weapons taken into the mission; a new player starts with these. Each player gets its own
## copy.
@export var loadout: Loadout
## The MK levels bought at the upgrade stations; a new player starts with these. Each player gets
## its own copy.
@export var upgrades: Upgrades
## The skills learned at the skill graph; a new player starts with these. Each player gets its own
## copy.
@export var skills: Skills
## The suit's armor: its MK level multiplies the health.
@export var armor_upgrade: Upgrade
@export var miner_scene: PackedScene
## Drawn over the suit: its silhouette behind walls and the rim light.
@export var body_overlay: Material
## The player's number (1–4; solo always 1), which picks its color.
@export_range(1, 4) var number: int = 1
## Whether this machine plays it: only the local player reads the input and sees its full suit
## ring; the others are teammates (remote with co-op, M7).
@export var local: bool = true

## Where the player aims and the alien it locked on.
var aim := PlayerAim.new()
## The in-game cursor where the mouse points (the local player's).
var reticle := AimReticle.new()
## Health, regeneration and death.
var vitals := PlayerVitals.new()
## The equipped weapon, its ammo and reloads, handing ammo.
var arms := PlayerArms.new()
## The actions it's told to do and where it walks.
var input := PlayerInput.new()
## The ore node `place_miner` would use right now, or null.
var miner_target: OreNode
## The interactable `interact` would use right now, or null.
var interact_target: Interactable
## Whether its silhouette shows behind walls (the rim light stays either way); off e.g. while the
## title view shows the closed ship.
var silhouette_shown: bool = true:
	set(value):
		silhouette_shown = value
		if is_node_ready():
			_update_overlay()
## The ore it carries during a run.
var cargo := PlayerCargo.new()
## What it brought back over all runs and hasn't spent yet (saved with the player).
var hold := PlayerHold.new()
## Its batches in the refinery's furnaces (saved with the player).
var refining := Refining.new()
## Its crafted miners and the standard-issue ones filling up a run (saved with the player).
var fleet := MinerFleet.new()
## The one-time hints it has seen (saved with the player).
var hints := PlayerHints.new()
## Current health, from 0 to `max_health()` (see `vitals`).
var health: float:
	get:
		return vitals.health
## Where the body lies (`lie_on`), or null while it stands.
var lying_on: Node3D
## Dead players can't move or act until they respawn.
var dead: bool:
	get:
		return vitals.dead
## Downed players lie still until they get up or die (see `PlayerVitals.down`).
var down: bool:
	get:
		return vitals.down
## Down or dead: can't move or act, and aliens leave it alone.
var fallen: bool:
	get:
		return vitals.life != PlayerVitals.Life.ALIVE
## The dash (a skill).
var suit_dash := SuitDash.new()
## Gets the player up once per run where they fell (a skill), from the backpack.
var rescue_drone := RescueDrone.new()
## Placing and picking up miners, which take time.
var handling := MinerHandling.new()
## Which miner it places next, and the preview of it.
var picker := MinerPicker.new()
## Its own sounds and, for the local player, the ears.
var sounds := PlayerSounds.new()
## The ground hazards it stands in (slick ice).
var ground_contact := GroundContact.new()
## The pause panel beside it (`pause`: resume, settings, quit).
var pause_panel: PausePanel
## The suit's radio: crew calls beside the player's head.
var radio := PlayerRadio.new()
## The 3D menu (a screen or a station) the player is using, or null. Meanwhile it doesn't move or
## act.
var menu: WorldMenu:
	set(value):
		menu = value
		input.hold_back()

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Shows the armor's MK level.
var _armor_pips := MkPips.new()
## Points to the nearest free ore node.
var _scanner := OreScanner.new()
## Points to its own miners that need it.
var _miner_radar := MinerRadar.new()

@onready var _weapon_mount: Marker3D = $WeaponMount
@onready var _shield_mount: Marker3D = $ShieldMount
@onready var _hose_port: Marker3D = $HosePort
@onready var _cargo_rack: CargoRack = $CargoRack
@onready var _suit_light: SuitLight = $SuitLight
@onready var _model: Node3D = $Body/Model
@onready var _animator: PlayerAnimator = $Animator
@onready var _ship_pointer: ShipPointer = $ShipPointer
@onready var _ring: SuitRing = $SuitRing
@onready var _body: Node3D = $Body
## The body's transform standing (turned to face the player's -Z).
@onready var _body_rest: Transform3D = _body.transform


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(ShipDoor.OPENERS)
	# The ship's open cradles set how many miners it takes (a ship ready after it links them).
	var ship: Ship = Ship.nearest(get_tree(), global_position)
	if ship:
		fleet.cradles = ship.cradles
	_animator.setup(_model)
	_suit_light.band = _model.find_child("SuitLight") as GeometryInstance3D
	_update_overlay()
	OccludedSilhouette.mark_visible(_model)
	RenderLayers.put(_model, RenderLayers.CHARACTERS)
	_attach(_weapon_mount, "WeaponGrip")
	_attach(_shield_mount, "ShieldGrip")
	_attach(_cargo_rack, "CargoRack")
	_attach(_hose_port, "HosePort")
	cargo.ore_changed.connect(_cargo_rack.show_cargo)
	upgrades = upgrades.duplicate() if upgrades else Upgrades.new()
	upgrades.levels = upgrades.levels.duplicate()
	upgrades.changed.connect(_on_upgrades_changed)
	skills = skills.duplicate() if skills else Skills.new()
	skills.ranks = skills.ranks.duplicate()
	skills.changed.connect(_on_skills_changed)
	_add_armor_pips()
	_scanner.name = "OreScanner"
	_scanner.position = Vector3.UP * 0.05
	_scanner.min_distance = settings.miner_place_range
	add_child(_scanner)
	_miner_radar.name = "MinerRadar"
	_miner_radar.holder = self
	_miner_radar.position = Vector3.UP * 0.05
	add_child(_miner_radar)
	_cargo_rack.safe_share = skills.value(Skill.Effect.HARDENED_CANISTER)
	input.holder = self
	suit_dash.name = "SuitDash"
	suit_dash.holder = self
	add_child(suit_dash)
	handling.name = "MinerHandling"
	handling.holder = self
	add_child(handling)
	picker.name = "MinerPicker"
	picker.holder = self
	add_child(picker)
	# Loaded here, not preloaded: its scripts refer back to the player's.
	pause_panel = (load(PAUSE_PANEL_PATH) as PackedScene).instantiate() as PausePanel
	pause_panel.name = "PausePanel"
	pause_panel.holder = self
	add_child(pause_panel)
	radio.name = "Radio"
	radio.holder = self
	add_child(radio)
	# What floats around the player: decals projected onto the ground leave it out.
	for part: Node3D in [_ship_pointer, $OreArrival as Node3D, pause_panel, radio]:
		RenderLayers.put(part, RenderLayers.CHARACTERS)
	aim.name = "Aim"
	aim.holder = self
	add_child(aim)
	reticle.name = "Reticle"
	reticle.holder = self
	add_child(reticle)
	vitals.name = "Vitals"
	vitals.holder = self
	vitals.light = _suit_light
	vitals.changed.connect(health_changed.emit)
	vitals.went_down.connect(_fall)
	vitals.got_up.connect(_on_got_up)
	vitals.died.connect(_on_died)
	add_child(vitals)
	vitals.revive()
	rescue_drone.name = "RescueDrone"
	rescue_drone.holder = self
	add_child(rescue_drone)
	_attach(rescue_drone, "CargoRack")
	sounds.name = "Sounds"
	sounds.holder = self
	add_child(sounds)
	arsenal = arsenal.duplicate() if arsenal else Arsenal.new()
	arsenal.weapons = arsenal.weapons.duplicate()
	arsenal.blueprints = arsenal.blueprints.duplicate()
	loadout = loadout.duplicate() if loadout else Loadout.new()
	loadout.weapons = loadout.weapons.duplicate()
	arms.name = "Arms"
	arms.holder = self
	arms.weapon_mount = _weapon_mount
	arms.shield_mount = _shield_mount
	arms.animator = _animator
	arms.ring = _ring
	add_child(arms)
	_report_progress()


func _physics_process(delta: float) -> void:
	if fallen:
		aim.target = null
		vitals.update(delta)
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var camera_basis: Basis = camera.global_basis if camera else Basis.IDENTITY

	input.update()
	var move: Vector3 = IsoInput.camera_relative(input.move(), camera_basis)
	ground_contact.tick(delta)
	var speed: float = settings.move_speed * ground_contact.speed() * arms.move_share()
	if input.just_pressed(&"dash"):
		suit_dash.dash(move)
	var horizontal: Vector3 = suit_dash.step(
		Vector3(velocity.x, 0.0, velocity.z).move_toward(
			move * speed, settings.acceleration * ground_contact.grip() * delta
		),
		speed,
		delta
	)
	velocity = Vector3(horizontal.x, velocity.y, horizontal.z)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()

	if menu:
		aim.target = null
		aim.towards(menu.get_look_target())
	elif local:
		aim.update(camera, camera_basis, move)
	var target_yaw: float = atan2(-aim.direction.x, -aim.direction.z)
	var yaw: float = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-settings.turn_speed * delta))
	# A fresh basis instead of setting rotation.y keeps the scale from drifting over time.
	basis = Basis(Vector3.UP, yaw)
	_animator.local_velocity = Vector2(velocity.dot(basis.x), -velocity.dot(basis.z))
	var weapon: Weapon = arms.weapon
	# Put away lying down.
	_animator.aiming = weapon != null and arms.allowed and not lying_on
	if weapon:
		_animator.hold = weapon.type.hold
		_animator.shake = weapon.wind
		_animator.drilling = is_instance_valid(weapon.latched)

	handling.update(delta)
	_update_miner_target()
	if input.just_pressed(&"place_miner"):
		place_miner()
	elif input.just_pressed(&"miner_prev"):
		picker.step(-1)
	elif input.just_pressed(&"miner_next"):
		picker.step(1)

	_update_interact_target()
	if input.just_pressed(&"interact"):
		interact()
	arms.update(delta)

	vitals.update(delta)


func _process(_delta: float) -> void:
	_scanner.reach = skills.value(Skill.Effect.ORE_SCANNER)


## Starts placing the miner of its `fleet` it chose (see `picker`) on `miner_target` (see
## `handling`) and returns it, or null without a target, while another goes on nearby (see
## `MinerHandling`), or once the run's miners are all placed.
func place_miner() -> Miner:
	_update_miner_target()
	if not miner_target or fleet.left_to_place() <= 0:
		return null
	var miner: Miner = handling.place(miner_target, picker.choice_for(miner_target))
	if miner:
		picker.placed()
	_update_miner_target()
	return miner


## Uses `interact_target` and returns it, or null without a target.
func interact() -> Interactable:
	_update_interact_target()
	if interact_target:
		interact_target.use(self)
	return interact_target


## Health when unhurt, with the skills and the armor upgrade.
func max_health() -> float:
	return vitals.maximum()


## The pips showing the armor's MK level.
func get_armor_pips() -> MkPips:
	return _armor_pips


## Loses `amount` health (from an attacker at `from`, if it has one: the suit ring marks where
## the hit came from); dies at zero. A blow of an `attacker` (`heavy`: a charge, a slam) may be
## stopped by the field of a shield the player holds (see `ShieldField.block`). `cause` dealt it
## (for the statistics; the attacker without one).
func take_damage(
	amount: float,
	from: Vector3 = Vector3.INF,
	attacker: Node3D = null,
	heavy: bool = false,
	cause: Node = null
) -> void:
	var weapon: Weapon = arms.weapon
	if attacker and weapon and weapon.field:
		amount = weapon.field.block(amount, attacker, heavy)
	vitals.damage(amount, from, cause if cause else attacker)


## Restores `amount` health (all of it by default; not when dead).
func heal(amount: float = INF) -> void:
	vitals.heal(amount)


## Lies the body down on `spot` (e.g. a med bed: its Y is where the head points, its -Z where the
## face looks), or stands it up again (null). The player itself (its collision shape, the suit
## ring) stays where it stands.
func lie_on(spot: Node3D) -> void:
	lying_on = spot
	arms.update_holster()
	_body.top_level = spot != null
	if spot:
		_body.global_transform = spot.global_transform * _body_rest
	else:
		_body.transform = _body_rest
	_body.reset_physics_interpolation()


## Brings a dead player back at `at` with full health.
func respawn(at: Vector3) -> void:
	vitals.revive()
	GameEvents.bus.player_respawned.emit(self)
	_animator.dead = false
	arms.update_holster()
	_ship_pointer.process_mode = Node.PROCESS_MODE_INHERIT
	arms.refill()
	global_position = at
	velocity = Vector3.ZERO
	reset_physics_interpolation()


## Where hoses attach, as rendered this frame (interpolated between physics steps).
func get_hose_port_position() -> Vector3:
	return _hose_port.get_global_transform_interpolated().origin


## The player's color (see `COLORS`).
func color() -> Color:
	return COLORS[clampi(number, 1, COLORS.size()) - 1]


## The first local player (the one playing on this machine), or null.
static func first_local(tree: SceneTree) -> Player:
	for player: Player in tree.get_nodes_in_group(GROUP):
		if player.local:
			return player
	return null


## The standing player closest to `from` within `max_distance` (horizontally), or null.
static func nearest(tree: SceneTree, from: Vector3, max_distance: float) -> Player:
	var nearest_player: Player = null
	var nearest_distance: float = max_distance
	for player: Player in tree.get_nodes_in_group(GROUP):
		if player.fallen:
			continue
		var offset: Vector3 = player.global_position - from
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance <= nearest_distance:
			nearest_player = player
			nearest_distance = distance
	return nearest_player


func _update_overlay() -> void:
	var suit := _model.find_child("Suit") as GeometryInstance3D
	suit.material_overlay = body_overlay if silhouette_shown else body_overlay.next_pass


## Passes what it achieves (ore collected, weapons, blueprints, upgrade levels, skill ranks, bars
## refined) on to `GameEvents`.
func _report_progress() -> void:
	var events: GameEvents = GameEvents.bus
	cargo.ore_added.connect(
		func(ore_type: OreType, amount: float) -> void:
			events.ore_collected.emit(self, ore_type, amount)
	)
	arsenal.unlocked.connect(
		func(weapon_type: WeaponType) -> void: events.weapon_unlocked.emit(self, weapon_type)
	)
	arsenal.learned.connect(
		func(weapon_type: WeaponType) -> void: events.blueprint_learned.emit(self, weapon_type)
	)
	upgrades.finished.connect(
		func(upgrade: Upgrade) -> void:
			events.upgrade_finished.emit(self, upgrade, upgrades.mk(upgrade))
	)
	skills.finished.connect(
		func(skill: Skill) -> void: events.skill_finished.emit(self, skill, skills.rank(skill))
	)
	refining.bars_finished.connect(
		func(_slot: int, alloy: AlloyType, count: int) -> void:
			events.bars_refined.emit(self, alloy, count)
	)


## Stops whatever it does and lies still (down or dead).
func _fall() -> void:
	if menu:
		menu.close()
	velocity = Vector3.ZERO
	suit_dash.cancel()
	arms.stop()
	handling.cancel()
	if is_instance_valid(interact_target):
		interact_target.highlighted = false
	miner_target = null
	interact_target = null
	# Falls and lies still; the collision shape stays, so the ship still knows where the body is.
	_animator.local_velocity = Vector2.ZERO
	_animator.dead = true
	_ship_pointer.visible = false
	_ship_pointer.process_mode = Node.PROCESS_MODE_DISABLED


## Stands up again from being down, the weapon drawn.
func _on_got_up() -> void:
	_animator.dead = false
	arms.update_holster()
	_ship_pointer.process_mode = Node.PROCESS_MODE_INHERIT


## Drops everything (but the share the hardened canister keeps safe) and lies still until
## `respawn`.
func _on_died() -> void:
	_fall()
	cargo.secure(skills.value(Skill.Effect.HARDENED_CANISTER))
	var dropped: Dictionary[OreType, float] = cargo.take_all()
	for ore_type: OreType in dropped:
		GameEvents.bus.ore_lost.emit(self, ore_type, dropped[ore_type])
	died.emit()


## Puts the armor's pips on the helmet, following the head's bone.
func _add_armor_pips() -> void:
	# The row runs from front to back.
	var marker: Marker3D = _bone_marker(
		ARMOR_PIPS_BONE, Transform3D(Basis(Vector3.UP, PI * 0.5), ARMOR_PIPS_POSITION)
	)
	_armor_pips.name = "ArmorPips"
	_armor_pips.pip_size = Vector3(0.045, 0.02, 0.045)
	_armor_pips.spacing = 0.06
	add_child(_armor_pips)
	_follow(marker, _armor_pips)
	_armor_pips.show_level(
		upgrades.mk(armor_upgrade), _armor_max_mk(), upgrades.is_running(armor_upgrade)
	)
	OccludedSilhouette.mark_visible(_armor_pips)
	RenderLayers.put(_armor_pips, RenderLayers.CHARACTERS)


## A marker following `bone`, at `in_model` (in the model's rest pose). The marker is placed from
## the bone's rest pose (the attachment doesn't follow the bone yet).
func _bone_marker(bone: StringName, in_model: Transform3D) -> Marker3D:
	var skeleton: Skeleton3D = _model.find_child("Skeleton3D") as Skeleton3D
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var bone_in_model: Transform3D = (
		_model.global_transform.affine_inverse()
		* skeleton.global_transform
		* skeleton.get_bone_global_rest(skeleton.find_bone(bone))
	)
	var marker := Marker3D.new()
	attachment.add_child(marker)
	marker.transform = bone_in_model.affine_inverse() * in_model
	return marker


func _armor_max_mk() -> int:
	return armor_upgrade.max_mk() if armor_upgrade else 1


## Makes `node` follow the model's marker `marker_name` (and so its animated bone).
func _attach(node: Node3D, marker_name: String) -> void:
	_follow(_model.find_child(marker_name) as Node3D, node)


## Makes `node` follow `marker`.
func _follow(marker: Node3D, node: Node3D) -> void:
	var follow := RemoteTransform3D.new()
	marker.add_child(follow)
	follow.remote_path = follow.get_path_to(node)


func _update_miner_target() -> void:
	miner_target = OreNode.nearest_free(get_tree(), global_position, settings.miner_place_range)


func _update_interact_target() -> void:
	var target: Interactable = Interactable.nearest(get_tree(), global_position)
	if target == interact_target:
		return
	if is_instance_valid(interact_target):
		interact_target.highlighted = false
	interact_target = target
	if interact_target:
		interact_target.highlighted = true


## Shows the armor's new MK level (a stronger armor adds its extra health) and the levels under way.
func _on_upgrades_changed() -> void:
	_armor_pips.show_level(
		upgrades.mk(armor_upgrade), _armor_max_mk(), upgrades.is_running(armor_upgrade)
	)
	vitals.update_maximum()


## Skills are learned aboard: more health adds the difference, the hardened canister's band grows.
func _on_skills_changed() -> void:
	vitals.update_maximum()
	_cargo_rack.safe_share = skills.value(Skill.Effect.HARDENED_CANISTER)
