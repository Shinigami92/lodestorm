class_name SkillStation
extends Station
## The skill graph in the skills room (see GAME_DESIGN.md, Upgrade stations): a hologram above an
## emitter that always faces the camera, styled like the star map. Each cluster of the `tree` is a
## constellation with its name, its skills are glowing points (`StationPart`s whose item is the
## `Skill`), linked to the skill they require; a link lights up once its skill is learned. Learned
## skills glow fully, ones the player can learn right now pulse, ones that open later stay dim.
## Its card (`SkillCard`) learns the selected skill's next rank for the player using it, with ore
## from the ship's hold; nothing can be learned while a mission is underway.
## The mouse pans (dragging) and zooms (wheel, around the cursor); `zoom_in`/`zoom_out` (triggers,
## +/-) zoom too. Directions select the nearest skill (the view follows it), `tab_prev`/`tab_next`
## jump between clusters. The camera frames `Graph/Focus` (moved by panning) at `view_height`
## (smaller when zoomed in); the card scales with it, so it keeps its size on screen.

## How far it zooms in (the share of the whole graph's view height).
const MIN_ZOOM: float = 0.45
## Zoom per wheel step, and per second while a zoom key or trigger is held.
const WHEEL_STEP: float = 0.85
const HOLD_SPEED: float = 1.2
## How far the mouse moves (px) before a press drags the view.
const DRAG_THRESHOLD: float = 6.0
## How close (m) to the view's edge a selected skill may be before the view follows it.
const FOLLOW_MARGIN: float = 0.35
## Size of a skill's point and of the links between them, in m.
const NODE_SIZE: float = 0.12
const LINK_WIDTH: float = 0.014
## Hologram energy of skills and links: learned, can be learned now (pulsing between the two), open
## but too expensive, and not open yet.
const ENERGY_LEARNED: float = 1.0
const ENERGY_PULSE_LOW: float = 0.35
const ENERGY_OPEN: float = 0.4
const ENERGY_CLOSED: float = 0.15
const ENERGY_LINK_LIT: float = 0.8
const ENERGY_LINK_DARK: float = 0.18
## Pulses per second of the skills that can be learned now.
const PULSE_RATE: float = 1.2
## Where the card may sit beside the selected skill, shifted up or down (in half card heights),
## in the order they're tried.
const CARD_SHIFTS: Array[float] = [0.0, -1.0, 1.0]
## How much further sideways it may go (in card widths), in the order they're tried.
const CARD_PUSHES: Array[float] = [0.0, 0.5, 1.0]
## Where a cluster's name sits, from its center (m, towards the middle: below the upper clusters,
## above the lower ones).
const LABEL_OFFSET: float = 0.32
## How far the backdrop reaches beyond the skills (m), its color and its frame's width (m).
const BACKDROP_MARGIN := Vector2(0.5, 0.45)
const BACKDROP_COLOR := Color(0.015, 0.035, 0.05, 0.95)
const FRAME_WIDTH: float = 0.012
const FRAME_COLOR := Color(0.3, 0.85, 1.0)
## The backdrop draws after the room's see-through things, the skills, links, names and frame
## after the backdrop. While used, the backdrop also skips the depth test (like the card), so the
## floor markings below the tilted graph don't show in front of it.
const BACKDROP_PRIORITY: int = 1
const HOLOGRAM_PRIORITY: int = 2

## Every skill of the game.
@export var tree: SkillTree

## The mission that locks it while underway; found in the scene tree when not set.
var mission: Mission
## The ship whose hold pays; the one it stands in when not set.
var ship: Ship
## How far it's zoomed (1: the whole graph, down to `MIN_ZOOM`).
var zoom: float = 1.0
## The point of the graph the view centers on, in m (x right, y up).
var pan: Vector2 = Vector2.ZERO

