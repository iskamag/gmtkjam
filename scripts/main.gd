extends Node3D

signal score_event(tag: StringName, payload: Dictionary)

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HudScript = preload("res://scripts/hud.gd")
const WorldAestheticScript = preload("res://scripts/world_aesthetic.gd")
const PackNightShader = preload("res://shaders/pack_night_material.gdshader")

var player: CharacterBody3D
var hud: CanvasLayer
var enemies_root: Node3D
var active_enemies: Array[Node] = []

var started := false
var run_finished := false
var boss_defeated := false
var wave := 0
var encounter_index := -1
var encounter_active := false
var encounter_resolving := false
var encounter_gates: Array[StaticBody3D] = []
var encounter_definitions: Array[Dictionary] = []
var deterioration := 0.0
var world_environment_resource: Environment
var ghost_materials: Array[ShaderMaterial] = []
var impact_level := 0.0
var wound_level := 0.0
var hitstop_until_msec := 0
var damage_number_serial := 0

var prologue_active := false
var prologue_time := 0.0
var prologue_flags: Dictionary = {}
var prologue_shell: Node3D
var prologue_window_motion: Node3D
var next_train_tick := 0.0
var prologue_look_yaw := 0.0
var prologue_look_pitch := 0.0


func _ready() -> void:
	_ensure_input_actions()
	_build_world()
	_build_level()
	_build_encounter_definitions()

	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)

	player = PlayerScript.new()
	player.name = "Chronosword"
	add_child(player)
	player.global_position = Vector3(0.0, 0.05, 16.0)
	player.expired.connect(_on_player_expired)
	player.rewound_wound.connect(_on_player_rewound)
	player.attack_landed.connect(_on_attack_landed)
	player.score_event.connect(_forward_score_event)

	hud = HudScript.new()
	hud.name = "Presentation"
	add_child(hud)
	hud.bind(player, self)
	score_event.connect(hud.receive_score_event)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_active(false)
	emit_signal("score_event", &"boot", {"room": "return_road"})


func _process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(hud):
		return

	_update_deterioration(delta)
	hud.set_effects(
		1.0 - player.time_left / max(player.max_time, 0.001),
		1.0 - player.max_time / player.STARTING_MAX_TIME,
		player.wound_visual,
		player.watchfire / player.MAX_WATCHFIRE
	)

	_update_hitstop()
	impact_level = maxf(impact_level - delta * 5.8, 0.0)
	wound_level = maxf(wound_level - delta * 3.7, 0.0)
	if prologue_active:
		_update_prologue(delta)
	elif started and not run_finished and not boss_defeated:
		_update_encounter_triggers()


func _unhandled_input(event: InputEvent) -> void:
	if (
		prologue_active
		and event is InputEventMouseMotion
	):
		prologue_look_yaw = wrapf(
			prologue_look_yaw - event.relative.x * 0.00225,
			-PI,
			PI
		)
		prologue_look_pitch = clampf(
			prologue_look_pitch - event.relative.y * 0.0021,
			-1.10,
			1.05
		)
		player.pitch = prologue_look_pitch
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		if not started and not run_finished:
			_begin_prologue()
			get_viewport().set_input_as_handled()
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return

	if prologue_active and event.is_action_pressed("jump") and prologue_time > 1.0:
		_finish_prologue()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

	if event.is_action_pressed("restart") and run_finished:
		get_tree().reload_current_scene()


func _begin_prologue() -> void:
	started = true
	prologue_active = true
	prologue_time = 0.0
	prologue_flags.clear()
	next_train_tick = 0.0
	prologue_look_yaw = 0.0
	prologue_look_pitch = -0.035
	run_finished = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_active(false)
	# Begin seated off-centre near the rear of the carriage. This gives the
	# player a composed view down the aisle, but mouse look is never taken away.
	player.global_position = Vector3(0.12, 0.05, 18.05)
	player.rotation = Vector3.ZERO
	player.pitch = prologue_look_pitch
	player.camera.position = Vector3(0.0, 1.31, 0.0)
	player.camera.rotation = Vector3(prologue_look_pitch, 0.0, 0.0)
	player.camera.fov = 73.0
	if is_instance_valid(prologue_shell):
		prologue_shell.visible = true
		prologue_shell.position = Vector3(0.0, 0.0, 16.0)
		prologue_shell.rotation = Vector3.ZERO
	hud.begin_prologue()
	emit_signal("score_event", &"intro_black", {})
	emit_signal("score_event", &"train_rhythm", {"state": "enter"})


