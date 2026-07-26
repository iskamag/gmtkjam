extends CanvasLayer

const HandsScript = preload("res://scripts/hands_2d.gd")
const InterfaceFont = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const STATUS_BAR_WIDTH := 840.0
const STATUS_BAR_HEIGHT := 36.0

var player: CharacterBody3D
var game: Node3D

var root: Control
var hands: Control
var post_rect: ColorRect
var post_material: ShaderMaterial
var crosshair: Label
var title_layer: Control
var announcement: Label
var subtitle: Label
var objective: Label
var debug_label: Label
var ending_layer: Control
var ending_title: Label
var ending_subtitle: Label
var boss_group: Control
var boss_bar: ProgressBar
var boss_label: Label
var prologue_layer: Control
var prologue_shade: ColorRect
var prologue_stats: Label
var prologue_fragment: Label
var prologue_title: Label
var prologue_subtitle: Label
var prologue_skip: Label
var time_art_group: Control
var time_art_label: Label
var time_art_detail: Label
var status_group: Control
var status_capacity_bar: ProgressBar
var status_current_bar: ProgressBar
var status_cap_marker: ColorRect
var status_current_fill: StyleBoxFlat
var status_condition: Label

var announcement_time := 0.0
var time_art_time := 0.0
var event_log: Array[String] = []
var debug_visible := false
var impact_pulse := 0.0
var wound_pulse := 0.0
var impact_origin := Vector2(0.5, 0.5)
var prologue_active := false
var prologue_time := 0.0
var time_bend_visual := 0.0
var intro_trauma_target := 0.0
var intro_trauma_visual := 0.0
var intro_crash_target := 0.0
var intro_crash_visual := 0.0
var intro_wound_target := 0.0
var intro_wound_visual := 0.0


func _ready() -> void:
	layer = 20
	_build_ui()


func bind(player_node: CharacterBody3D, game_node: Node3D) -> void:
	player = player_node
	game = game_node
	hands.bind(player)


func _process(delta: float) -> void:
	impact_pulse = maxf(impact_pulse - delta * 7.8, 0.0)
	wound_pulse = maxf(wound_pulse - delta * 3.8, 0.0)
	var bend_target := 0.0
	if is_instance_valid(player) and player.watch_active:
		bend_target = 1.0
	var bend_duration := 0.09 if bend_target > time_bend_visual else 0.14
	time_bend_visual = move_toward(time_bend_visual, bend_target, delta / bend_duration)
	intro_trauma_visual = move_toward(intro_trauma_visual, intro_trauma_target, delta * 2.4)
	var crash_speed := 18.0 if intro_crash_target > intro_crash_visual else 4.8
	intro_crash_visual = move_toward(intro_crash_visual, intro_crash_target, delta * crash_speed)
	var intro_wound_speed := 10.0 if intro_wound_target > intro_wound_visual else 1.15
	intro_wound_visual = move_toward(
		intro_wound_visual,
		intro_wound_target,
		delta * intro_wound_speed
	)
	if is_instance_valid(post_material):
		post_material.set_shader_parameter("time_bend", time_bend_visual)
		post_material.set_shader_parameter("trauma", intro_trauma_visual)
		post_material.set_shader_parameter("crash", intro_crash_visual)
	if Input.is_action_just_pressed("toggle_debug"):
		debug_visible = not debug_visible
		debug_label.visible = debug_visible

	if announcement_time > 0.0:
		announcement_time -= delta
		var fade: float = clampf(announcement_time / 0.35, 0.0, 1.0)
		if announcement_time > 0.35:
			fade = 1.0
		announcement.modulate.a = fade
		subtitle.modulate.a = fade
	else:
		announcement.visible = false
		subtitle.visible = false

	if time_art_time > 0.0:
		time_art_time = maxf(time_art_time - delta, 0.0)
		var art_fade := clampf(time_art_time / 0.22, 0.0, 1.0)
		time_art_group.modulate.a = art_fade
		time_art_group.position.x = lerpf(-7.0, 0.0, art_fade)
	else:
		time_art_group.visible = false

	if is_instance_valid(player):
		post_material.set_shader_parameter("impact", impact_pulse)
		post_material.set_shader_parameter("impact_origin", impact_origin)
		var localized_intro_wound := intro_wound_visual
		if prologue_active and prologue_time >= 6.25:
			# The crash aftermath breathes around the broken watch instead of
			# holding a flat red grade over the entire exterior reveal.
			localized_intro_wound *= 0.90 + sin(prologue_time * 4.1) * 0.10
		post_material.set_shader_parameter(
			"wound",
			maxf(maxf(wound_pulse, player.wound_visual), localized_intro_wound)
		)
		post_material.set_shader_parameter("chronostep", player.chronostep_visual)
		post_material.set_shader_parameter(
			"dagger_rewind",
			1.0 if player.dagger_state == player.DaggerState.REWINDING else 0.0
		)
		objective.text = "CHRONOSWORD  //  LV 50"
		_update_status_bar()
		if debug_visible:
			debug_label.text = (
				"PROTOTYPE TELEMETRY\n"
				+ "time        %06.2f\n" % player.time_left
				+ "maximum     %06.2f\n" % player.max_time
				+ "max eroded  %06.2f\n" % (player.STARTING_MAX_TIME - player.max_time)
				+ "watchfire   %06.2f\n" % player.watchfire
				+ "speed       %06.2f\n" % player.planar_speed
				+ "movement    %s\n" % ("SLIDE" if player.is_sliding else ("STEP" if player.chronostep_timer > 0.0 else "GROUND"))
				+ "hostile x   %06.3f\n\n" % player.get_hostile_time_scale()
				+ "\n".join(event_log)
			)


