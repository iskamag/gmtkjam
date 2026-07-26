extends Control

var player: CharacterBody3D
var visual_time := 0.0
var canvas_scale := 1.0
var canvas_offset := Vector2.ZERO
var displayed_fire_ratio := 0.0
var displayed_watch_lift := 0.0
var displayed_ignition := 0.0
var displayed_overclock := 0.0
var second_hand_angle := -PI * 0.5

const DESIGN_SIZE := Vector2(1280.0, 720.0)
const SKIN := Color(0.44, 0.35, 0.27)
const SKIN_DARK := Color(0.20, 0.15, 0.115)
const LEATHER := Color(0.075, 0.055, 0.042)
const STEEL := Color(0.61, 0.60, 0.55)
const STEEL_DARK := Color(0.16, 0.15, 0.135)
const FACE := Color(0.038, 0.041, 0.035)
const IVORY := Color(0.82, 0.79, 0.65)
const PURPLE_DARK := Color(0.19, 0.055, 0.28, 0.88)
const PURPLE := Color(0.39, 0.13, 0.53, 0.88)
const PURPLE_HOT := Color(0.69, 0.42, 0.78, 0.82)


func bind(player_node: CharacterBody3D) -> void:
	player = player_node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	visual_time += delta
	if is_instance_valid(player):
		var seconds_degrees := 6.0
		if player.watch_active:
			seconds_degrees = 96.0
		if player.is_watch_overclocked():
			seconds_degrees = 390.0
		var seconds_speed := deg_to_rad(seconds_degrees)
		second_hand_angle = wrapf(second_hand_angle - seconds_speed * delta, -PI, PI)
		var target_ratio: float = clampf(player.watchfire / player.MAX_WATCHFIRE, 0.0, 1.0)
		displayed_fire_ratio = lerpf(
			displayed_fire_ratio,
			target_ratio,
			1.0 - exp(-delta * 7.5)
		)
		var target_lift := 62.0 if player.watch_active else 0.0
		if player.is_watch_overclocked():
			target_lift = 82.0
		displayed_watch_lift = lerpf(
			displayed_watch_lift,
			target_lift,
			1.0 - exp(-delta * (17.0 if player.watch_active else 9.0))
		)
		var ignition_target: float = maxf(player.watch_entry_visual, player.overclock_visual)
		displayed_ignition = lerpf(
			displayed_ignition,
			ignition_target,
			1.0 - exp(-delta * (28.0 if ignition_target > displayed_ignition else 9.0))
		)
		displayed_overclock = lerpf(
			displayed_overclock,
			player.overclock_visual,
			1.0 - exp(-delta * 18.0)
		)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(player):
		return
	canvas_scale = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	canvas_offset = (size - DESIGN_SIZE * canvas_scale) * 0.5
	_set_design_transform()

	var lift := displayed_watch_lift
	lift += sin(visual_time * 24.0) * player.wound_visual * 10.0
	var movement_offset := Vector2(
		player.movement_sway * 3.0 + player.camera_kick.x * 3.0,
		player.stride_bob * 3.0 + player.landing_visual * 12.0
	)
	movement_offset += Vector2(-18.0, -22.0) * displayed_ignition
	var watch_center := Vector2(250.0, 584.0 - lift) + movement_offset

	_draw_left_hand(watch_center)
	_draw_time_aperture(watch_center)
	_draw_watchfire(watch_center)
	_draw_watch(watch_center)
	_draw_right_hand()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_watchfire(center: Vector2) -> void:
	var ratio := displayed_fire_ratio
	if ratio <= 0.02:
		return
	# The envelope has one authority: the meter. Slow time and Overclock alter
	# its motion and internal heat, never its apparent amount.
	var envelope := get_watchfire_envelope()
	var width := envelope.x
	var height := envelope.y
	var flame_rate := 24.0 if player.watch_active else 5.0
	if player.is_watch_overclocked():
		flame_rate = 43.0
	var flutter := sin(visual_time * flame_rate)
	var time_pull := (28.0 + displayed_overclock * 34.0) if player.watch_active else 0.0
	var base_y := center.y - 48.0
	var common_sway := sin(visual_time * (flame_rate * 0.43) + ratio * 2.7) * width * 0.055

	# Nested contours share one base and one dominant tip. Offsetting the old
	# layers into separate triangles left only three disconnected horns visible
	# above the watch bezel.
	for layer in 3:
		var layer_scale := 1.0 - float(layer) * 0.18
		var layer_width := width * (1.0 - float(layer) * 0.22)
		var x_shift := common_sway * (1.0 - float(layer) * 0.18)
		x_shift -= time_pull * (0.16 + float(layer) * 0.035)
		var tongue_height := height * layer_scale * (
			0.98 + sin(visual_time * 7.0 + float(layer) * 2.1) * 0.018
		)
		var layer_base := base_y + float(layer) * 7.0
		var points := PackedVector2Array([
			Vector2(center.x - layer_width * 0.50 + x_shift, layer_base),
			Vector2(center.x - layer_width * 0.46 + x_shift + flutter * 1.5, layer_base - tongue_height * 0.20),
			Vector2(center.x - layer_width * 0.28 + x_shift, layer_base - tongue_height * 0.40),
			Vector2(center.x - layer_width * 0.12 + x_shift - flutter * 2.0, layer_base - tongue_height * 0.63),
			Vector2(center.x + x_shift + sin(visual_time * 13.0 + float(layer)) * width * 0.055, layer_base - tongue_height),
			Vector2(center.x + layer_width * 0.16 + x_shift, layer_base - tongue_height * 0.58),
			Vector2(center.x + layer_width * 0.34 + x_shift + flutter * 1.7, layer_base - tongue_height * 0.36),
			Vector2(center.x + layer_width * 0.50 + x_shift, layer_base - tongue_height * 0.14),
			Vector2(center.x + layer_width * 0.46 + x_shift, layer_base),
		])
		if width < 2.0 or tongue_height < 2.0:
			continue
		var color := PURPLE_DARK if layer == 0 else (PURPLE if layer == 1 else PURPLE_HOT)
		draw_colored_polygon(points, color)

	if player.watch_active:
		# The hottest part is an ivory tear, not a larger purple glow. At
		# Overclock it stretches backward like time is being pulled through the hand.
		var core_height := height * 0.48
		draw_colored_polygon(PackedVector2Array([
			Vector2(center.x - 18.0 - time_pull * 0.12, base_y + 8.0),
			Vector2(center.x - 10.0 - time_pull * 0.24, base_y - core_height * 0.48),
			Vector2(center.x - 3.0 - time_pull * 0.34, base_y - core_height),
			Vector2(center.x + 12.0, base_y - core_height * 0.42),
			Vector2(center.x + 22.0, base_y + 8.0),
		]), Color(0.86, 0.81, 0.67, 0.68 + displayed_overclock * 0.18))

		for index in 5:
			var trail := float(index) / 4.0
			var mote := center + Vector2(
				-58.0 - trail * (70.0 + displayed_overclock * 64.0),
				-62.0 - trail * 36.0 + sin(visual_time * 9.0 + float(index)) * 8.0
			)
			var mote_color := Color(0.49, 0.30, 0.54, 0.44 - trail * 0.25)
			draw_line(mote, mote + Vector2(22.0 + trail * 18.0, -5.0), mote_color, 3.0, true)


