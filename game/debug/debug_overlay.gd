extends CanvasLayer
## Developer tool (autoload `DebugOverlay`): a 2D panel to tune values while playing, toggled with
## `debug_overlay` (F3). Two tabs: "State" (live values and the shortcuts, grouped) and "Tuning" (a
## folded section of sliders per settings file). It only exists when the game runs from the editor;
## in exported builds (debug ones too) it removes itself at start. Tuning changes the settings
## resources live, so every scene using them sees the new values right away; they last until the
## game stops and aren't written to the files. Also shows the mission and flight state and has
## shortcuts for testing the flight, storm, death, fights, weapons, ammo, upgrades, the heat
## shield and the furnaces, and teammates standing still (to see their rings before co-op, and hurt
## to heal them), and switches for god mode (players take no damage) and the aliens' AI (off: they
## stand still).
## Integer settings get whole-number sliders.

## Sliders per settings resource: property, min, max, step. All ranges are generous on purpose.
const TUNING: Dictionary[String, Array] = {
	"res://game/mission/mission_settings.tres":
	[
		["duration", 10.0, 1800.0, 10.0],
		["warning_time", 5.0, 300.0, 5.0],
		["storm_damage", 0.0, 50.0, 0.5],
		["storm_damage_growth", 0.0, 20.0, 0.5],
		["respawn_delay", 0.0, 10.0, 0.5],
	],
	"res://game/ship/flight_settings.tres":
	[
		["departure_time", 0.0, 60.0, 1.0],
		["travel_time", 0.0, 120.0, 1.0],
		["descent_time", 0.0, 120.0, 1.0],
		["touchdown_time", 0.0, 30.0, 0.5],
		["takeoff_delay", 0.0, 30.0, 0.5],
		["takeoff_time", 0.0, 60.0, 1.0],
	],
	"res://game/mining/miner_settings.tres":
	[
		["fill_rate", 0.1, 20.0, 0.1],
		["capacity", 10.0, 1000.0, 10.0],
		["hose_range", 1.0, 15.0, 0.5],
		["transfer_rate", 1.0, 200.0, 1.0],
		["max_health", 10.0, 1000.0, 10.0],
		["repair_rate", 1.0, 200.0, 1.0],
		["repair_range", 0.5, 10.0, 0.5],
	],
	"res://game/player/player_settings.tres":
	[
		["move_speed", 1.0, 20.0, 0.5],
		["max_health", 10.0, 500.0, 10.0],
		["reload_move_speed", 0.1, 1.0, 0.05],
		["spare_magazines", 0.0, 10.0, 1.0],
	],
	"res://game/aliens/strains/swarmer/swarmer.tres":
	[
		["max_health", 1.0, 300.0, 1.0],
		["armor", 0.0, 50.0, 1.0],
		["stagger_threshold", 1.0, 200.0, 1.0],
		["stagger_time", 0.0, 3.0, 0.05],
		["knockback", 0.0, 3.0, 0.1],
		["move_speed", 0.5, 15.0, 0.1],
		["detection_range", 1.0, 40.0, 1.0],
		["chase_range", 1.0, 60.0, 1.0],
	],
	"res://game/aliens/strains/swarmer/bite.tres":
	[
		["damage", 0.0, 100.0, 1.0],
		["reach", 0.5, 5.0, 0.1],
		["cooldown", 0.1, 5.0, 0.1],
	],
	"res://game/aliens/strains/swarmer/pounce.tres":
	[
		["damage", 0.0, 100.0, 1.0],
		["cooldown", 0.5, 20.0, 0.5],
		["wind_up", 0.0, 2.0, 0.05],
		["recovery", 0.0, 3.0, 0.05],
		["max_range", 1.0, 15.0, 0.5],
		["leap_distance", 1.0, 10.0, 0.5],
		["leap_speed", 2.0, 30.0, 1.0],
	],
	"res://game/aliens/strains/mite/mite.tres":
	[
		["max_health", 1.0, 100.0, 1.0],
		["move_speed", 0.5, 15.0, 0.1],
		["cap_share", 0.05, 1.0, 0.05],
	],
	"res://game/aliens/strains/mite/bite.tres":
	[
		["damage", 0.0, 50.0, 1.0],
		["cooldown", 0.1, 5.0, 0.1],
	],
	"res://game/aliens/strains/spitter/spitter.tres":
	[
		["max_health", 1.0, 300.0, 1.0],
		["move_speed", 0.5, 15.0, 0.1],
		["keep_away", 0.0, 20.0, 0.5],
	],
	"res://game/aliens/strains/spitter/spit.tres":
	[
		["damage", 0.0, 100.0, 1.0],
		["reach", 2.0, 30.0, 0.5],
		["cooldown", 0.5, 20.0, 0.5],
		["wind_up", 0.0, 2.0, 0.05],
		["glob_speed", 2.0, 40.0, 1.0],
		["puddle_radius", 0.2, 5.0, 0.1],
		["puddle_time", 0.5, 20.0, 0.5],
		["puddle_damage", 0.0, 50.0, 1.0],
	],
	"res://game/aliens/strains/burrower/burrower.tres":
	[
		["max_health", 1.0, 300.0, 1.0],
		["move_speed", 0.5, 15.0, 0.1],
		["surface_time", 0.0, 15.0, 0.5],
	],
	"res://game/aliens/strains/burrower/eruption.tres":
	[
		["damage", 0.0, 100.0, 1.0],
		["cooldown", 0.5, 20.0, 0.5],
		["wind_up", 0.0, 3.0, 0.05],
		["trigger_range", 0.2, 4.0, 0.1],
	],
	"res://game/aliens/nest/alien_nest_settings.tres":
	[
		["guards", 0.0, 5.0, 1.0],
		["hunter_interval_start", 1.0, 300.0, 1.0],
		["hunter_interval_end", 1.0, 300.0, 1.0],
		["max_hunters_start", 0.0, 20.0, 0.25],
		["max_hunters_end", 0.0, 20.0, 0.25],
		["raider_interval_start", 1.0, 300.0, 1.0],
		["raider_interval_end", 1.0, 300.0, 1.0],
		["max_raiders_start", 0.0, 20.0, 0.25],
		["max_raiders_end", 0.0, 20.0, 0.25],
		["raider_draw", 0.0, 1.0, 0.05],
		["raider_draw_signature", 0.0, 1.0, 0.05],
		["frenzy_speed", 1.0, 2.0, 0.05],
		["call_cooldown", 0.0, 60.0, 1.0],
	],
	"res://game/aliens/strains/brute/brute.tres":
	[
		["max_health", 1.0, 600.0, 5.0],
		["armor", 0.0, 50.0, 1.0],
		["armor_arc", 0.0, 360.0, 5.0],
		["armored_stagger", 0.0, 1.0, 0.05],
		["stagger_threshold", 1.0, 300.0, 1.0],
		["move_speed", 0.5, 15.0, 0.1],
		["turn_speed", 0.5, 20.0, 0.5],
	],
	"res://game/aliens/strains/brute/charge.tres":
	[
		["damage", 0.0, 100.0, 1.0],
		["cooldown", 0.5, 20.0, 0.5],
		["wind_up", 0.0, 3.0, 0.05],
		["recovery", 0.0, 3.0, 0.05],
		["max_range", 2.0, 30.0, 0.5],
		["charge_speed", 2.0, 30.0, 0.5],
		["width", 0.3, 3.0, 0.1],
		["daze", 0.0, 5.0, 0.1],
	],
	"res://game/aliens/strains/shrieker/shrieker.tres":
	[
		["max_health", 1.0, 300.0, 1.0],
		["stagger_threshold", 1.0, 200.0, 1.0],
		["move_speed", 0.5, 15.0, 0.1],
		["keep_away", 0.0, 25.0, 0.5],
	],
	"res://game/aliens/strains/shrieker/scream.tres":
	[
		["reach", 2.0, 40.0, 0.5],
		["cooldown", 0.5, 30.0, 0.5],
		["radius", 1.0, 40.0, 0.5],
		["boost", 1.0, 2.0, 0.05],
		["boost_time", 0.0, 20.0, 0.5],
	],
	"res://game/aliens/strains/bloater/bloater.tres":
	[
		["max_health", 1.0, 300.0, 1.0],
		["move_speed", 0.5, 15.0, 0.1],
	],
	"res://game/aliens/strains/bloater/burst.tres":
	[
		["damage", 0.0, 100.0, 1.0],
		["radius", 0.5, 8.0, 0.1],
		["cloud_time", 0.0, 20.0, 0.5],
		["cloud_damage", 0.0, 50.0, 1.0],
	],
	"res://game/aliens/strains/tender/tender.tres":
	[
		["max_health", 1.0, 300.0, 1.0],
		["move_speed", 0.5, 15.0, 0.1],
		["keep_away", 0.0, 25.0, 0.5],
	],
	"res://game/aliens/strains/tender/mend.tres":
	[
		["links", 0.0, 8.0, 1.0],
		["link_range", 1.0, 30.0, 0.5],
		["break_range", 1.0, 40.0, 0.5],
		["heal_per_second", 0.0, 50.0, 0.5],
		["armor", 0.0, 30.0, 0.5],
	],
	"res://game/aliens/strains/darter/darter.tres":
	[
		["max_health", 1.0, 300.0, 1.0],
		["move_speed", 0.5, 15.0, 0.1],
		["flight_height", 0.5, 10.0, 0.1],
		["dive_height", 0.2, 3.0, 0.1],
	],
	"res://game/aliens/strains/darter/dive.tres":
	[
		["damage", 0.0, 100.0, 1.0],
		["cooldown", 0.5, 20.0, 0.5],
		["wind_up", 0.0, 3.0, 0.05],
		["recovery", 0.0, 3.0, 0.05],
		["max_range", 2.0, 30.0, 0.5],
		["charge_speed", 2.0, 30.0, 0.5],
	],
	"res://game/aliens/strains/stalker/stalker.tres":
	[
		["max_health", 1.0, 300.0, 1.0],
		["move_speed", 0.5, 15.0, 0.1],
		["retreat_time", 0.0, 10.0, 0.25],
	],
	"res://game/aliens/strains/stalker/cloak.tres":
	[
		["reveal_range", 0.0, 30.0, 0.5],
		["shown_time", 0.0, 10.0, 0.25],
		["fade_time", 0.05, 2.0, 0.05],
		["ambush_damage", 0.0, 100.0, 1.0],
		["bend", 0.0, 0.2, 0.005],
	],
	"res://game/aliens/strains/stalker/hook.tres":
	[
		["cooldown", 0.5, 30.0, 0.5],
		["max_range", 2.0, 30.0, 0.5],
		["snare", 0.0, 1.0, 0.05],
		["snare_time", 0.0, 5.0, 0.1],
	],
	"res://game/aliens/strains/skimmer/skimmer.tres":
	[
		["max_health", 1.0, 300.0, 1.0],
		["move_speed", 0.5, 15.0, 0.1],
		["flight_height", 0.5, 10.0, 0.1],
		["keep_away", 0.0, 25.0, 0.5],
	],
	"res://game/aliens/strains/skimmer/spit.tres":
	[
		["damage", 0.0, 100.0, 1.0],
		["reach", 2.0, 40.0, 0.5],
		["cooldown", 0.5, 20.0, 0.5],
		["glob_speed", 2.0, 40.0, 0.5],
	],
	"res://game/aliens/strains/ravager/ravager.tres":
	[
		["max_health", 1.0, 5000.0, 10.0],
		["armor", 0.0, 50.0, 1.0],
		["stagger_threshold", 1.0, 1000.0, 5.0],
		["move_speed", 0.5, 15.0, 0.1],
		["detection_range", 1.0, 60.0, 1.0],
		["chase_range", 1.0, 80.0, 1.0],
		["tremor", 0.0, 0.5, 0.01],
	],
	"res://game/aliens/strains/ravager/shed.tres":
	[
		["count", 0.0, 10.0, 1.0],
		["cooldown", 1.0, 60.0, 1.0],
		["max_range", 2.0, 40.0, 0.5],
	],
}
const PANEL_WIDTH: float = 460.0
## Every weapon of the game, for `unlock_weapons`, `_give_blueprints` and the tuning.
const ALL_WEAPONS: Arsenal = preload("res://game/weapons/all_weapons.tres")
## Every skill of the game, for `learn_skills`.
const SKILL_TREE: SkillTree = preload("res://game/progression/skills/tree/skill_tree.tres")
## Every ore of the game: `fill_hold` and `give_ore` add each of them.
const ALL_ORES: OreCatalog = preload("res://game/ores/all_ores.tres")
## Every alloy of the game: `fill_hold` adds bars of each of them.
const ALL_ALLOYS: AlloyCatalog = preload("res://game/refinery/all_alloys.tres")
## How much `fill_hold` adds of each ore, and how many bars of each alloy.
const HOLD_FILL: float = 900.0
const ALLOY_FILL: float = 30.0
const CARGO_FILL: float = 60.0
const PLAYER_SCENE_PATH: String = "res://game/player/player.tscn"
## Loaded when the panel is built: it refers to every strain's scene.
const HIVE_PATH: String = "res://game/aliens/hive/hive.tres"

