shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float doom : hint_range(0.0, 1.0) = 0.0;
uniform float scar : hint_range(0.0, 1.0) = 0.0;
uniform float rewind : hint_range(0.0, 1.0) = 0.0;
uniform float watchfire : hint_range(0.0, 1.0) = 0.0;
uniform float impact : hint_range(0.0, 1.5) = 0.0;
uniform vec2 impact_origin = vec2(0.5);
uniform float wound : hint_range(0.0, 1.0) = 0.0;
uniform float chronostep : hint_range(0.0, 1.0) = 0.0;
uniform float dagger_rewind : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = 1.0 / vec2(textureSize(screen_texture, 0));

	// A hit is a radial tear in recorded time, concentrated at the contact point.
	vec2 from_hit = uv - impact_origin;
	float hit_distance = length(from_hit);
	float hit_ring = exp(-abs(hit_distance - impact * 0.12) * 72.0) * impact;
	vec2 hit_direction = from_hit / max(hit_distance, 0.001);
	uv -= hit_direction * hit_ring * 0.009;

	// Chronostep shears broad horizontal bands instead of leaving a neon speed tunnel.
	float broad_band = sin(uv.y * 17.0 + TIME * 3.0) * 0.5 + 0.5;
	uv.x += (broad_band - 0.5) * chronostep * 0.018;

	// The dagger's literal recorded-path rewind briefly misaligns a few scan rows.
	float row = floor(uv.y * 180.0);
	float row_noise = hash(vec2(row, floor(TIME * 30.0))) - 0.5;
	uv.x += row_noise * dagger_rewind * 0.0035;

	// A wound is instinctively pulled toward the broken watch, not converted
	// into an arbitrary full-screen glitch. The second sample is its discarded
	// instant collapsing into the left hand.
	vec2 watch_anchor = vec2(0.225, 0.79);
	vec2 from_watch = uv - watch_anchor;
	float watch_field = exp(-length(from_watch) * 2.8) * max(wound, rewind);
	vec2 discarded_uv = watch_anchor + from_watch * (1.0 + watch_field * 0.045);
	uv = mix(uv, discarded_uv, watch_field * 0.42);
	uv = clamp(uv, pixel, vec2(1.0) - pixel);

	// Channel separation exists only at violent temporal discontinuities.
	float separation = impact * 1.8 + wound * 2.5 + chronostep * 1.2 + dagger_rewind * 0.7;
	vec2 channel_offset = pixel * separation * vec2(1.0, 0.35);
	vec3 col;
	col.r = texture(screen_texture, uv + channel_offset).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - channel_offset).b;

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 old_light = vec3(luma) * vec3(1.015, 0.995, 0.94);
	col = mix(col, old_light, doom * 0.17 + scar * 0.07 + wound * 0.20);

	// PS2-era surface character: continuous colour and fine analogue grain.
	// There is deliberately no palette quantization or posterization here.
	float grain = hash(FRAGCOORD.xy + vec2(floor(TIME * 24.0), -floor(TIME * 19.0))) - 0.5;
	col += grain * mix(0.007, 0.016, doom);
	vec3 discarded = texture(screen_texture, clamp(discarded_uv, pixel, vec2(1.0) - pixel)).rgb;
	col = mix(col, discarded, watch_field * 0.18);

	// Watchfire lives in shadows and in temporal edges, never as a global neon wash.
	float shadow = 1.0 - smoothstep(0.05, 0.58, luma);
	col += vec3(0.038, 0.006, 0.052) * watchfire * shadow;
	col += vec3(0.08, 0.035, 0.095) * dagger_rewind * hit_ring * 0.35;

	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float vignette = 1.0 - dot(centered, centered) * mix(0.075, 0.20, doom);
	col *= max(vignette, 0.56);
	col += vec3(0.12, 0.085, 0.035) * hit_ring * 0.24;

	COLOR = vec4(col, 1.0);
}
