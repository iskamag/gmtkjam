extends Node3D

signal score_event(tag: StringName, payload: Dictionary)

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HudScript = preload("res://scripts/hud.gd")

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
	if started and not run_finished and not boss_defeated:
		_update_encounter_triggers()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not started and not run_finished:
			_start_run()
			get_viewport().set_input_as_handled()
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
	for spawn_data in definition["spawns"]:
		_spawn_enemy(spawn_data[0], spawn_data[1])
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
			"title": "PLACE THE BLADE",
			"subtitle": "A thrown weapon is a position you must account for.",
			"threat": 0.35,
			"spawns": [
				[Vector3(-3.7, 0.05, 5.5), EnemyScript.Kind.MELEE],
				[Vector3(5.0, 0.05, 0.0), EnemyScript.Kind.RANGED],
			],
		},
		{
			"trigger_z": -7.0,
			"title": "THE ROAD REMEMBERS",
			"subtitle": "Break the guard. Decide whether recall is worth the flame.",
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
			"subtitle": "Your first job. Your last job.",
			"threat": 1.0,
			"spawns": [
				[Vector3(0.0, 0.05, -28.0), EnemyScript.Kind.BOSS],
			],
		},
	]


func _spawn_enemy(at: Vector3, kind: int) -> void:
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
		_spawn_enemy(Vector3(-7.0, 0.05, -20.0), EnemyScript.Kind.MELEE)
	elif phase == 3:
		_spawn_enemy(Vector3(7.0, 0.05, -20.0), EnemyScript.Kind.RANGED)


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
	echo.global_transform = at_transform
	echo.position.y += 0.9
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.32, 0.25, 0.36, 0.30)
	material.emission_enabled = true
	material.emission = Color(0.23, 0.16, 0.28)
	material.emission_energy_multiplier = 0.32
	echo.material_override = material
	add_child(echo)
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
	cut.global_position = at
	if is_instance_valid(player):
		cut.look_at(player.camera.global_position, Vector3.UP)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.92, 0.82, 0.58, 0.82)
	material.emission_enabled = true
	material.emission = Color(0.58, 0.45, 0.27)
	material.emission_energy_multiplier = 1.1
	cut.material_override = material
	add_child(cut)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(cut, "scale", Vector3(2.6, 0.2, 1.0), 0.16)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.16)
	tween.set_parallel(false)
	tween.tween_callback(cut.queue_free)


func spawn_burst(at: Vector3, color: Color, count: int = 8) -> void:
	var root := Node3D.new()
	root.global_position = at
	add_child(root)
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
	var label := Label3D.new()
	label.text = "%s%d" % ["✦" if critical else "", amount]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.font_size = 92 if not critical else 116
	label.pixel_size = 0.0028
	label.outline_size = 14
	label.modulate = Color(0.88, 0.84, 0.66) if not critical else Color(0.92, 0.57, 0.20)
	label.outline_modulate = Color(0.025, 0.021, 0.016, 0.95)
	label.no_depth_test = false
	add_child(label)
	label.global_position = at

	var side := -0.55 if amount % 2 == 0 else 0.55
	var target := at + Vector3(side, 2.7 if not critical else 3.4, 0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", target, 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.72).set_delay(0.28)
	tween.tween_property(label, "scale", Vector3.ONE * (1.22 if critical else 1.08), 0.18).set_trans(Tween.TRANS_BACK)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)


func _build_world() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.061, 0.063)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.39, 0.41, 0.39)
	environment.ambient_light_energy = 0.72
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.13, 0.14, 0.135)
	environment.fog_light_energy = 0.62
	environment.fog_density = 0.012
	environment.fog_sky_affect = 0.9
	world_environment_resource = environment
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-47.0, -33.0, 0.0)
	sun.light_color = Color(0.73, 0.70, 0.61)
	sun.light_energy = 1.05
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
		world_environment_resource.fog_density = 0.012 + deterioration * 0.012
		world_environment_resource.fog_light_color = Color(0.13, 0.14, 0.135).lerp(
			Color(0.105, 0.083, 0.112),
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


func _add_asset(path: String, at: Vector3, asset_scale: Vector3, rotation: Vector3, tint: Color) -> void:
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
	_tint_meshes(instance, tint)


func _tint_meshes(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		material.roughness = 0.85
		material.metallic = 0.12
		node.material_override = material
	for child in node.get_children():
		_tint_meshes(child, tint)


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
