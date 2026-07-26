extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return

	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame

	var player = game.player
	_check(player != null, "player is constructed")
	_check(is_equal_approx(player.time_left, 54.0), "watch starts at 54 seconds")
	_check(is_equal_approx(player.max_time, 60.0), "watch maximum starts at 60 seconds")
	_check(
		game.world_environment_resource.background_mode == Environment.BG_SKY
		and game.world_environment_resource.sky != null,
		"the exterior is backed by a real procedural night sky"
	)
	_check(
		game.world_environment_resource.ambient_light_energy >= 0.8
		and game.get_node_or_null("ColdMoonKey") != null,
		"the rail town has readable ambient fill and a named moon key"
	)

	player.set_active(true)
	for frame in 12:
		await physics_frame
		if player.is_on_floor():
			break
	_check(player.is_on_floor(), "player settles onto authored floor before movement")
	var grounded_height: float = player.global_position.y
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await physics_frame
	_check(player.global_position.y > grounded_height + 0.02, "jump impulse produces upward world movement")
	player.velocity = player.global_transform.basis.x * player.RUN_SPEED
	player.planar_speed = player.RUN_SPEED
	player._update_camera(0.05)
	_check(absf(player.camera.rotation.z) > 0.025, "view lean reaches a readable angle within 50 milliseconds")
	var strafe_lean: float = player.camera.rotation.z
	player._update_camera(0.05)
	_check(
		signf(player.camera.rotation.z) == signf(strafe_lean),
		"held strafe intent cannot create an alternating horizon wobble"
	)
	player.velocity = Vector3.ZERO
	player.planar_speed = 0.0
	player._update_camera(0.16)
	_check(absf(player.camera.rotation.z) < 0.001, "view lean settles promptly after strafe release")

	var hands = game.hud.hands
	player.watch_active = false
	var second_before: float = hands.second_hand_angle
	hands._process(0.25)
	var ordinary_second_motion := absf(angle_difference(hands.second_hand_angle, second_before))
	player.watch_active = true
	var bend_second_before: float = hands.second_hand_angle
	hands._process(0.25)
	var bent_second_motion := absf(angle_difference(hands.second_hand_angle, bend_second_before))
	_check(
		bent_second_motion > ordinary_second_motion * 3.5,
		"Watchfire visibly accelerates the analog seconds hand"
	)
	player.watch_active = false

	player.time_left = 30.0
	player.max_time = 60.0
	player.invulnerability = 0.0
	var wound_applied: bool = player.hurt(6.0, 1.5, Vector3(0.0, 0.0, 5.0))
	_check(wound_applied, "a wound triggers an automatic rewind")
	_check(is_equal_approx(player.time_left, 24.0), "rewinding a wound spends current time")
	_check(is_equal_approx(player.max_time, 58.5), "rewinding a wound permanently shrinks the maximum")

	player.restore_time(100.0)
	_check(is_equal_approx(player.time_left, 58.5), "elimination recovery cannot exceed the damaged maximum")

	player.watchfire = 95.0
	player.gain_watchfire(20.0)
	_check(is_equal_approx(player.watchfire, 100.0), "Watchfire is capped")

	player.set_active(false)
	var flame_before_throw: float = player.watchfire
	player._throw_dagger()
	_check(player.dagger_state == player.DaggerState.OUTBOUND, "right click can place the dagger outbound")
	await process_frame
	_check(is_equal_approx(player.watchfire, flame_before_throw), "throwing the one physical dagger is free")
	var dagger = player.dagger_entity
	_check(dagger != null and is_instance_valid(dagger), "the thrown dagger exists in world space")
	if dagger != null and is_instance_valid(dagger):
		dagger._set_stuck()
		_check(player.dagger_state == player.DaggerState.STUCK, "the dagger can remain away instead of auto-returning")
		var flame_before_rewind: float = player.watchfire
		player._handle_dagger_input()
		_check(player.dagger_state == player.DaggerState.REWINDING, "a second input manually begins dagger rewind")
		_check(player.watchfire < flame_before_rewind, "manual dagger rewind spends a substantial flame charge")
		dagger._finish_return(true)
		await process_frame
		_check(player.dagger_state == player.DaggerState.HELD, "completed rewind restores the held dagger")

	var flame_before_retrieval: float = player.watchfire
	player._throw_dagger()
	var pickup_dagger = player.dagger_entity
	if pickup_dagger != null and is_instance_valid(pickup_dagger):
		pickup_dagger._set_stuck()
		pickup_dagger.pick_up()
		await process_frame
		_check(player.dagger_state == player.DaggerState.HELD, "physical dagger pickup restores the held state")
		_check(is_equal_approx(player.watchfire, flame_before_retrieval), "physical retrieval is the free recall fallback")

	game._spawn_damage_number(13200, Vector3(0.0, 2.0, 0.0), true)
	await process_frame
	_check(not game.find_children("*", "Label3D", true, false).is_empty(), "damage numbers are Label3D world objects")
	_check(game._format_damage(13200) == "13,200", "late-game damage values use readable thousands grouping")

	var ProjectileScript = load("res://scripts/enemy_projectile.gd")
	var inspected_projectiles: Array[Node] = []
	for projectile_style in [
		ProjectileScript.Style.NEEDLE,
		ProjectileScript.Style.SEAL,
		ProjectileScript.Style.BLADE,
	]:
		var projectile = ProjectileScript.new()
		projectile.player = player
		projectile.game = game
		projectile.style = projectile_style
		projectile.process_mode = Node.PROCESS_MODE_DISABLED
		game.add_child(projectile)
		var uses_visible_blob := false
		for mesh_node in projectile.find_children("*", "MeshInstance3D", true, false):
			if mesh_node.mesh is SphereMesh:
				uses_visible_blob = true
		_check(not uses_visible_blob, "enemy projectile style %d has no visible sphere blob" % projectile_style)
		inspected_projectiles.append(projectile)
	for projectile in inspected_projectiles:
		projectile.queue_free()
	await process_frame

	game._spawn_enemy(Vector3(0.0, 0.05, 9.0), game.EnemyScript.Kind.ELITE, 0.0)
	var manifested_enemy = game.active_enemies.back()
	_check(manifested_enemy.manifesting, "an authored enemy begins in manifestation state")
	_check(manifested_enemy.collision_layer == 0, "manifesting enemies cannot collide or attack")
	manifested_enemy._update_manifest(manifested_enemy.manifest_duration + 0.05)
	await process_frame
	_check(not manifested_enemy.manifesting, "enemy manifestation has a finite authored completion")
	manifested_enemy.vanish()
	game.active_enemies.erase(manifested_enemy)

	game._begin_prologue()
	_check(game.prologue_active and not player.active, "the train opening holds gameplay until the crash survives")
	_check(game.hud.prologue_layer.visible, "the train opening presents clear-data and epilogue layers")
	var look_yaw_before: float = game.prologue_look_yaw
	var look_event := InputEventMouseMotion.new()
	look_event.relative = Vector2(96.0, -38.0)
	game._unhandled_input(look_event)
	_check(
		not is_equal_approx(game.prologue_look_yaw, look_yaw_before)
		and not is_zero_approx(game.prologue_look_pitch),
		"the train opening preserves free mouse look"
	)
	_check(
		game.prologue_shell.get_node_or_null("SealedPassingTunnel") != null,
		"the train windows show a separate passing tunnel instead of the combat level"
	)
	game.prologue_time = 8.15
	game._update_prologue(0.10)
	_check(game.hud.prologue_title.visible, "the opening reveals EPILOGUE before returning control")
	game._finish_prologue()
	_check(player.active and not game.hud.prologue_layer.visible, "skipping or completing the opening returns identical control")

	_check(InputMap.has_action("chronostep"), "the chronosword movement burst is mapped")
	_check(InputMap.has_action("slide"), "ground slide is mapped")
	_check(InputMap.has_action("kick"), "kick has an independent combat input")
	_check(game.encounter_gates.size() == 2, "combat rooms have authored lock thresholds")
	_check(game.encounter_definitions.size() == 3, "encounters are data-defined instead of empty-list auto-waves")
	_check(game.ghost_materials.size() > 0, "historical geometry is available for deterioration")
	_check(
		game.get_node_or_null("ReturnRoadArtDirection") != null,
		"the authored rail-town aesthetic layer is present"
	)

	game.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)


func _finish() -> void:
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED: ", failures)
		quit(1)