## Values from the files, for `reset_tuning`, keyed by "path:property".
var _defaults: Dictionary[String, float] = {}
var _sliders: Dictionary[String, HSlider] = {}
var _live: Label
var _time_buttons: Array[Button] = []
var _skip_flight_button: Button
## Buttons that need a nest (the hatches), aliens or a working miner; off without one (aboard
## in space, in flight).
var _nest_buttons: Array[Button] = []
var _kill_aliens_button: Button
var _break_miners_button: Button


func _ready() -> void:
	if not OS.has_feature("editor"):
		queue_free()
		return
	layer = 100
	visible = false
	_build()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_overlay"):
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	var mission: Mission = _mission()
	var lines: PackedStringArray = []
	if mission:
		lines.append("Mission: %s" % Mission.State.keys()[mission.state])
		var flight: ShipFlight = mission.flight
		lines.append(
			(
				"Flight: %s (%.1f / %.1f s)"
				% [
					ShipFlight.Phase.keys()[flight.phase],
					flight.phase_time,
					flight.phase_duration()
				]
			)
		)
		lines.append("Time left: %.1f s" % mission.time_left)
		if mission.state == Mission.State.STORM:
			lines.append("Storm: %.1f HP/s" % mission.storm_damage_per_second())
		lines.append("Escalation: %d%%" % roundi(mission.progress() * 100.0))
		(
			lines
			. append(
				(
					"Tier %d: aliens x%.2f health, x%.2f damage; warning %.0f s; upgrades up to MK%d"
					% [
						mission.tier(),
						mission.settings.alien_health_at(mission.tier()),
						mission.settings.alien_damage_at(mission.tier()),
						mission.warning_time(),
						mission.ship.heat_shield.upgrade_cap(),
					]
				)
			)
		)
	else:
		lines.append("No mission in this scene")
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		var carried: float = 0.0
		for amount: float in player.cargo.values():
			carried += amount
		var status: String = "dead" if player.dead else "%.0f HP" % player.health
		if PlayerVitals.god_mode:
			status += " (god mode)"
		lines.append("%s: %s, carrying %.0f" % [player.name, status, carried])
	var aliens: Array[Node] = get_tree().get_nodes_in_group(Alien.GROUP)
	var chasing: int = aliens.filter(func(alien: Alien) -> bool: return alien.target != null).size()
	var hunters: int = aliens.filter(_has_role.bind(Alien.Role.HUNTER)).size()
	var raiders: int = aliens.filter(_has_role.bind(Alien.Role.RAIDER)).size()
	var nests: int = get_tree().get_nodes_in_group(AlienNest.GROUP).size()
	var bodies: Array[Node] = get_tree().get_nodes_in_group(Destructible.GROUP)
	var husks: int = bodies.filter(func(body: Destructible) -> bool: return body.dead).size()
	var counts: Array = [aliens.size(), chasing, hunters, raiders, nests, husks]
	counts.append("" if Alien.ai_on else ", AI off")
	lines.append(
		"Aliens: %d (%d chasing, %d hunters, %d raiders), nests: %d (%d destroyed)%s" % counts
	)
	var miners: Array[Node] = get_tree().get_nodes_in_group(Miner.GROUP)
	var broken: int = miners.filter(func(miner: Miner) -> bool: return miner.broken).size()
	lines.append("Miners: %d (%d broken)" % [miners.size(), broken])
	_live.text = "\n".join(lines)
	var running: bool = mission != null and mission.state == Mission.State.RUNNING
	for button: Button in _time_buttons:
		button.disabled = not running
	_skip_flight_button.disabled = mission == null or not mission.flight.is_flying()
	for button: Button in _nest_buttons:
		button.disabled = nests == 0
	_kill_aliens_button.disabled = aliens.is_empty()
	_break_miners_button.disabled = miners.size() == broken


