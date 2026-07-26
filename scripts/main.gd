extends Node3D

signal score_event(tag: StringName, payload: Dictionary)

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HudScript = preload("res://scripts/hud.gd")
const WorldAestheticScript = preload("res://scripts/world_aesthetic.gd")
const PackNightShader = preload("res://shaders/pack_night_material.gdshader")
const SFX_TRAIN_LOOP := preload("res://sounds/train.wav")
const SFX_TRAIN_CRASH := preload("res://sounds/train-crash.wav")

var player: CharacterBody3D
var hud: CanvasLayer
var enemies_root: Node3D
var world_root: Node3D
var active_enemies: Array[Node] = []
var _music: AudioStreamPlayer
var _train_ambient: AudioStreamPlayer

var started := false
var run_finished := false
var boss_defeated := false
var wave := 0
var encounter_index := -1
var encounter_active := false
var encounter_resolving := false
var encounter_gates: Array[StaticBody3D] = []
var encounter_definitions: Array[Dictionary] = []
var boss_reinforcement_definitions: Dictionary = {}
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
	if "--export-world" in OS.get_cmdline_user_args():
		if "--gen-textures" in OS.get_cmdline_user_args():
			WorldBuilder.generate_textures()
		if "--export-train" in OS.get_cmdline_user_args():
			WorldBuilder.build_train(self)
			var train_err := WorldBuilder.export_scene_at(self, "res://scenes/train.tscn")
			if train_err == OK:
				print("WorldBuilder: wrote res://scenes/train.tscn")
			# Remove train, build world.
			world_root.queue_free()
			WorldBuilder.build_all(self)
		else:
			WorldBuilder.build_all(self)
		var err := WorldBuilder.export_scene_at(self, "res://scenes/world.tscn")
		if err == OK:
			print("WorldBuilder: wrote res://scenes/world.tscn")
		get_tree().quit()
		return
	_load_train()

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
	# Boot directly into the train interior as the main menu. The player is
	# seated inside the carriage, can look around, and clicks to start the
	# crash sequence that transitions into gameplay.
	_enter_train_menu()
	# Train ambient loop plays during the menu/cutscene.
	_train_ambient = AudioStreamPlayer.new()
	_train_ambient.stream = SFX_TRAIN_LOOP
	_train_ambient.volume_db = -8.0
	_train_ambient.name = "TrainAmbient"
	add_child(_train_ambient)
	_train_ambient.play()
	emit_signal("score_event", &"boot", {"room": "return_road"})

	# Background music — loops continuously; pitch warps under witch time (below).
	var music_stream = load("res://music.ogg")
	if music_stream is AudioStream:
		if music_stream is AudioStreamOggVorbis:
			(music_stream as AudioStreamOggVorbis).loop = true
		_music = AudioStreamPlayer.new()
		_music.stream = music_stream
		_music.volume_db = -6.0
		_music.name = "Music"
		add_child(_music)


var in_train_menu := true
var _world_loaded := false


# Boot state: player seated inside the train carriage, can look around.
# Clicking starts the crash sequence that transitions into gameplay.
func _enter_train_menu() -> void:
	in_train_menu = true
	started = false
	prologue_active = false
	player.global_position = Vector3(0.12, 0.05, 18.05)
	player.rotation = Vector3.ZERO
	player.pitch = -0.035
	player.camera.position = Vector3(0.0, 1.31, 0.0)
	player.camera.rotation = Vector3(-0.035, 0.0, 0.0)
	player.camera.fov = 73.0
	player.camera.near = 0.1
	if is_instance_valid(prologue_shell):
		prologue_shell.visible = true
		prologue_shell.position = Vector3(0.0, 0.0, 16.0)
		prologue_shell.rotation = Vector3.ZERO
	# Don't call hud.begin_prologue() here — it starts a black-screen shade
	# at alpha 1.0 that only fades once the crash animation runs. The HUD
	# prologue is triggered by _begin_prologue() when the player clicks.