var _parts: Dictionary[Skill, StationPart] = {}
var _materials: Dictionary[Skill, ShaderMaterial] = {}
var _pips: Dictionary[Skill, MkPips] = {}
## The link of each skill that requires another, from that one to it.
var _links: Dictionary[Skill, ShaderMaterial] = {}
var _time: float = 0.0
## `view_height` at zoom 1.
var _full_view_height: float
## Where a mouse press started (px) and whether it drags the view; INF: no press.
var _press_from: Vector2 = Vector2.INF
var _dragging: bool = false
var _backdrop_material := StandardMaterial3D.new()

@onready var _graph: Node3D = $Graph
@onready var _focus: Node3D = $Graph/Focus


func _ready() -> void:
	super()
	_full_view_height = view_height
	_build()


func _process(delta: float) -> void:
	_time += delta
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	if not ship:
		ship = Ship.nearest(get_tree(), global_position)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		# Faces the camera like the cards, so the graph reads from the isometric view.
		_graph.global_basis = camera.global_basis.orthonormalized()
	if user:
		var held: float = (
			Input.get_action_strength(&"zoom_in") - Input.get_action_strength(&"zoom_out")
		)
		if absf(held) > 0.01:
			# Around the selected skill, so it stays in view.
			var around: Vector2 = _graph_position(selected.item as Skill) if selected else pan
			set_zoom(zoom * exp(-held * HOLD_SPEED * delta), around)
	_show_states()
	super(delta)
	# The hold or the mission may change meanwhile.
	if user:
		refresh()


func get_parts() -> Array[StationPart]:
	var parts: Array[StationPart] = []
	parts.assign(_parts.values())
	return parts


## The point showing `skill`, or null.
func get_part(skill: Skill) -> StationPart:
	return _parts.get(skill, null)


## Whether nothing can be learned right now.
func is_locked() -> bool:
	return mission != null and mission.is_underway()


## Whether the player using it can learn the next rank of `skill` right now.
func can_learn(skill: Skill) -> bool:
	if is_locked() or not user or not ship or not skill:
		return false
	if not user.skills.is_open(skill):
		return false
	var next: SkillRank = user.skills.next_rank(skill)
	return next != null and ship.can_pay(next.cost)


## Learns the next rank of `skill` for the player using it, paid from the hold. Returns whether it
## did.
func learn(skill: Skill) -> bool:
	if not can_learn(skill):
		return false
	if not ship.pay(user.skills.next_rank(skill).cost):
		return false
	user.skills.raise(skill)
	refresh()
	return true


## Zooms to `value` (clamped), keeping the graph point `around` where it is on screen.
func set_zoom(value: float, around: Vector2 = Vector2.INF) -> void:
	var before: float = zoom
	zoom = clampf(value, MIN_ZOOM, 1.0)
	if around != Vector2.INF and before > 0.0:
		set_pan(around + (pan - around) * zoom / before)
	view_height = _full_view_height * zoom


## Centers the view on `value` (graph m), kept within the graph.
func set_pan(value: Vector2) -> void:
	var bounds: Rect2 = graph_bounds()
	pan = value.clamp(bounds.position, bounds.end)
	_focus.position = Vector3(pan.x, pan.y, 0.0)


## The area the skills cover on the graph, in m.
func graph_bounds() -> Rect2:
	var bounds := Rect2()
	var first: bool = true
	for skill: Skill in _parts:
		var point: Vector2 = _graph_position(skill)
		if first:
			bounds = Rect2(point, Vector2.ZERO)
			first = false
		else:
			bounds = bounds.expand(point)
	return bounds


## The cluster of the selected skill, or null.
func selected_cluster() -> SkillCluster:
	return tree.cluster_of(selected.item as Skill) if selected and tree else null


func select(part: StationPart) -> void:
	super(part)
	if part and user:
		_follow(part)


func _opened() -> void:
	_press_from = Vector2.INF
	_dragging = false
	_backdrop_material.no_depth_test = true
	super()