func toggle() -> void:
	visible = not visible


## Jumps to the start of the warning time (only while the timer runs).
func skip_to_warning() -> void:
	var mission: Mission = _mission()
	if mission and mission.state == Mission.State.RUNNING:
		mission.time_left = minf(mission.time_left, mission.warning_time())


## Lets the storm hit right away (only while the timer runs).
func start_storm() -> void:
	var mission: Mission = _mission()
	if mission and mission.state == Mission.State.RUNNING:
		mission.time_left = 0.0


## Ends the ship's flight right away (only while it flies).
func skip_flight() -> void:
	var mission: Mission = _mission()
	if mission and mission.flight.is_flying():
		mission.skip_flight()


## Kills every player, in god mode too.
func kill_players() -> void:
	var god_mode: bool = PlayerVitals.god_mode
	PlayerVitals.god_mode = false
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		player.take_damage(player.health)
	PlayerVitals.god_mode = god_mode


func kill_aliens() -> void:
	for alien: Alien in get_tree().get_nodes_in_group(Alien.GROUP):
		alien.take_damage(alien.health)


## Takes a burst's share of its health off every nest (with two bursts a third: each press is one
## stage, the third destroys them).
func _damage_nests() -> void:
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.body.take_damage(nest.body.max_health / (nest.settings.bursts + 1.0))


