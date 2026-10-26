// Flat toon shading: lambert diffuse quantized into a few hard bands, no specular.
// Ambient comes from the scene's WorldEnvironment and fills the darkest band.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest, hint_default_white;
// Number of lit levels including fully dark (2 = lit/unlit, 3 = lit/half/unlit).
uniform int bands : hint_range(2, 4) = 3;

void fragment() {
	ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float steps = float(bands - 1);
	float banded = floor(ndl * steps + 0.5) / steps;
	// LIGHT_COLOR is pre-multiplied by PI for physically based models.
	DIFFUSE_LIGHT += banded * LIGHT_COLOR / PI;
}