func set_effects(doom: float, scar: float, rewind: float, watchfire: float) -> void:
	if not is_instance_valid(post_material):
		return
	post_material.set_shader_parameter("doom", clamp(doom, 0.0, 1.0))
	post_material.set_shader_parameter("scar", clamp(scar, 0.0, 1.0))
	post_material.set_shader_parameter("rewind", clamp(rewind, 0.0, 1.0))
	post_material.set_shader_parameter("watchfire", clamp(watchfire, 0.0, 1.0))


func pulse_impact(strength: float, at: Vector2) -> void:
	impact_pulse = maxf(impact_pulse, strength)
	impact_origin = Vector2(clampf(at.x, 0.0, 1.0), clampf(at.y, 0.0, 1.0))


func pulse_wound(side: float) -> void:
	wound_pulse = 1.0
	impact_origin = Vector2(0.5 + side * 0.24, 0.56)


func begin_prologue() -> void:
	prologue_active = true
	prologue_time = 0.0
	prologue_layer.visible = true
	title_layer.visible = false
	crosshair.visible = false
	objective.visible = false
	status_group.visible = false
	boss_group.visible = false
	announcement.visible = false
	subtitle.visible = false
	prologue_stats.visible = true
	prologue_fragment.visible = false
	prologue_title.visible = false
	prologue_subtitle.visible = false
	prologue_skip.visible = true
	set_intro_effects(0.0, 0.0)
	update_prologue(0.0)


func update_prologue(t: float) -> void:
	if not prologue_active:
		return
	prologue_time = maxf(t, 0.0)

	# Shade removed — no black screen at any point during the cutscene.
	var shade_alpha := 0.0
	prologue_shade.color = Color(0.018, 0.014, 0.011, shade_alpha)

	var stats_alpha := (
		_smooth_range(prologue_time, 0.55, 1.02)
		* (1.0 - _smooth_range(prologue_time, 3.18, 3.72))
	)
	prologue_stats.visible = stats_alpha > 0.001
	prologue_stats.modulate.a = stats_alpha

	var fragment_alpha := 0.0
	if prologue_time >= 2.55 and prologue_time < 3.45:
		prologue_fragment.text = "VICTORY RECORDED  //  48"
		fragment_alpha = _pulse_range(prologue_time, 2.55, 3.45, 0.16)
	elif prologue_time >= 3.45 and prologue_time < 4.42:
		prologue_fragment.text = "FIRST CONTRACT  //  DEFERRED"
		fragment_alpha = _pulse_range(prologue_time, 3.45, 4.42, 0.18)
	elif prologue_time >= 4.42 and prologue_time < 5.42:
		prologue_fragment.text = "RETURN OVERDUE"
		fragment_alpha = _pulse_range(prologue_time, 4.42, 5.42, 0.18)
	prologue_fragment.visible = fragment_alpha > 0.001
	prologue_fragment.modulate.a = fragment_alpha

	var crash_amount := 0.0
	if prologue_time >= 5.18 and prologue_time < 5.72:
		crash_amount = _smooth_range(prologue_time, 5.18, 5.72)
	elif prologue_time < 6.72 and prologue_time >= 5.72:
		crash_amount = 1.0 - _smooth_range(prologue_time, 5.72, 6.72)
	var trauma_amount := 0.0
	if prologue_time >= 5.58:
		trauma_amount = lerpf(
			0.86,
			0.10,
			_smooth_range(prologue_time, 5.88, 9.35)
		)
	set_intro_effects(trauma_amount, crash_amount)

	var epilogue_alpha := _smooth_range(prologue_time, 7.45, 8.02)
	prologue_title.visible = epilogue_alpha > 0.001
	prologue_title.modulate.a = epilogue_alpha
	var first_job_alpha := _smooth_range(prologue_time, 7.92, 8.48)
	prologue_subtitle.visible = first_job_alpha > 0.001
	prologue_subtitle.modulate.a = first_job_alpha
	prologue_skip.modulate.a = 0.48 * (1.0 - _smooth_range(prologue_time, 7.1, 8.1))


