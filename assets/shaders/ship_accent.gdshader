// The ship's accent lights (lamp strips in a room's color): emissive in `accent`, set per room by ShipShell from
// the room's RoomLook.
shader_type spatial;
render_mode unshaded;

uniform float energy = 3.0;
instance uniform vec4 accent : source_color = vec4(1.0, 0.85, 0.6, 1.0);

void fragment() {
	ALBEDO = accent.rgb * energy;
}
