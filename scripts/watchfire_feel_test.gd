extends SceneTree

const PlayerScript = preload("res://scripts/player.gd")
const HandsScript = preload("res://scripts/hands_2d.gd")
const ProjectileScript = preload("res://scripts/enemy_projectile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not InputMap.has_action("watch"):
		InputMap.add_action("watch")
	var player = PlayerScript.new()
	root.add_child(player)
	await process_frame

	player.watchfire = 60.0
	player.watch_active = true
	_check(
		is_equal_approx(player.get_hostile_time_scale(), player.WATCH_HOSTILE_SCALE),
		"ordinary Watchfire gives the player hostile-time dominance"
	)
	_check(
		player.get_player_time_dominance() > 1.0
		and player.get_player_combat_time_scale() > 1.0,
		"ordinary Watchfire never slows player movement or attacks"
	)

	player.watch_active = false
	var projectile = ProjectileScript.new()
	projectile.player = player
	projectile.direction = Vector3(0.0, 0.0, -1.0)
	projectile.speed = 10.0
	root.add_child(projectile)
	projectile.set_physics_process(false)
	projectile.global_position = player.global_position + Vector3(0.0, 0.85, 5.0)
	await physics_frame
	var danger: Dictionary = player._detect_last_instant_danger()
	_check(
		danger.get("reason", &"") == &"last_instant",
		"an incoming collision path is recognized as a last-instant activation"
	)
	Input.action_press("watch")
	player._update_watch(0.016)
	Input.action_release("watch")
	_check(
		player.is_watch_overclocked() and player.overclock_reason == &"last_instant",
		"pressing Watchfire on that collision path immediately earns Overclock"
	)
	player._update_watch(0.016)
	projectile.queue_free()
	await process_frame

	player.watch_active = true
	player._trigger_watch_overclock(&"test_danger", 1.2, 1.0)
	_check(player.is_watch_overclocked(), "a danger reward enters Overclock immediately")
	_check(
		player.get_hostile_time_scale() <= 0.05,
		"Overclock nearly arrests hostile simulation"
	)
	_check(
		player.get_player_time_dominance() >= 1.25
		and player.get_player_combat_time_scale() >= 1.6,
		"Overclock accelerates the player while hostiles are arrested"
	)
	_check(player.watch_entry_visual > 0.99, "Overclock retriggers the activation shutter")

	var hands = HandsScript.new()
	hands.bind(player)
	root.add_child(hands)
	var second_before: float = hands.second_hand_angle
	hands._process(0.10)
	var overclock_second_motion := absf(angle_difference(hands.second_hand_angle, second_before))
	_check(
		overclock_second_motion > deg_to_rad(35.0),
		"the analog seconds hand visibly races during Overclock"
	)

	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/post_process.gdshader")
	material.set_shader_parameter("time_snap", 1.0)
	material.set_shader_parameter("overclock", 1.0)
	material.set_shader_parameter("time_motion", 0.8)
	_check(
		is_equal_approx(float(material.get_shader_parameter("overclock")), 1.0),
		"the Compatibility shader accepts explicit Overclock choreography"
	)

	player.watch_active = false
	_check(
		is_equal_approx(player.get_hostile_time_scale(), 1.0),
		"releasing Watchfire immediately restores hostile simulation"
	)

	player.queue_free()
	hands.queue_free()
	await process_frame
	if failures.is_empty():
		print("WATCHFIRE FEEL TEST PASSED")
		quit(0)
	else:
		print("WATCHFIRE FEEL TEST FAILED: ", failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)