func get_watchfire_envelope() -> Vector2:
	var ratio := clampf(displayed_fire_ratio, 0.0, 1.0)
	return Vector2(
		112.0 * pow(ratio, 0.46),
		218.0 * pow(ratio, 0.72)
	)


func _draw_time_aperture(center: Vector2) -> void:
	if not player.watch_active and displayed_ignition <= 0.01:
		return
	var aperture := maxf(displayed_ignition, displayed_overclock * 0.72)
	var ring_radius: float = 86.0 + (1.0 - player.watch_entry_visual) * 35.0
	var ring_color := Color(0.72, 0.67, 0.54, aperture * 0.34)
	draw_arc(center, ring_radius, -PI, PI, 64, ring_color, 2.0, true)

	# Twelve physical timing cuts make the state read as clockwork even when the
	# flame sprite is eventually replaced by authored art.
	for index in 12:
		var angle := second_hand_angle + float(index) * TAU / 12.0
		var inner := center + Vector2(cos(angle), sin(angle)) * (91.0 + displayed_overclock * 8.0)
		var tick_length := 10.0 if index % 3 else 19.0
		var outer := center + Vector2(cos(angle), sin(angle)) * (
			91.0 + displayed_overclock * 8.0 + tick_length
		)
		var alpha := 0.18 + displayed_overclock * (0.22 if index % 3 else 0.34)
		draw_line(inner, outer, Color(0.74, 0.69, 0.56, alpha), 2.0, true)