func _update_prologue(delta: float) -> void:
	prologue_time += delta
	hud.update_prologue(prologue_time)

	if prologue_time >= next_train_tick and prologue_time < 5.55:
		player.play_sfx(&"train")
		next_train_tick += 0.64 if prologue_time < 4.35 else 0.46

	_update_prologue_exterior()

	# Mouse look is the base orientation. Rail movement and the crash are only
	# additive offsets, so the cutscene never wrestles the view away.
	player.rotation.y = prologue_look_yaw
	var camera_position := Vector3(
		sin(prologue_time * 1.74) * 0.005,
		1.31 + sin(prologue_time * 9.35) * 0.006,
		0.0
	)
	var camera_pitch_offset := sin(prologue_time * 0.79) * 0.0035
	var camera_roll := sin(prologue_time * 0.91) * 0.0025

	if prologue_time >= 2.1 and not prologue_flags.has("stats"):
		prologue_flags["stats"] = true
		emit_signal("score_event", &"status_reveal", {
			"level": 50,
			"attack": 13870,
			"art": 99,
		})
	if prologue_time >= 3.7 and not prologue_flags.has("memory"):
		prologue_flags["memory"] = true
		player.play_sfx(&"memory")
		emit_signal("score_event", &"memory_intrusion", {"layer": 1})
	if prologue_time >= 4.62 and not prologue_flags.has("premonition"):
		prologue_flags["premonition"] = true
		player.play_sfx(&"watch")
		emit_signal("score_event", &"crash_premonition", {})
	if prologue_time >= 5.24 and not prologue_flags.has("first_jolt"):
		prologue_flags["first_jolt"] = true
		player.play_sfx(&"wound")
		emit_signal("score_event", &"crash_premonition", {"impact": 1})
	if prologue_time >= 5.48 and not prologue_flags.has("crash"):
		prologue_flags["crash"] = true
		player.play_sfx(&"crash")
		player.play_sfx(&"wound")
		player.wound_visual = 1.0
		player.watch_previous_time = player.STARTING_MAX_TIME
		hud.set_intro_effects(1.0, 1.0)
		emit_signal("score_event", &"crash_hit", {})
	if prologue_time >= 5.78 and not prologue_flags.has("secondary_impact"):
		prologue_flags["secondary_impact"] = true
		player.play_sfx(&"crash")
	if prologue_time >= 6.08 and not prologue_flags.has("final_impact"):
		prologue_flags["final_impact"] = true
		player.play_sfx(&"train")

	if prologue_time >= 5.24 and prologue_time < 6.34:
		var crash_phase := clampf((prologue_time - 5.24) / 1.10, 0.0, 1.0)
		var crash_ease := crash_phase * crash_phase * (3.0 - 2.0 * crash_phase)
		var judder := sin(crash_phase * PI * 8.0) * (1.0 - crash_phase)
		if is_instance_valid(prologue_shell):
			prologue_shell.rotation = Vector3(
				-crash_ease * 0.13 + judder * 0.025,
				crash_ease * 0.08,
				crash_ease * 0.31 + judder * 0.045
			)
			prologue_shell.position = Vector3(
				judder * 0.08,
				-crash_ease * 0.46,
				16.0 - crash_ease * 0.16
			)
		camera_position += Vector3(
			-crash_ease * 0.24 + judder * 0.085,
			-crash_ease * 0.38 + absf(judder) * 0.045,
			-crash_ease * 0.15
		)
		camera_pitch_offset += crash_ease * 0.18 + judder * 0.035
		camera_roll += -crash_ease * 0.37 + judder * 0.075
	elif prologue_time >= 6.34:
		if not prologue_flags.has("aftermath"):
			prologue_flags["aftermath"] = true
			player.global_position = Vector3(0.0, 0.05, 16.0)
		if is_instance_valid(prologue_shell):
			prologue_shell.visible = false
		var recovery := clampf((prologue_time - 6.34) / 2.85, 0.0, 1.0)
		var recovery_ease := 1.0 - pow(1.0 - recovery, 3.0)
		camera_position = Vector3(
			lerpf(-0.19, 0.0, recovery_ease),
			lerpf(0.72, 1.55, recovery_ease),
			lerpf(-0.08, 0.0, recovery_ease)
		)
		camera_pitch_offset += lerpf(0.12, 0.0, recovery_ease)
		camera_roll += lerpf(-0.31, 0.0, recovery_ease)
		hud.set_intro_effects(
			1.0 - recovery,
			maxf(0.0, 1.0 - (prologue_time - 5.48) * 3.3)
		)

	player.camera.position = camera_position
	player.camera.rotation = Vector3(
		clampf(prologue_look_pitch + camera_pitch_offset, -1.22, 1.12),
		0.0,
		camera_roll
	)

	if prologue_time >= 7.82 and not prologue_flags.has("epilogue"):
		prologue_flags["epilogue"] = true
		emit_signal("score_event", &"title_epilogue", {"chapter": "the_first_job"})

	if prologue_time >= 9.55:
		_finish_prologue()


func _finish_prologue() -> void:
	if not prologue_active:
		return
	prologue_active = false
	if is_instance_valid(prologue_shell):
		prologue_shell.visible = false
	player.global_position = Vector3(0.0, 0.05, 16.0)
	player.rotation = Vector3.ZERO
	player.pitch = 0.0
	player.camera.position = Vector3(0.0, 1.55, 0.0)
	player.camera.rotation = Vector3.ZERO
	player.camera.fov = 79.0
	player.set_active(true)
	hud.set_intro_effects(0.0, 0.0)
	hud.end_prologue()
	hud.announce("EPILOGUE", "THE FIRST JOB", 2.1)
	emit_signal("score_event", &"control_return", {"time": player.time_left})
	emit_signal("score_event", &"run_started", {"time": player.time_left})


func _start_run() -> void:
	started = true
	run_finished = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_active(true)
	hud.begin_run()
	emit_signal("score_event", &"run_started", {"time": player.time_left})


func _update_encounter_triggers() -> void:
	if encounter_active or encounter_resolving:
		return
	var next_index := encounter_index + 1
	if next_index >= encounter_definitions.size():
		return
	var definition := encounter_definitions[next_index]
	if player.global_position.z <= float(definition["trigger_z"]):
		_start_encounter(next_index)


func _start_encounter(index: int) -> void:
	if index < 0 or index >= encounter_definitions.size():
		return
	encounter_index = index
	wave = index + 1
	encounter_active = true
	var definition := encounter_definitions[index]
	hud.announce(String(definition["title"]), String(definition["subtitle"]), 1.55)
	var spawn_sequence: Array = definition["spawns"]
	for spawn_index in spawn_sequence.size():
		var spawn_data: Array = spawn_sequence[spawn_index]
		_spawn_enemy(spawn_data[0], spawn_data[1], float(spawn_index) * 0.22)
	var tag: StringName = &"boss_started" if index == encounter_definitions.size() - 1 else &"encounter_started"
	emit_signal("score_event", tag, {
		"room": index + 1,
		"threat": definition["threat"],
	})


func _complete_encounter(index: int) -> void:
	if index != encounter_index or run_finished:
		return
	encounter_active = false
	encounter_resolving = false
	if index < encounter_gates.size():
		_open_gate(encounter_gates[index])
		hud.announce(
			"PASSAGE %02d RELEASED" % (index + 1),
			"Your clock did not stop.",
			1.1
		)
	emit_signal("score_event", &"encounter_cleared", {
		"room": index + 1,
		"time": player.time_left,
		"maximum": player.max_time,
	})


func _build_encounter_definitions() -> void:
	encounter_definitions = [
			{
				"trigger_z": 13.0,
				"title": "THE ARREARS",
				"subtitle": "The train brought an old collector with it.",
			"threat": 0.35,
			"spawns": [
				[Vector3(-3.7, 0.05, 5.5), EnemyScript.Kind.MELEE],
				[Vector3(5.0, 0.05, 0.0), EnemyScript.Kind.RANGED],
			],
		},
			{
				"trigger_z": -7.0,
				"title": "THE SIGNAL WITNESS",
				"subtitle": "Read the timetable. Break the buried guard.",
			"threat": 0.70,
			"spawns": [
				[Vector3(-6.3, 0.05, -10.0), EnemyScript.Kind.RANGED],
				[Vector3(5.6, 0.05, -14.0), EnemyScript.Kind.MELEE],
				[Vector3(-1.7, 0.05, -17.8), EnemyScript.Kind.ELITE],
			],
		},
			{
				"trigger_z": -22.0,
				"title": "THE UNFINISHED",
				"subtitle": "The first thing you postponed rises to meet the last.",
			"threat": 1.0,
			"spawns": [
				[Vector3(0.0, 0.05, -28.0), EnemyScript.Kind.BOSS],
			],
		},
	]


