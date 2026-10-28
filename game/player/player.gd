class_name Player
extends CharacterBody3D
## Twin-stick player: moves relative to the camera and faces where it aims (`aim`: the mouse
## cursor on the ground, the right stick or else the movement direction; aliens there get locked
## on), and attacks there with the equipped weapon while `attack` is held. Places the miners of
## its `fleet` (up to six per run, its crafted ones first) on the nearest free ore node in range
## with `place_miner`, picks miners up again with `interact`, both taking a few seconds while it
## stays near the miner (`handling`), and carries the ore that
## miners' hoses move to it (`cargo`), shown in canisters on its back and as a badge rising above
## it (`OreArrival`). An arrow on the suit ring's edge points back to the ship (`ShipPointer`). Uses
## the nearest interactable in range (buttons, terminals, ...) with `interact`. While it uses a 3D
## menu (`menu`), it stands still and only the menu gets its input. Its health (`vitals`) shows on
## the suit ring around its feet (`SuitRing`, with the ammo, the spare magazines and the dash) and
## the suit light; at zero health the player dies, drops everything carried and lies still until
## `respawn`.
## Owns the weapons in its `arsenal` and carries the ones in its `loadout` (picked in the armory);
## `switch_weapon` equips and draws the next one. Fed weapons keep their loaded rounds while
## holstered for the run and `reload` them with ammo the suit makes from the carried ore (`OreAmmo`;
## free aboard), walking slower meanwhile. Holding `interact` next to a teammate, with nothing else
## to use there, hands them a magazine for their equipped weapon, paid from its ore. Its `upgrades`
## (bought at the upgrade stations) raise its weapons' parts (damage, capacity, ...) and its armor
## (`armor_upgrade`: more health, shown by pips on the helmet); each crafted miner has its own.
## Its own `hold` keeps the ore brought back over all runs (every haul goes to every player in the
## session) and pays for its gear; its `refining` are its batches in the refinery's furnaces. Its
## `skills` (learned at the skill graph) add health, regeneration, the dash (`suit_dash`, its
## cooldown shown on the suit ring), more spare magazines, reloading at full speed,
## careful reloads, the ore scanner's arrow (`OreScanner`) and the damage readout
## (`DamageNumber`).
## The suit model (Body/Model) is animated by `PlayerAnimator` (holding the weapon as its type
## says, swinging it with its melee attacks); the weapon, the cargo rack and the hose port follow
## its markers (WeaponGrip in the right hand, ShieldGrip on the left forearm for a shield, the
## others on the backpack).
## While the mouse is over a 2D control (developer tools), it neither aims nor attacks with it.
## `pause` with no menu open shows its pause panel (`pause_panel`).
## Each player has a `number` (1–4) and its color; only the `local` one (the one this machine plays
## and its camera follows) reads the input, teammates' rings show only their health. Its `sounds`
## play its hits, death and dash, and the local player's are where the game is heard from.

## Emitted when health changes (damage, healing).
signal health_changed(health: float)
## Emitted when health reaches zero.
signal died

const GROUP: StringName = &"players"
## The players' colors by number (1 orange, 2 sky blue, 3 yellow, 4 reddish purple), always shown
## with the number, so color is never the only cue (see docs/design/art.md, Art direction).
const COLORS: Array[Color] = [
	Color(0.95, 0.55, 0.15), Color(0.35, 0.7, 0.95), Color(0.95, 0.85, 0.25), Color(0.8, 0.4, 0.65)
]
const PAUSE_PANEL_PATH: String = "res://game/player/pause/pause_panel.tscn"

## Actions that make the player act; ones still held when a menu closes wait for their release.
const ACTIONS: Array[StringName] = [
	&"attack", &"place_miner", &"interact", &"switch_weapon", &"reload", &"dash"
]
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
## The equipped weapon, or null with an empty loadout.
var weapon: Weapon
## The loadout slot of the equipped weapon (or the one to fill first when it's empty).
var weapon_slot: int = 0
## The ore node `place_miner` would use right now, or null.
var miner_target: OreNode
## The interactable `interact` would use right now, or null.
var interact_target: Interactable
## Whether the weapon can be used here; it's holstered (hidden) otherwise, e.g. inside the ship.
var weapon_allowed: bool = true:
	set(value):
		weapon_allowed = value
		if weapon:
			# Put away while lying down too.
			weapon.visible = value and not lying_on
			weapon.stop()
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
## Whether reloads cost nothing (aboard: from the ship's stock).
var ammo_free: bool = false
## The teammate `interact` hands ammo to while it's held, or null; and for how long it's held (s).
var give_ammo_target: Player
var give_ammo_time: float = 0.0
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
## Spare magazines per ranged weapon a run starts with, with the skills.
var spare_magazines: int:
	get:
		return settings.spare_magazines + roundi(skills.value(Skill.Effect.SPARE_MAGAZINES))