func end_prologue() -> void:
	prologue_active = false
	prologue_layer.visible = false
	crosshair.visible = true
	objective.visible = true
	intro_crash_target = 0.0
	intro_trauma_target = 0.0
	intro_wound_target = 0.0
	status_group.visible = true


func set_intro_effects(trauma: float, crash: float) -> void:
	var injury := clampf(trauma, 0.0, 1.0)
	# Trauma is now only the restrained, dried-rust grade. Most of the injury
	# travels through the localized watch-side wound field.
	intro_trauma_target = pow(injury, 1.45) * 0.34
	intro_wound_target = pow(injury, 0.72)
	intro_crash_target = clampf(crash, 0.0, 1.0)


func begin_run() -> void:
	title_layer.visible = false
	crosshair.visible = true
	objective.visible = true
	status_group.visible = true
	announce("CHRONOSWORD — LV 50", "Your time has come.", 1.7)


func announce(headline: String, detail: String, duration: float = 1.3) -> void:
	announcement.text = headline
	subtitle.text = detail
	announcement.visible = true
	subtitle.visible = true
	announcement.modulate.a = 1.0
	subtitle.modulate.a = 1.0
	announcement_time = duration


func show_boss(maximum: int) -> void:
	boss_group.visible = true
	boss_bar.max_value = maximum
	boss_bar.value = maximum


func set_boss_health(value: int, maximum: int) -> void:
	boss_group.visible = true
	boss_bar.max_value = maximum
	boss_bar.value = max(value, 0)


func hide_boss() -> void:
	boss_group.visible = false


func show_ending(job_complete: bool) -> void:
	ending_layer.visible = true
	objective.visible = false
	status_group.visible = false
	boss_group.visible = false
	if job_complete:
		ending_title.text = "YOUR TIME HAS COME"
		ending_subtitle.text = "The first job is finished.\nThe last day is over.\n\nR — live it again"
	else:
		ending_title.text = "THE HAND REACHED ZERO"
		ending_subtitle.text = "The job remains unfinished.\n\nR — replay the last job"


func receive_score_event(tag: StringName, payload: Dictionary) -> void:
	var compact := "%-21s %s" % [String(tag), _compact_payload(payload)]
	event_log.push_front(compact)
	if event_log.size() > 10:
		event_log.pop_back()
	if tag == &"watch_overclock":
		time_art_label.text = "DEAD SECOND"
		time_art_detail.text = "THE WORLD MISSED ITS TURN"
		time_art_group.position.x = -18.0
		time_art_group.modulate.a = 1.0
		time_art_group.visible = true
		time_art_time = maxf(float(payload.get("duration", 1.2)), 0.72)
	elif tag == &"overclock_hit":
		time_art_label.text = "TIME DEBT COLLECTED"
		time_art_detail.text = "%s DAMAGE  //  BETWEEN TICKS" % _group_damage(
			int(payload.get("damage", 0))
		)
		time_art_group.position.x = -10.0
		time_art_group.modulate.a = 1.0
		time_art_group.visible = true
		time_art_time = maxf(time_art_time, 0.62)


func _group_damage(value: int) -> String:
	var text := str(absi(value))
	var grouped := ""
	while text.length() > 3:
		grouped = "," + text.right(3) + grouped
		text = text.left(text.length() - 3)
	return ("-" if value < 0 else "") + text + grouped