## Lets the nest nearest to the local player hatch a pack of hunters right away.
func hatch_hunters() -> void:
	var nest: AlienNest = _nearest_nest()
	if nest:
		nest.hatch_pack()


## Lets the nest nearest to the local player hatch an alien of `strain` in its role right away
## (also one that doesn't hatch there).
func hatch_strain(strain: AlienStrain) -> void:
	var nest: AlienNest = _nearest_nest()
	if nest:
		nest.hatch(strain.role, strain)


## Lets the nest nearest to the local player hatch a raider right away.
func hatch_raiders() -> void:
	var nest: AlienNest = _nearest_nest()
	if nest:
		nest.hatch(Alien.Role.RAIDER)


## The nest nearest to the local player (any player without a local one), or null.
func _nearest_nest() -> AlienNest:
	var from: Player = null
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if not from or (player.local and not from.local):
			from = player
	var nearest: AlienNest = null
	var nearest_distance: float = INF
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		var distance: float = (
			nest.global_position.distance_to(from.global_position) if from else 0.0
		)
		if distance < nearest_distance:
			nearest = nest
			nearest_distance = distance
	return nearest


func break_miners() -> void:
	for miner: Miner in get_tree().get_nodes_in_group(Miner.GROUP):
		miner.take_damage(miner.health)