func _spawn_enemy(at: Vector3, kind: int, manifest_delay: float = 0.0) -> void:
	var enemy := EnemyScript.new()
	enemy.kind = kind
	enemy.player = player
	enemy.game = self
	enemies_root.add_child(enemy)
	enemy.global_position = at
	enemy.died.connect(_on_enemy_died)
	enemy.damaged.connect(_on_enemy_damaged.bind(enemy))
	enemy.phase_changed.connect(_on_boss_phase)
	active_enemies.append(enemy)
	if enemy.has_method("begin_manifest"):
		enemy.begin_manifest(
			manifest_delay,
			4.2 if kind == EnemyScript.Kind.BOSS else (1.8 if kind == EnemyScript.Kind.ELITE else 0.75)
		)
	if kind == EnemyScript.Kind.BOSS:
		hud.show_boss(enemy.maximum_health)


func _on_enemy_damaged(amount: int, world_position: Vector3, critical: bool, enemy: Node) -> void:
	_spawn_damage_number(amount, world_position, critical)
	if is_instance_valid(enemy) and enemy.kind == EnemyScript.Kind.BOSS:
		hud.set_boss_health(enemy.health, enemy.maximum_health)


func _on_enemy_died(enemy: Node, reward: float, was_boss: bool) -> void:
	active_enemies.erase(enemy)
	spawn_burst(enemy.global_position + Vector3.UP, Color(0.83, 0.75, 0.57), 9 if not was_boss else 24)

	if was_boss:
		boss_defeated = true
		encounter_active = false
		hud.hide_boss()
		for remainder in active_enemies.duplicate():
			if is_instance_valid(remainder):
				remainder.vanish()
		active_enemies.clear()
		player.restore_time(player.max_time)
		player.gain_watchfire(player.MAX_WATCHFIRE)
		hud.announce("LAST JOB COMPLETE", "There is nothing left to kill.")
		emit_signal("score_event", &"boss_defeated", {"time_remaining": player.time_left})
		return

	player.restore_time(reward)
	player.gain_watchfire(16.0)
	emit_signal("score_event", &"enemy_eliminated", {
		"reward": reward,
		"time": player.time_left,
		"remaining": active_enemies.size(),
	})
	if active_enemies.is_empty() and encounter_active and not encounter_resolving:
		encounter_resolving = true
		var completed_index := encounter_index
		get_tree().create_timer(0.58).timeout.connect(_complete_encounter.bind(completed_index))


func _on_boss_phase(phase: int) -> void:
	hud.announce("THE UNFINISHED — PHASE %d" % phase, "Keep the hand moving")
	emit_signal("score_event", &"boss_phase", {"phase": phase, "player_time": player.time_left})
	if phase == 2:
		_spawn_enemy(Vector3(-7.0, 0.05, -20.0), EnemyScript.Kind.MELEE, 0.2)
	elif phase == 3:
		_spawn_enemy(Vector3(7.0, 0.05, -20.0), EnemyScript.Kind.RANGED, 0.2)


func _on_player_expired() -> void:
	if run_finished:
		return
	run_finished = true
	player.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.set_process_mode(Node.PROCESS_MODE_DISABLED)
	hud.show_ending(boss_defeated)
	emit_signal("score_event", &"time_expired", {
		"job_complete": boss_defeated,
		"maximum_remaining": player.max_time,
	})


func _on_player_rewound(seconds_spent: float, maximum_lost: float) -> void:
	emit_signal("score_event", &"wound_rewound", {
		"cost": seconds_spent,
		"scar": maximum_lost,
		"time": player.time_left,
		"maximum": player.max_time,
	})


func _on_attack_landed(amount: int, critical: bool) -> void:
	emit_signal("score_event", &"player_hit_confirmed", {
		"damage": amount,
		"critical": critical,
		"watchfire": player.watchfire,
	})


func _forward_score_event(tag: StringName, payload: Dictionary) -> void:
	emit_signal("score_event", tag, payload)


func get_hostile_time_scale() -> float:
	if is_instance_valid(player) and player.watch_active:
		return 0.18
	return 1.0


func request_impact(strength: float, at: Vector3) -> void:
	impact_level = maxf(impact_level, strength)
	var screen_position := Vector2(0.5, 0.5)
	if is_instance_valid(player) and is_instance_valid(player.camera):
		var pixels: Vector2 = player.camera.unproject_position(at)
		var viewport_size := get_viewport().get_visible_rect().size
		if viewport_size.x > 0.0 and viewport_size.y > 0.0:
			screen_position = Vector2(pixels.x / viewport_size.x, pixels.y / viewport_size.y)
	if is_instance_valid(hud) and hud.has_method("pulse_impact"):
		hud.pulse_impact(strength, screen_position)
	var freeze_msec := int(18.0 + strength * 28.0)
	hitstop_until_msec = maxi(hitstop_until_msec, Time.get_ticks_msec() + freeze_msec)
	Engine.time_scale = 0.10 if strength < 0.85 else 0.035
	spawn_burst(at, Color(0.84, 0.76, 0.55), 5 if strength < 0.85 else 9)
	_spawn_time_cut(at, strength)


func request_wound_effect(source_position: Vector3) -> void:
	wound_level = 1.0
	hitstop_until_msec = maxi(hitstop_until_msec, Time.get_ticks_msec() + 34)
	Engine.time_scale = 0.12
	if is_instance_valid(hud) and hud.has_method("pulse_wound"):
		var side := clampf((source_position.x - player.global_position.x) / 10.0, -1.0, 1.0)
		hud.pulse_wound(side)


func _update_hitstop() -> void:
	if hitstop_until_msec <= 0:
		return
	if Time.get_ticks_msec() >= hitstop_until_msec:
		hitstop_until_msec = 0
		Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func spawn_time_echo(at_transform: Transform3D) -> void:
	var echo := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 1.8, 0.06)
	echo.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.32, 0.25, 0.36, 0.30)
	material.emission_enabled = true
	material.emission = Color(0.23, 0.16, 0.28)
	material.emission_energy_multiplier = 0.32
	echo.material_override = material
	add_child(echo)
	echo.global_transform = at_transform
	echo.position.y += 0.9
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(echo, "scale", Vector3(1.7, 0.82, 1.0), 0.26)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.26)
	tween.tween_property(material, "emission_energy_multiplier", 0.0, 0.26)
	tween.set_parallel(false)
	tween.tween_callback(echo.queue_free)