func _compact_payload(payload: Dictionary) -> String:
	var parts: Array[String] = []
	for key in payload.keys():
		var value = payload[key]
		if value is float:
			parts.append("%s=%.1f" % [key, value])
		else:
			parts.append("%s=%s" % [key, value])
	return " ".join(parts)


func _smooth_range(value: float, from: float, to: float) -> float:
	if to <= from:
		return 1.0 if value >= to else 0.0
	var unit := clampf((value - from) / (to - from), 0.0, 1.0)
	return unit * unit * (3.0 - 2.0 * unit)


func _pulse_range(value: float, from: float, to: float, edge: float) -> float:
	return (
		_smooth_range(value, from, from + edge)
		* (1.0 - _smooth_range(value, to - edge, to))
	)


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var interface_theme := Theme.new()
	interface_theme.default_font = InterfaceFont
	interface_theme.default_font_size = 17
	root.theme = interface_theme
	add_child(root)

	post_rect = ColorRect.new()
	post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_rect.color = Color.WHITE
	post_material = ShaderMaterial.new()
	post_material.shader = load("res://shaders/post_process.gdshader")
	post_rect.material = post_material
	root.add_child(post_rect)

	hands = HandsScript.new()
	hands.name = "TwoDimensionalHands"
	root.add_child(hands)

	crosshair = Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-16.0, -25.0)
	crosshair.size = Vector2(32.0, 50.0)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size", 32)
	crosshair.add_theme_color_override("font_color", Color(0.79, 0.76, 0.62, 0.78))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.visible = false
	root.add_child(crosshair)

	objective = Label.new()
	objective.position = Vector2(28.0, 18.0)
	objective.size = Vector2(520.0, 30.0)
	objective.add_theme_font_size_override("font_size", 17)
	objective.add_theme_color_override("font_color", Color(0.76, 0.72, 0.59, 0.90))
	objective.add_theme_color_override("font_shadow_color", Color.BLACK)
	objective.add_theme_constant_override("shadow_offset_x", 2)
	objective.add_theme_constant_override("shadow_offset_y", 2)
	objective.visible = false
	root.add_child(objective)

	announcement = Label.new()
	announcement.set_anchors_preset(Control.PRESET_CENTER_TOP)
	announcement.position = Vector2(-340.0, 194.0)
	announcement.size = Vector2(680.0, 54.0)
	announcement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announcement.add_theme_font_size_override("font_size", 32)
	announcement.add_theme_color_override("font_color", Color(0.90, 0.84, 0.65))
	announcement.add_theme_color_override("font_shadow_color", Color(0.02, 0.018, 0.014))
	announcement.add_theme_constant_override("shadow_offset_x", 4)
	announcement.add_theme_constant_override("shadow_offset_y", 4)
	announcement.visible = false
	root.add_child(announcement)

	subtitle = Label.new()
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.position = Vector2(-340.0, 240.0)
	subtitle.size = Vector2(680.0, 38.0)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(0.66, 0.64, 0.55))
	subtitle.add_theme_color_override("font_shadow_color", Color.BLACK)
	subtitle.add_theme_constant_override("shadow_offset_x", 3)
	subtitle.add_theme_constant_override("shadow_offset_y", 3)
	subtitle.visible = false
	root.add_child(subtitle)

	_build_status_bar()
	_build_boss_bar()
	_build_title()
	_build_prologue()
	_build_ending()
	_build_time_art_callout()

	debug_label = Label.new()
	debug_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	debug_label.position = Vector2(-530.0, -350.0)
	debug_label.size = Vector2(510.0, 330.0)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	debug_label.add_theme_font_size_override("font_size", 13)
	debug_label.add_theme_color_override("font_color", Color(0.70, 0.81, 0.59, 0.86))
	debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	debug_label.add_theme_constant_override("shadow_offset_x", 2)
	debug_label.add_theme_constant_override("shadow_offset_y", 2)
	debug_label.visible = false
	root.add_child(debug_label)


