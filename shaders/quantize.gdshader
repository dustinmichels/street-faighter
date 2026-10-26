// Final-image color quantization: snaps each channel to a fixed number of levels
// for a limited-palette pixel-art look. Applied to the GameView SubViewportContainer.
shader_type canvas_item;

// Levels per RGB channel (e.g. 6 -> 216-color palette). 256 effectively disables it.
uniform float levels : hint_range(2.0, 256.0, 1.0) = 6.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float steps = levels - 1.0;
	COLOR = vec4(floor(c.rgb * steps + 0.5) / steps, c.a);
}
