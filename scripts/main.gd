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
var pending_wave := false
var deterioration := 0.0
var world_environment_resource: Environment
var ghost_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	_ensure_input_actions()
	_build_world()
	_build_level()

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

	if started and not run_finished and active_enemies.is_empty() and not pending_wave and not boss_defeated:
		pending_wave = true
		get_tree().create_timer(1.15).timeout.connect(_spawn_next_wave)


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


func _spawn_next_wave() -> void:
	pending_wave = false
	if run_finished or boss_defeated:
		return

	wave += 1
	match wave:
		1:
			hud.announce("PLACE THE BLADE", "THROW • FIGHT EMPTY-HANDED • REWIND")
			_spawn_enemy(Vector3(-2.8, 0.05, 7.0), EnemyScript.Kind.MELEE)
			_spawn_enemy(Vector3(3.2, 0.05, -1.0), EnemyScript.Kind.RANGED)
			emit_signal("score_event", &"encounter_started", {"room": 1, "threat": 0.35})
		2:
			hud.announce("THE ROAD REMEMBERS", "Wounds return. The maximum does not.")
			_spawn_enemy(Vector3(-6.5, 0.05, -10.0), EnemyScript.Kind.RANGED)
			_spawn_enemy(Vector3(5.7, 0.05, -14.0), EnemyScript.Kind.MELEE)
			_spawn_enemy(Vector3(-2.0, 0.05, -20.0), EnemyScript.Kind.ELITE)
			emit_signal("score_event", &"encounter_started", {"room": 2, "threat": 0.68})
		3:
			hud.announce("THE UNFINISHED", "Your first job. Your last job.")
			_spawn_enemy(Vector3(0.0, 0.05, -25.0), EnemyScript.Kind.BOSS)
			emit_signal("score_event", &"boss_started", {"room": 3, "phase": 1})
		_:
			pass


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
	hud.announce("WOUND REWOUND", "THE RIM BREAKS", 0.58)
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


func _update_deterioration(delta: float) -> void:
	var permanent_loss: float = 1.0 - player.max_time / player.STARTING_MAX_TIME
	var encounter_depth: float = clampf(float(maxi(wave - 1, 0)) * 0.28, 0.0, 0.72)
	var target: float = maxf(permanent_loss * 2.8, encounter_depth)
	deterioration = move_toward(deterioration, target, delta * 0.22)

	for material in ghost_materials:
		material.albedo_color.a = 0.025 + deterioration * 0.42
		material.emission_energy_multiplier = 0.08 + deterioration * 0.22

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


func _make_ghost_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, 0.025)
	material.emission_enabled = true
	material.emission = color * 0.22
	material.emission_energy_multiplier = 0.08
	material.no_depth_test = false
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