func _spawn_time_cut(at: Vector3, strength: float) -> void:
	var cut := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.3 + strength * 1.5, 0.045 + strength * 0.035)
	cut.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.92, 0.82, 0.58, 0.82)
	material.emission_enabled = true
	material.emission = Color(0.58, 0.45, 0.27)
	material.emission_energy_multiplier = 1.1
	cut.material_override = material
	add_child(cut)
	cut.global_position = at
	if is_instance_valid(player):
		cut.look_at(player.camera.global_position, Vector3.UP)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(cut, "scale", Vector3(2.6, 0.2, 1.0), 0.16)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.16)
	tween.set_parallel(false)
	tween.tween_callback(cut.queue_free)


func spawn_burst(at: Vector3, color: Color, count: int = 8) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	for index in count:
		var shard := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.06, 0.06, 0.32 + float(index % 3) * 0.08)
		shard.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color * 0.5
		material.roughness = 0.7
		shard.material_override = material
		root.add_child(shard)
		var angle := TAU * float(index) / float(max(count, 1))
		var target := Vector3(cos(angle), 0.25 + float(index % 4) * 0.18, sin(angle)) * (1.2 + float(index % 3))
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", target, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "rotation", Vector3(angle * 0.4, angle, angle * 0.7), 0.42)
		tween.tween_property(shard, "scale", Vector3.ZERO, 0.42).set_delay(0.16)
	get_tree().create_timer(0.7).timeout.connect(root.queue_free)


func _spawn_damage_number(amount: int, at: Vector3, critical: bool) -> void:
	damage_number_serial += 1
	var label := Label3D.new()
	label.text = _format_damage(amount) + ("!" if critical else "")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.font_size = 88 if not critical else 108
	label.pixel_size = 0.00265
	label.outline_size = 12
	label.modulate = Color(0.89, 0.85, 0.72) if not critical else Color(0.62, 0.29, 0.22)
	label.outline_modulate = Color(0.025, 0.021, 0.016, 0.95)
	label.no_depth_test = false
	add_child(label)
	var lane := -1.0 if damage_number_serial % 2 == 0 else 1.0
	var camera_right := Vector3.RIGHT
	if is_instance_valid(player) and is_instance_valid(player.camera):
		camera_right = player.camera.global_transform.basis.x
	label.global_position = at + camera_right * lane * 0.15
	label.scale = Vector3.ONE * 0.68

	var target := label.global_position + Vector3.UP * (1.05 if not critical else 1.22) + camera_right * lane * 0.24
	var drift := create_tween()
	drift.set_parallel(true)
	drift.tween_property(label, "global_position", target, 0.66).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	drift.tween_property(label, "modulate:a", 0.0, 0.30).set_delay(0.36)
	drift.set_parallel(false)
	drift.tween_callback(label.queue_free)

	var pop := create_tween()
	pop.tween_property(label, "scale", Vector3.ONE * (1.23 if critical else 1.14), 0.055).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "scale", Vector3.ONE, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _format_damage(amount: int) -> String:
	var digits := str(maxi(amount, 0))
	var formatted := ""
	while digits.length() > 3:
		formatted = "," + digits.right(3) + formatted
		digits = digits.left(digits.length() - 3)
	return digits + formatted


func _build_world() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.016, 0.017)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.25, 0.285, 0.27)
	environment.ambient_light_energy = 0.62
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.62
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 0.94
	environment.glow_hdr_scale = 1.38
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.92
	environment.adjustment_contrast = 1.16
	environment.adjustment_saturation = 0.78
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.065, 0.078, 0.072)
	environment.fog_light_energy = 0.52
	environment.fog_density = 0.016
	environment.fog_sky_affect = 0.9
	world_environment_resource = environment
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-47.0, -33.0, 0.0)
	sun.light_color = Color(0.51, 0.56, 0.52)
	sun.light_energy = 0.74
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	for data in [
		[Vector3(-11.0, 3.5, 4.0), Color(0.38, 0.32, 0.23), 3.2],
		[Vector3(10.0, 2.5, -17.0), Color(0.28, 0.30, 0.27), 2.8],
		[Vector3(0.0, 5.5, -31.0), Color(0.42, 0.29, 0.18), 4.4],
	]:
		var light := OmniLight3D.new()
		light.position = data[0]
		light.light_color = data[1]
		light.light_energy = data[2]
		light.omni_range = 13.0
		light.shadow_enabled = false
		add_child(light)