func _build_status_bar() -> void:
	status_group = Control.new()
	status_group.name = "ChronoswordStatus"
	status_group.position = Vector2(28.0, 48.0)
	status_group.size = Vector2(STATUS_BAR_WIDTH, 65.0)
	status_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_group.visible = false
	root.add_child(status_group)

	# The rear bar is the watch's surviving capacity. Because both bars share
	# the original sixty-second scale, the empty section at the right is the
	# permanent maximum that wounds have physically taken away.
	status_capacity_bar = ProgressBar.new()
	status_capacity_bar.name = "SurvivingMaximum"
	status_capacity_bar.position = Vector2.ZERO
	status_capacity_bar.size = Vector2(STATUS_BAR_WIDTH, STATUS_BAR_HEIGHT)
	status_capacity_bar.min_value = 0.0
	status_capacity_bar.max_value = 60.0
	status_capacity_bar.show_percentage = false
	status_capacity_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var capacity_background := StyleBoxFlat.new()
	capacity_background.bg_color = Color(0.025, 0.024, 0.021, 0.96)
	capacity_background.border_color = Color(0.32, 0.29, 0.225, 0.92)
	capacity_background.set_border_width_all(2)
	var capacity_fill := StyleBoxFlat.new()
	capacity_fill.bg_color = Color(0.285, 0.265, 0.215, 0.96)
	capacity_fill.border_color = Color(0.49, 0.44, 0.335, 0.88)
	capacity_fill.set_border_width_all(2)
	status_capacity_bar.add_theme_stylebox_override("background", capacity_background)
	status_capacity_bar.add_theme_stylebox_override("fill", capacity_fill)
	status_group.add_child(status_capacity_bar)

	# Current life lies over the surviving maximum. The exposed dull strip is
	# time that may still be restored; the black scar beyond the cap may not.
	status_current_bar = ProgressBar.new()
	status_current_bar.name = "CurrentTime"
	status_current_bar.position = Vector2(3.0, 3.0)
	status_current_bar.size = Vector2(STATUS_BAR_WIDTH - 6.0, STATUS_BAR_HEIGHT - 6.0)
	status_current_bar.min_value = 0.0
	status_current_bar.max_value = 60.0
	status_current_bar.show_percentage = false
	status_current_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var transparent_background := StyleBoxEmpty.new()
	status_current_fill = StyleBoxFlat.new()
	status_current_fill.bg_color = Color(0.67, 0.285, 0.105, 0.98)
	status_current_fill.border_color = Color(0.81, 0.62, 0.34, 0.66)
	status_current_fill.border_width_top = 2
	status_current_bar.add_theme_stylebox_override("background", transparent_background)
	status_current_bar.add_theme_stylebox_override("fill", status_current_fill)
	status_group.add_child(status_current_bar)

	for fraction in [0.25, 0.5, 0.75]:
		var division := ColorRect.new()
		division.position = Vector2(STATUS_BAR_WIDTH * fraction - 1.0, 3.0)
		division.size = Vector2(2.0, STATUS_BAR_HEIGHT - 6.0)
		division.color = Color(0.025, 0.022, 0.018, 0.58)
		division.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_group.add_child(division)

	status_cap_marker = ColorRect.new()
	status_cap_marker.name = "MaximumScar"
	status_cap_marker.position = Vector2(STATUS_BAR_WIDTH - 4.0, -3.0)
	status_cap_marker.size = Vector2(4.0, STATUS_BAR_HEIGHT + 6.0)
	status_cap_marker.color = Color(0.72, 0.66, 0.50, 0.88)
	status_cap_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_group.add_child(status_cap_marker)

	var life_caption := Label.new()
	life_caption.text = "TIME  //  LIFE"
	life_caption.position = Vector2(1.0, 39.0)
	life_caption.size = Vector2(250.0, 23.0)
	life_caption.add_theme_font_size_override("font_size", 13)
	life_caption.add_theme_color_override("font_color", Color(0.63, 0.59, 0.48, 0.84))
	status_group.add_child(life_caption)

	status_condition = Label.new()
	status_condition.text = "LAST JOB"
	status_condition.position = Vector2(550.0, 39.0)
	status_condition.size = Vector2(289.0, 23.0)
	status_condition.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_condition.add_theme_font_size_override("font_size", 13)
	status_condition.add_theme_color_override("font_color", Color(0.63, 0.59, 0.48, 0.84))
	status_group.add_child(status_condition)


