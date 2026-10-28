class_name PlayerArms
extends Node
## The `holder`'s weapons in hand: the equipped `weapon` from its loadout (`slot`), held in the
## right hand (`weapon_mount`) or on the left forearm for a shield (`shield_mount`) and aimed where
## the holder aims; `switch_weapon` equips and draws the next one. Fed weapons keep their loaded
## rounds and spares while holstered for the run and `reload` them with ammo the suit makes from
## the carried ore (`OreAmmo`; free aboard, `ammo_free`), the holder walking slower meanwhile
## (`move_share`). Holding `interact` next to a teammate, with nothing else to use there, hands
## them a magazine for their equipped weapon (`give_ammo`), paid from the holder's ore. The weapon
## is put away where it can't be used (`allowed`) and while the holder lies down. New MK levels
## and skills (bought aboard) apply to the weapon and fill the magazines. The holder ticks it every
## physics step (`update`) and stops it when it falls (`stop`).

## The player holding the weapons.
var holder: Player
## Where a weapon is held, and a shield.
var weapon_mount: Node3D
var shield_mount: Node3D
## Swings the body with the weapon's melee attacks.
var animator: PlayerAnimator
## Flashes on a reload denied or timed.
var ring: SuitRing
## The equipped weapon, or null with an empty loadout.
var weapon: Weapon
## The loadout slot of the equipped weapon (or the one to fill first when it's empty).
var slot: int = 0
## Whether the weapon can be used here; it's holstered (hidden) otherwise, e.g. inside the ship.
var allowed: bool = true:
	set(value):
		allowed = value
		update_holster()
## Whether reloads cost nothing (aboard: from the ship's stock).
var ammo_free: bool = false
## The teammate `interact` hands ammo to while it's held, or null; and for how long it's held (s).
var give_target: Player
var give_time: float = 0.0
## Spare magazines per ranged weapon a run starts with, with the skills.
var spare_magazines: int:
	get:
		return (
			holder.settings.spare_magazines
			+ roundi(holder.skills.value(Skill.Effect.SPARE_MAGAZINES))
		)

var _weapon_type: WeaponType
## Rounds loaded per fed weapon of the loadout that isn't equipped; missing ones are full.
var _rounds: Dictionary[WeaponType, int] = {}
## Spare rounds per fed weapon of the loadout that isn't equipped; missing ones have all spares.
var _spares: Dictionary[WeaponType, int] = {}


## Equips the weapon of the holder's loadout and follows its changes, the MK levels and the skills.
func _ready() -> void:
	holder.loadout.changed.connect(_on_loadout_changed)
	holder.upgrades.changed.connect(_on_upgrades_changed)
	holder.skills.changed.connect(_on_skills_changed)
	_on_loadout_changed()


## Aims the weapon where the holder aims and pulls its trigger while `attack` is held; switches,
## reloads and hands ammo on the holder's input.
func update(delta: float) -> void:
	var input: PlayerInput = holder.input
	if weapon:
		var aim: PlayerAim = holder.aim
		weapon.aim_direction = aim.direction
		weapon.aim_target = aim.target
		weapon.aim_point = aim.ground_point
		weapon.trigger_held = allowed and input.held(&"attack") and not aim.is_mouse_over_ui()
	_update_give_ammo(delta)
	if input.just_pressed(&"switch_weapon"):
		switch_weapon()
	if input.just_pressed(&"reload"):
		reload()


## The share of the walking speed it leaves: the weapon's, and slower while reloading (unless the
## skill keeps the speed up).
func move_share() -> float:
	var share: float = 1.0
	if _is_reloading() and not holder.skills.has(Skill.Effect.RELOAD_ON_THE_MOVE):
		share *= holder.settings.reload_move_speed
	if weapon:
		share *= weapon.move_share()
	return share


## The `reload` action on the equipped weapon's ammo (see `WeaponAmmo.reload`). Returns whether
## it started or timed a reload.
func reload() -> bool:
	var ammo: WeaponAmmo = get_ammo()
	return ammo != null and allowed and not holder.fallen and ammo.reload()


## Fills every fed weapon's magazine and spare magazines for free (the ship's stock, for a new
## run).
func refill() -> void:
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


## Hands `teammate` a magazine for their equipped fed weapon, paid from the holder's carried ore
## (see `WeaponAmmo.receive_ammo`). Returns whether it did.
func give_ammo(teammate: Player) -> bool:
	if teammate == holder or teammate.fallen or holder.fallen:
		return false
	var ammo: WeaponAmmo = teammate.arms.get_ammo()
	return ammo != null and ammo.receive_ammo(holder)