func _build_level() -> void:
	var asphalt := Color(0.075, 0.079, 0.078)
	var concrete := Color(0.22, 0.22, 0.205)
	var soot := Color(0.105, 0.105, 0.10)
	var rust := Color(0.25, 0.145, 0.075)
	var old_gold := Color(0.37, 0.31, 0.19)

	# A road through a ruined transit-ritual court: open sky, modern service
	# infrastructure, and an older ceremonial axis underneath it.
	_add_static_box(Vector3(0.0, -0.5, -7.0), Vector3(19.0, 1.0, 58.0), asphalt)
	_add_static_box(Vector3(-13.0, -0.25, -7.0), Vector3(7.0, 0.5, 58.0), concrete)
	_add_static_box(Vector3(13.0, -0.25, -7.0), Vector3(7.0, 0.5, 58.0), concrete)
	_add_static_box(Vector3(-16.8, 0.8, -7.0), Vector3(0.8, 1.6, 58.0), soot)
	_add_static_box(Vector3(16.8, 0.8, -7.0), Vector3(0.8, 1.6, 58.0), soot)
	_add_static_box(Vector3(0.0, 0.6, -36.0), Vector3(34.0, 1.2, 1.0), soot)

	# Worn meridian inlay, broken into segments rather than a glowing runway.
	for z in range(17, -33, -5):
		_add_visual_box(Vector3(0.0, 0.012, float(z)), Vector3(0.17, 0.025, 2.6), old_gold)
		if z % 10 != 2:
			_add_visual_box(Vector3(-2.4, 0.014, float(z) - 0.5), Vector3(2.2, 0.022, 0.11), old_gold)

	# Low cover creates combat lanes while preserving sight of the final arch.
	for obstacle in [
		[Vector3(-6.8, 0.72, 3.0), Vector3(2.8, 1.45, 1.2), rust],
		[Vector3(7.0, 0.52, -5.5), Vector3(3.4, 1.05, 1.4), soot],
		[Vector3(-7.4, 0.58, -15.0), Vector3(2.7, 1.15, 2.8), soot],
		[Vector3(7.6, 0.74, -22.0), Vector3(2.4, 1.48, 3.2), rust],
	]:
		_add_static_box(obstacle[0], obstacle[1], obstacle[2])

	# The gate is visibly fantasy-shaped, but braced with utility metal.
	_add_static_box(Vector3(-7.0, 4.0, -32.0), Vector3(3.0, 8.0, 2.2), concrete)
	_add_static_box(Vector3(7.0, 4.0, -32.0), Vector3(3.0, 8.0, 2.2), concrete)
	_add_static_box(Vector3(0.0, 8.0, -32.0), Vector3(11.0, 2.0, 2.2), concrete)
	_add_static_box(Vector3(0.0, 9.3, -32.0), Vector3(2.6, 0.7, 2.5), rust)

	for prop in [
		["res://assets/kenney/crate-color.glb", Vector3(-12.5, 0.0, 7.0), Vector3(2.0, 2.0, 2.0), Vector3(0.0, 0.4, 0.0), rust],
		["res://assets/kenney/crate-color.glb", Vector3(12.2, 0.0, -10.0), Vector3(2.3, 2.3, 2.3), Vector3(0.0, -0.3, 0.0), rust],
		["res://assets/kenney/pipe.glb", Vector3(-16.0, 2.2, -5.0), Vector3(2.0, 5.0, 2.0), Vector3(0.0, 0.0, PI * 0.5), soot],
		["res://assets/kenney/pipe-corner.glb", Vector3(15.6, 2.0, -24.0), Vector3(2.0, 2.0, 2.0), Vector3(0.0, PI, 0.0), soot],
		["res://assets/kenney/weapon-sword.glb", Vector3(0.0, 0.1, -29.0), Vector3(4.2, 4.2, 4.2), Vector3(0.0, 0.0, PI), Color(0.16, 0.16, 0.145)],
	]:
		_add_asset(prop[0], prop[1], prop[2], prop[3], prop[4])

	# The locally supplied apocalypse kit turns the abstract road into one
	# specific familiar town. Every call is optional; the authored collision
	# and procedural dressing above remain a playable fallback.
	_add_optional_pack_asset(
		"res://assets/user_pack/SM_Train_Speed_Derailment_Apocalypse.fbx",
		Vector3(-9.2, 0.02, 18.2),
		Vector3.ONE,
		Vector3(-0.06, 1.26, 0.13),
		Color(0.74, 0.70, 0.61)
	)
	_add_optional_pack_asset(
		"res://assets/user_pack/SM_Building_House_Modern_Apocalypse_A.fbx",
		Vector3(-14.8, 0.0, -7.0),
		Vector3.ONE * 1.12,
		Vector3(0.0, 0.58, 0.0),
		Color(0.60, 0.59, 0.53)
	)
	_add_optional_pack_asset(
		"res://assets/user_pack/SM_Building_Cafe_Apocalypse.fbx",
		Vector3(14.2, 0.0, -20.0),
		Vector3.ONE * 1.05,
		Vector3(0.0, -0.64, 0.0),
		Color(0.60, 0.57, 0.49)
	)
	# The pack's "rail tile" includes a 30-metre terrain slab, so the route uses
	# authored rails instead of allowing that atlas-green slab to cover the road.
	for rail_x in [-11.55, -10.15]:
		_add_visual_box(
			Vector3(rail_x, 0.09, -3.0),
			Vector3(0.13, 0.14, 41.0),
			Color(0.25, 0.22, 0.18)
		)
	for sleeper_z in range(16, -24, -2):
		_add_visual_box(
			Vector3(-10.85, 0.045, float(sleeper_z)),
			Vector3(2.4, 0.09, 0.22),
			Color(0.19, 0.13, 0.09)
		)
	for rubble_data in [
		[Vector3(-7.7, 0.0, 11.3), Vector3(0.9, 0.9, 0.9), 0.4],
		[Vector3(10.7, 0.0, -3.6), Vector3(1.2, 1.2, 1.2), -0.8],
		[Vector3(-10.2, 0.0, -23.6), Vector3(1.4, 1.4, 1.4), 1.1],
	]:
		_add_optional_pack_asset(
			"res://assets/user_pack/SM_Rubble_Concrete_Apocalypse_A.fbx",
			rubble_data[0],
			rubble_data[1],
			Vector3(0.0, rubble_data[2], 0.0),
			Color(0.58, 0.56, 0.50)
		)
	for lamp_data in [
		[Vector3(-9.0, 0.0, 4.0), 0.15],
		[Vector3(9.2, 0.0, -10.0), PI + 0.1],
		[Vector3(-9.2, 0.0, -23.0), -0.08],
	]:
		_add_optional_pack_asset(
			"res://assets/user_pack/SM_Lamp_Road_Apocalypse_A.fbx",
			lamp_data[0],
			Vector3.ONE,
			Vector3(0.0, lamp_data[1], 0.0),
			Color(0.52, 0.50, 0.43)
		)

	# These fragments are the place at a different age. Permanent wounds and
	# completed encounters make them increasingly legible.
	_add_ghost_box(Vector3(0.0, 0.14, 5.0), Vector3(15.0, 0.28, 3.5), Color(0.24, 0.20, 0.27))
	_add_ghost_box(Vector3(-5.8, 3.2, -10.0), Vector3(1.25, 6.4, 1.25), Color(0.24, 0.20, 0.27))
	_add_ghost_box(Vector3(5.8, 3.2, -10.0), Vector3(1.25, 6.4, 1.25), Color(0.24, 0.20, 0.27))
	_add_ghost_box(Vector3(0.0, 6.1, -10.0), Vector3(10.4, 1.0, 1.25), Color(0.24, 0.20, 0.27))
	_add_ghost_asset("res://assets/kenney/figurine.glb", Vector3(-3.7, 0.0, -18.0), Vector3(1.45, 1.45, 1.45), Vector3.ZERO)
	_add_ghost_asset("res://assets/kenney/figurine.glb", Vector3(3.7, 0.0, -18.0), Vector3(1.45, 1.45, 1.45), Vector3.ZERO)

	encounter_gates.append(_create_encounter_gate(-5.0))
	encounter_gates.append(_create_encounter_gate(-21.0))
	var art_direction := WorldAestheticScript.new()
	art_direction.name = "ReturnRoadArtDirection"
	add_child(art_direction)
	_build_prologue_shell()