func _update_status_bar() -> void:
	if not is_instance_valid(status_group):
		return
	status_capacity_bar.max_value = player.STARTING_MAX_TIME
	status_current_bar.max_value = player.STARTING_MAX_TIME
	status_capacity_bar.value = clampf(player.max_time, 0.0, player.STARTING_MAX_TIME)
	status_current_bar.value = clampf(player.time_left, 0.0, player.STARTING_MAX_TIME)
	var maximum_ratio: float = clampf(
		player.max_time / maxf(player.STARTING_MAX_TIME, 0.001),
		0.0,
		1.0
	)
	status_cap_marker.position.x = clampf(
		STATUS_BAR_WIDTH * maximum_ratio - 2.0,
		0.0,
		STATUS_BAR_WIDTH - 4.0
	)
	status_cap_marker.visible = maximum_ratio < 0.995

	var life_ratio: float = clampf(
		player.time_left / maxf(player.max_time, 0.001),
		0.0,
		1.0
	)
	var healthy_color := Color(0.67, 0.285, 0.105, 0.98)
	var critical_color := Color(0.43, 0.075, 0.045, 0.98)
	status_current_fill.bg_color = healthy_color.lerp(
		critical_color,
		clampf((0.42 - life_ratio) / 0.42, 0.0, 1.0)
	)
	status_current_fill.border_color = Color(0.81, 0.62, 0.34, 0.66).lerp(
		Color(0.66, 0.25, 0.13, 0.76),
		clampf((0.42 - life_ratio) / 0.42, 0.0, 1.0)
	)
	if player.wound_visual > 0.01:
		status_current_fill.bg_color = status_current_fill.bg_color.lerp(
			Color(0.87, 0.76, 0.52, 0.98),
			player.wound_visual * 0.58
		)
	status_condition.text = "WATCH FRACTURED" if maximum_ratio < 0.82 else "LAST JOB"


func _build_time_art_callout() -> void:
	time_art_group = Control.new()
	time_art_group.name = "DeadSecondCallout"
	time_art_group.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	time_art_group.position = Vector2(42.0, 112.0)
	time_art_group.size = Vector2(390.0, 92.0)
	time_art_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_art_group.visible = false
	root.add_child(time_art_group)

	var rule := ColorRect.new()
	rule.position = Vector2(0.0, 4.0)
	rule.size = Vector2(4.0, 72.0)
	rule.color = Color(0.52, 0.34, 0.56, 0.88)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_art_group.add_child(rule)

	time_art_label = Label.new()
	time_art_label.position = Vector2(18.0, -6.0)
	time_art_label.size = Vector2(360.0, 54.0)
	time_art_label.add_theme_font_size_override("font_size", 36)
	time_art_label.add_theme_color_override("font_color", Color(0.91, 0.86, 0.69))
	time_art_label.add_theme_color_override("font_shadow_color", Color(0.07, 0.018, 0.075, 0.96))
	time_art_label.add_theme_constant_override("shadow_offset_x", 4)
	time_art_label.add_theme_constant_override("shadow_offset_y", 4)
	time_art_group.add_child(time_art_label)

	time_art_detail = Label.new()
	time_art_detail.position = Vector2(20.0, 43.0)
	time_art_detail.size = Vector2(360.0, 30.0)
	time_art_detail.add_theme_font_size_override("font_size", 14)
	time_art_detail.add_theme_color_override("font_color", Color(0.61, 0.57, 0.48))
	time_art_group.add_child(time_art_detail)


func _build_boss_bar() -> void:
	boss_group = Control.new()
	boss_group.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_group.position = Vector2(-440.0, 118.0)
	boss_group.size = Vector2(880.0, 65.0)
	boss_group.visible = false
	root.add_child(boss_group)

	boss_label = Label.new()
	boss_label.text = "THE UNFINISHED  //  FIRST DEBT"
	boss_label.position = Vector2(0.0, 0.0)
	boss_label.size = Vector2(880.0, 25.0)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	boss_label.add_theme_font_size_override("font_size", 16)
	boss_label.add_theme_color_override("font_color", Color(0.75, 0.69, 0.55, 0.92))
	boss_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	boss_label.add_theme_constant_override("shadow_offset_x", 2)
	boss_label.add_theme_constant_override("shadow_offset_y", 2)
	boss_group.add_child(boss_label)

	boss_bar = ProgressBar.new()
	boss_bar.position = Vector2(0.0, 27.0)
	boss_bar.size = Vector2(880.0, 29.0)
	boss_bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.024, 0.021, 0.96)
	background.border_color = Color(0.32, 0.29, 0.225, 0.92)
	background.set_border_width_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.50, 0.105, 0.065, 0.98)
	fill.border_color = Color(0.72, 0.31, 0.16, 0.72)
	fill.border_width_top = 2
	boss_bar.add_theme_stylebox_override("background", background)
	boss_bar.add_theme_stylebox_override("fill", fill)
	boss_group.add_child(boss_bar)

	for fraction in [0.25, 0.5, 0.75]:
		var division := ColorRect.new()
		division.position = Vector2(880.0 * fraction - 1.0, 30.0)
		division.size = Vector2(2.0, 23.0)
		division.color = Color(0.025, 0.022, 0.018, 0.58)
		division.mouse_filter = Control.MOUSE_FILTER_IGNORE
		boss_group.add_child(division)


