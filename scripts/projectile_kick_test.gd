extends SceneTree

const PlayerScript = preload("res://scripts/player.gd")
const ProjectileScript = preload("res://scripts/enemy_projectile.gd")

var failures: Array[String] = []
var score_tags: Array[StringName] = []
var score_payloads: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)

	var player = PlayerScript.new()
	arena.add_child(player)
	player.set_active(false)
	player.score_event.connect(_on_score_event)
	await physics_frame

	var aim: Vector3 = -player.camera.global_transform.basis.z
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 2
	blocker.collision_mask = 0
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(0.9, 1.8, 0.45)
	blocker_shape.shape = blocker_box
	blocker_shape.position.y = 0.9
	blocker.add_child(blocker_shape)
	arena.add_child(blocker)
	blocker.global_position = player.global_position + aim * 1.25

	var kicked_projectile = ProjectileScript.new()
	kicked_projectile.player = player
	kicked_projectile.speed = 10.0
	kicked_projectile.direction = -aim
	arena.add_child(kicked_projectile)
	kicked_projectile.set_physics_process(false)
	kicked_projectile.global_position = (
		player.camera.global_position
		+ aim * 2.35
		+ player.camera.global_transform.basis.x * 0.62
	)
	await physics_frame

	var kick_target: Dictionary = player._find_kickable_projectile(3.35, 1.6)
	_check(
		kick_target.get("collider") == kicked_projectile,
		"kick sweep prioritizes a hostile projectile despite a body in the center ray"
	)

	player.watchfire = 0.0
	player.watch_active = false
	player._start_attack(&"kick")
	player._update_combat(0.12)
	_check(kicked_projectile.deflected and kicked_projectile.kicked, "E kick returns a hostile projectile")
	_check(
		kicked_projectile.direction.dot(aim) > 0.999,
		"kicked projectile launches exactly along camera aim"
	)
	_check(
		kicked_projectile.speed >= ProjectileScript.KICK_MIN_SPEED
		and kicked_projectile.deflected_damage >= ProjectileScript.KICK_DAMAGE,
		"kicked projectile gains strong outgoing speed and late-game damage"
	)
	_check(player.watchfire > 0.0, "projectile kick works at zero meter and rewards Watchfire")
	_check(
		score_tags.has(&"projectile_kicked"),
		"projectile kick emits its dedicated choreography event"
	)
	_check(player.impact_visual >= 1.4, "projectile kick requests a distinct heavy impact")
	_check(
		not kicked_projectile.kick(aim),
		"friendly returned projectiles cannot be kicked repeatedly"
	)
	_check(
		kicked_projectile.collision_layer == 0,
		"returned projectile leaves the hostile kick-targeting layer"
	)

	kicked_projectile.queue_free()
	blocker.queue_free()
	await process_frame
	await physics_frame

	# The existing blade interaction remains the ordinary, lower-speed deflect.
	var blade_projectile = ProjectileScript.new()
	blade_projectile.player = player
	blade_projectile.speed = 10.0
	blade_projectile.direction = -aim
	arena.add_child(blade_projectile)
	blade_projectile.set_physics_process(false)
	blade_projectile.global_position = player.camera.global_position + aim * 2.0
	await physics_frame

	player.combat_state = player.CombatState.IDLE
	player.watch_active = false
	var blade_target: Dictionary = player._find_melee_target(4.0, 1.9)
	_check(
		blade_target.get("collider") == blade_projectile,
		"ordinary melee targeting still sees a hostile projectile"
	)
	player._start_attack(&"blade")
	player._update_combat(0.07)
	_check(
		blade_projectile.deflected and not blade_projectile.kicked,
		"blade deflection remains distinct from projectile kicking"
	)
	_check(
		is_equal_approx(blade_projectile.speed, 17.5)
		and blade_projectile.deflected_damage == 15600,
		"ordinary dagger deflect retains its original speed and damage"
	)

	arena.queue_free()
	await process_frame
	if failures.is_empty():
		print("PROJECTILE KICK TEST PASSED")
		quit(0)
	else:
		print("PROJECTILE KICK TEST FAILED: ", failures)
		quit(1)


func _on_score_event(tag: StringName, payload: Dictionary) -> void:
	score_tags.append(tag)
	score_payloads.append(payload)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)