## The dash (a skill).
var suit_dash := SuitDash.new()
## Placing and picking up miners, which take time.
var handling := MinerHandling.new()
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
		# The press that closed the menu (e.g. a click) doesn't act again in the world.
		_held_since_menu.clear()
		for action: StringName in ACTIONS:
			if Input.is_action_pressed(action):
				_held_since_menu.append(action)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Actions held since a menu opened or closed; they're ignored until released.
var _held_since_menu: Array[StringName] = []
var _weapon_type: WeaponType
## Rounds loaded per fed weapon of the loadout that isn't equipped; missing ones are full.
var _rounds: Dictionary[WeaponType, int] = {}
## Spare rounds per fed weapon of the loadout that isn't equipped; missing ones have all spares.
var _spares: Dictionary[WeaponType, int] = {}
## Shows the armor's MK level.
var _armor_pips := MkPips.new()
## Points to the nearest free ore node.
var _scanner := OreScanner.new()

@onready var _weapon_mount: Marker3D = $WeaponMount
@onready var _shield_mount: Marker3D = $ShieldMount
@onready var _hose_port: Marker3D = $HosePort
@onready var _cargo_rack: CargoRack = $CargoRack
@onready var _suit_light: SuitLight = $SuitLight
@onready var _model: Node3D = $Body/Model
@onready var _animator: PlayerAnimator = $Animator
@onready var _ship_pointer: Node3D = $ShipPointer
@onready var _ring: SuitRing = $SuitRing
@onready var _body: Node3D = $Body
## The body's transform standing (turned to face the player's -Z).
@onready var _body_rest: Transform3D = _body.transform


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(ShipDoor.OPENERS)
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
	suit_dash.name = "SuitDash"
	suit_dash.holder = self
	add_child(suit_dash)
	handling.name = "MinerHandling"
	handling.holder = self
	add_child(handling)
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
	vitals.died.connect(_on_died)
	add_child(vitals)
	vitals.revive()
	sounds.name = "Sounds"
	sounds.holder = self
	add_child(sounds)
	arsenal = arsenal.duplicate() if arsenal else Arsenal.new()
	arsenal.weapons = arsenal.weapons.duplicate()
	arsenal.blueprints = arsenal.blueprints.duplicate()
	loadout = loadout.duplicate() if loadout else Loadout.new()
	loadout.weapons = loadout.weapons.duplicate()
	loadout.changed.connect(_on_loadout_changed)
	_on_loadout_changed()
	_report_progress()


func _physics_process(delta: float) -> void:
	if dead:
		aim.target = null
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var camera_basis: Basis = camera.global_basis if camera else Basis.IDENTITY

	_held_since_menu.assign(_held_since_menu.filter(Input.is_action_pressed))
	var acting: bool = menu == null and local
	var move_input: Vector2 = Vector2.ZERO
	if acting:
		move_input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move: Vector3 = IsoInput.camera_relative(move_input, camera_basis)
	ground_contact.tick(delta)
	var speed: float = settings.move_speed * ground_contact.speed()
	if _is_reloading() and not skills.has(Skill.Effect.RELOAD_ON_THE_MOVE):
		speed *= settings.reload_move_speed
	if weapon:
		speed *= weapon.move_share()
	if acting and _action_just_pressed(&"dash"):
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
	# Put away lying down.
	_animator.aiming = weapon != null and weapon_allowed and not lying_on

	if weapon:
		_animator.hold = weapon.type.hold
		_animator.shake = weapon.wind
		_animator.drilling = is_instance_valid(weapon.latched)
		weapon.aim_direction = aim.direction
		weapon.aim_target = aim.target
		weapon.aim_point = aim.ground_point
		weapon.trigger_held = (
			weapon_allowed and _action_held(&"attack") and not aim.is_mouse_over_ui()
		)

	handling.update(delta)
	_update_miner_target()
	if _action_just_pressed(&"place_miner"):
		place_miner()

	_update_interact_target()
	if _action_just_pressed(&"interact"):
		interact()
	_update_give_ammo(delta)

	if _action_just_pressed(&"switch_weapon"):
		switch_weapon()

	if _action_just_pressed(&"reload"):
		reload()

	vitals.update(delta)


func _process(_delta: float) -> void:
	_scanner.reach = skills.value(Skill.Effect.ORE_SCANNER)


## Starts placing the next miner of its `fleet` on `miner_target` (see `handling`) and returns
## it, or null without a target, while another goes on nearby (see `MinerHandling`), or once the
## run's miners are all placed.
func place_miner() -> Miner:
	_update_miner_target()
	if not miner_target or fleet.left_to_place() <= 0:
		return null
	var miner: Miner = handling.place(miner_target)
	_update_miner_target()
	return miner


