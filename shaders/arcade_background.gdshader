shader_type canvas_item;
// Start menu backdrop, drawn in chunky pixels at `resolution` (the game's
// 480×270): a night-sky gradient with twinkling stars above `horizon`, and
// below it a dark floor with a neon perspective grid scrolling toward the
// viewer. Grid lines are found by comparing a pixel's grid cell with its
// neighbor's, so they stay exactly one pixel wide at any depth.

uniform vec2 resolution = vec2(480.0, 270.0);
// Height of the horizon, as a fraction of the screen from the top.
uniform float horizon = 0.62;
uniform vec4 sky_top : source_color = vec4(0.02, 0.01, 0.07, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.30, 0.04, 0.32, 1.0);
uniform vec4 floor_color : source_color = vec4(0.03, 0.0, 0.07, 1.0);
uniform vec4 grid_color : source_color = vec4(0.1, 0.85, 1.0, 1.0);
// Grid rows passing the viewer per second.
uniform float scroll_speed = 0.8;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Grid coordinates (across, depth) of the floor point at screen `uv`.
vec2 grid_at(vec2 uv) {
	float depth = 0.12 / max(uv.y - horizon, 1e-4);
	return vec2((uv.x - 0.5) * depth * 10.0, depth * 3.0 + TIME * scroll_speed);
}

void fragment() {
	vec2 px = floor(UV * resolution);
	vec2 uv = (px + 0.5) / resolution;
	vec3 col;
	if (uv.y < horizon) {
		float t = uv.y / horizon;
		col = mix(sky_top.rgb, sky_bottom.rgb, t * t);
		float h = hash(px);
		if (h > 0.996) {
			float rate = 1.0 + 4.0 * hash(px + 17.0);
			float twinkle = 0.55 + 0.45 * sin(TIME * rate + h * 600.0);
			col += vec3(twinkle * (1.0 - 0.7 * t));
		}
	} else {
		float d = uv.y - horizon;
		vec2 g = grid_at(uv);
		vec2 g_up = grid_at(uv - vec2(0.0, 1.0 / resolution.y));
		vec2 g_left = grid_at(uv - vec2(1.0 / resolution.x, 0.0));
		bool line = floor(g.y) != floor(g_up.y) || floor(g.x) != floor(g_left.x);
		// Lines fade into the horizon, where they would turn to noise.
		float strength = smoothstep(0.0, 0.25, d);
		col = floor_color.rgb;
		if (line) {
			col = mix(col, grid_color.rgb, strength);
		}
		// Glow along the horizon.
		col += sky_bottom.rgb * exp(-d * 40.0);
	}
	COLOR = vec4(col, 1.0);
}
