// Flat toon shading: lambert diffuse quantized into a few hard bands, no specular.
// Ambient comes from the scene's WorldEnvironment and fills the darkest band.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
// Repeats so stage textures can tile (world-projected UVs); character UVs stay in 0-1.
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable, hint_default_white;
// Unlit glow added on top (neon, lit windows, lamps); black = none.
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Number of lit levels including fully dark (2 = lit/unlit, 3 = lit/half/unlit).
uniform int bands : hint_range(2, 4) = 3;
// Mirror-match tint (`CharacterLoader.set_tint()`): hue rotation in turns, 0 = off.
// Only saturated colors turn, so skin, greys, black and white keep their look.
uniform float tint_hue : hint_range(0.0, 1.0) = 0.0;

// Saturation (HSV) below which a color keeps its hue, and above which it turns fully.
const float TINT_SAT_FROM = 0.55;
const float TINT_SAT_TO = 0.75;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// `color` is linear; hue and saturation are judged on its (approximate) sRGB value,
// the colors the model was painted with.
vec3 apply_tint(vec3 color) {
	if (tint_hue == 0.0) {
		return color;
	}
	vec3 hsv = rgb_to_hsv(pow(color, vec3(1.0 / 2.2)));
	vec3 turned = pow(hsv_to_rgb(vec3(fract(hsv.x + tint_hue), hsv.yz)), vec3(2.2));
	return mix(color, turned, smoothstep(TINT_SAT_FROM, TINT_SAT_TO, hsv.y));
}

void fragment() {
	ALBEDO = apply_tint(albedo.rgb * texture(albedo_texture, UV).rgb);
	EMISSION = apply_tint(emission.rgb);
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float steps = float(bands - 1);
	float banded = floor(ndl * steps + 0.5) / steps;
	// LIGHT_COLOR is pre-multiplied by PI for physically based models.
	DIFFUSE_LIGHT += banded * LIGHT_COLOR / PI;
}