## Uses `interact_target` and returns it, or null without a target.
func interact() -> Interactable:
	_update_interact_target()
	if interact_target:
		interact_target.use(self)
	return interact_target


## The `reload` action on the equipped weapon's ammo (see `WeaponAmmo.reload`). Returns whether
## it started or timed a reload.
func reload() -> bool:
	var ammo: WeaponAmmo = get_ammo()
	return ammo != null and weapon_allowed and not dead and ammo.reload()


## Fills every fed weapon's magazine and spare magazines for free (the ship's stock, for a new
## run).
func refill_ammo() -> void:
	_rounds.clear()
	_spares.clear()
	var ammo: WeaponAmmo = get_ammo()
	if ammo:
		ammo.fill(spare_magazines)


## Fills the spare magazines of every fed weapon in the loadout (a supply cache in a crate),
## leaving the loaded rounds as they are.
func refill_spares() -> void:
	_spares.clear()
	var ammo: WeaponAmmo = get_ammo()
	if ammo:
		ammo.spare_rounds = spare_magazines * ammo.capacity()


## Hands `teammate` a magazine for their equipped fed weapon, paid from the carried ore (see
## `WeaponAmmo.receive_ammo`). Returns whether it did.
func give_ammo(teammate: Player) -> bool:
	if teammate == self or teammate.dead or dead:
		return false
	var ammo: WeaponAmmo = teammate.get_ammo()
	return ammo != null and ammo.receive_ammo(self)


## Equips the weapon in the next filled loadout slot (wrapping around) and draws it. Returns
## whether it switched.
func switch_weapon() -> bool:
	var slots: int = settings.loadout_slots
	for step: int in range(1, slots):
		var slot: int = (weapon_slot + step) % slots
		if loadout.get_weapon(slot):
			weapon_slot = slot
			_equip(loadout.get_weapon(slot))
			if weapon:
				weapon.draw()
			return true
	return false


## The equipped weapon's ammo, or null (no weapon, or a melee one).
func get_ammo() -> WeaponAmmo:
	return weapon.ammo if weapon else null


## The weapon type of the equipped weapon, or null.
func get_weapon_type() -> WeaponType:
	return _weapon_type


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
	weapon_allowed = weapon_allowed
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
	weapon_allowed = weapon_allowed
	_ship_pointer.process_mode = Node.PROCESS_MODE_INHERIT
	refill_ammo()
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


## The living player closest to `from` within `max_distance` (horizontally), or null.
static func nearest(tree: SceneTree, from: Vector3, max_distance: float) -> Player:
	var nearest_player: Player = null
	var nearest_distance: float = max_distance
	for player: Player in tree.get_nodes_in_group(GROUP):
		if player.dead:
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


func _is_reloading() -> bool:
	var ammo: WeaponAmmo = get_ammo()
	return ammo != null and ammo.reloading


## Whether `action` is held for the player to act (not while using a menu, nor a press from it).
func _action_held(action: StringName) -> bool:
	return local and not menu and action not in _held_since_menu and Input.is_action_pressed(action)


func _action_just_pressed(action: StringName) -> bool:
	return _action_held(action) and Input.is_action_just_pressed(action)


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


## Drops everything and lies still until `respawn`.
func _on_died() -> void:
	if menu:
		menu.close()
	velocity = Vector3.ZERO
	suit_dash.cancel()
	if weapon:
		weapon.stop()
		weapon.visible = false
	if get_ammo():
		get_ammo().cancel_reload()
	give_ammo_target = null
	give_ammo_time = 0.0
	handling.cancel()
	if is_instance_valid(miner_target):
		miner_target.highlighted = false
	if is_instance_valid(interact_target):
		interact_target.highlighted = false
	miner_target = null
	interact_target = null
	var dropped: Dictionary[OreType, float] = cargo.take_all()
	for ore_type: OreType in dropped:
		GameEvents.bus.ore_lost.emit(self, ore_type, dropped[ore_type])
	# Falls and lies still; the collision shape stays, so the ship still knows where the body is.
	_animator.local_velocity = Vector2.ZERO
	_animator.dead = true
	_ship_pointer.visible = false
	_ship_pointer.process_mode = Node.PROCESS_MODE_DISABLED
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
	var target: OreNode = OreNode.nearest_free(
		get_tree(), global_position, settings.miner_place_range
	)
	if target == miner_target:
		return
	if is_instance_valid(miner_target):
		miner_target.highlighted = false
	miner_target = target
	if miner_target:
		miner_target.highlighted = true


