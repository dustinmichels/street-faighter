shader_type canvas_item;
// CRT look for the start menu, drawn over everything: a dark gap between
// each of the `rows` pixel rows, and a vignette darkening the corners.
// Transparent elsewhere, so the menu shows through.

uniform float rows = 270.0;
uniform float line_darkness : hint_range(0.0, 1.0) = 0.35;
uniform float vignette : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	float in_row = fract(SCREEN_UV.y * rows);
	float line = in_row > 0.65 ? line_darkness : 0.0;
	vec2 centered = SCREEN_UV - 0.5;
	float corner = smoothstep(0.25, 0.75, length(centered)) * vignette;
	COLOR = vec4(0.0, 0.0, 0.0, 1.0 - (1.0 - line) * (1.0 - corner));
}
