class_name Player
extends CharacterBody3D
## Twin-stick player: moves relative to the camera and faces where it aims (`aim`: the mouse
## cursor on the ground, the right stick or else the movement direction; aliens there get locked
## on), and attacks there with the equipped weapon while `attack` is held. Places miners on the
## nearest free ore node in range with `place_miner`, and carries the ore that miners' hoses move
## to it, shown in canisters on its back. An arrow on the ground points back to the ship. Uses the
## nearest interactable in range (buttons, terminals, ...) with `interact`. While it uses a 3D
## menu (`menu`), it stands still and only the menu gets its input. Its health (`vitals`) shows on
## the suit light; at zero health the player dies, drops everything carried and lies still until
## `respawn`.
## Owns the weapons in its `arsenal` and carries the ones in its `loadout` (picked in the armory);
## `switch_weapon` equips the next one. Ranged weapons keep their loaded rounds while holstered
## for the run and `reload` them with ammo the suit makes from the carried ore (`OreAmmo`; free
## aboard), walking slower meanwhile. Holding `interact` next to a teammate, with nothing else to
## use there, hands them a magazine for their equipped weapon, paid from its ore. Its `upgrades`
## (bought at the upgrade stations) raise its weapons' damage and magazines, its armor
## (`armor_upgrade`: more health, shown by pips on the helmet) and the miners it places. Its
## `skills` (learned at the skill graph) add health, regeneration, the dash (`suit_dash`, its
## cooldown shown by a strip on the backpack), more spare magazines, reloading at full speed,
## careful reloads, the ore scanner's arrow (`OreScanner`) and the damage readout
## (`DamageNumber`).
## The suit model (Body/Model) is animated by `PlayerAnimator`; the weapon, the cargo rack and
## the hose port follow its markers (WeaponGrip in the right hand, the others on the backpack).
## While the mouse is over a 2D control (developer tools), it neither aims nor attacks with it.

## Emitted when the carried amount of an ore type changes.
signal cargo_changed(ore_type: OreType, amount: float)
## Emitted when health changes (damage, healing).
signal health_changed(health: float)
## Emitted when health reaches zero.
signal died

const GROUP: StringName = &"players"

## Actions that make the player act; ones still held when a menu closes wait for their release.
const ACTIONS: Array[StringName] = [
	&"attack", &"place_miner", &"interact", &"switch_weapon", &"reload", &"dash"
]
## Stencil value the suit writes where it's visible (occluded_silhouette.gdshader skips those).
const STENCIL_VISIBLE: int = 1
## Where the armor's MK pips sit, in the model's rest pose: on top of the helmet, left of its fin
## (the isometric camera always sees it), following this bone.
const ARMOR_PIPS_POSITION := Vector3(0.075, 1.805, 0.0)
const ARMOR_PIPS_BONE: StringName = &"Head"
## Where the spare magazine cells sit, in the model's rest pose: on top of the backpack (the
## isometric camera sees it from every side), following this bone.
const POUCHES_POSITION := Vector3(0.0, 1.57, -0.25)
const POUCHES_BONE: StringName = &"UpperChest"
## Where the dash's cooldown strip sits, in the model's rest pose: across the back of the
## backpack, following the same bone as the spare magazine cells.
const DASH_STRIP_POSITION := Vector3(0.0, 1.22, -0.312)

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

## Where the player aims and the alien it locked on.
var aim := PlayerAim.new()
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
			weapon.visible = value
			weapon.trigger_held = false
## Units carried per ore type; no carry limit.
var cargo: Dictionary[OreType, float] = {}
## Whether reloads cost nothing (aboard: from the ship's stock).
var ammo_free: bool = false
## The teammate `interact` hands ammo to while it's held, or null; and for how long it's held (s).
var give_ammo_target: Player
var give_ammo_time: float = 0.0
## Current health, from 0 to `max_health()` (see `vitals`).
var health: float:
	get:
		return vitals.health
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
## The wrist display (`wrist` shows the cargo).
var wrist := WristDisplay.new()
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
## Rounds loaded per ranged weapon of the loadout that isn't equipped; missing ones are full.
var _rounds: Dictionary[WeaponType, int] = {}
## Spare rounds per ranged weapon of the loadout that isn't equipped; missing ones have all spares.
var _spares: Dictionary[WeaponType, int] = {}
## Shows the armor's MK level.
var _armor_pips := MkPips.new()
## Shows the equipped weapon's spare magazines.
var _pouches := SparePouches.new()
## Shows the dash's cooldown.
var _dash_strip := DashStrip.new()
## Points to the nearest free ore node.
var _scanner := OreScanner.new()

