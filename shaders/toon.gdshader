// Flat toon shading: lambert diffuse quantized into a few hard bands, no specular.
// Ambient comes from the scene's WorldEnvironment and fills the darkest band.
// While `backdrop_dim` (0-1, set by FollowCamera during the sweep's camera spin)
// is up, everything but the fighters (`spotlit`) is darkened and desaturated and
// the fighters glow a little, so they stay easy to follow.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
// Repeats so stage textures can tile (world-projected UVs); character UVs stay in 0-1.
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable, hint_default_white;
// Unlit glow added on top (neon, lit windows, lamps); black = none.
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Number of lit levels including fully dark (2 = lit/unlit, 3 = lit/half/unlit).
uniform int bands : hint_range(2, 4) = 3;
// Fighters' materials (set by CharacterLoader.load_character): kept bright while
// the backdrop dims.
uniform bool spotlit = false;

global uniform float backdrop_dim;

// Backdrop color at full dim: this much of its brightness and saturation.
const float DIM_BRIGHTNESS = 0.35;
const float DIM_SATURATION = 0.4;
// Fighters' added glow at full dim, as a fraction of their color.
const float SPOTLIT_GLOW = 0.3;

vec3 dimmed(vec3 color) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	vec3 dull = mix(vec3(luma), color, DIM_SATURATION) * DIM_BRIGHTNESS;
	return mix(color, dull, backdrop_dim);
}

void fragment() {
	vec3 color = albedo.rgb * texture(albedo_texture, UV).rgb;
	if (spotlit) {
		ALBEDO = color;
		EMISSION = emission.rgb + color * SPOTLIT_GLOW * backdrop_dim;
	} else {
		ALBEDO = dimmed(color);
		EMISSION = dimmed(emission.rgb);
	}
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float steps = float(bands - 1);
	float banded = floor(ndl * steps + 0.5) / steps;
	// LIGHT_COLOR is pre-multiplied by PI for physically based models.
	DIFFUSE_LIGHT += banded * LIGHT_COLOR / PI;
}
