// Body of the ore shaders (ore_crystal.gdshader, ore_fill.gdshader): the ore's color, glowing in
// its pattern (see ore_glow.gdshaderinc). With ORE_CRYSTAL defined, the patterns also play over the
// crystal's facets (twinkling facets, a view-dependent hue). Each instance gets its own `phase` so
// neighboring deposits don't pulse in sync (`OreGlow.set_phase`); without one, it's taken from the
// node's position. Materials stay shared per ore type.

#include "res://assets/shaders/ore_glow.gdshaderinc"

// The ore's color (OreType.color).
uniform vec4 color : source_color = vec4(1.0);
// Its glow pattern (OreType.Glow).
uniform int glow = 0;
// A near-black body with glowing veins in its color (OreType.dark_body).
uniform bool dark_body = false;
// Emission energy at the pattern's full brightness.
uniform float energy = 2.5;
// Veins (cells) per meter of a dark body.
uniform float vein_density = 4.0;
// Seconds this instance runs ahead of the others; negative: taken from the node's position.
instance uniform float phase = -1.0;

varying vec3 v_object;
varying vec3 v_object_normal;
varying flat float v_phase;

void vertex() {
	v_object = VERTEX;
	v_object_normal = NORMAL;
	v_phase = phase >= 0.0 ? phase : ore_hash31(floor(NODE_POSITION_WORLD * 2.0)) * 10.0;
}

void fragment() {
	float t = TIME + v_phase;
	float level = ore_intensity(glow, t, v_object.y);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 tint = color.rgb;
	if (glow == GLOW_SHIFTING) {
		float angle = ore_hue_angle(t);
#ifdef ORE_CRYSTAL
		// Iridescent: the hue also turns over the facets as they face away.
		angle += (1.0 - facing) * 2.0;
#endif
		tint = max(ore_hue_rotate(tint, angle), vec3(0.0));
	} else if (glow == GLOW_BREATHING) {
		// A brighter core (the parts facing the camera), more so while breathing in.
		float core = mix(0.6, 1.3, facing * facing);
		level *= mix(1.0, core, 0.4 + 0.6 * ore_breath(t));
	}
#ifdef ORE_CRYSTAL
	if (glow == GLOW_SPARKLE) {
		// Flat-shaded facets: each normal is one facet.
		float facet = ore_hash31(floor(v_object_normal * 24.0 + 0.5) + 41.0) * 977.0;
		float twinkle = ore_twinkle(t, facet);
		level *= 1.0 + 1.8 * twinkle;
		tint = mix(tint, vec3(1.0), 0.35 * twinkle);
	}
#endif
	if (dark_body) {
		float edge = ore_cell_edge(v_object * vein_density);
		float aa = fwidth(edge);
		float width = max(0.045, aa * 1.2);
		float vein = 1.0 - smoothstep(width, width + aa * 1.5, edge);
		ALBEDO = vec3(0.012);
		ROUGHNESS = 0.12;
		SPECULAR = 0.6;
#ifdef ORE_CRYSTAL
		float rim = 0.3 * pow(1.0 - facing, 3.0);
		EMISSION = tint * energy * level * (1.4 * vein + rim);
#else
		EMISSION = tint * energy * level * (0.35 + 0.65 * vein);
#endif
	} else {
		ALBEDO = tint;
		ROUGHNESS = 0.2;
		EMISSION = tint * energy * level;
	}
}
