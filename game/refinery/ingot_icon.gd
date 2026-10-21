class_name IngotIcon
## An alloy's badge icon (`AlloyType.get_badge_icon`), drawn in code like the ores' fallback
## crystal (`ItemBadge.fallback_icon`): an ingot seen from the front and a bit above, a white top
## and grey faces on transparent, with 1–4 ticks stamped into its front for the alloy's tier, so
## the badge shader tints it the same way and the shape alone tells an alloy from an ore.

## Edge length of the texture.
const SIZE: int = 96
## Grey of each face: lit from above, the stamped ticks darkest.
const TOP_SHADE: float = 1.0
const FRONT_SHADE: float = 0.72
const END_SHADE: float = 0.55
const TICK_SHADE: float = 0.4
## The ticks' width, gap and height, in the icon's units (-1.1..1.1 both ways).
const TICK_WIDTH: float = 0.11
const TICK_GAP: float = 0.13
const TICK_HEIGHT: float = 0.34


## The icon of a tier-`tier` alloy.
static func draw(tier: int) -> Texture2D:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			# 4x4 samples per pixel for smooth edges.
			var covered: int = 0
			var shade: float = 0.0
			for sample: int in 16:
				@warning_ignore("integer_division")
				var at := Vector2(x + (sample % 4 + 0.5) / 4.0, y + (sample / 4 + 0.5) / 4.0)
				var face: float = shade_at(at / SIZE * 2.2 - Vector2(1.1, 1.1), tier)
				if face > 0.0:
					covered += 1
					shade += face
			if covered > 0:
				shade /= covered
				image.set_pixel(x, y, Color(shade, shade, shade, covered / 16.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Grey of the ingot at `p` (-1.1..1.1 both ways, y down), 0 outside. The top face runs from the
## back edge (y -0.5, x +-0.62) to the front's top edge (y -0.12, x +-0.74); the front face from
## there down to its foot (y 0.55, x +-1.0), its slanted ends a bit darker.
static func shade_at(p: Vector2, tier: int) -> float:
	if p.y < -0.5 or p.y > 0.55:
		return 0.0
	if p.y < -0.12:
		var top_t: float = (p.y + 0.5) / 0.38
		return TOP_SHADE if absf(p.x) <= lerpf(0.62, 0.74, top_t) else 0.0
	var t: float = (p.y + 0.12) / 0.67
	var half: float = lerpf(0.74, 1.0, t)
	if absf(p.x) > half:
		return 0.0
	# The ends slant outwards: the strip beyond the top edge's width is an end face.
	if absf(p.x) > 0.74:
		return END_SHADE
	return TICK_SHADE if _on_tick(p, tier) else FRONT_SHADE


## Whether `p` is on one of the `tier` ticks, centered on the front face.
static func _on_tick(p: Vector2, tier: int) -> bool:
	var middle: float = 0.2
	if absf(p.y - middle) > TICK_HEIGHT * 0.5:
		return false
	var span: float = tier * TICK_WIDTH + (tier - 1) * TICK_GAP
	var x: float = p.x + span * 0.5
	if x < 0.0 or x > span:
		return false
	return fmod(x, TICK_WIDTH + TICK_GAP) <= TICK_WIDTH
