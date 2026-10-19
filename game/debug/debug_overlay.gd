extends CanvasLayer
## Developer tool (autoload `DebugOverlay`): a 2D panel to tune values while playing, toggled with
## `debug_overlay` (F3). Two tabs: "State" (live values and the shortcuts, grouped) and "Tuning" (a
## folded section of sliders per settings file). It only exists when the game runs from the editor;
## in exported builds (debug ones too) it removes itself at start. Tuning changes the settings
## resources live, so every scene using them sees the new values right away; they last until the
## game stops and aren't written to the files. Also shows the mission and flight state and has
## shortcuts for testing the flight, storm, death, fights, weapons, ammo, upgrades and the heat
## shield, and teammates standing still (to see their rings before co-op). Integer settings get
## whole-number sliders.

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
	"res://game/weapons/blaster_settings.tres":
	[
		["damage", 1.0, 100.0, 1.0],
		["attack_rate", 0.5, 20.0, 0.5],
		["stagger", 0.0, 100.0, 1.0],
		["push", 0.0, 10.0, 0.1],
		["projectile_speed", 5.0, 100.0, 1.0],
		["projectile_range", 5.0, 60.0, 1.0],
		["magazine", 1.0, 200.0, 1.0],
		["ore_per_round", 0.0, 5.0, 0.05],
		["reload_time", 0.1, 5.0, 0.05],
		["sweet_spot_start", 0.0, 1.0, 0.05],
		["sweet_spot_width", 0.0, 1.0, 0.05],
		["fumble_time", 0.0, 3.0, 0.05],
	],
	"res://game/weapons/shotgun_settings.tres":
	[
		["damage", 1.0, 100.0, 1.0],
		["attack_rate", 0.5, 20.0, 0.5],
		["stagger", 0.0, 100.0, 1.0],
		["push", 0.0, 10.0, 0.1],
		["pellets", 1.0, 20.0, 1.0],
		["spread", 0.0, 90.0, 1.0],
		["projectile_speed", 5.0, 100.0, 1.0],
		["projectile_range", 5.0, 60.0, 1.0],
		["magazine", 1.0, 200.0, 1.0],
		["ore_per_round", 0.0, 5.0, 0.05],
		["reload_time", 0.1, 5.0, 0.05],
		["sweet_spot_start", 0.0, 1.0, 0.05],
		["sweet_spot_width", 0.0, 1.0, 0.05],
		["fumble_time", 0.0, 3.0, 0.05],
		["chain_speedup", 0.0, 0.5, 0.05],
		["max_chain_speedup", 0.0, 0.9, 0.05],
	],
	"res://game/weapons/hammer_settings.tres":
	[
		["damage", 1.0, 200.0, 1.0],
		["attack_rate", 0.2, 5.0, 0.1],
		["stagger", 0.0, 100.0, 1.0],
		["push", 0.0, 10.0, 0.1],
		["reach", 0.5, 6.0, 0.1],
		["arc", 10.0, 360.0, 5.0],
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
	],
}
const PANEL_WIDTH: float = 460.0
## Every weapon of the game, for `unlock_weapons`.
const ALL_WEAPONS: Arsenal = preload("res://game/weapons/all_weapons.tres")
## Every skill of the game, for `learn_skills`.
const SKILL_TREE: SkillTree = preload("res://game/progression/skills/tree/skill_tree.tres")
## Every ore of the game: `fill_hold` and `give_ore` add each of them.
const ALL_ORES: OreCatalog = preload("res://game/ores/all_ores.tres")
## How much `fill_hold` adds of each ore.
const HOLD_FILL: float = 900.0
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
		lines.append("%s: %s, carrying %.0f" % [player.name, status, carried])
	var aliens: Array[Node] = get_tree().get_nodes_in_group(Alien.GROUP)
	var chasing: int = aliens.filter(func(alien: Alien) -> bool: return alien.target != null).size()
	var hunters: int = aliens.filter(_has_role.bind(Alien.Role.HUNTER)).size()
	var raiders: int = aliens.filter(_has_role.bind(Alien.Role.RAIDER)).size()
	var nests: int = get_tree().get_nodes_in_group(AlienNest.GROUP).size()
	lines.append(
		(
			"Aliens: %d (%d chasing, %d hunters, %d raiders), nests: %d"
			% [aliens.size(), chasing, hunters, raiders, nests]
		)
	)
	var miners: Array[Node] = get_tree().get_nodes_in_group(Miner.GROUP)
	var broken: int = miners.filter(func(miner: Miner) -> bool: return miner.broken).size()
	lines.append("Miners: %d (%d broken)" % [miners.size(), broken])
	_live.text = "\n".join(lines)
	var running: bool = mission != null and mission.state == Mission.State.RUNNING
	for button: Button in _time_buttons:
		button.disabled = not running
	_skip_flight_button.disabled = mission == null or not mission.flight.is_flying()


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


func kill_players() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		player.take_damage(player.health)


func kill_aliens() -> void:
	for alien: Alien in get_tree().get_nodes_in_group(Alien.GROUP):
		alien.take_damage(alien.health)


## Lets every nest hatch a pack of hunters right away.
func hatch_hunters() -> void:
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.hatch_pack()


## Lets every nest hatch an alien of `strain` in its role right away (also one that doesn't hatch
## there).
func hatch_strain(strain: AlienStrain) -> void:
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.hatch(strain.role, strain)


## Lets every nest hatch a raider right away.
func hatch_raiders() -> void:
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.hatch(Alien.Role.RAIDER)


func break_miners() -> void:
	for miner: Miner in get_tree().get_nodes_in_group(Miner.GROUP):
		miner.take_damage(miner.health)


## Gives every player every weapon of the game (until blueprints unlock them).
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


## Adds `HOLD_FILL` units of every ore type to each ship's hold, to test the upgrade stations.
func fill_hold() -> void:
	for ship: Ship in get_tree().get_nodes_in_group(Ship.GROUP):
		for ore_type: OreType in ALL_ORES.ores:
			ship.add_to_hold(ore_type, HOLD_FILL)


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
	_button(players, "Kill players", kill_players)
	_button(players, "Heal players", heal_players)
	_button(players, "Give ore", give_ore)
	_button(players, "Add teammate", _add_teammate)
	_button(players, "Remove teammates", _remove_teammates)
	var world: GridContainer = _group(state, "Aliens and miners")
	_button(world, "Kill aliens", kill_aliens)
	_button(world, "Hatch hunters", hatch_hunters)
	_button(world, "Hatch raiders", hatch_raiders)
	_button(world, "Break miners", break_miners)
	var hive: AlienHive = load(HIVE_PATH)
	for strain: AlienStrain in hive.strains:
		_button(world, "Hatch %s" % strain.display_name.to_lower(), hatch_strain.bind(strain))
	var progress: GridContainer = _group(state, "Progress")
	_button(progress, "Unlock weapons", unlock_weapons)
	_button(progress, "Learn skills", learn_skills)
	_button(progress, "Fill hold", fill_hold)
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


static func _has_role(alien: Alien, role: Alien.Role) -> bool:
	return alien.role == role


static func _format(value: float, step: float) -> String:
	return "%.1f" % value if step < 1.0 else "%d" % roundi(value)