func _draw_left_hand(center: Vector2) -> void:
	var wrist := center + Vector2(-18.0, 54.0)
	var forearm := PackedVector2Array([
		Vector2(-35.0, 720.0),
		Vector2(120.0, 720.0),
		wrist + Vector2(72.0, 48.0),
		wrist + Vector2(58.0, -30.0),
		wrist + Vector2(-52.0, -35.0),
	])
	draw_colored_polygon(forearm, SKIN_DARK)

	var palm := PackedVector2Array([
		center + Vector2(-92.0, 62.0),
		center + Vector2(-104.0, 4.0),
		center + Vector2(-70.0, -55.0),
		center + Vector2(32.0, -62.0),
		center + Vector2(89.0, -19.0),
		center + Vector2(84.0, 50.0),
		center + Vector2(38.0, 88.0),
	])
	draw_colored_polygon(palm, SKIN)
	draw_polyline(PackedVector2Array([center + Vector2(-75.0, 38.0), center + Vector2(-24.0, 63.0), center + Vector2(45.0, 55.0)]), SKIN_DARK, 7.0)


func _draw_watch(center: Vector2) -> void:
	var max_ratio: float = clampf(player.max_time / player.STARTING_MAX_TIME, 0.0, 1.0)
	draw_rect(Rect2(center + Vector2(-91.0, -28.0), Vector2(182.0, 56.0)), LEATHER, true)
	draw_circle(center, 78.0, STEEL_DARK)
	draw_circle(center, 66.0, FACE)

	# The remaining arc is the maximum capacity. Missing arc never returns.
	draw_arc(center, 75.0, -PI * 0.5, -PI * 0.5 + TAU * max_ratio, 52, STEEL, 9.0, true)
	draw_arc(center, 67.0, 0.0, TAU, 52, Color(0.09, 0.095, 0.08), 4.0, true)

	for index in 12:
		var fraction := float(index) / 12.0
		if fraction > max_ratio:
			continue
		var angle := -PI * 0.5 + fraction * TAU
		var inner := center + Vector2(cos(angle), sin(angle)) * (51.0 if index % 3 else 46.0)
		var outer := center + Vector2(cos(angle), sin(angle)) * 60.0
		draw_line(inner, outer, IVORY, 3.0 if index % 3 else 5.0, true)

	var current_angle: float = -PI * 0.5 - TAU * (1.0 - player.time_left / player.STARTING_MAX_TIME)
	var hand_end := center + Vector2(cos(current_angle), sin(current_angle)) * 49.0
	if player.wound_visual > 0.01 or player.restore_visual > 0.01:
		var ghost_strength: float = maxf(player.wound_visual, player.restore_visual)
		var old_angle: float = -PI * 0.5 - TAU * (1.0 - player.watch_previous_time / player.STARTING_MAX_TIME)
		for index in 3:
			var blend := float(index + 1) / 4.0
			var ghost_angle := lerp_angle(old_angle, current_angle, blend)
			var ghost_end := center + Vector2(cos(ghost_angle), sin(ghost_angle)) * 48.0
			draw_line(center, ghost_end, Color(0.53, 0.35, 0.62, ghost_strength * 0.24), 3.0, true)

	draw_line(center, hand_end, IVORY, 5.0, true)

	# The thin seconds hand is the ability tell. The life hand stays truthful
	# while Watchfire makes this mechanism race backward through discarded time.
	if player.watch_active:
		var echo_count := 6 if player.is_watch_overclocked() else 3
		for echo in echo_count:
			var spacing := 11.0 if player.is_watch_overclocked() else 5.0
			var echo_alpha := 0.24 * (1.0 - float(echo) / float(echo_count))
			var echo_angle := second_hand_angle + deg_to_rad(spacing * float(echo + 1))
			var echo_end := center + Vector2(cos(echo_angle), sin(echo_angle)) * 56.0
			draw_line(
				center,
				echo_end,
				Color(PURPLE_HOT.r, PURPLE_HOT.g, PURPLE_HOT.b, echo_alpha),
				2.0,
				true
			)
	var seconds_end := center + Vector2(cos(second_hand_angle), sin(second_hand_angle)) * 57.0
	draw_line(center, seconds_end, Color(0.55, 0.19, 0.13), 2.0, true)
	draw_circle(seconds_end, 2.5, Color(0.72, 0.55, 0.38))
	draw_circle(center, 7.0, STEEL)

	var crack_count := int(ceil((1.0 - max_ratio) * 9.0))
	var crack_origins := [
		Vector2(35.0, -48.0), Vector2(53.0, -18.0), Vector2(48.0, 31.0),
		Vector2(12.0, 55.0), Vector2(-28.0, 51.0), Vector2(-54.0, 20.0),
		Vector2(-51.0, -27.0), Vector2(-18.0, -55.0), Vector2(6.0, -51.0),
	]
	for index in mini(crack_count, crack_origins.size()):
		var origin: Vector2 = center + crack_origins[index]
		var inward := (center - origin).normalized()
		draw_polyline(PackedVector2Array([
			origin,
			origin + inward * 13.0 + Vector2(inward.y, -inward.x) * 5.0,
			origin + inward * 27.0,
		]), Color(0.025, 0.025, 0.022), 4.0, true)

	# A permanently missing upper-right chunk keeps the watch broken even before damage.
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(38.0, -71.0),
		center + Vector2(79.0, -57.0),
		center + Vector2(72.0, -18.0),
		center + Vector2(54.0, -26.0),
	]), Color(0.018, 0.018, 0.016))