@onready var _weapon_mount: Marker3D = $WeaponMount
@onready var _hose_port: Marker3D = $HosePort
@onready var _cargo_rack: CargoRack = $CargoRack
@onready var _suit_light: SuitLight = $SuitLight
@onready var _model: Node3D = $Body/Model
@onready var _animator: PlayerAnimator = $Animator
@onready var _ship_pointer: Node3D = $ShipPointer
@onready var _target_marker: Node3D = $TargetMarker
@onready var _reload_ring: ReloadRing = $ReloadRing


func _ready() -> void:
	add_to_group(GROUP)
	_animator.setup(_model)
	_suit_light.band = _model.find_child("SuitLight") as GeometryInstance3D
	(_model.find_child("Suit") as GeometryInstance3D).material_overlay = body_overlay
	_mark_visible(_model)
	_attach(_weapon_mount, "WeaponGrip")
	_attach(_cargo_rack, "CargoRack")
	_attach(_hose_port, "HosePort")
	cargo_changed.connect(_cargo_rack.show_cargo)
	upgrades = upgrades.duplicate() if upgrades else Upgrades.new()
	upgrades.levels = upgrades.levels.duplicate()
	upgrades.changed.connect(_on_upgrades_changed)
	skills = skills.duplicate() if skills else Skills.new()
	skills.ranks = skills.ranks.duplicate()
	skills.changed.connect(_on_skills_changed)
	_add_armor_pips()
	_add_pouches()
	_add_dash_strip()
	_scanner.name = "OreScanner"
	_scanner.position = Vector3.UP * 0.05
	_scanner.min_distance = settings.miner_place_range
	add_child(_scanner)
	suit_dash.name = "SuitDash"
	suit_dash.holder = self
	add_child(suit_dash)
	wrist.name = "WristDisplay"
	wrist.holder = self
	add_child(wrist)
	aim.name = "Aim"
	aim.holder = self
	aim.marker = _target_marker
	add_child(aim)
	vitals.name = "Vitals"
	vitals.holder = self
	vitals.light = _suit_light
	vitals.changed.connect(health_changed.emit)
	vitals.died.connect(_on_died)
	add_child(vitals)
	vitals.revive()
	arsenal = arsenal.duplicate() if arsenal else Arsenal.new()
	arsenal.weapons = arsenal.weapons.duplicate()
	loadout = loadout.duplicate() if loadout else Loadout.new()
	loadout.weapons = loadout.weapons.duplicate()
	loadout.changed.connect(_on_loadout_changed)
	_on_loadout_changed()


func _physics_process(delta: float) -> void:
	if dead:
		aim.target = null
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var camera_basis: Basis = camera.global_basis if camera else Basis.IDENTITY

	_held_since_menu.assign(_held_since_menu.filter(Input.is_action_pressed))
	var acting: bool = menu == null
	var move_input: Vector2 = Vector2.ZERO
	if acting:
		move_input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move: Vector3 = IsoInput.camera_relative(move_input, camera_basis)
	var speed: float = settings.move_speed
	if _is_reloading() and not skills.has(Skill.Effect.RELOAD_ON_THE_MOVE):
		speed *= settings.reload_move_speed
	if acting and _action_just_pressed(&"dash"):
		suit_dash.dash(move)
	var horizontal: Vector3 = suit_dash.step(
		Vector3(velocity.x, 0.0, velocity.z).move_toward(
			move * speed, settings.acceleration * delta
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

	if acting:
		aim.update(camera, camera_basis, move)
	else:
		aim.target = null
		aim.towards(menu.get_look_target())
	var target_yaw: float = atan2(-aim.direction.x, -aim.direction.z)
	var yaw: float = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-settings.turn_speed * delta))
	# A fresh basis instead of setting rotation.y keeps the scale from drifting over time.
	basis = Basis(Vector3.UP, yaw)
	_animator.local_velocity = Vector2(velocity.dot(basis.x), -velocity.dot(basis.z))
	_animator.aiming = weapon != null and weapon_allowed

	if weapon:
		weapon.aim_direction = aim.direction
		weapon.aim_target = aim.target
		weapon.trigger_held = (
			weapon_allowed and _action_held(&"attack") and not aim.is_mouse_over_ui()
		)

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
	_update_pouches()
	_dash_strip.visible = skills.has(Skill.Effect.DASH)
	_dash_strip.show_fill(suit_dash.ready_ratio())
	_scanner.reach = skills.value(Skill.Effect.ORE_SCANNER)


## Places a miner on `miner_target` and returns it, or null without a target.
func place_miner() -> Miner:
	_update_miner_target()
	if not miner_target:
		return null
	var miner: Miner = miner_target.place_miner(miner_scene, upgrades)
	_update_miner_target()
	return miner


## Uses `interact_target` and returns it, or null without a target.
func interact() -> Interactable:
	_update_interact_target()
	if interact_target:
		interact_target.use(self)
	return interact_target


