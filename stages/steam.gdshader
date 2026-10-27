// Steam puff for GPUParticles3D (stages/steam.tscn): camera-facing billboard, a lumpy
// disc whose alpha is cut into a few hard steps so it reads as pixel art. Particle
// COLOR (color ramp) tints and fades it. Drawn after the outline pass (higher
// render_priority than Camera3D/Outline), which would otherwise paint over it, so
// steam itself gets no outline.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 tint : source_color = vec4(0.78, 0.8, 0.86, 1.0);
// Peak opacity of a puff's core.
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
// Number of alpha levels from edge to core.
uniform int alpha_steps : hint_range(1, 6) = 3;

varying float seed;

void vertex() {
	// Billboard keeping the particle's scale (as BaseMaterial3D's particle billboard).
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]),
			normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	world = world * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	seed = float(INSTANCE_ID) * 1.7;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	// Lumpy outline, different per particle.
	float edge = 0.78 + 0.12 * sin(a * 3.0 + seed) + 0.08 * sin(a * 5.0 - seed * 1.3);
	float core = clamp((1.0 - length(p) / edge) * 2.0, 0.0, 1.0);
	float steps = float(alpha_steps);
	ALBEDO = tint.rgb * COLOR.rgb;
	ALPHA = ceil(core * steps) / steps * opacity * COLOR.a;
}