func _draw_right_hand() -> void:
	if player.kick_visual > 0.01:
		_draw_kick()

	if player.dagger_state == player.DaggerState.HELD:
		var slash := sin(player.swing_visual * PI)
		var origin := Vector2(
			1040.0 - slash * 115.0 - player.movement_sway * 3.0,
			615.0 - slash * 65.0 + player.stride_bob * 3.0 + player.landing_visual * 12.0
		)
		_set_component_transform(origin, -0.35 - slash * 0.85)
		_draw_arm_from_origin()
		_draw_dagger_from_origin()
		_set_design_transform()
	else:
		var punch := sin(player.punch_visual * PI)
		var origin := Vector2(
			1090.0 - punch * 225.0 - player.movement_sway * 3.0,
			625.0 - punch * 55.0 + player.stride_bob * 3.0 + player.landing_visual * 12.0
		)
		_set_component_transform(origin, -0.22 - punch * 0.12)
		_draw_arm_from_origin()
		_draw_fist_from_origin()
		_set_design_transform()


func _draw_arm_from_origin() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(45.0, 25.0),
		Vector2(290.0, 105.0),
		Vector2(310.0, 170.0),
		Vector2(28.0, 88.0),
	]), SKIN_DARK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-20.0, -20.0),
		Vector2(65.0, -16.0),
		Vector2(88.0, 59.0),
		Vector2(30.0, 103.0),
		Vector2(-45.0, 62.0),
	]), SKIN)


func _draw_dagger_from_origin() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-14.0, 10.0), Vector2(4.0, -225.0), Vector2(22.0, 12.0)
	]), STEEL)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-33.0, 6.0), Vector2(36.0, 6.0), Vector2(31.0, 20.0), Vector2(-30.0, 20.0)
	]), STEEL_DARK)
	draw_rect(Rect2(Vector2(-13.0, 17.0), Vector2(28.0, 83.0)), LEATHER, true)


func _draw_fist_from_origin() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-50.0, -38.0), Vector2(42.0, -47.0), Vector2(70.0, 3.0),
		Vector2(48.0, 58.0), Vector2(-42.0, 61.0), Vector2(-67.0, 12.0),
	]), SKIN)
	for index in 3:
		draw_line(Vector2(-28.0 + index * 29.0, -35.0), Vector2(-24.0 + index * 29.0, 12.0), SKIN_DARK, 5.0)


func _draw_kick() -> void:
	var kick := sin(player.kick_visual * PI)
	var origin := Vector2(765.0 - kick * 110.0, 760.0 - kick * 250.0)
	_set_component_transform(origin, -0.25 + kick * 0.18)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-52.0, 20.0), Vector2(62.0, 4.0), Vector2(160.0, 245.0), Vector2(28.0, 270.0)
	]), SKIN_DARK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-82.0, -12.0), Vector2(55.0, -24.0), Vector2(93.0, 26.0),
		Vector2(35.0, 71.0), Vector2(-91.0, 55.0)
	]), LEATHER)
	_set_design_transform()


func _set_design_transform() -> void:
	draw_set_transform(canvas_offset, 0.0, Vector2.ONE * canvas_scale)


func _set_component_transform(origin: Vector2, rotation: float) -> void:
	draw_set_transform(canvas_offset + origin * canvas_scale, rotation, Vector2.ONE * canvas_scale)