## The `reload` action on the equipped ranged weapon (see `RangedWeapon.reload`). Returns whether
## it started or timed a reload.
func reload() -> bool:
	var ranged := weapon as RangedWeapon
	return ranged != null and weapon_allowed and not dead and ranged.reload()


## Fills every ranged weapon's magazine and spare magazines for free (the ship's stock, for a new
## run).
func refill_ammo() -> void:
	_rounds.clear()
	_spares.clear()
	var ranged := weapon as RangedWeapon
	if ranged:
		ranged.fill(spare_magazines)


## Hands `teammate` a magazine for their equipped ranged weapon, paid from the carried ore (see
## `RangedWeapon.receive_ammo`). Returns whether it did.
func give_ammo(teammate: Player) -> bool:
	if teammate == self or teammate.dead or dead:
		return false
	var ranged := teammate.weapon as RangedWeapon
	return ranged != null and ranged.receive_ammo(self)


## Equips the weapon in the next filled loadout slot (wrapping around). Returns whether it switched.
func switch_weapon() -> bool:
	var slots: int = settings.loadout_slots
	for step: int in range(1, slots):
		var slot: int = (weapon_slot + step) % slots
		if loadout.get_weapon(slot):
			weapon_slot = slot
			_equip(loadout.get_weapon(slot))
			return true
	return false


## The weapon type of the equipped weapon, or null.
func get_weapon_type() -> WeaponType:
	return _weapon_type


## Health when unhurt, with the skills and the armor upgrade.
func max_health() -> float:
	return vitals.maximum()


## The pips showing the armor's MK level.
func get_armor_pips() -> MkPips:
	return _armor_pips


## Adds `amount` units of `ore_type` to the cargo.
func add_cargo(ore_type: OreType, amount: float) -> void:
	if amount <= 0.0:
		return
	var carried: float = cargo.get(ore_type, 0.0)
	carried += amount
	cargo[ore_type] = carried
	cargo_changed.emit(ore_type, carried)


## Removes up to `amount` units of `ore_type` from the cargo (e.g. made into ammo).
func take_ore(ore_type: OreType, amount: float) -> void:
	var carried: float = cargo.get(ore_type, 0.0)
	if amount <= 0.0 or carried <= 0.0:
		return
	carried = maxf(carried - amount, 0.0)
	if carried < 0.0001:
		carried = 0.0
	cargo[ore_type] = carried
	cargo_changed.emit(ore_type, carried)


## Removes all cargo and returns it.
func take_cargo() -> Dictionary[OreType, float]:
	var taken: Dictionary[OreType, float] = cargo
	cargo = {}
	for ore_type: OreType in taken:
		cargo_changed.emit(ore_type, 0.0)
	return taken


## Loses `amount` health; dies at zero.
func take_damage(amount: float) -> void:
	vitals.damage(amount)


## Restores full health.
func heal() -> void:
	vitals.heal()


## Brings a dead player back at `at` with full health.
func respawn(at: Vector3) -> void:
	vitals.revive()
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


func _is_reloading() -> bool:
	var ranged := weapon as RangedWeapon
	return ranged != null and ranged.reloading


## Whether `action` is held for the player to act (not while using a menu, nor a press from it).
func _action_held(action: StringName) -> bool:
	return not menu and action not in _held_since_menu and Input.is_action_pressed(action)


func _action_just_pressed(action: StringName) -> bool:
	return _action_held(action) and Input.is_action_just_pressed(action)


## Drops everything and lies still until `respawn`.
func _on_died() -> void:
	if menu:
		menu.close()
	velocity = Vector3.ZERO
	suit_dash.cancel()
	if weapon:
		weapon.trigger_held = false
		weapon.visible = false
	if weapon is RangedWeapon:
		(weapon as RangedWeapon).cancel_reload()
	give_ammo_target = null
	give_ammo_time = 0.0
	if is_instance_valid(miner_target):
		miner_target.highlighted = false
	if is_instance_valid(interact_target):
		interact_target.highlighted = false
	miner_target = null
	interact_target = null
	take_cargo()
	# Falls and lies still; the collision shape stays, so the ship still knows where the body is.
	_animator.local_velocity = Vector2.ZERO
	_animator.dead = true
	_ship_pointer.visible = false
	_ship_pointer.process_mode = Node.PROCESS_MODE_DISABLED
	died.emit()