# Load the train interior scene on boot. This is the main menu — the player
# is seated inside the carriage, can look around, and clicks to start the
# crash sequence. After the crash, _finish_prologue loads world.tscn.
func _load_train() -> void:
	var packed := load("res://scenes/train.tscn") as PackedScene
	if packed == null:
		push_error("main: res://scenes/train.tscn missing. Run: godot --headless -- --export-world --export-train")
		return
	world_root = packed.instantiate()
	world_root.name = "Train"
	add_child(world_root)
	prologue_shell = world_root.find_child("LastServiceCarriage", true)
	# Bind environment for lighting.
	var env_nodes := world_root.find_children("*", "WorldEnvironment", true)
	if not env_nodes.is_empty():
		world_environment_resource = env_nodes[0].environment
	WorldBuilder.apply_runtime_tints(self, world_root)


# Load the authored world scene (geometry + encounter trigger zones) and bind
# its nodes back into the runtime state WorldBuilder used to populate directly.
func _load_world() -> void:
	var packed := load("res://scenes/world.tscn") as PackedScene
	if packed == null:
		push_error("main: res://scenes/world.tscn missing. Run: godot --headless -- --export-world")
		return
	world_root = packed.instantiate()
	world_root.name = "World"
	add_child(world_root)
	_bind_world_from_scene(world_root)
	WorldBuilder.apply_runtime_tints(self, world_root)
	_world_loaded = true


func _bind_world_from_scene(root: Node3D) -> void:
	var env_nodes := root.find_children("*", "WorldEnvironment", true)
	if not env_nodes.is_empty():
		world_environment_resource = env_nodes[0].environment

	ghost_materials.clear()
	var ghost_shader := load("res://shaders/deferred_history.gdshader")
	for mi in root.find_children("*", "MeshInstance3D", true):
		var mat = mi.material_override
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader == ghost_shader:
			ghost_materials.append(mat)

	prologue_shell = root.find_child("LastServiceCarriage", true)
	prologue_window_motion = root.find_child("SealedPassingTunnel", true)

	encounter_gates.clear()
	var gates := get_tree().get_nodes_in_group("encounter_gate")
	gates.sort_custom(func(a, b): return a.position.z > b.position.z)
	for gate in gates:
		encounter_gates.append(gate as StaticBody3D)

	encounter_definitions.clear()
	var zones: Array = root.find_children("Encounter*", "Area3D", true)
	zones.sort_custom(func(a, b): return a.position.z > b.position.z)
	for zone in zones:
		var spawns: Array = []
		for marker in zone.find_children("Spawn*", "Marker3D", true):
			spawns.append([marker.global_position, int(marker.get_meta("kind", EnemyScript.Kind.MELEE))])
		encounter_definitions.append({
			"trigger_z": zone.position.z,
			"title": String(zone.get_meta("title", "")),
			"subtitle": String(zone.get_meta("subtitle", "")),
			"threat": float(zone.get_meta("threat", 0.5)),
			"spawns": spawns,
		})

	boss_reinforcement_definitions.clear()
	var boss_node := root.find_child("BossReinforcements", true)
	if boss_node != null:
		for phase_node in boss_node.get_children():
			var phase_num := int(phase_node.name.trim_prefix("Phase"))
			var spawns: Array = []
			for marker in phase_node.find_children("Spawn*", "Marker3D", true):
				spawns.append([marker.global_position, int(marker.get_meta("kind", EnemyScript.Kind.MELEE))])
			boss_reinforcement_definitions[phase_num] = spawns


func _process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(hud):
		return

	_update_deterioration(delta)
	# Warp music pitch during witch time (the master low-pass muffles it too).
	if is_instance_valid(_music) and is_instance_valid(player):
		var target := 1.0
		if player.is_watch_overclocked():
			target = 0.5
		elif player.watch_active:
			target = 0.68
		_music.pitch_scale = lerpf(_music.pitch_scale, target, 1.0 - exp(-delta * 8.0))
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
		(prologue_active or in_train_menu)
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
		if in_train_menu and not started:
			_start_crash_sequence()
			get_viewport().set_input_as_handled()
			return
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


