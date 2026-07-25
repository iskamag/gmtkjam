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

	player.set_active(true)
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
	_check(InputMap.has_action("chronostep"), "the chronosword movement burst is mapped")
	_check(InputMap.has_action("slide"), "ground slide is mapped")
	_check(InputMap.has_action("kick"), "kick has an independent combat input")
	_check(game.encounter_gates.size() == 2, "combat rooms have authored lock thresholds")
	_check(game.encounter_definitions.size() == 3, "encounters are data-defined instead of empty-list auto-waves")
	_check(game.ghost_materials.size() > 0, "historical geometry is available for deterioration")

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
