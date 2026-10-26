// Screen-space outline post-process for the pixel-art look.
// Used on a full-screen QuadMesh parented to the camera (see scenes/main.tscn).
// Silhouettes come from the depth Laplacian, which is ~0 on any plane (orthographic
// depth is linear), so floors don't produce false edges at grazing angles. The line
// is drawn on the nearer object's own border pixels, 1 px wide, like a sprite outline.
// Creases (e.g. box edges, overlapping limbs at equal depth) come from normal changes.
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, filter_nearest;

uniform vec4 outline_color : source_color = vec4(0.05, 0.04, 0.08, 1.0);
// Minimum depth step (meters) that counts as a silhouette.
uniform float depth_threshold = 0.15;
// Minimum normal change (1 - cos(angle)) that counts as a crease; > 2 disables creases.
uniform float normal_threshold = 0.6;

void vertex() {
	// Cover the whole screen regardless of camera transform.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_projection) {
	float d = texture(depth_texture, uv).r;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -view.z / view.w;
}

vec3 view_normal(vec2 uv) {
	return texture(normal_roughness_texture, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;

	float c = linear_depth(uv, INV_PROJECTION_MATRIX);
	float l = linear_depth(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float r = linear_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float u = linear_depth(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float d = linear_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);

	// Positive when this pixel sits in front of its neighbours.
	float lap = max(l + r - 2.0 * c, u + d - 2.0 * c);
	bool silhouette = lap > depth_threshold;

	vec3 n = view_normal(uv);
	float crease = max(
		max(1.0 - dot(n, view_normal(uv + vec2(px.x, 0.0))), 1.0 - dot(n, view_normal(uv - vec2(px.x, 0.0)))),
		max(1.0 - dot(n, view_normal(uv + vec2(0.0, px.y))), 1.0 - dot(n, view_normal(uv - vec2(0.0, px.y)))));
	bool is_crease = crease > normal_threshold;

	vec3 color = texture(screen_texture, uv).rgb;
	float edge = (silhouette || is_crease) ? outline_color.a : 0.0;
	ALBEDO = mix(color, outline_color.rgb, edge);
}
