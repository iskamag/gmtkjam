extends SceneTree

const EnemyScript = preload("res://scripts/enemy.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ProjectileScript = preload("res://scripts/enemy_projectile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)

	var player = PlayerScript.new()
	arena.add_child(player)
	player.set_active(false)
	await physics_frame

	var aim: Vector3 = -player.camera.global_transform.basis.z
	var target = EnemyScript.new()
	target.kind = EnemyScript.Kind.MELEE
	target.player = player
	arena.add_child(target)
	target.set_physics_process(false)
	target.manifesting = false
	target.collision_layer = 2
	target.global_position = (
		player.global_position
		+ aim * 11.0
		+ player.camera.global_transform.basis.x * 2.1
	)
	await physics_frame
	target.body_collision.disabled = false
	await physics_frame

	var shot = ProjectileScript.new()
	shot.player = player
	shot.speed = 10.0
	arena.add_child(shot)
	shot.set_physics_process(false)
	shot.global_position = player.camera.global_position + aim * 2.0
	await physics_frame

	var target_direction: Vector3 = (
		target.global_position + Vector3.UP - shot.global_position
	).normalized()
	var assisted: Vector3 = player._assisted_reflect_direction(
		shot,
		aim,
		player.KICK_ASSIST_ANGLE,
		36.0
	)
	_check(
		assisted.dot(target_direction) > 0.995,
		"kick aim assist bends a near-crosshair return onto a valid enemy"
	)

	target.global_position = (
		player.global_position
		+ aim.rotated(Vector3.UP, deg_to_rad(42.0)) * 11.0
	)
	await physics_frame
	var deliberate: Vector3 = player._assisted_reflect_direction(
		shot,
		aim,
		player.KICK_ASSIST_ANGLE,
		36.0
	)
	_check(
		deliberate.dot(aim) > 0.9999,
		"aim assist does not steal a deliberate shot outside its cone"
	)

	var cover := StaticBody3D.new()
	cover.collision_layer = 1
	var cover_collision := CollisionShape3D.new()
	var cover_shape := BoxShape3D.new()
	cover_shape.size = Vector3(3.2, 3.0, 0.7)
	cover_collision.shape = cover_shape
	cover.add_child(cover_collision)
	arena.add_child(cover)
	var target_contact: Vector3 = target.global_position + Vector3.UP * 0.8
	cover.global_position = player.camera.global_position.lerp(target_contact, 0.5)
	cover.look_at(target_contact, Vector3.UP)
	await physics_frame
	_check(
		not player._melee_path_clear(
			player.camera.global_position,
			target_contact,
			target
		),
		"player melee cannot pass through solid world cover"
	)
	_check(
		not target._has_clear_line_to_player(),
		"enemy melee cannot pass through solid world cover"
	)

	shot.global_position = cover.global_position + cover.global_transform.basis.z * 1.4
	shot.direction = -cover.global_transform.basis.z
	shot.speed = 30.0
	shot.deflected = true
	shot._physics_process(0.1)
	_check(
		shot.is_queued_for_deletion(),
		"returned projectiles collide with world cover"
	)

	var boss = EnemyScript.new()
	boss.kind = EnemyScript.Kind.BOSS
	boss.player = player
	arena.add_child(boss)
	boss.set_physics_process(false)
	var ranged = EnemyScript.new()
	ranged.kind = EnemyScript.Kind.RANGED
	ranged.player = player
	arena.add_child(ranged)
	ranged.set_physics_process(false)
	_check(
		boss._boss_ring_direction(0.0).y < -0.05,
		"boss clock-face projectiles travel downward instead of upward"
	)
	_check(
		target.maximum_health >= 31500
		and target.move_speed >= 6.3
		and boss.maximum_health >= 220000,
		"late-game enemies have meaningful durability and pursuit pressure"
	)
	_check(
		ProjectileScript.KICK_DAMAGE > ranged.maximum_health,
		"a clean projectile kick decisively eliminates a ranged attacker"
	)
	player.watch_active = false
	_check(
		is_equal_approx(player._melee_watchfire_reward(false, &"blade"), 6.0)
		and is_equal_approx(player._melee_watchfire_reward(true, &"blade"), 11.0),
		"ordinary-time melee still builds Watchfire"
	)
	player.watch_active = true
	_check(
		is_zero_approx(player._melee_watchfire_reward(false, &"blade"))
		and is_zero_approx(player._melee_watchfire_reward(true, &"kick")),
		"Watchfire melee cannot sustain its own hostile-time arrest"
	)

	arena.queue_free()
	await process_frame
	if failures.is_empty():
		print("COMBAT PRESSURE TEST PASSED")
		quit(0)
	else:
		print("COMBAT PRESSURE TEST FAILED: ", failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)