func _build_title() -> void:
	title_layer = Control.new()
	title_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_layer)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.018, 0.017, 0.014, 0.74)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_layer.add_child(shade)

	var title := Label.new()
	title.text = "CHRONOSWORD'S\nLAST DAY"
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-410.0, -190.0)
	title.size = Vector2(820.0, 190.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 66)
	title.add_theme_color_override("font_color", Color(0.83, 0.78, 0.61))
	title.add_theme_color_override("font_shadow_color", Color(0.08, 0.035, 0.012))
	title.add_theme_constant_override("shadow_offset_x", 7)
	title.add_theme_constant_override("shadow_offset_y", 7)
	title_layer.add_child(title)

	var copy := Label.new()
	copy.text = (
		"YOUR TIME HAS COME.\n\n"
		+ "WASD move   •   SHIFT chronostep   •   CTRL slide\n"
		+ "SPACE jump / wall-kick   •   LMB combo   •   E kick\n"
		+ "RMB hold to guide the throw   •   RMB again to pay for rewind\n"
		+ "Q burn the watch   •   walking over the dagger retrieves it for free\n\n"
		+ "[ CLICK TO BEGIN ]"
	)
	copy.set_anchors_preset(Control.PRESET_CENTER)
	copy.size = Vector2(940.0, 220.0)
	copy.position = Vector2(-470.0, 18.0)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.add_theme_font_size_override("font_size", 18)
	copy.add_theme_color_override("font_color", Color(0.65, 0.62, 0.52))
	copy.add_theme_color_override("font_shadow_color", Color.BLACK)
	copy.add_theme_constant_override("shadow_offset_x", 3)
	copy.add_theme_constant_override("shadow_offset_y", 3)
	title_layer.add_child(copy)

	var credits := Label.new()
	credits.text = "ASSET CREDITS  //  ATTRIBUTION.md"
	credits.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	credits.position = Vector2(-346.0, -31.0)
	credits.size = Vector2(318.0, 20.0)
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credits.add_theme_font_size_override("font_size", 12)
	credits.add_theme_color_override("font_color", Color(0.57, 0.54, 0.46, 0.52))
	credits.add_theme_color_override("font_shadow_color", Color.BLACK)
	credits.add_theme_constant_override("shadow_offset_x", 2)
	credits.add_theme_constant_override("shadow_offset_y", 2)
	title_layer.add_child(credits)