func _build_prologue_shell() -> void:
	prologue_shell = Node3D.new()
	prologue_shell.name = "LastServiceCarriage"
	prologue_shell.position = Vector3(0.0, 0.0, 16.0)
	add_child(prologue_shell)

	var upholstery := Color(0.255, 0.125, 0.070)
	var upholstery_wear := Color(0.37, 0.205, 0.092)
	var train_metal := Color(0.37, 0.355, 0.305)
	var inner_metal := Color(0.19, 0.18, 0.155)
	var tarnished_brass := Color(0.44, 0.33, 0.15)
	var tunnel_black := Color(0.012, 0.016, 0.017)

	# A complete carriage volume. The end bulkheads are intentionally opaque:
	# before the wreck, no angle can expose the combat level outside.
	_add_child_visual_box(prologue_shell, Vector3(0.0, -0.08, 0.0), Vector3(5.5, 0.16, 10.6), inner_metal, 0.66, 0.34)
	_add_child_visual_box(prologue_shell, Vector3(0.0, 3.18, 0.0), Vector3(4.8, 0.16, 10.6), inner_metal, 0.62, 0.38)
	_add_child_visual_box(prologue_shell, Vector3(-2.52, 2.91, 0.0), Vector3(0.55, 0.52, 10.6), train_metal.darkened(0.18), 0.58, 0.42)
	_add_child_visual_box(prologue_shell, Vector3(2.52, 2.91, 0.0), Vector3(0.55, 0.52, 10.6), train_metal.darkened(0.18), 0.58, 0.42)
	_add_child_visual_box(prologue_shell, Vector3(0.0, 1.55, -5.18), Vector3(5.5, 3.25, 0.18), train_metal, 0.62, 0.35)
	_add_child_visual_box(prologue_shell, Vector3(0.0, 1.55, 5.18), Vector3(5.5, 3.25, 0.18), train_metal.darkened(0.08), 0.62, 0.35)
	_add_child_visual_box(
		prologue_shell,
		Vector3(0.0, 0.012, 0.0),
		Vector3(1.58, 0.022, 9.65),
		Color(0.13, 0.12, 0.105),
		0.97,
		0.0
	)
	for floor_seam_z in [-3.2, -1.6, 0.0, 1.6, 3.2]:
		_add_child_visual_box(
			prologue_shell,
			Vector3(0.0, 0.026, floor_seam_z),
			Vector3(1.54, 0.012, 0.022),
			Color(0.34, 0.29, 0.19),
			0.78,
			0.18
		)

	# Recessed end doors and their battered ceremonial route marks.
	for end_z in [-5.075, 5.075]:
		_add_child_visual_box(prologue_shell, Vector3(0.0, 1.48, end_z), Vector3(1.82, 2.68, 0.035), inner_metal, 0.58, 0.40)
		_add_child_visual_box(prologue_shell, Vector3(-0.97, 1.48, end_z), Vector3(0.06, 2.76, 0.055), tarnished_brass, 0.48, 0.62)
		_add_child_visual_box(prologue_shell, Vector3(0.97, 1.48, end_z), Vector3(0.06, 2.76, 0.055), tarnished_brass, 0.48, 0.62)
		_add_child_emissive_box(
			prologue_shell,
			Vector3(0.0, 2.48, end_z - signf(end_z) * 0.021),
			Vector3(0.56, 0.055, 0.028),
			Color(0.48, 0.29, 0.12),
			0.72
		)

	# Side walls are built around real window openings rather than hiding an
	# unbroken wall behind black rectangles.
	for side in [-1.0, 1.0]:
		_add_child_visual_box(
			prologue_shell,
			Vector3(side * 2.69, 0.42, 0.0),
			Vector3(0.17, 0.94, 10.6),
			train_metal.darkened(0.08)
		)
		_add_child_visual_box(
			prologue_shell,
			Vector3(side * 2.69, 2.76, 0.0),
			Vector3(0.17, 0.84, 10.6),
			train_metal.darkened(0.15)
		)
		for pillar_z in [-5.0, -2.55, 0.0, 2.55, 5.0]:
			_add_child_visual_box(
				prologue_shell,
				Vector3(side * 2.69, 1.62, pillar_z),
				Vector3(0.19, 1.52, 0.22),
				inner_metal
			)
		for window_z in [-3.78, -1.28, 1.28, 3.78]:
			_add_child_glass_box(
				prologue_shell,
				Vector3(side * 2.71, 1.63, window_z),
				Vector3(0.025, 1.31, 2.17)
			)
			# Thin reflected tubes make the windows read as glass while the
			# dedicated tunnel remains visible through them.
			_add_child_emissive_box(
				prologue_shell,
				Vector3(side * 2.665, 1.92, window_z - side * 0.42),
				Vector3(0.018, 0.42, 0.026),
				Color(0.42, 0.40, 0.33),
				0.34
			)

	for light_z in [-3.65, -1.22, 1.22, 3.65]:
		_add_child_emissive_box(
			prologue_shell,
			Vector3(0.0, 3.055, light_z),
			Vector3(2.3, 0.045, 0.22),
			Color(0.82, 0.77, 0.62),
			2.05
		)
		var practical := OmniLight3D.new()
		practical.position = Vector3(0.0, 2.72, light_z)
		practical.light_color = Color(0.83, 0.79, 0.67)
		practical.light_energy = 3.55
		practical.omni_range = 5.2
		practical.shadow_enabled = false
		prologue_shell.add_child(practical)

	# One low fill makes the seat fabric, scratched rails, and abandoned case
	# readable from the starting position. It is still motivated by the ceiling
	# fluorescents rather than behaving like a film-set key light.
	var carriage_fill := OmniLight3D.new()
	carriage_fill.position = Vector3(0.0, 1.38, 2.45)
	carriage_fill.light_color = Color(0.68, 0.64, 0.53)
	carriage_fill.light_energy = 1.65
	carriage_fill.omni_range = 5.8
	carriage_fill.shadow_enabled = false
	prologue_shell.add_child(carriage_fill)

	# Seats face the aisle, leaving a strong central sightline to the sealed
	# door. Empty places, one abandoned case, and a hanging coat imply a last
	# service without needing dialogue or a cutaway.
	for side in [-1.0, 1.0]:
		for seat_z in [-3.55, -1.18, 1.18, 3.55]:
			_add_child_visual_box(
				prologue_shell,
				Vector3(side * 2.08, 0.49, seat_z),
				Vector3(0.94, 0.36, 1.45),
				upholstery,
				0.97,
				0.0
			)
			_add_child_visual_box(
				prologue_shell,
				Vector3(side * 2.42, 1.08, seat_z),
				Vector3(0.24, 1.35, 1.43),
				upholstery.darkened(0.16),
				0.98,
				0.0
			)
			_add_child_visual_box(
				prologue_shell,
				Vector3(side * 2.285, 1.11, seat_z),
				Vector3(0.018, 0.92, 0.032),
				upholstery_wear.darkened(0.12),
				0.99,
				0.0
			)
			_add_child_visual_box(
				prologue_shell,
				Vector3(side * 1.57, 0.56, seat_z - 0.69),
				Vector3(0.10, 0.52, 0.09),
				tarnished_brass,
				0.46,
				0.62
			)

		# Luggage rack, overhead rail, and hanging handles make looking up and
		# behind as authored as the initial aisle composition.
		_add_child_visual_box(
			prologue_shell,
			Vector3(side * 2.18, 2.43, 0.0),
			Vector3(0.07, 0.07, 9.2),
			tarnished_brass,
			0.44,
			0.66
		)
		for handle_z in [-3.6, -1.8, 0.0, 1.8, 3.6]:
			_add_child_visual_box(
				prologue_shell,
				Vector3(side * 1.74, 2.18, handle_z),
				Vector3(0.035, 0.48, 0.035),
				tarnished_brass,
				0.44,
				0.66
			)
			_add_child_visual_box(
				prologue_shell,
				Vector3(side * 1.74, 1.94, handle_z),
				Vector3(0.22, 0.035, 0.035),
				tarnished_brass,
				0.44,
				0.66
			)

	# A worn case and discarded coat break the perfect procedural repetition.
	_add_child_visual_box(prologue_shell, Vector3(-1.76, 0.22, 2.15), Vector3(0.58, 0.38, 0.92), upholstery_wear)
	_add_child_visual_box(prologue_shell, Vector3(-1.76, 0.44, 2.15), Vector3(0.22, 0.06, 0.36), tarnished_brass)
	_add_child_visual_box(prologue_shell, Vector3(2.37, 1.38, -1.18), Vector3(0.16, 1.12, 1.12), Color(0.078, 0.072, 0.063))
	_add_child_visual_box(prologue_shell, Vector3(2.14, 1.62, -1.18), Vector3(0.42, 0.16, 1.18), Color(0.078, 0.072, 0.063))
	_add_child_visual_box(
		prologue_shell,
		Vector3(2.592, 2.56, 1.30),
		Vector3(0.024, 0.34, 0.66),
		Color(0.64, 0.61, 0.50),
		0.90,
		0.0
	)
	for notice_line in [-0.19, -0.06, 0.08]:
		_add_child_visual_box(
			prologue_shell,
			Vector3(2.575, 2.56 + notice_line, 1.30),
			Vector3(0.012, 0.018, 0.48),
			Color(0.15, 0.13, 0.095),
			0.90,
			0.0
		)

	# A small analogue route diagram repeats the watch motif without becoming
	# glowing sci-fi signage.
	_add_child_visual_box(prologue_shell, Vector3(-2.575, 2.64, 0.0), Vector3(0.025, 0.29, 3.65), inner_metal)
	for mark_z in [-1.45, -0.72, 0.0, 0.72, 1.45]:
		_add_child_emissive_box(
			prologue_shell,
			Vector3(-2.586, 2.64, mark_z),
			Vector3(0.019, 0.105, 0.045),
			Color(0.49, 0.28, 0.12),
			0.62
		)

	# The windows look into a dedicated opaque service tunnel, never the combat
	# map. Repeating buttresses and amber maintenance lamps slide past it.
	for side in [-1.0, 1.0]:
		_add_child_visual_box(
			prologue_shell,
			Vector3(side * 4.05, 1.58, 0.0),
			Vector3(0.34, 3.65, 24.0),
			tunnel_black
		)
		_add_child_visual_box(
			prologue_shell,
			Vector3(side * 3.72, 0.30, 0.0),
			Vector3(0.44, 0.58, 24.0),
			Color(0.055, 0.051, 0.043)
		)
	prologue_window_motion = Node3D.new()
	prologue_window_motion.name = "SealedPassingTunnel"
	prologue_shell.add_child(prologue_window_motion)
	for bar_index in range(9):
		var bar_z := -12.0 + float(bar_index) * 3.0
		for side in [-1.0, 1.0]:
			var buttress := _add_child_visual_box_return(
				prologue_window_motion,
				Vector3(side * 3.65, 1.58, bar_z),
				Vector3(0.55, 3.42, 0.32),
				Color(0.115, 0.105, 0.085)
			)
			buttress.set_meta("travel_z", bar_z)
			if bar_index % 2 == 0:
				var lamp := _add_child_emissive_box_return(
					prologue_window_motion,
					Vector3(side * 3.43, 2.10, bar_z + 0.62),
					Vector3(0.035, 0.17, 0.54),
					Color(0.74, 0.39, 0.13),
					1.9
				)
				lamp.set_meta("travel_z", bar_z + 0.62)

	prologue_shell.visible = false


