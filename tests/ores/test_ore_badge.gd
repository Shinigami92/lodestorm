extends GutTest
## Ore badges on holo cards: the ore's icon tinted and glowing like the ore, and its name.

const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const NOCTILE: OreType = preload("res://game/ores/types/ore_noctile.tres")


func after_each() -> void:
	TranslationServer.set_locale("en")


func test_badge_is_tinted_and_glows_like_its_ore() -> void:
	for ore_type: OreType in OreCatalog.all().ores:
		var badge: OreBadge = autofree(OreBadge.new(ore_type))
		var material: ShaderMaterial = badge.get_icon_material()
		assert_eq(material.shader, OreBadge.SHADER)
		var color: Color = material.get_shader_parameter(&"color")
		var glow: int = material.get_shader_parameter(&"glow")
		var dark_body: bool = material.get_shader_parameter(&"dark_body")
		assert_eq(color, ore_type.color, ore_type.display_name)
		assert_eq(glow, int(ore_type.glow), ore_type.display_name)
		assert_eq(dark_body, ore_type.dark_body, ore_type.display_name)


func test_badge_shows_the_icon_and_name() -> void:
	var badge: OreBadge = add_child_autofree(OreBadge.new(KYRITE))
	assert_eq(badge.get_icon_texture(), KYRITE.icon)
	assert_eq(badge.get_shown_name(), KYRITE.get_display_name())
	badge.show_name = false
	assert_eq(badge.get_shown_name(), "")
	badge.ore_type = NOCTILE
	var dark_body: bool = badge.get_icon_material().get_shader_parameter(&"dark_body")
	assert_true(dark_body)


func test_name_follows_the_language() -> void:
	var badge: OreBadge = add_child_autofree(OreBadge.new(KYRITE))
	TranslationServer.set_locale("de")
	await wait_process_frames(1)
	assert_eq(badge.get_shown_name(), KYRITE.get_display_name())


func test_ore_without_icon_gets_a_drawn_crystal() -> void:
	var ore_type := OreType.new()
	ore_type.display_name = "Testite"
	ore_type.color = Color(1.0, 0.5, 0.2)
	var badge: OreBadge = autofree(OreBadge.new(ore_type))
	var texture: Texture2D = badge.get_icon_texture()
	assert_not_null(texture)
	assert_eq(texture, OreBadge.fallback_icon())
	assert_eq(badge.get_shown_name(), "Testite")
	var image: Image = texture.get_image()
	var center: Color = image.get_pixel(OreBadge.FALLBACK_SIZE / 2, OreBadge.FALLBACK_SIZE / 2)
	assert_eq(center.a, 1.0, "solid inside")
	assert_eq(image.get_pixel(0, 0).a, 0.0, "transparent around it")
	# Facets in different greys, which the shader tints.
	var shades: Array[float] = []
	for y: int in OreBadge.FALLBACK_SIZE:
		for x: int in OreBadge.FALLBACK_SIZE:
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a == 1.0 and pixel.r not in shades:
				shades.append(pixel.r)
	assert_gte(shades.size(), 4)
	assert_true(image.has_mipmaps())