## Lets the meshes under `root` (the suit, the weapon) mark where they're visible in the stencil
## buffer, so the silhouette only shows where something else hides the player. Marks their
## materials in place: the imported ones are only used by players (and weapons they hold).
func _mark_visible(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.material_override:  # e.g. the suit light's own material
			write_stencil(mesh.material_override as BaseMaterial3D)
			continue
		for surface: int in mesh.mesh.get_surface_count():
			write_stencil(mesh.mesh.surface_get_material(surface) as BaseMaterial3D)


## Makes `material` mark where it's visible like the suit (see `_mark_visible`), e.g. for meshes a
## weapon builds later.
static func write_stencil(material: BaseMaterial3D) -> void:
	if not material:
		return
	material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	material.stencil_reference = STENCIL_VISIBLE


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
	_armor_pips.show_level(upgrades.mk(armor_upgrade), _armor_max_mk())
	_mark_visible(_armor_pips)


## Puts the spare magazine cells on the backpack, following the upper chest (like the armor's
## pips).
func _add_pouches() -> void:
	_pouches.name = "SparePouches"
	add_child(_pouches)
	_follow(_bone_marker(POUCHES_BONE, Transform3D(Basis.IDENTITY, POUCHES_POSITION)), _pouches)
	_pouches.visible = false


## Shows the equipped ranged weapon's spare magazines while it's drawn.
func _update_pouches() -> void:
	var ranged := weapon as RangedWeapon
	_pouches.visible = ranged != null and ranged.visible
	if not _pouches.visible:
		return
	var gauge := ranged.get_node_or_null(^"AmmoGauge") as AmmoGauge
	_pouches.show_spares(
		float(ranged.spare_rounds) / ranged.capacity(),
		spare_magazines,
		gauge.color if gauge else Color.WHITE
	)


## Puts the dash's cooldown strip across the back of the backpack, following the upper chest.
func _add_dash_strip() -> void:
	_dash_strip.name = "DashStrip"
	add_child(_dash_strip)
	_follow(
		_bone_marker(POUCHES_BONE, Transform3D(Basis.IDENTITY, DASH_STRIP_POSITION)), _dash_strip
	)
	_dash_strip.visible = false
	_mark_visible(_dash_strip)


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
## equipped ranged weapon isn't full) a magazine once it's held for `settings.give_ammo_time`.
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
		var ranged := teammate.weapon as RangedWeapon
		if not ranged or ranged.rounds >= ranged.capacity():
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
	if weapon is RangedWeapon:
		# A magazine reload cut short leaves it empty; loaded single rounds stay.
		_rounds[_weapon_type] = (weapon as RangedWeapon).rounds
		_spares[_weapon_type] = (weapon as RangedWeapon).spare_rounds
	_weapon_type = weapon_type
	if weapon:
		_weapon_mount.remove_child(weapon)
		weapon.queue_free()
		weapon = null
	if not weapon_type:
		return
	weapon = weapon_type.scene.instantiate() as Weapon
	weapon.holder = self
	weapon.apply_upgrades(upgrades, weapon_type)
	var ranged := weapon as RangedWeapon
	if ranged:
		ranged.supplier = self
		var loaded: int = _rounds.get(weapon_type, ranged.capacity())
		ranged.rounds = mini(loaded, ranged.capacity())
		ranged.spare_rounds = _spares.get(weapon_type, spare_magazines * ranged.capacity())
		ranged.careful = skills.has(Skill.Effect.CAREFUL_RELOAD)
		ranged.reload_denied.connect(_on_reload_denied)
		ranged.reload_timed.connect(_on_reload_timed.bind(ranged))
	weapon.visible = weapon_allowed and not dead
	_mark_visible(weapon)
	_weapon_mount.add_child(weapon)


## Applies new MK levels: to the equipped weapon, and a stronger armor adds its extra health.
func _on_reload_denied() -> void:
	_reload_ring.flash(ReloadRing.FUMBLE_COLOR)


## A hit that finished the reload flashes the ring (single rounds go on loading meanwhile).
func _on_reload_timed(hit: bool, ranged: RangedWeapon) -> void:
	if hit and not ranged.reloading:
		_reload_ring.flash(AmmoGauge.TIMING)


## Upgrades are bought aboard, so the magazines are filled to their new size.
func _on_upgrades_changed() -> void:
	if weapon:
		weapon.apply_upgrades(upgrades, _weapon_type)
	refill_ammo()
	_armor_pips.show_level(upgrades.mk(armor_upgrade), _armor_max_mk())
	vitals.update_maximum()


## Skills are learned aboard: more spare magazines fill up, more health adds the difference, the
## equipped weapon reloads carefully.
func _on_skills_changed() -> void:
	var ranged := weapon as RangedWeapon
	if ranged:
		ranged.careful = skills.has(Skill.Effect.CAREFUL_RELOAD)
	refill_ammo()
	vitals.update_maximum()


## Keeps the equipped weapon in the loadout: the one in its slot, or else the first one there.
func _on_loadout_changed() -> void:
	if not loadout.get_weapon(weapon_slot):
		for slot: int in settings.loadout_slots:
			if loadout.get_weapon(slot):
				weapon_slot = slot
				break
	_equip(loadout.get_weapon(weapon_slot))
