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
uniform float time_bend : hint_range(0.0, 1.0) = 0.0;
uniform float time_snap : hint_range(0.0, 1.0) = 0.0;
uniform float overclock : hint_range(0.0, 1.0) = 0.0;
uniform float time_motion : hint_range(0.0, 1.5) = 0.0;
uniform float trauma : hint_range(0.0, 1.0) = 0.0;
uniform float crash : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = 1.0 / vec2(textureSize(screen_texture, 0));

	// The crash is one localized failure of the image around the carriage
	// impact, not a permanent glitch overlay. Its slow procedural drift avoids
	// high-contrast flicker while still making the frame feel physically torn.
	vec2 from_crash = SCREEN_UV - vec2(0.58, 0.43);
	vec2 crash_shape = from_crash * vec2(0.82, 1.42);
	float crash_field = exp(-dot(crash_shape, crash_shape) * 4.8) * crash;
	float crash_row = floor(SCREEN_UV.y * 31.0);
	float crash_row_seed = hash(vec2(crash_row, 41.0)) - 0.5;
	float crash_wobble = sin(
		SCREEN_UV.y * 71.0
		+ TIME * 2.6
		+ crash_row_seed * 5.0
	);
	float crash_cut = exp(
		-abs(
			SCREEN_UV.y
			- 0.43
			+ sin(SCREEN_UV.x * 11.0 + 0.8) * 0.024
		) * 38.0
	);
	uv.x += crash_field * (crash_wobble * 0.007 + crash_row_seed * 0.005);
	uv += normalize(from_crash + vec2(0.001)) * crash_field * crash_cut * 0.009;

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

	// Activation is a mechanical shutter sweeping out from the aiming point.
	// The world visibly arrests in one beat instead of slowly fading into a filter.
	vec2 from_center = uv - vec2(0.5);
	float center_distance = length(from_center * vec2(1.0, 1.45));
	float snap_radius = (1.0 - time_snap) * 0.92;
	float snap_ring = exp(-abs(center_distance - snap_radius) * 52.0) * time_snap;
	vec2 center_direction = from_center / max(length(from_center), 0.001);
	uv -= center_direction * snap_ring * (0.012 + overclock * 0.009);

	// Bending hostile time drags complete colour samples around the watch's
	// temporal field. Overclock pulls a second, harder exposure through it.
	vec2 time_tangent = normalize(vec2(-from_watch.y, from_watch.x) + vec2(0.001));
	float time_arc = sin(length(from_watch) * 19.0 - TIME * (2.3 + overclock * 3.4));
	float time_field = mix(0.42, 1.0, smoothstep(0.12, 0.88, length(from_watch)));
	vec2 time_offset = time_tangent * time_bend * time_field * (
		0.0024
		+ (time_arc * 0.5 + 0.5) * 0.0028
		+ overclock * 0.0042
	);
	vec2 motion_offset = from_center * time_bend * time_motion * (
		0.0032 + overclock * 0.0048
	);
	uv += time_offset + motion_offset;
	uv = clamp(uv, pixel, vec2(1.0) - pixel);

	// Channel separation exists only at violent temporal discontinuities.
	float separation = impact * 1.8 + wound * 2.5 + chronostep * 1.2 + dagger_rewind * 0.7;
	vec2 channel_offset = pixel * separation * vec2(1.0, 0.35);
	vec3 col;
	col.r = texture(screen_texture, uv + channel_offset).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - channel_offset).b;

	// Two earlier exposures make motion feel recorded rather than generically
	// blurred. All channels travel together, preserving material colour.
	vec3 time_history_near = texture(
		screen_texture,
		clamp(uv - time_offset * 2.2, pixel, vec2(1.0) - pixel)
	).rgb;
	vec3 time_history_far = texture(
		screen_texture,
		clamp(uv - time_offset * 4.6, pixel, vec2(1.0) - pixel)
	).rgb;
	vec3 temporal_smear = time_history_near * 0.68 + time_history_far * 0.32;
	vec3 motion_history = texture(
		screen_texture,
		clamp(uv - motion_offset * (3.0 + overclock * 2.0), pixel, vec2(1.0) - pixel)
	).rgb;
	col = mix(col, temporal_smear, time_bend * (0.22 + overclock * 0.14));
	col = mix(col, motion_history, time_bend * time_motion * (0.10 + overclock * 0.12));

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 old_light = vec3(luma) * vec3(1.015, 0.995, 0.94);
	col = mix(col, old_light, doom * 0.17 + scar * 0.07 + wound * 0.20);

	// Time dominance removes colour from the hostile world while retaining
	// graphite, old ivory and bruised plum. It is high contrast, not neon.
	float time_state = clamp(time_bend * 0.68 + overclock * 0.48, 0.0, 1.0);
	vec3 stopped_light = vec3(luma) * vec3(1.06, 1.015, 0.88);
	stopped_light += vec3(0.022, 0.006, 0.029) * (1.0 - smoothstep(0.08, 0.62, luma));
	stopped_light = (stopped_light - vec3(0.5)) * (1.10 + overclock * 0.18) + vec3(0.5);
	col = mix(col, stopped_light, time_state * (0.62 + overclock * 0.16));

	// The outer aperture is a twelve-cut clock face. It provides a stable spatial
	// frame during player motion and avoids the generic coloured speed tunnel.
	vec2 clock_space = (SCREEN_UV - vec2(0.5)) * vec2(1.0, 1.78);
	float clock_radius = length(clock_space);
	float clock_angle = atan(clock_space.y, clock_space.x) / 6.2831853 + 0.5;
	float clock_cell = abs(fract(clock_angle * 12.0 - TIME * overclock * 0.16) - 0.5);
	float clock_cut = 1.0 - smoothstep(0.055, 0.14, clock_cell);
	float clock_band = smoothstep(0.61, 0.69, clock_radius) * (
		1.0 - smoothstep(0.91, 1.04, clock_radius)
	);
	float clock_aperture = clock_cut * clock_band * time_bend * (0.22 + overclock * 0.34);
	col += vec3(0.34, 0.30, 0.21) * clock_aperture;
	col *= 1.0 - time_state * smoothstep(0.56, 1.02, clock_radius) * 0.12;

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

	// Post-crash trauma is spatial rather than a red fullscreen multiply. The
	// centre stays readable while peripheral double exposure, crushed colour,
	// and dried-rust shadow contamination retreat toward the broken watch.
	vec2 trauma_space = (SCREEN_UV - watch_anchor) * vec2(0.88, 1.12);
	float trauma_radius = length(trauma_space);
	float trauma_periphery = smoothstep(0.24, 0.88, trauma_radius);
	vec2 trauma_drag = normalize(trauma_space + vec2(0.001)) * pixel * (
		2.0 + trauma_periphery * 5.0
	) * trauma;
	vec3 trauma_history = texture(
		screen_texture,
		clamp(uv + trauma_drag, pixel, vec2(1.0) - pixel)
	).rgb;
	col = mix(col, trauma_history, trauma * trauma_periphery * 0.18);

	float trauma_luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 trauma_grade = mix(
		vec3(trauma_luma) * vec3(0.94, 0.89, 0.80),
		col,
		0.32
	);
	trauma_grade *= mix(0.82, 0.91, 1.0 - trauma_periphery);
	trauma_grade += vec3(0.105, 0.021, 0.007) * shadow * (
		0.26 + trauma_periphery * 0.74
	);
	float trauma_mix = trauma * mix(0.38, 0.76, trauma_periphery);
	col = mix(col, trauma_grade, trauma_mix);

	// One quiet restoration seam marks the rewind finishing; it is tied to the
	// watch and cannot become a generic pulsating damage vignette.
	float recovery_radius = (1.0 - trauma) * 1.08;
	float recovery_seam = exp(-abs(trauma_radius - recovery_radius) * 36.0);
	recovery_seam *= trauma * (1.0 - trauma) * 4.0;
	col += vec3(0.18, 0.14, 0.085) * recovery_seam * 0.10;

	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float vignette_weight = mix(0.075, 0.20, doom) + trauma * 0.10 + crash * 0.05;
	float vignette = 1.0 - dot(centered, centered) * vignette_weight;
	col *= max(vignette, 0.56);
	col += vec3(0.12, 0.085, 0.035) * hit_ring * 0.24;
	col += vec3(0.42, 0.36, 0.22) * snap_ring * (0.20 + overclock * 0.14);
	col *= 1.0 - time_snap * 0.11;
	col *= 1.0 - crash_field * crash_cut * 0.16;

	COLOR = vec4(col, 1.0);
}