## Holding `interact` with nothing to use in range hands the nearest teammate in range (whose
## equipped fed weapon isn't full) a magazine once it's held for `settings.give_ammo_time`.
func _update_give_ammo(delta: float) -> void:
	var target: Player = null
	if not interact_target and _action_held(&"interact"):
		target = _teammate_needing_ammo()
	if target != give_ammo_target:
		give_ammo_target = target
		give_ammo_time = 0.0
	if not give_ammo_target:
		return
	give_ammo_time += delta
	if give_ammo_time >= settings.give_ammo_time:
		give_ammo(give_ammo_target)
		give_ammo_target = null
		give_ammo_time = 0.0
		# Once per hold.
		_held_since_menu.append(&"interact")


func _teammate_needing_ammo() -> Player:
	var best: Player = null
	var best_distance: float = settings.give_ammo_range
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var teammate := node as Player
		if teammate == self or teammate.dead:
			continue
		var ammo: WeaponAmmo = teammate.get_ammo()
		if not ammo or ammo.is_full():
			continue
		var distance: float = global_position.distance_to(teammate.global_position)
		if distance <= best_distance:
			best = teammate
			best_distance = distance
	return best


func _update_interact_target() -> void:
	var target: Interactable = Interactable.nearest(get_tree(), global_position)
	if target == interact_target:
		return
	if is_instance_valid(interact_target):
		interact_target.highlighted = false
	interact_target = target
	if interact_target:
		interact_target.highlighted = true


## Equips `weapon_type` (null: none) unless it's equipped already.
func _equip(weapon_type: WeaponType) -> void:
	if weapon_type == _weapon_type:
		return
	if get_ammo():
		# A magazine reload cut short leaves it empty; loaded single rounds stay.
		_rounds[_weapon_type] = get_ammo().rounds
		_spares[_weapon_type] = get_ammo().spare_rounds
	_weapon_type = weapon_type
	if weapon:
		weapon.get_parent().remove_child(weapon)
		weapon.queue_free()
		weapon = null
	if not weapon_type:
		return
	weapon = weapon_type.create()
	weapon.holder = self
	weapon.motion_started.connect(_animator.play_motion)
	weapon.apply_upgrades(upgrades)
	var ammo: WeaponAmmo = weapon.ammo
	if ammo:
		ammo.supplier = self
		var loaded: int = _rounds.get(weapon_type, ammo.capacity())
		ammo.rounds = mini(loaded, ammo.capacity())
		ammo.spare_rounds = _spares.get(weapon_type, spare_magazines * ammo.capacity())
		_set_careful()
		ammo.reload_denied.connect(_on_reload_denied)
		ammo.reload_timed.connect(_on_reload_timed.bind(ammo))
	weapon.visible = weapon_allowed and not dead
	OccludedSilhouette.mark_visible(weapon)
	RenderLayers.put(weapon, RenderLayers.CHARACTERS)
	var shield: bool = weapon_type.hold == WeaponType.Hold.SHIELD
	(_shield_mount if shield else _weapon_mount).add_child(weapon)


## A reload that can't start (no ore) flashes the ring's ammo arc red.
func _on_reload_denied() -> void:
	_ring.flash(SuitRing.FUMBLE_COLOR)


## A hit that finished the reload flashes the ring (single rounds go on loading meanwhile).
func _on_reload_timed(hit: bool, ammo: WeaponAmmo) -> void:
	if hit and not ammo.reloading:
		_ring.flash(AmmoGauge.TIMING)


## Applies new MK levels to the equipped weapon (a stronger armor adds its extra health) and shows
## the levels under way. Levels take effect aboard, so the magazines are filled to their new size.
func _on_upgrades_changed() -> void:
	if weapon:
		weapon.apply_upgrades(upgrades)
	refill_ammo()
	_armor_pips.show_level(
		upgrades.mk(armor_upgrade), _armor_max_mk(), upgrades.is_running(armor_upgrade)
	)
	vitals.update_maximum()


## Skills are learned aboard: more spare magazines fill up, more health adds the difference, the
## equipped weapon reloads carefully.
func _on_skills_changed() -> void:
	_set_careful()
	refill_ammo()
	vitals.update_maximum()


## Whether the equipped weapon's magazine reloads keep the rounds left in it (the skill).
func _set_careful() -> void:
	var magazine := get_ammo() as MagazineAmmo
	if magazine:
		magazine.careful = skills.has(Skill.Effect.CAREFUL_RELOAD)


## Keeps the equipped weapon in the loadout: the one in its slot, or else the first one there.
func _on_loadout_changed() -> void:
	if not loadout.get_weapon(weapon_slot):
		for slot: int in settings.loadout_slots:
			if loadout.get_weapon(slot):
				weapon_slot = slot
				break
	_equip(loadout.get_weapon(weapon_slot))
