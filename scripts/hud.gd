extends CanvasLayer

const HandsScript = preload("res://scripts/hands_2d.gd")

var player: CharacterBody3D
var game: Node3D

var root: Control
var hands: Control
var post_rect: ColorRect
var post_material: ShaderMaterial
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

var announcement_time := 0.0
var event_log: Array[String] = []
var debug_visible := false
var impact_pulse := 0.0
var wound_pulse := 0.0
var impact_origin := Vector2(0.5, 0.5)


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


func begin_run() -> void:
	title_layer.visible = false
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
		ending_subtitle.text = "The job remains unfinished.\n\nR — rewind the day"


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

	var crosshair := Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-16.0, -25.0)
	crosshair.size = Vector2(32.0, 50.0)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size", 32)
	crosshair.add_theme_color_override("font_color", Color(0.79, 0.76, 0.62, 0.78))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
