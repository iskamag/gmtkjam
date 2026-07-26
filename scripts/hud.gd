extends CanvasLayer

const HandsScript = preload("res://scripts/hands_2d.gd")

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

var announcement_time := 0.0
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

	if is_instance_valid(player):
		post_material.set_shader_parameter("impact", impact_pulse)
		post_material.set_shader_parameter("impact_origin", impact_origin)
		post_material.set_shader_parameter("wound", maxf(wound_pulse, player.wound_visual))
		post_material.set_shader_parameter("chronostep", player.chronostep_visual)
		post_material.set_shader_parameter(
			"dagger_rewind",
			1.0 if player.dagger_state == player.DaggerState.REWINDING else 0.0
		)
		objective.text = "LV 50  //  LAST JOB"
		if debug_visible:
			debug_label.text = (
				"PROTOTYPE TELEMETRY\n"
				+ "time        %06.2f\n" % player.time_left
				+ "maximum     %06.2f\n" % player.max_time
				+ "max eroded  %06.2f\n" % (player.STARTING_MAX_TIME - player.max_time)
				+ "watchfire   %06.2f\n" % player.watchfire
				+ "speed       %06.2f\n" % player.planar_speed
				+ "movement    %s\n" % ("SLIDE" if player.is_sliding else ("STEP" if player.chronostep_timer > 0.0 else "GROUND"))
				+ "hostile x   %06.2f\n\n" % (0.18 if player.watch_active else 1.0)
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

	# The entire opening is deliberately one continuous exposure change. The
	# crash reaches black once and releases once; there is no flash/strobe cut.
	var shade_alpha := 0.12
	if prologue_time < 0.72:
		shade_alpha = lerpf(1.0, 0.16, _smooth_range(prologue_time, 0.0, 0.72))
	elif prologue_time >= 5.42 and prologue_time < 5.78:
		shade_alpha = lerpf(0.12, 1.0, _smooth_range(prologue_time, 5.42, 5.78))
	elif prologue_time < 6.12 and prologue_time >= 5.78:
		shade_alpha = 1.0
	elif prologue_time < 6.88 and prologue_time >= 6.12:
		shade_alpha = lerpf(1.0, 0.12, _smooth_range(prologue_time, 6.12, 6.88))
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


func set_intro_effects(trauma: float, crash: float) -> void:
	intro_trauma_target = clampf(trauma, 0.0, 1.0)
	intro_crash_target = clampf(crash, 0.0, 1.0)


func begin_run() -> void:
	title_layer.visible = false
	crosshair.visible = true
	objective.visible = true
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
	objective.position = Vector2(26.0, 22.0)
	objective.size = Vector2(310.0, 80.0)
	objective.add_theme_font_size_override("font_size", 17)
	objective.add_theme_color_override("font_color", Color(0.70, 0.68, 0.57, 0.82))
	objective.add_theme_color_override("font_shadow_color", Color.BLACK)
	objective.add_theme_constant_override("shadow_offset_x", 2)
	objective.add_theme_constant_override("shadow_offset_y", 2)
	objective.visible = false
	root.add_child(objective)

	announcement = Label.new()
	announcement.set_anchors_preset(Control.PRESET_CENTER_TOP)
	announcement.position = Vector2(-340.0, 70.0)
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
	subtitle.position = Vector2(-340.0, 116.0)
	subtitle.size = Vector2(680.0, 38.0)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(0.66, 0.64, 0.55))
	subtitle.add_theme_color_override("font_shadow_color", Color.BLACK)
	subtitle.add_theme_constant_override("shadow_offset_x", 3)
	subtitle.add_theme_constant_override("shadow_offset_y", 3)
	subtitle.visible = false
	root.add_child(subtitle)

	_build_boss_bar()
	_build_title()
	_build_prologue()
	_build_ending()

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


func _build_boss_bar() -> void:
	boss_group = Control.new()
	boss_group.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_group.position = Vector2(-360.0, 24.0)
	boss_group.size = Vector2(720.0, 54.0)
	boss_group.visible = false
	root.add_child(boss_group)

	boss_label = Label.new()
	boss_label.text = "THE UNFINISHED  //  FIRST DEBT"
	boss_label.position = Vector2(0.0, 0.0)
	boss_label.size = Vector2(720.0, 24.0)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_font_size_override("font_size", 15)
	boss_label.add_theme_color_override("font_color", Color(0.74, 0.68, 0.53))
	boss_group.add_child(boss_label)

	boss_bar = ProgressBar.new()
	boss_bar.position = Vector2(0.0, 28.0)
	boss_bar.size = Vector2(720.0, 12.0)
	boss_bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.045, 0.04, 0.032, 0.92)
	background.border_color = Color(0.28, 0.25, 0.20)
	background.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.26, 0.09)
	boss_bar.add_theme_stylebox_override("background", background)
	boss_bar.add_theme_stylebox_override("fill", fill)
	boss_group.add_child(boss_bar)


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