func _update_prologue_exterior() -> void:
	if not is_instance_valid(prologue_window_motion):
		return
	var travel := prologue_time * (14.0 if prologue_time < 4.65 else 18.5)
	for feature in prologue_window_motion.get_children():
		if not feature.has_meta("travel_z"):
			continue
		var base_z := float(feature.get_meta("travel_z"))
		feature.position.z = wrapf(base_z + travel + 12.0, 0.0, 24.0) - 12.0


func _create_encounter_gate(z_position: float) -> StaticBody3D:
	var gate := StaticBody3D.new()
	gate.position = Vector3(0.0, 0.0, z_position)
	gate.collision_layer = 1
	gate.collision_mask = 0
	gate.name = "EncounterSeal"
	add_child(gate)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(33.0, 5.0, 0.48)
	collision.shape = shape
	collision.position.y = 2.5
	gate.add_child(collision)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.13, 0.12, 0.105)
	material.metallic = 0.42
	material.roughness = 0.63
	for x in range(-15, 16, 2):
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.18, 5.2, 0.30)
		bar.mesh = bar_mesh
		bar.position = Vector3(float(x), 2.6, 0.0)
		bar.material_override = material
		gate.add_child(bar)
	for y in [0.8, 4.4]:
		var brace := MeshInstance3D.new()
		var brace_mesh := BoxMesh.new()
		brace_mesh.size = Vector3(32.0, 0.24, 0.36)
		brace.mesh = brace_mesh
		brace.position = Vector3(0.0, y, 0.0)
		brace.material_override = material
		gate.add_child(brace)
	return gate


