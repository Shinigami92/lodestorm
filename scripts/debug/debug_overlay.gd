extends CanvasLayer
## Developer tool (autoload `DebugOverlay`): a 2D panel to tune values while playing, toggled with
## `debug_overlay` (F3). It only exists when the game runs from the editor; in exported builds
## (debug ones too) it removes itself at start. Tuning changes the settings resources live, so
## every scene using them sees the new values right away; they last until the game stops and
## aren't written to the files. Also shows the mission state and has shortcuts for testing the
## storm, death and fights. Integer settings get whole-number sliders.

## Sliders per settings resource: property, min, max, step. All ranges are generous on purpose.
const TUNING: Dictionary[String, Array] = {
	"res://scenes/mission/mission_settings.tres":
	[
		["duration", 10.0, 1800.0, 10.0],
		["warning_time", 5.0, 300.0, 5.0],
		["storm_damage", 0.0, 50.0, 0.5],
		["storm_damage_growth", 0.0, 20.0, 0.5],
		["respawn_delay", 0.0, 10.0, 0.5],
	],
	"res://scenes/mining/miner_settings.tres":
	[
		["fill_rate", 0.1, 20.0, 0.1],
		["capacity", 10.0, 1000.0, 10.0],
		["hose_range", 1.0, 15.0, 0.5],
		["transfer_rate", 1.0, 200.0, 1.0],
		["max_health", 10.0, 1000.0, 10.0],
		["repair_rate", 1.0, 200.0, 1.0],
		["repair_range", 0.5, 10.0, 0.5],
	],
	"res://scenes/player/player_settings.tres":
	[
		["move_speed", 1.0, 20.0, 0.5],
		["max_health", 10.0, 500.0, 10.0],
	],
	"res://scenes/weapons/blaster_settings.tres":
	[
		["damage", 1.0, 100.0, 1.0],
		["attack_rate", 0.5, 20.0, 0.5],
		["projectile_speed", 5.0, 100.0, 1.0],
		["projectile_range", 5.0, 60.0, 1.0],
	],
	"res://scenes/aliens/alien_settings.tres":
	[
		["max_health", 1.0, 300.0, 1.0],
		["move_speed", 0.5, 15.0, 0.5],
		["detection_range", 1.0, 40.0, 1.0],
		["chase_range", 1.0, 60.0, 1.0],
		["attack_range", 0.5, 5.0, 0.1],
		["attack_damage", 0.0, 100.0, 1.0],
		["attack_rate", 0.1, 5.0, 0.1],
	],
	"res://scenes/aliens/alien_nest_settings.tres":
	[
		["guards", 0.0, 10.0, 1.0],
		["hunter_interval_start", 1.0, 300.0, 1.0],
		["hunter_interval_end", 1.0, 300.0, 1.0],
		["max_hunters_start", 0.0, 20.0, 1.0],
		["max_hunters_end", 0.0, 20.0, 1.0],
		["raider_interval_start", 1.0, 300.0, 1.0],
		["raider_interval_end", 1.0, 300.0, 1.0],
		["max_raiders_start", 0.0, 20.0, 1.0],
		["max_raiders_end", 0.0, 20.0, 1.0],
	],
}
const PANEL_WIDTH: float = 420.0

## Values from the files, for `reset_tuning`, keyed by "path:property".
var _defaults: Dictionary[String, float] = {}
var _sliders: Dictionary[String, HSlider] = {}
var _live: Label
var _time_buttons: Array[Button] = []


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
		lines.append("Time left: %.1f s" % mission.time_left)
		if mission.state == Mission.State.STORM:
			lines.append("Storm: %.1f HP/s" % mission.storm_damage_per_second())
		lines.append("Escalation: %d%%" % roundi(mission.progress() * 100.0))
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


func toggle() -> void:
	visible = not visible


## Jumps to the start of the warning time (only while the timer runs).
func skip_to_warning() -> void:
	var mission: Mission = _mission()
	if mission and mission.state == Mission.State.RUNNING:
		mission.time_left = minf(mission.time_left, mission.settings.warning_time)


## Lets the storm hit right away (only while the timer runs).
func start_storm() -> void:
	var mission: Mission = _mission()
	if mission and mission.state == Mission.State.RUNNING:
		mission.time_left = 0.0


func kill_players() -> void:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		player.take_damage(player.health)


func kill_aliens() -> void:
	for alien: Alien in get_tree().get_nodes_in_group(Alien.GROUP):
		alien.take_damage(alien.health)


## Lets every nest hatch a hunter right away.
func hatch_hunters() -> void:
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.hatch(Alien.Role.HUNTER)


## Lets every nest hatch a raider right away.
func hatch_raiders() -> void:
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.hatch(Alien.Role.RAIDER)


func break_miners() -> void:
	for miner: Miner in get_tree().get_nodes_in_group(Miner.GROUP):
		miner.take_damage(miner.health)


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
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.85)
	style.set_content_margin_all(10.0)
	panel.add_theme_stylebox_override(&"panel", style)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	box.add_child(_heading("Debug (F3)"))
	_live = Label.new()
	box.add_child(_live)

	var actions := HFlowContainer.new()
	box.add_child(actions)
	_time_buttons.append(_button(actions, "Skip to warning", skip_to_warning))
	_time_buttons.append(_button(actions, "Storm now", start_storm))
	_button(actions, "Kill players", kill_players)
	_button(actions, "Heal players", heal_players)
	_button(actions, "Kill aliens", kill_aliens)
	_button(actions, "Hatch hunters", hatch_hunters)
	_button(actions, "Hatch raiders", hatch_raiders)
	_button(actions, "Break miners", break_miners)
	_button(actions, "Reset tuning", reset_tuning)

	for path: String in TUNING:
		var resource: Resource = load(path)
		box.add_child(_heading(path.get_file().get_basename().capitalize()))
		for row: Array in TUNING[path]:
			_add_slider(box, resource, path, row)


func _add_slider(box: VBoxContainer, resource: Resource, path: String, row: Array) -> void:
	var property: String = row[0]
	var key: String = "%s:%s" % [path, property]
	var line := HBoxContainer.new()
	box.add_child(line)
	var name_label := Label.new()
	name_label.text = property.capitalize()
	name_label.custom_minimum_size.x = 170.0
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
			resource.set(property, roundi(new_value) if whole else new_value)
			value_label.text = _format(new_value, slider.step)
	)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 18)
	return label


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


static func _has_role(alien: Alien, role: Alien.Role) -> bool:
	return alien.role == role


static func _format(value: float, step: float) -> String:
	return "%.1f" % value if step < 1.0 else "%d" % roundi(value)