func _start_crash_sequence() -> void:
	in_train_menu = false
	# Stop ambient train loop, play the crash sound.
	if is_instance_valid(_train_ambient):
		_train_ambient.stop()
	var crash_voice := AudioStreamPlayer.new()
	crash_voice.stream = SFX_TRAIN_CRASH
	crash_voice.volume_db = -2.0
	crash_voice.name = "TrainCrash"
	add_child(crash_voice)
	crash_voice.play()
	crash_voice.finished.connect(crash_voice.queue_free)
	_begin_prologue()


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

	if prologue_time >= next_train_tick and prologue_time < 10.0:
		player.play_sfx(&"train")
		next_train_tick += 0.64 if prologue_time < 8.0 else 0.46

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

	if prologue_time >= 4.0 and not prologue_flags.has("stats"):
		prologue_flags["stats"] = true
		emit_signal("score_event", &"status_reveal", {
			"level": 50,
			"attack": 13870,
			"art": 99,
		})
	if prologue_time >= 6.0 and not prologue_flags.has("memory"):
		prologue_flags["memory"] = true
		player.play_sfx(&"memory")
		emit_signal("score_event", &"memory_intrusion", {"layer": 1})
	if prologue_time >= 8.0 and not prologue_flags.has("premonition"):
		prologue_flags["premonition"] = true
		player.play_sfx(&"watch")
		emit_signal("score_event", &"crash_premonition", {})
	if prologue_time >= 9.0 and not prologue_flags.has("first_jolt"):
		prologue_flags["first_jolt"] = true
		player.play_sfx(&"wound")
		emit_signal("score_event", &"crash_premonition", {"impact": 1})
	if prologue_time >= 9.5 and not prologue_flags.has("crash"):
		prologue_flags["crash"] = true
		player.play_sfx(&"crash")
		player.play_sfx(&"wound")
		player.wound_visual = 1.0
		player.watch_previous_time = player.STARTING_MAX_TIME
		hud.set_intro_effects(1.0, 1.0)
		emit_signal("score_event", &"crash_hit", {})
	if prologue_time >= 10.0 and not prologue_flags.has("secondary_impact"):
		prologue_flags["secondary_impact"] = true
		player.play_sfx(&"crash")
	if prologue_time >= 10.5 and not prologue_flags.has("final_impact"):
		prologue_flags["final_impact"] = true
		player.play_sfx(&"train")

	if prologue_time >= 9.0 and prologue_time < 11.0:
		var crash_phase := clampf((prologue_time - 9.0) / 2.0, 0.0, 1.0)
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
	elif prologue_time >= 11.0:
		if not prologue_flags.has("aftermath"):
			prologue_flags["aftermath"] = true
			# Swap scenes immediately: hide train, load world arena.
			if is_instance_valid(prologue_shell):
				prologue_shell.visible = false
			if is_instance_valid(world_root):
				world_root.queue_free()
			_world_loaded = false
			_load_world()
			player.global_position = Vector3(0.0, 0.05, 16.0)
		var recovery := clampf((prologue_time - 11.0) / 2.0, 0.0, 1.0)
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
			maxf(0.0, 1.0 - (prologue_time - 9.5) * 3.3)
		)

	player.camera.position = camera_position
	player.camera.rotation = Vector3(
		clampf(prologue_look_pitch + camera_pitch_offset, -1.22, 1.12),
		0.0,
		camera_roll
	)

	if prologue_time >= 12.5 and not prologue_flags.has("epilogue"):
		prologue_flags["epilogue"] = true
		emit_signal("score_event", &"title_epilogue", {"chapter": "the_first_job"})

	if prologue_time >= 13.0:
		_finish_prologue()


func _finish_prologue() -> void:
	if not prologue_active:
		return
	prologue_active = false
	# If the world wasn't loaded during the recovery phase (e.g. skip), load it now.
	if not _world_loaded:
		if is_instance_valid(world_root):
			world_root.queue_free()
		_load_world()
	player.global_position = Vector3(0.0, 0.05, 16.0)
	player.rotation = Vector3.ZERO
	player.pitch = 0.0
	player.camera.position = Vector3(0.0, 1.55, 0.0)
	player.camera.rotation = Vector3.ZERO
	player.camera.fov = 79.0
	player.camera.near = 0.04
	player.set_active(true)
	hud.set_intro_effects(0.0, 0.0)
	hud.end_prologue()
	hud.announce("EPILOGUE", "THE FIRST JOB", 2.1)
	if _music != null:
		_music.play()
	emit_signal("score_event", &"control_return", {"time": player.time_left})
	emit_signal("score_event", &"run_started", {"time": player.time_left})


