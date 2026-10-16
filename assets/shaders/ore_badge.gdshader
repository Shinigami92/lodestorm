// An ore's badge on holo cards (OreBadge): its icon (a white crystal silhouette with grey facets)
// tinted in its color and glowing in its pattern (see ore_glow.gdshaderinc). A dark-bodied ore is
// a dark icon with a rim and facet edges in its color.
shader_type canvas_item;

#include "res://assets/shaders/ore_glow.gdshaderinc"

// The ore's color (OreType.color).
uniform vec4 color : source_color = vec4(1.0);
// Its glow pattern (OreType.Glow).
uniform int glow = 0;
// A near-black body with glowing veins in its color (OreType.dark_body).
uniform bool dark_body = false;
// Seconds this badge runs ahead.
uniform float phase = 0.0;
// Width of a dark body's rim, in UV.
uniform float rim_width = 0.06;

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 icon = texture(TEXTURE, UV);
	float shade = icon.r;
	float t = TIME + phase;
	// Waves rise from the bottom of the icon, about two bands over its height.
	float level = ore_intensity(glow, t, (1.0 - UV.y) * 2.0 * WAVE_LENGTH);
	vec3 tint = color.rgb;
	if (glow == GLOW_SHIFTING) {
		tint = max(ore_hue_rotate(tint, ore_hue_angle(t) + UV.x * 1.5), vec3(0.0));
	} else if (glow == GLOW_BREATHING) {
		float core = mix(1.25, 0.6, clamp(distance(UV, vec2(0.5)) * 2.2, 0.0, 1.0));
		level *= mix(1.0, core, 0.4 + 0.6 * ore_breath(t));
	} else if (glow == GLOW_SPARKLE) {
		// Each grey level of the icon is one facet.
		float twinkle = ore_twinkle(t, floor(shade * 24.0 + 0.5) * 7.0 + 3.0);
		level *= 1.0 + 1.2 * twinkle;
		tint = mix(tint, vec3(1.0), 0.4 * twinkle);
	}
	vec3 rgb;
	if (dark_body) {
		float inside = 1.0;
		for (int i = 0; i < 8; i++) {
			float angle = TAU * float(i) / 8.0;
			inside = min(inside, texture(TEXTURE, UV + vec2(cos(angle), sin(angle)) * rim_width).a);
		}
		float rim = 1.0 - inside;
		float edges = clamp(fwidth(shade) * 4.0, 0.0, 1.0);
		rgb = vec3(0.05) * shade + tint * clamp(level, 0.0, 1.5) * max(rim, edges);
	} else {
		rgb = tint * shade * (0.3 + 0.7 * level);
	}
	COLOR = vec4(rgb, icon.a) * v_modulate;
}