## Gives every player the blueprint of every weapon they don't own, to build them at the
## workbench (until the quests hand them out).
func _give_blueprints() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		for weapon_type: WeaponType in ALL_WEAPONS.weapons:
			player.arsenal.learn(weapon_type)


## Gives every player every weapon of the game, without building them.
func unlock_weapons() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		for weapon_type: WeaponType in ALL_WEAPONS.weapons:
			player.arsenal.unlock(weapon_type)


## Installs the next plate of every ship's heat shield without paying: the next planet inwards
## opens.
func install_shield() -> void:
	for ship: Ship in get_tree().get_nodes_in_group(Ship.GROUP):
		ship.heat_shield.install_next()


## Installs every plate of every ship's heat shield, to try later planets' biomes before they're
## reached.
func open_all_bodies() -> void:
	for ship: Ship in get_tree().get_nodes_in_group(Ship.GROUP):
		while ship.heat_shield.install_next():
			pass


## Teaches every player every skill at its highest rank, to try them without paying.
func learn_skills() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		for skill: Skill in SKILL_TREE.get_skills():
			while player.skills.raise(skill):
				pass


## Adds `CARGO_FILL` units of every ore type to each player's cargo, to test reloading.
func give_ore() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		for ore_type: OreType in ALL_ORES.ores:
			player.add_cargo(ore_type, CARGO_FILL)