func _closed() -> void:
	super()
	_backdrop_material.no_depth_test = false
	set_zoom(1.0)
	set_pan(Vector2.ZERO)


## Jumps to the previous (-1) or next (1) cluster's first skill and centers on the cluster.
func _cycle(step: int) -> void:
	if not tree or tree.clusters.is_empty():
		return
	var index: int = tree.clusters.find(selected_cluster())
	var cluster: SkillCluster = tree.clusters[posmod(index + step, tree.clusters.size())]
	if cluster.skills.is_empty():
		return
	select(get_part(cluster.skills[0]))
	set_pan(cluster.center)


func _shortcut(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button:
		return _mouse_button(button)
	var motion := event as InputEventMouseMotion
	if motion and _press_from != Vector2.INF:
		if not _dragging and motion.position.distance_to(_press_from) > DRAG_THRESHOLD:
			_dragging = true
			if hovered:
				_hover(null)
		if _dragging:
			var from: Vector2 = _graph_point(motion.position - motion.relative)
			var to: Vector2 = _graph_point(motion.position)
			if from != Vector2.INF and to != Vector2.INF:
				set_pan(pan - (to - from))
			return true
	return false


func _mouse_button(event: InputEventMouseButton) -> bool:
	if event.pressed and event.is_action_pressed(&"zoom_in"):
		set_zoom(zoom * WHEEL_STEP, _graph_point(event.position))
		return true
	if event.pressed and event.is_action_pressed(&"zoom_out"):
		set_zoom(zoom / WHEEL_STEP, _graph_point(event.position))
		return true
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		return false
	if event.pressed:
		# A press on the card is for its buttons; anywhere else it may start dragging.
		var camera: Camera3D = get_viewport().get_camera_3d()
		var on_card: bool = (
			camera != null
			and (
				card.pixel_at(
					camera.project_ray_origin(event.position),
					camera.project_ray_normal(event.position)
				)
				!= Vector2.INF
			)
		)
		_press_from = Vector2.INF if on_card else event.position
		_dragging = false
		return false
	var dragged: bool = _dragging
	_press_from = Vector2.INF
	_dragging = false
	# The release of a drag doesn't click.
	return dragged


func _card_position(_camera: Camera3D) -> Vector3:
	var spot: Vector2 = card_spot(selected)
	return _graph.to_global(Vector3(spot.x, spot.y, 0.0))


## Where the card's center goes on the graph (m) while `part` is selected: beside it, where it
## covers no other skill (so the mouse can still point at them) and stays in view. Tries towards
## the middle of the graph first (room between the clusters), then outwards; level with the skill,
## then shifted down or up by half the card, then pushed further sideways past a neighbor.
func card_spot(part: StationPart) -> Vector2:
	var point := Vector2(part.position.x, part.position.y)
	var card_size: Vector2 = card.size * _card_scale()
	var view: Rect2 = view_rect()
	var inwards: float = -1.0 if point.x > 0.0 else 1.0
	var best: Vector2 = point
	var best_score: int = -1
	var order: int = 0
	for side: float in [inwards, -inwards]:
		for push: float in CARD_PUSHES:
			for shift: float in CARD_SHIFTS:
				var center := Vector2(
					point.x + side * (card_size.x * (0.5 + push) + NODE_SIZE * 2.0),
					point.y + shift * card_size.y * 0.5
				)
				var rect := Rect2(center - card_size * 0.5, card_size)
				var score: int = _covered(rect, part) * 1000 + order
				if not view.encloses(rect):
					score += 100
				if best_score < 0 or score < best_score:
					best = center
					best_score = score
				order += 1
	return best


## What the camera sees of the graph right now (m), about: `view_height` high around `pan`, as
## wide as the window's aspect.
func view_rect() -> Rect2:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = size.x / size.y if size.y > 0.0 else 16.0 / 9.0
	var view := Vector2(view_height * aspect, view_height)
	return Rect2(pan - view * 0.5, view)


## How many skills other than `except` the card would cover at `rect` (graph m).
func _covered(rect: Rect2, except: StationPart) -> int:
	var grown: Rect2 = rect.grow(NODE_SIZE * 0.5)
	var count: int = 0
	for part: StationPart in _parts.values():
		if part != except and grown.has_point(Vector2(part.position.x, part.position.y)):
			count += 1
	return count


func _card_scale() -> float:
	return zoom


## Pans so `part` is in view (with a margin), as far as the graph allows.
func _follow(part: StationPart) -> void:
	var point: Vector2 = _graph_position(part.item as Skill)
	var half: Vector2 = view_rect().size * 0.5 - Vector2.ONE * FOLLOW_MARGIN * zoom
	var offset: Vector2 = point - pan
	set_pan(pan + offset - offset.clamp(-half, half))


## The graph point (m) under `screen_position`, or `Vector2.INF` when the ray misses its plane.
func _graph_point(screen_position: Vector2) -> Vector2:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera or screen_position == Vector2.INF:
		return Vector2.INF
	var plane := Plane(_graph.global_basis.z.normalized(), _graph.global_position)
	var hit: Variant = plane.intersects_ray(
		camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position)
	)
	if hit == null:
		return Vector2.INF
	var local: Vector3 = _graph.to_local(hit as Vector3)
	return Vector2(local.x, local.y)