func _build_prologue() -> void:
	prologue_layer = Control.new()
	prologue_layer.name = "Prologue"
	prologue_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prologue_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prologue_layer.z_index = 20
	prologue_layer.visible = false
	root.add_child(prologue_layer)

	prologue_shade = ColorRect.new()
	prologue_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prologue_shade.color = Color(0.018, 0.014, 0.011, 1.0)
	prologue_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prologue_layer.add_child(prologue_shade)

	prologue_stats = Label.new()
	prologue_stats.text = (
		"CLEAR DATA\n"
		+ "CHRONOSWORD\n\n"
		+ "LEVEL          50\n"
		+ "ATTACK     13,870\n"
		+ "ART            99\n"
		+ "EXPERIENCE      —"
	)
	prologue_stats.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	prologue_stats.position = Vector2(54.0, -154.0)
	prologue_stats.size = Vector2(390.0, 310.0)
	prologue_stats.add_theme_font_size_override("font_size", 22)
	prologue_stats.add_theme_color_override("font_color", Color(0.79, 0.75, 0.62))
	prologue_stats.add_theme_color_override("font_shadow_color", Color(0.025, 0.018, 0.012, 0.92))
	prologue_stats.add_theme_constant_override("shadow_offset_x", 3)
	prologue_stats.add_theme_constant_override("shadow_offset_y", 3)
	prologue_layer.add_child(prologue_stats)

	prologue_fragment = Label.new()
	prologue_fragment.set_anchors_preset(Control.PRESET_CENTER)
	prologue_fragment.position = Vector2(-430.0, 102.0)
	prologue_fragment.size = Vector2(860.0, 44.0)
	prologue_fragment.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prologue_fragment.add_theme_font_size_override("font_size", 17)
	prologue_fragment.add_theme_color_override("font_color", Color(0.67, 0.61, 0.49))
	prologue_fragment.add_theme_color_override("font_shadow_color", Color(0.02, 0.015, 0.01))
	prologue_fragment.add_theme_constant_override("shadow_offset_x", 3)
	prologue_fragment.add_theme_constant_override("shadow_offset_y", 3)
	prologue_fragment.visible = false
	prologue_layer.add_child(prologue_fragment)

	prologue_title = Label.new()
	prologue_title.text = "EPILOGUE"
	prologue_title.set_anchors_preset(Control.PRESET_CENTER)
	prologue_title.position = Vector2(-440.0, -98.0)
	prologue_title.size = Vector2(880.0, 86.0)
	prologue_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prologue_title.add_theme_font_size_override("font_size", 58)
	prologue_title.add_theme_color_override("font_color", Color(0.86, 0.81, 0.67))
	prologue_title.add_theme_color_override("font_shadow_color", Color(0.085, 0.037, 0.016, 0.92))
	prologue_title.add_theme_constant_override("shadow_offset_x", 6)
	prologue_title.add_theme_constant_override("shadow_offset_y", 6)
	prologue_title.visible = false
	prologue_layer.add_child(prologue_title)

	prologue_subtitle = Label.new()
	prologue_subtitle.text = "THE FIRST JOB"
	prologue_subtitle.set_anchors_preset(Control.PRESET_CENTER)
	prologue_subtitle.position = Vector2(-440.0, 4.0)
	prologue_subtitle.size = Vector2(880.0, 48.0)
	prologue_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prologue_subtitle.add_theme_font_size_override("font_size", 20)
	prologue_subtitle.add_theme_color_override("font_color", Color(0.60, 0.56, 0.47))
	prologue_subtitle.add_theme_color_override("font_shadow_color", Color(0.025, 0.018, 0.012))
	prologue_subtitle.add_theme_constant_override("shadow_offset_x", 3)
	prologue_subtitle.add_theme_constant_override("shadow_offset_y", 3)
	prologue_subtitle.visible = false
	prologue_layer.add_child(prologue_subtitle)

	prologue_skip = Label.new()
	prologue_skip.text = "SPACE TO SKIP"
	prologue_skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	prologue_skip.position = Vector2(-250.0, -54.0)
	prologue_skip.size = Vector2(220.0, 30.0)
	prologue_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prologue_skip.add_theme_font_size_override("font_size", 13)
	prologue_skip.add_theme_color_override("font_color", Color(0.62, 0.58, 0.48))
	prologue_skip.add_theme_color_override("font_shadow_color", Color.BLACK)
	prologue_skip.add_theme_constant_override("shadow_offset_x", 2)
	prologue_skip.add_theme_constant_override("shadow_offset_y", 2)
	prologue_layer.add_child(prologue_skip)


func _build_ending() -> void:
	ending_layer = Control.new()
	ending_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ending_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ending_layer.visible = false
	root.add_child(ending_layer)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.018, 0.014, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ending_layer.add_child(shade)

	ending_title = Label.new()
	ending_title.set_anchors_preset(Control.PRESET_CENTER)
	ending_title.position = Vector2(-440.0, -130.0)
	ending_title.size = Vector2(880.0, 90.0)
	ending_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending_title.add_theme_font_size_override("font_size", 48)
	ending_title.add_theme_color_override("font_color", Color(0.80, 0.74, 0.58))
	ending_layer.add_child(ending_title)

	ending_subtitle = Label.new()
	ending_subtitle.set_anchors_preset(Control.PRESET_CENTER)
	ending_subtitle.position = Vector2(-440.0, -20.0)
	ending_subtitle.size = Vector2(880.0, 220.0)
	ending_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending_subtitle.add_theme_font_size_override("font_size", 19)
	ending_subtitle.add_theme_color_override("font_color", Color(0.62, 0.59, 0.50))
	ending_layer.add_child(ending_subtitle)