## Adds a teammate beside the local player: a player this machine doesn't play (it stands still),
## with the lowest free number. Returns it, or null when all four are there.
func _add_teammate() -> Player:
	var local: Player = null
	var numbers: Array[int] = []
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		numbers.append(player.number)
		if player.local and not local:
			local = player
	if not local:
		return null
	for number: int in range(1, Player.COLORS.size() + 1):
		if number in numbers:
			continue
		# Loaded here, not preloaded: the player's scripts are heavy for an autoload.
		var teammate := (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as Player
		teammate.local = false
		teammate.number = number
		local.get_parent().add_child(teammate)
		teammate.global_position = local.global_position + local.global_basis.x * 2.5
		teammate.reset_physics_interpolation()
		return teammate
	return null


## Removes the teammates `_add_teammate` added (every player this machine doesn't play).
func _remove_teammates() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if not player.local:
			player.queue_free()


## Takes half the health of every teammate (to try healing them, Kith).
func _hurt_teammates() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if not player.local:
			player.take_damage(player.vitals.maximum() * 0.5)


## Adds `HOLD_FILL` units of every ore type and `ALLOY_FILL` bars of every alloy to every player's
## hold, to test the upgrade stations, the furnaces and the ingot rack.
func fill_hold() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		for ore_type: OreType in ALL_ORES.ores:
			player.hold.add(ore_type, HOLD_FILL)
		for alloy: AlloyType in ALL_ALLOYS.alloys:
			player.hold.add(alloy, ALLOY_FILL)


## Unlocks the next of every ship's furnaces (until the quests do).
func _unlock_furnace() -> void:
	for ship: Ship in get_tree().get_nodes_in_group(Ship.GROUP):
		ship.furnaces.unlock()


## Finishes every bar of every player's batches in the furnaces now.
func _finish_refining() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		player.refining.finish_all(player.hold)


## Lets every player's upgrade levels and skill ranks under way take effect right now.
func _finish_jobs() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		player.upgrades.finish_all()
		player.skills.finish_all()


## Deletes the save (the dev save in the editor) and reloads the map, without asking (only while
## alone, see `SaveGame.reset_progress`).
func reset_save() -> void:
	var save_game := get_tree().get_first_node_in_group(SaveGame.GROUP) as SaveGame
	if save_game:
		save_game.reset_progress()
	else:
		SaveGame.erase()


func heal_players() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		player.heal()


## Sets every tuning value back to the one in its file.
func reset_tuning() -> void:
	for key: String in _sliders:
		_sliders[key].value = _defaults[key]


## The slider for `property` of the settings resource at `path`, or null.
func get_slider(path: String, property: String) -> HSlider:
	return _sliders.get("%s:%s" % [path, property])


func _mission() -> Mission:
	return get_tree().get_first_node_in_group(Mission.GROUP) as Mission


func _build() -> void:
	var panel := PanelContainer.new()
	# A developer tool: stays English (else e.g. "Progress" shows a game text's translation).
	panel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.85)
	style.set_content_margin_all(10.0)
	panel.add_theme_stylebox_override(&"panel", style)
	add_child(panel)

	var tabs := TabContainer.new()
	# Keyboard focus would let the movement keys switch tabs while playing.
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	panel.add_child(tabs)

	var state: VBoxContainer = _tab(tabs, "State (F3)")
	_live = Label.new()
	# Wraps instead of widening the panel (long lines pushed the buttons off the screen).
	_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_live.custom_minimum_size.x = 1.0
	state.add_child(_live)
	var mission: GridContainer = _group(state, "Mission")
	_time_buttons.append(_button(mission, "Skip to warning", skip_to_warning))
	_time_buttons.append(_button(mission, "Storm now", start_storm))
	_skip_flight_button = _button(mission, "Skip flight", skip_flight)
	var players: GridContainer = _group(state, "Players")
	_button(players, "Heal players", heal_players)
	_button(players, "Kill players", kill_players)
	_button(players, "Add teammate", _add_teammate)
	_button(players, "Remove teammates", _remove_teammates)
	_button(players, "Hurt teammates", _hurt_teammates)
	_button(players, "Give ore", give_ore)
	_switch(
		players,
		"God mode",
		PlayerVitals.god_mode,
		func(on: bool) -> void: PlayerVitals.god_mode = on
	)
	var aliens: GridContainer = _group(state, "Aliens")
	_switch(aliens, "Alien AI", Alien.ai_on, func(on: bool) -> void: Alien.ai_on = on)
	_nest_buttons.append(_button(aliens, "Hatch hunter packs", hatch_hunters))
	_nest_buttons.append(_button(aliens, "Hatch raiders", hatch_raiders))
	_nest_buttons.append(_button(aliens, "Damage nests", _damage_nests))
	_kill_aliens_button = _button(aliens, "Kill aliens", kill_aliens)
	var strains: GridContainer = _group(state, "Hatch a strain")
	var hive: AlienHive = load(HIVE_PATH)
	# By tier, in the hive's order within one.
	var by_tier: Array[AlienStrain] = hive.strains.duplicate()
	if hive.apex:
		by_tier.append(hive.apex)
	by_tier.sort_custom(
		func(a: AlienStrain, b: AlienStrain) -> bool:
			return (
				a.tier < b.tier
				or (a.tier == b.tier and hive.strains.find(a) < hive.strains.find(b))
			)
	)
	for strain: AlienStrain in by_tier:
		var role: String = (Alien.Role.keys()[strain.role] as String).capitalize()
		if strain == hive.apex:
			role = "Apex"
		var label: String = "%s (T%d, %s)" % [strain.display_name, strain.tier, role]
		_nest_buttons.append(_button(strains, label, hatch_strain.bind(strain)))
	var miners: GridContainer = _group(state, "Miners")
	_break_miners_button = _button(miners, "Break miners", break_miners)
	var progress: GridContainer = _group(state, "Progress")
	_button(progress, "Give blueprints", _give_blueprints)
	_button(progress, "Unlock weapons", unlock_weapons)
	_button(progress, "Learn skills", learn_skills)
	_button(progress, "Fill hold", fill_hold)
	_button(progress, "Unlock furnace", _unlock_furnace)
	_button(progress, "Finish refining", _finish_refining)
	_button(progress, "Finish jobs", _finish_jobs)
	_button(progress, "Install shield", install_shield)
	_button(progress, "Open all", open_all_bodies)
	_button(progress, "Reset save", reset_save)

	var tuning: VBoxContainer = _tab(tabs, "Tuning")
	_button(tuning, "Reset tuning", reset_tuning)
	for path: String in TUNING:
		var resource: Resource = load(path)
		var section := FoldableContainer.new()
		section.title = _tuning_title(path)
		section.folded = true
		section.focus_mode = Control.FOCUS_NONE
		tuning.add_child(section)
		var rows := VBoxContainer.new()
		section.add_child(rows)
		for row: Array in TUNING[path]:
			_add_slider(rows, resource, path, row)
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		var parts: Array[Resource] = [
			weapon_type,
			weapon_type.feed,
			weapon_type.trigger,
			weapon_type.delivery,
			weapon_type.guard
		]
		parts.append_array(weapon_type.effects)
		for resource: Resource in parts:
			var rows_of: Array = WeaponTuning.ROWS.get(_class_of(resource), [])
			if rows_of.is_empty():
				continue
			var section := FoldableContainer.new()
			section.title = "%s %s" % [weapon_type.display_name, _class_of(resource).capitalize()]
			section.folded = true
			section.focus_mode = Control.FOCUS_NONE
			tuning.add_child(section)
			var rows := VBoxContainer.new()
			section.add_child(rows)
			for row: Array in rows_of:
				_add_slider(rows, resource, resource.resource_path, row)