func _open_gate(gate: StaticBody3D) -> void:
	if not is_instance_valid(gate):
		return
	gate.collision_layer = 0
	var tween := create_tween()
	tween.tween_property(gate, "position:y", -5.6, 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	spawn_burst(gate.global_position + Vector3.UP * 2.2, Color(0.41, 0.34, 0.25), 12)


func _update_deterioration(delta: float) -> void:
	var permanent_loss: float = 1.0 - player.max_time / player.STARTING_MAX_TIME
	var encounter_depth: float = clampf(float(maxi(wave - 1, 0)) * 0.28, 0.0, 0.72)
	var target: float = maxf(permanent_loss * 2.8, encounter_depth)
	deterioration = move_toward(deterioration, target, delta * 0.22)

	for material in ghost_materials:
		material.set_shader_parameter("visibility", deterioration)

	if world_environment_resource != null:
		world_environment_resource.fog_density = 0.016 + deterioration * 0.014
		world_environment_resource.fog_light_color = Color(0.065, 0.078, 0.072).lerp(
			Color(0.095, 0.071, 0.102),
			deterioration
		)


func _add_static_box(at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.metallic = 0.04
	mesh_instance.material_override = material
	body.add_child(mesh_instance)


func _add_visual_box(at: Vector3, size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	mesh_instance.material_override = material
	add_child(mesh_instance)


func _add_ghost_box(at: Vector3, size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := _make_ghost_material(color)
	mesh_instance.material_override = material
	add_child(mesh_instance)


func _add_ghost_asset(path: String, at: Vector3, asset_scale: Vector3, rotation: Vector3) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var holder := Node3D.new()
	holder.position = at
	holder.scale = asset_scale
	holder.rotation = rotation
	add_child(holder)
	var instance := packed.instantiate()
	holder.add_child(instance)
	_apply_ghost_material(instance, Color(0.27, 0.21, 0.30))


func _make_ghost_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/deferred_history.gdshader")
	material.set_shader_parameter("history_color", color)
	material.set_shader_parameter("visibility", deterioration)
	material.set_shader_parameter("phase_seed", float(ghost_materials.size()) * 0.137)
	ghost_materials.append(material)
	return material


func _apply_ghost_material(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		node.material_override = _make_ghost_material(color)
	for child in node.get_children():
		_apply_ghost_material(child, color)


func _add_child_visual_box(
	parent: Node3D,
	at: Vector3,
	size: Vector3,
	color: Color,
	roughness := 0.86,
	metallic := 0.08
) -> void:
	_add_child_visual_box_return(parent, at, size, color, roughness, metallic)


func _add_child_visual_box_return(
	parent: Node3D,
	at: Vector3,
	size: Vector3,
	color: Color,
	roughness := 0.86,
	metallic := 0.08
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_child_glass_box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.065, 0.075, 0.072, 0.24)
	material.metallic = 0.16
	material.roughness = 0.26
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _add_child_emissive_box(
	parent: Node3D,
	at: Vector3,
	size: Vector3,
	color: Color,
	energy: float
) -> void:
	_add_child_emissive_box_return(parent, at, size, color, energy)


func _add_child_emissive_box_return(
	parent: Node3D,
	at: Vector3,
	size: Vector3,
	color: Color,
	energy: float
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.52
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_optional_pack_asset(
	path: String,
	at: Vector3,
	asset_scale: Vector3,
	rotation: Vector3,
	tint: Color
) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	return _add_asset(
		path,
		at,
		asset_scale,
		rotation,
		tint,
		"res://assets/user_pack/Atlas_Albedo_LPUP.png",
		"res://assets/user_pack/color-atlas-emission-night.png",
		"res://assets/user_pack/color-atlas-specular.png"
	)


func _add_asset(
	path: String,
	at: Vector3,
	asset_scale: Vector3,
	rotation: Vector3,
	tint: Color,
	texture_path: String = "",
	emission_path: String = "",
	specular_path: String = ""
) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var holder := Node3D.new()
	holder.position = at
	holder.scale = asset_scale
	holder.rotation = rotation
	add_child(holder)
	var instance := packed.instantiate()
	holder.add_child(instance)
	var texture: Texture2D = null
	var emission_texture: Texture2D = null
	var specular_texture: Texture2D = null
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		texture = load(texture_path) as Texture2D
	if not emission_path.is_empty() and ResourceLoader.exists(emission_path):
		emission_texture = load(emission_path) as Texture2D
	if not specular_path.is_empty() and ResourceLoader.exists(specular_path):
		specular_texture = load(specular_path) as Texture2D
	_tint_meshes(instance, tint, texture, emission_texture, specular_texture)
	return holder


func _tint_meshes(
	node: Node,
	tint: Color,
	texture: Texture2D = null,
	emission_texture: Texture2D = null,
	specular_texture: Texture2D = null
) -> void:
	if node is MeshInstance3D:
		var material: Material
		if texture != null and emission_texture != null and specular_texture != null:
			var night_material := ShaderMaterial.new()
			night_material.shader = PackNightShader
			night_material.set_shader_parameter("albedo_atlas", texture)
			night_material.set_shader_parameter("night_emission_atlas", emission_texture)
			night_material.set_shader_parameter("specular_atlas", specular_texture)
			night_material.set_shader_parameter("tint", tint)
			material = night_material
		else:
			var standard_material := StandardMaterial3D.new()
			standard_material.albedo_color = tint
			standard_material.albedo_texture = texture
			standard_material.roughness = 0.78
			standard_material.metallic = 0.18
			material = standard_material
		node.material_override = material
	for child in node.get_children():
		_tint_meshes(child, tint, texture, emission_texture, specular_texture)


func _ensure_input_actions() -> void:
	_add_key_action(&"move_forward", KEY_W)
	_add_key_action(&"move_backward", KEY_S)
	_add_key_action(&"move_left", KEY_A)
	_add_key_action(&"move_right", KEY_D)
	_add_key_action(&"jump", KEY_SPACE)
	_add_key_action(&"slide", KEY_CTRL)
	_add_key_action(&"kick", KEY_E)
	_add_key_action(&"chronostep", KEY_SHIFT)
	_add_key_action(&"watch", KEY_Q)
	_add_key_action(&"restart", KEY_R)
	_add_key_action(&"toggle_debug", KEY_F3)
	_add_mouse_action(&"attack", MOUSE_BUTTON_LEFT)
	_add_mouse_action(&"throw_dagger", MOUSE_BUTTON_RIGHT)


func _add_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _add_mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
