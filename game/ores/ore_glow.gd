class_name OreGlow
## The ores' glowing materials (see `OreType.get_material`, `ItemType.get_glow_material`): shaders
## that glow in the ore's color and its glow pattern (`ItemType.Glow`). The rhythms are in
## `assets/shaders/ore_glow.gdshaderinc`; `intensity` is the same in GDScript (change both
## together). Nothing flashes faster than 3 times a second (photosensitivity). Rates and depths
## are TBD (playtest).

const CRYSTAL_SHADER: Shader = preload("res://assets/shaders/ore_crystal.gdshader")
const FILL_SHADER: Shader = preload("res://assets/shaders/ore_fill.gdshader")
## Emission energy at a pattern's full brightness (intensity 1).
const ENERGY: float = 2.5
## Veins per meter of a dark body: in its crystals, and in what's filled with it.
const CRYSTAL_VEIN_DENSITY: float = 4.0
const FILL_VEIN_DENSITY: float = 5.0
## Phases spread over this many seconds.
const PHASE_SPREAD: float = 10.0
## Bright bands of a wave passing a point per second (see the shader).
const WAVE_RATE: float = 0.6


## Material of `ore_type`'s crystals.
static func crystal_material(ore_type: OreType) -> Material:
	return _material(CRYSTAL_SHADER, ore_type, CRYSTAL_VEIN_DENSITY)


## Material for what's filled with `item` (an ore's miner column, hose, canisters).
static func fill_material(item: ItemType) -> Material:
	return _material(FILL_SHADER, item, FILL_VEIN_DENSITY)


## Brightness of `glow` at `time` seconds, `phase` seconds ahead, 1.0 being the ore's full glow
## (at the bottom of a wave; the crystals add patterns over their facets).
static func intensity(glow: ItemType.Glow, time: float, phase: float = 0.0) -> float:
	var t: float = time + phase
	match glow:
		ItemType.Glow.SLOW_PULSE:
			return 0.775 + 0.225 * sin(TAU * 0.4 * t)
		ItemType.Glow.FAST_PULSE:
			return 0.88 + 0.12 * sin(TAU * 2.5 * t)
		ItemType.Glow.FLICKER:
			var flicker: float = _value_noise(t * 3.5)
			var dip: float = smoothstep(0.65, 0.9, _value_noise(t * 0.6 + 31.7))
			return (0.8 + 0.25 * flicker) * (1.0 - 0.4 * dip)
		ItemType.Glow.WAVE:
			var wave: float = 0.5 + 0.5 * sin(TAU * WAVE_RATE * t)
			return 0.6 + 0.55 * wave * wave * wave
		ItemType.Glow.SPARKLE:
			return 0.85 + 0.08 * sin(TAU * 1.3 * t) + 0.07 * sin(TAU * 1.9 * t + 1.0)
		ItemType.Glow.BREATHING:
			return 0.5 + 0.55 * (0.5 - 0.5 * cos(TAU * 0.25 * t))
		ItemType.Glow.HEARTBEAT:
			var x: float = fposmod(t * 1.1, 1.0) / 1.1
			var lub: float = (x - 0.15) / 0.06
			var dub: float = (x - 0.38) / 0.07
			return 0.55 + 0.5 * (exp(-lub * lub) + 0.65 * exp(-dub * dub))
	return 1.0


## A phase (seconds) for an ore glowing at `world_position`, so neighboring deposits don't pulse in
## sync; a deposit and the miner on it get the same one.
static func phase_at(world_position: Vector3) -> float:
	var cell := Vector2i(floori(world_position.x * 2.0), floori(world_position.z * 2.0))
	return float(posmod(hash(cell), 10007)) / 10007.0 * PHASE_SPREAD


## Gives `geometry` (drawn in an ore material) its own `phase`, see `phase_at`.
static func set_phase(geometry: GeometryInstance3D, phase: float) -> void:
	geometry.set_instance_shader_parameter(&"phase", phase)


static func _material(shader: Shader, item: ItemType, vein_density: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"color", item.color)
	material.set_shader_parameter(&"glow", int(item.glow))
	material.set_shader_parameter(&"dark_body", item.dark_body)
	material.set_shader_parameter(&"energy", ENERGY)
	material.set_shader_parameter(&"vein_density", vein_density)
	return material


## Smooth value noise, 0..1, changing direction at most once per unit (as in the shader).
static func _value_noise(x: float) -> float:
	var i: float = floorf(x)
	var f: float = x - i
	var u: float = f * f * (3.0 - 2.0 * f)
	return lerpf(_hash(i), _hash(i + 1.0), u)


static func _hash(p: float) -> float:
	var q: float = fposmod(p * 0.1031, 1.0)
	q *= q + 33.33
	q *= q + q
	return fposmod(q, 1.0)