func _graph_position(skill: Skill) -> Vector2:
	var cluster: SkillCluster = tree.cluster_of(skill)
	return (cluster.center if cluster else Vector2.ZERO) + skill.graph_position


## Builds the constellations: a point per skill, its rank pips, links and the cluster names.
func _build() -> void:
	if not tree:
		return
	for cluster: SkillCluster in tree.clusters:
		var label := Label3D.new()
		label.text = cluster.display_name
		label.uppercase = true
		label.font_size = 56
		label.outline_size = 0
		label.pixel_size = 0.0022
		label.modulate = Color(cluster.color, 0.85)
		label.shaded = false
		label.double_sided = false
		var inwards: float = -1.0 if cluster.center.y >= 0.0 else 1.0
		label.position = Vector3(cluster.center.x, cluster.center.y + inwards * LABEL_OFFSET, 0.0)
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.render_priority = HOLOGRAM_PRIORITY
		_graph.add_child(label)
		for skill: Skill in cluster.skills:
			_add_skill(skill, cluster)
	for skill: Skill in _parts:
		if skill.requires and _parts.has(skill.requires):
			_add_link(skill)
	_add_backdrop()


## A dark, see-through panel with a thin frame behind the skills, so the room doesn't show through.
func _add_backdrop() -> void:
	var bounds: Rect2 = graph_bounds().grow_individual(
		BACKDROP_MARGIN.x, BACKDROP_MARGIN.y, BACKDROP_MARGIN.x, BACKDROP_MARGIN.y
	)
	var center: Vector2 = bounds.get_center()
	var quad := QuadMesh.new()
	quad.size = bounds.size
	var material: StandardMaterial3D = _backdrop_material
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = BACKDROP_COLOR
	material.render_priority = BACKDROP_PRIORITY
	var backdrop := MeshInstance3D.new()
	backdrop.name = "Backdrop"
	backdrop.mesh = quad
	backdrop.material_override = material
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.position = Vector3(center.x, center.y, -NODE_SIZE)
	_graph.add_child(backdrop)
	var frame: ShaderMaterial = HoloTable.hologram_material(FRAME_COLOR)
	frame.set_shader_parameter(&"energy", ENERGY_LINK_LIT)
	frame.render_priority = HOLOGRAM_PRIORITY
	for side: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var box := BoxMesh.new()
		var across: bool = side.x != 0.0
		box.size = Vector3(
			FRAME_WIDTH if across else bounds.size.x + FRAME_WIDTH,
			bounds.size.y + FRAME_WIDTH if across else FRAME_WIDTH,
			FRAME_WIDTH
		)
		var edge := MeshInstance3D.new()
		edge.mesh = box
		edge.material_override = frame
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var reach: Vector2 = center + side * bounds.size * 0.5
		edge.position = Vector3(reach.x, reach.y, -NODE_SIZE)
		backdrop.add_sibling(edge)