func _start_run() -> void:
	started = true
	run_finished = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_active(true)
	hud.begin_run()
	if _music != null:
		_music.play()
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
	var reinforcements: Array = boss_reinforcement_definitions.get(phase, [])
	for index in reinforcements.size():
		var spawn_data: Array = reinforcements[index]
		_spawn_enemy(spawn_data[0], spawn_data[1], 0.16 + float(index) * 0.18)


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


# Ground-slam AoE: damage every active enemy within radius, falloff with
# distance, plus a debris burst at the impact point.
func apply_slam(at: Vector3, radius: float, damage: int, force: float, launch: float) -> void:
	for enemy in active_enemies:
		if not is_instance_valid(enemy):
			continue
		var d: float = enemy.global_position.distance_to(at)
		if d <= radius:
			var falloff := 1.0 - (d / radius) * 0.55
			enemy.take_damage(int(float(damage) * falloff), enemy.global_position, true, force, launch)
	spawn_burst(at + Vector3.UP * 0.3, Color(0.66, 0.58, 0.40), 18)


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
	# Perspective must own its apparent size. fixed_size made a distant hit
	# occupy the same screen area as a close one, which only impersonated
	# world-space feedback.
	label.fixed_size = false
	label.font_size = 58 if not critical else 66
	label.pixel_size = 0.0032
	label.outline_size = 8
	label.modulate = Color(0.89, 0.85, 0.72) if not critical else Color(0.62, 0.29, 0.22)
	label.outline_modulate = Color(0.025, 0.021, 0.016, 0.95)
	label.no_depth_test = false
	add_child(label)
	var lane := -1.0 if damage_number_serial % 2 == 0 else 1.0
	var camera_right := Vector3.RIGHT
	if is_instance_valid(player) and is_instance_valid(player.camera):
		camera_right = player.camera.global_transform.basis.x
	label.global_position = at + Vector3.UP * 0.08 + camera_right * lane * 0.12
	label.scale = Vector3.ONE * (0.88 if critical else 0.82)

	var target := (
		label.global_position
		+ Vector3.UP * (0.72 if not critical else 0.88)
		+ camera_right * lane * 0.12
	)
	var drift := create_tween()
	drift.set_parallel(true)
	drift.tween_property(label, "global_position", target, 0.58).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	drift.tween_property(label, "modulate:a", 0.0, 0.24).set_delay(0.31)
	drift.set_parallel(false)
	drift.tween_callback(label.queue_free)

	var pop := create_tween()
	pop.tween_property(
		label,
		"scale",
		Vector3.ONE * (1.06 if critical else 1.0),
		0.045
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(
		label,
		"scale",
		Vector3.ONE * (1.0 if critical else 0.96),
		0.08
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _format_damage(amount: int) -> String:
	var digits := str(maxi(amount, 0))
	var formatted := ""
	while digits.length() > 3:
		formatted = "," + digits.right(3) + formatted
		digits = digits.left(digits.length() - 3)
	return digits + formatted


func _update_prologue_exterior() -> void:
	if not is_instance_valid(prologue_window_motion):
		return
	var travel := prologue_time * (14.0 if prologue_time < 4.65 else 18.5)
	for feature in prologue_window_motion.get_children():
		if not feature.has_meta("travel_z"):
			continue
		var base_z := float(feature.get_meta("travel_z"))
		feature.position.z = wrapf(base_z + travel + 12.0, 0.0, 24.0) - 12.0


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
		world_environment_resource.fog_density = 0.011 + deterioration * 0.012
		world_environment_resource.fog_light_color = Color(0.145, 0.166, 0.17).lerp(
			Color(0.155, 0.112, 0.142),
			deterioration
		)


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
