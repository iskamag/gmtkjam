shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float doom : hint_range(0.0, 1.0) = 0.0;
uniform float scar : hint_range(0.0, 1.0) = 0.0;
uniform float rewind : hint_range(0.0, 1.0) = 0.0;
uniform float watchfire : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_texture, uv).rgb;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 old_light = vec3(luma) * vec3(1.015, 0.995, 0.94);
	col = mix(col, old_light, doom * 0.20 + scar * 0.08);

	// Fine surface noise keeps the image tactile without quantizing its colours.
	float grain = hash(FRAGCOORD.xy + vec2(floor(TIME * 20.0), -floor(TIME * 17.0))) - 0.5;
	col += grain * mix(0.008, 0.018, doom);

	// Watchfire stains the shadows rather than painting the whole scene neon.
	float shadow = 1.0 - smoothstep(0.05, 0.58, luma);
	col += vec3(0.045, 0.008, 0.065) * watchfire * shadow;

	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float vignette = 1.0 - dot(centered, centered) * mix(0.08, 0.22, doom);
	vec3 edge_tint = mix(vec3(1.0), vec3(0.70, 0.53, 0.76), watchfire * dot(centered, centered) * 0.12);
	col *= max(vignette, 0.55) * edge_tint;

	// Wounds are shown by the two-dimensional hands and broken watch. Keeping the
	// parameter here lets presentation code stay stable without another screen hit.
	col += vec3(0.0) * rewind;
	COLOR = vec4(col, 1.0);
}