func _add_skill(skill: Skill, cluster: SkillCluster) -> void:
	var part := StationPart.new()
	part.name = skill.resource_path.get_file().get_basename().to_pascal_case()
	part.item = skill
	part.pick_radius = NODE_SIZE * 1.4
	var point: Vector2 = _graph_position(skill)
	part.position = Vector3(point.x, point.y, 0.0)
	var sphere := SphereMesh.new()
	sphere.radius = NODE_SIZE * 0.5
	sphere.height = NODE_SIZE
	sphere.radial_segments = 24
	sphere.rings = 12
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: ShaderMaterial = HoloTable.hologram_material(cluster.color)
	material.render_priority = HOLOGRAM_PRIORITY
	mesh.material_override = material
	part.add_child(mesh)
	part.outline = mesh
	if skill.max_rank() > 1:
		var pips := MkPips.new()
		pips.pip_size = Vector3(0.035, 0.02, 0.01)
		pips.spacing = 0.05
		pips.lit_color = cluster.color
		pips.position = Vector3(0.0, -NODE_SIZE * 0.95, 0.0)
		part.add_child(pips)
		_pips[skill] = pips
	_graph.add_child(part)
	_parts[skill] = part
	_materials[skill] = material


## A thin hologram bar from the skill `skill` requires to it.
func _add_link(skill: Skill) -> void:
	var from: Vector3 = _parts[skill.requires].position
	var to: Vector3 = _parts[skill].position
	var box := BoxMesh.new()
	var length: float = from.distance_to(to) - NODE_SIZE
	box.size = Vector3(length, LINK_WIDTH, LINK_WIDTH)
	var link := MeshInstance3D.new()
	link.mesh = box
	link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cluster: SkillCluster = tree.cluster_of(skill)
	var material: ShaderMaterial = HoloTable.hologram_material(
		cluster.color if cluster else Color.WHITE
	)
	material.render_priority = HOLOGRAM_PRIORITY
	link.material_override = material
	var along: Vector3 = to - from
	link.position = (from + to) * 0.5
	link.rotation.z = atan2(along.y, along.x)
	_graph.add_child(link)
	_links[skill] = material


## Lights the skills and links for the player using it (or the first player while nobody does,
## so the room shows theirs).
func _show_states() -> void:
	var player: Player = user if user else Station.nth_player(get_tree(), 1)
	var skills: Skills = player.skills if player else null
	var pulse: float = lerpf(
		ENERGY_PULSE_LOW, ENERGY_LEARNED, 0.5 + 0.5 * cos(_time * TAU * PULSE_RATE)
	)
	for skill: Skill in _parts:
		var rank: int = skills.rank(skill) if skills else 0
		var energy: float = ENERGY_CLOSED
		if rank >= skill.max_rank():
			energy = ENERGY_LEARNED
		elif skills and skills.is_open(skill):
			var next: SkillRank = skills.next_rank(skill)
			var affordable: bool = ship != null and not is_locked() and ship.can_pay(next.cost)
			energy = pulse if affordable else maxf(ENERGY_OPEN, ENERGY_LEARNED * float(rank > 0))
		_materials[skill].set_shader_parameter(&"energy", energy)
		if (
			_pips.has(skill)
			and (_pips[skill].mk != rank or _pips[skill].max_mk != skill.max_rank())
		):
			_pips[skill].show_level(rank, skill.max_rank())
		if _links.has(skill):
			_links[skill].set_shader_parameter(
				&"energy", ENERGY_LINK_LIT if rank > 0 else ENERGY_LINK_DARK
			)