## A tab of `tabs` named `title`, scrolling vertically; returns its content box.
func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 8)
	scroll.add_child(box)
	return box


## A heading and a grid of buttons below it in `box`, two equal columns; returns the grid.
func _group(box: VBoxContainer, title: String) -> GridContainer:
	box.add_child(_heading(title))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	return grid


func _add_slider(box: VBoxContainer, resource: Resource, path: String, row: Array) -> void:
	var property: String = row[0]
	var key: String = "%s:%s" % [path, property]
	var line := HBoxContainer.new()
	box.add_child(line)
	var name_label := Label.new()
	name_label.text = property.capitalize()
	name_label.custom_minimum_size.x = 170.0
	# Long names end in "…" instead of pushing the slider and its value off the panel.
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = name_label.text
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = row[1]
	slider.max_value = row[2]
	slider.step = row[3]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Keyboard focus would let the movement keys change the value while playing.
	slider.focus_mode = Control.FOCUS_NONE
	line.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 50.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value_label)

	var value: float = resource.get(property)
	var whole: bool = typeof(resource.get(property)) == TYPE_INT
	_defaults[key] = value
	_sliders[key] = slider
	slider.value = value
	value_label.text = _format(value, slider.step)
	slider.value_changed.connect(
		func(new_value: float) -> void:
			if whole:
				resource.set(property, roundi(new_value))
			else:
				resource.set(property, new_value)
			value_label.text = _format(new_value, slider.step)
	)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 18)
	return label


## The class name of `resource`'s script ("MagazineFeed"), or "" (none, e.g. no feed).
static func _class_of(resource: Resource) -> String:
	if not resource or not resource.get_script():
		return ""
	return (resource.get_script() as Script).get_global_name()


## A tuning section's title: the file's name, with its strain's for an attack ("Mite bite").
static func _tuning_title(path: String) -> String:
	var title: String = path.get_file().get_basename()
	var folder: String = path.get_base_dir().get_file()
	if path.get_base_dir().get_base_dir().ends_with("strains") and folder != title:
		title = "%s %s" % [folder, title]
	return title.capitalize()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## A switch in `parent`, starting `on`; `action` gets its new state.
func _switch(parent: Control, text: String, on: bool, action: Callable) -> CheckButton:
	var button := CheckButton.new()
	button.text = text
	button.button_pressed = on
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.toggled.connect(action)
	parent.add_child(button)
	return button


static func _has_role(alien: Alien, role: Alien.Role) -> bool:
	return alien.role == role


static func _format(value: float, step: float) -> String:
	return "%.1f" % value if step < 1.0 else "%d" % roundi(value)
