shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform float visibility : hint_range(0.0, 1.0) = 0.0;
uniform vec4 history_color : source_color = vec4(0.24, 0.20, 0.27, 1.0);
uniform float phase_seed = 0.0;

varying vec3 local_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	local_position = VERTEX;
	float slab = floor(VERTEX.y * 2.4 + phase_seed * 7.0);
	float awake = smoothstep(0.18, 0.75, visibility);
	float offset = sin(slab * 4.17 + TIME * 0.72 + phase_seed) * 0.018 * awake;
	VERTEX.x += offset;
	VERTEX.z -= offset * 0.55;
}

void fragment() {
	float slab = floor(local_position.y * 2.4 + phase_seed * 7.0);
	float slow_pulse = sin(TIME * 0.83 + slab * 1.71 + phase_seed) * 0.5 + 0.5;
	float surface_noise = hash(floor(FRAGCOORD.xy * 0.32) + vec2(slab, phase_seed * 19.0));
	float uneven_return = mix(0.58, 1.0, surface_noise);
	float alpha = visibility * uneven_return * (0.25 + slow_pulse * 0.08);
	ALBEDO = history_color.rgb * mix(0.72, 1.05, slow_pulse);
	EMISSION = history_color.rgb * (0.10 + visibility * 0.13);
	ALPHA = alpha;
}