## Equips the weapon in the next filled loadout slot (wrapping around) and draws it. Returns
## whether it switched.
func switch_weapon() -> bool:
	var slots: int = holder.settings.loadout_slots
	for step: int in range(1, slots):
		var next: int = (slot + step) % slots
		if holder.loadout.get_weapon(next):
			slot = next
			_equip(holder.loadout.get_weapon(next))
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


## Shows the weapon while it can be used (`allowed`, the holder standing and not lying on a bed)
## and stops what it does.
func update_holster() -> void:
	if weapon:
		weapon.visible = allowed and not holder.lying_on and not holder.fallen
		weapon.stop()


## Stops everything (the holder fell): puts the weapon away, cuts a reload short and stops handing
## ammo.
func stop() -> void:
	update_holster()
	if get_ammo():
		get_ammo().cancel_reload()
	give_target = null
	give_time = 0.0


func _is_reloading() -> bool:
	var ammo: WeaponAmmo = get_ammo()
	return ammo != null and ammo.reloading


## Holding `interact` with nothing to use in range hands the nearest teammate in range (whose
## equipped fed weapon isn't full) a magazine once it's held for `settings.give_ammo_time`.
func _update_give_ammo(delta: float) -> void:
	var target: Player = null
	if not holder.interact_target and holder.input.held(&"interact"):
		target = _teammate_needing_ammo()
	if target != give_target:
		give_target = target
		give_time = 0.0
	if not give_target:
		return
	give_time += delta
	if give_time >= holder.settings.give_ammo_time:
		give_ammo(give_target)
		give_target = null
		give_time = 0.0
		holder.input.use_up(&"interact")


func _teammate_needing_ammo() -> Player:
	var best: Player = null
	var best_distance: float = holder.settings.give_ammo_range
	for node: Node in holder.get_tree().get_nodes_in_group(Player.GROUP):
		var teammate := node as Player
		if teammate == holder or teammate.fallen:
			continue
		var ammo: WeaponAmmo = teammate.arms.get_ammo()
		if not ammo or ammo.is_full():
			continue
		var distance: float = holder.global_position.distance_to(teammate.global_position)
		if distance <= best_distance:
			best = teammate
			best_distance = distance
	return best


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
	weapon.holder = holder
	weapon.motion_started.connect(animator.play_motion)
	weapon.apply_upgrades(holder.upgrades)
	var ammo: WeaponAmmo = weapon.ammo
	if ammo:
		ammo.supplier = holder
		var loaded: int = _rounds.get(weapon_type, ammo.capacity())
		ammo.rounds = mini(loaded, ammo.capacity())
		ammo.spare_rounds = _spares.get(weapon_type, spare_magazines * ammo.capacity())
		_set_careful()
		ammo.reload_denied.connect(_on_reload_denied)
		ammo.reload_timed.connect(_on_reload_timed.bind(ammo))
	weapon.visible = allowed and not holder.fallen
	OccludedSilhouette.mark_visible(weapon)
	RenderLayers.put(weapon, RenderLayers.CHARACTERS)
	var shield: bool = weapon_type.hold == WeaponType.Hold.SHIELD
	(shield_mount if shield else weapon_mount).add_child(weapon)


## A reload that can't start (no ore) flashes the ring's ammo arc red.
func _on_reload_denied() -> void:
	ring.flash(SuitRing.FUMBLE_COLOR)


## A hit that finished the reload flashes the ring (single rounds go on loading meanwhile).
func _on_reload_timed(hit: bool, ammo: WeaponAmmo) -> void:
	if hit and not ammo.reloading:
		ring.flash(AmmoGauge.TIMING)


## Applies new MK levels to the equipped weapon. Levels take effect aboard, so the magazines are
## filled to their new size.
func _on_upgrades_changed() -> void:
	if weapon:
		weapon.apply_upgrades(holder.upgrades)
	refill()


## Skills are learned aboard: more spare magazines fill up, the equipped weapon reloads carefully.
func _on_skills_changed() -> void:
	_set_careful()
	refill()


## Whether the equipped weapon's magazine reloads keep the rounds left in it (the skill).
func _set_careful() -> void:
	var magazine := get_ammo() as MagazineAmmo
	if magazine:
		magazine.careful = holder.skills.has(Skill.Effect.CAREFUL_RELOAD)


## Keeps the equipped weapon in the loadout: the one in its slot, or else the first one there.
func _on_loadout_changed() -> void:
	var loadout: Loadout = holder.loadout
	if not loadout.get_weapon(slot):
		for filled: int in holder.settings.loadout_slots:
			if loadout.get_weapon(filled):
				slot = filled
				break
	_equip(loadout.get_weapon(slot))
