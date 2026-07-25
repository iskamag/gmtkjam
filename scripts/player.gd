extends CharacterBody3D

signal expired
signal rewound_wound(seconds_spent: float, maximum_lost: float)
signal attack_landed(amount: int, critical: bool)
signal score_event(tag: StringName, payload: Dictionary)

const DaggerThrowScript = preload("res://scripts/dagger_throw.gd")

const STARTING_MAX_TIME := 60.0
const MAX_WATCHFIRE := 100.0
const WATCH_SLOW_BURN := 15.0
const DAGGER_RECALL_BASE_COST := 18.0
const RUN_SPEED := 10.8
const GROUND_ACCELERATION := 48.0
const GROUND_FRICTION := 31.0
const AIR_ACCELERATION := 15.0
const AIR_SPEED_LIMIT := 12.8
const JUMP_VELOCITY := 9.0
const GRAVITY := 27.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.13
const SLIDE_DURATION := 0.72
const CHRONOSTEP_SPEED := 19.5
const CHRONOSTEP_DURATION := 0.16

enum DaggerState {
	HELD,
	OUTBOUND,
	BALLISTIC,
	STUCK,
	REWINDING,
}

enum CombatState {
	IDLE,
	WINDUP,
	ACTIVE,
	RECOVERY,
}

var time_left := 54.0
var max_time := STARTING_MAX_TIME
var watchfire := 52.0
var watch_active := false
var active := false

var camera: Camera3D
var collision_shape: CollisionShape3D
var dagger_state: int = DaggerState.HELD
var dagger_entity: Node3D

var pitch := 0.0
var combo_index := 0
var combo_window := 0.0
var swing_visual := 0.0
var punch_visual := 0.0
var kick_visual := 0.0
var wound_visual := 0.0
var restore_visual := 0.0
var watch_previous_time := 54.0
var invulnerability := 0.0
var expired_once := false
var was_watch_active := false

var planar_speed := 0.0
var movement_sway := 0.0
var move_cycle := 0.0
var is_sliding := false
var slide_ratio := 0.0
var landing_visual := 0.0
var chronostep_visual := 0.0
var impact_visual := 0.0
var camera_kick := Vector2.ZERO

var combat_state: int = CombatState.IDLE
var combat_state_time := 0.0
var combat_state_duration := 0.0
var combat_action: StringName = &""
var attack_data: Dictionary = {}
var buffered_action: StringName = &""
var attack_buffer := 0.0

var coyote_timer := 0.0
var jump_buffer := 0.0
var slide_timer := 0.0
var chronostep_timer := 0.0
var chronostep_cooldown := 0.0
var chronostep_direction := Vector3.ZERO
var air_step_available := true
var _was_on_floor := true


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1

	collision_shape = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.8
	collision_shape.shape = shape
	collision_shape.position.y = 0.9
	add_child(collision_shape)

	camera = Camera3D.new()
	camera.name = "Eyes"
	camera.position = Vector3(0.0, 1.55, 0.0)
	camera.fov = 79.0
	camera.near = 0.04
	add_child(camera)


func set_active(value: bool) -> void:
	active = value
	if value:
		expired_once = false


func _unhandled_input(event: InputEvent) -> void:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * 0.00225)
		pitch = clampf(pitch - event.relative.y * 0.0021, -1.28, 1.18)
		camera.rotation.x = pitch


func _physics_process(delta: float) -> void:
	_update_visual_timers(delta)
	if not active:
		return

	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0:
		_expire()
		return

	_update_watch(delta)
	_read_action_inputs()
	_move(delta)
	_update_combat(delta)
	_check_dagger_pickup()


func _update_visual_timers(delta: float) -> void:
	invulnerability = maxf(invulnerability - delta, 0.0)
	combo_window = maxf(combo_window - delta, 0.0)
	attack_buffer = maxf(attack_buffer - delta, 0.0)
	if attack_buffer <= 0.0:
		buffered_action = &""
	jump_buffer = maxf(jump_buffer - delta, 0.0)
	chronostep_cooldown = maxf(chronostep_cooldown - delta, 0.0)
	wound_visual = maxf(wound_visual - delta * 3.3, 0.0)
	restore_visual = maxf(restore_visual - delta * 3.7, 0.0)
	landing_visual = maxf(landing_visual - delta * 5.5, 0.0)
	chronostep_visual = maxf(chronostep_visual - delta * 5.0, 0.0)
	impact_visual = maxf(impact_visual - delta * 7.5, 0.0)
	camera_kick = camera_kick.lerp(Vector2.ZERO, 1.0 - exp(-delta * 13.0))


func _update_watch(delta: float) -> void:
	watch_active = Input.is_action_pressed("watch") and watchfire > 0.0
	if watch_active:
		watchfire = maxf(watchfire - WATCH_SLOW_BURN * delta, 0.0)
	if watch_active != was_watch_active:
		if watch_active:
			play_sfx(&"watch")
		emit_signal("score_event", &"watch_state", {
			"active": watch_active,
			"meter": watchfire,
			"time": time_left,
		})
		was_watch_active = watch_active


func _read_action_inputs() -> void:
	if Input.is_action_just_pressed("jump"):
		jump_buffer = JUMP_BUFFER_TIME
	if Input.is_action_just_pressed("attack"):
		_queue_attack(&"blade" if dagger_state == DaggerState.HELD else &"fist")
	if Input.is_action_just_pressed("kick"):
		_queue_attack(&"kick")
	if Input.is_action_just_pressed("throw_dagger"):
		_handle_dagger_input()
	if Input.is_action_just_pressed("chronostep"):
		_try_chronostep()


func _move(delta: float) -> void:
	var grounded := is_on_floor()
	if grounded:
		coyote_timer = COYOTE_TIME
		air_step_available = true
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	if chronostep_timer > 0.0:
		chronostep_timer -= delta
		var step_steer := chronostep_direction
		if direction != Vector3.ZERO:
			step_steer = step_steer.slerp(direction, delta * 4.2).normalized()
		chronostep_direction = step_steer
		horizontal = step_steer * CHRONOSTEP_SPEED
		velocity.y = 0.0
		if chronostep_timer <= 0.0:
			horizontal *= 0.72
	elif is_sliding:
		slide_timer -= delta
		slide_ratio = clampf(slide_timer / SLIDE_DURATION, 0.0, 1.0)
		if direction != Vector3.ZERO:
			var steered := horizontal.normalized().slerp(direction, delta * 1.9)
			horizontal = steered * horizontal.length()
		horizontal = horizontal.move_toward(Vector3.ZERO, delta * 5.4)
		if jump_buffer > 0.0:
			var launch_speed := clampf(horizontal.length() * 1.08, 10.5, 15.0)
			horizontal = horizontal.normalized() * launch_speed
			velocity.y = 8.15
			jump_buffer = 0.0
			coyote_timer = 0.0
			_end_slide()
			play_sfx(&"jump")
		elif slide_timer <= 0.0 or (
			slide_timer < SLIDE_DURATION - 0.18
			and not Input.is_action_pressed("slide")
		):
			_end_slide()
	elif grounded:
		if direction != Vector3.ZERO:
			horizontal = horizontal.move_toward(direction * RUN_SPEED, GROUND_ACCELERATION * delta)
		else:
			horizontal = horizontal.move_toward(Vector3.ZERO, GROUND_FRICTION * delta)
	else:
		if direction != Vector3.ZERO:
			horizontal = horizontal.move_toward(direction * AIR_SPEED_LIMIT, AIR_ACCELERATION * delta)

	if Input.is_action_just_pressed("slide") and grounded and horizontal.length() >= 6.0:
		_begin_slide(horizontal)
		horizontal = Vector3(velocity.x, 0.0, velocity.z)

	if jump_buffer > 0.0 and chronostep_timer <= 0.0 and not is_sliding:
		if coyote_timer > 0.0:
			velocity.y = JUMP_VELOCITY
			jump_buffer = 0.0
			coyote_timer = 0.0
			play_sfx(&"jump")
		else:
			var wall_normal := _find_wall_normal()
			if wall_normal != Vector3.ZERO:
				var tangent := horizontal.slide(wall_normal) * 0.5
				horizontal = wall_normal * 9.2 + tangent
				velocity.y = 8.7
				jump_buffer = 0.0
				camera_kick += Vector2(wall_normal.dot(global_transform.basis.x), -0.2) * 0.45
				play_sfx(&"jump")

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor() and chronostep_timer <= 0.0:
		velocity.y -= GRAVITY * delta
	elif is_on_floor():
		velocity.y = minf(velocity.y, -0.5)

	var fall_speed := absf(velocity.y)
	_was_on_floor = is_on_floor()
	move_and_slide()
	if not _was_on_floor and is_on_floor():
		landing_visual = clampf(fall_speed / 12.0, 0.25, 1.0)
		camera_kick.y -= landing_visual * 0.55
		play_sfx(&"land")

	planar_speed = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar_speed > 1.0:
		move_cycle += delta * planar_speed * (0.23 if is_sliding else 0.48)
	movement_sway = sin(move_cycle) * clampf(planar_speed / RUN_SPEED, 0.0, 1.3)
	_update_camera(delta)


func _begin_slide(horizontal: Vector3) -> void:
	is_sliding = true
	slide_timer = SLIDE_DURATION
	slide_ratio = 1.0
	var boosted := clampf(horizontal.length() * 1.13, 8.0, 14.2)
	var slide_direction := horizontal.normalized()
	velocity.x = slide_direction.x * boosted
	velocity.z = slide_direction.z * boosted
	_set_collision_height(1.1, 0.55)
	_cancel_recovery()
	play_sfx(&"slide")


func _end_slide() -> void:
	is_sliding = false
	slide_ratio = 0.0
	_set_collision_height(1.8, 0.9)


func _try_chronostep() -> void:
	if chronostep_cooldown > 0.0:
		return
	if not is_on_floor() and not air_step_available:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	chronostep_direction = (
		global_transform.basis * Vector3(input.x, 0.0, input.y)
	).normalized()
	if chronostep_direction == Vector3.ZERO:
		chronostep_direction = -global_transform.basis.z
	if is_sliding:
		_end_slide()
	if not is_on_floor():
		air_step_available = false
	chronostep_timer = CHRONOSTEP_DURATION
	chronostep_cooldown = 0.58
	chronostep_visual = 1.0
	_cancel_recovery()
	play_sfx(&"step")
	emit_signal("score_event", &"chronostep", {"time": time_left})
	var game := get_parent()
	if game.has_method("spawn_time_echo"):
		game.spawn_time_echo(global_transform)


func _find_wall_normal() -> Vector3:
	var directions: Array[Vector3] = [
		-global_transform.basis.z,
		global_transform.basis.x,
		-global_transform.basis.x,
		global_transform.basis.z,
	]
	var origin := global_position + Vector3.UP * 0.75
	for cast_direction in directions:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + cast_direction * 0.82, 1)
		query.exclude = [get_rid()]
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if not result.is_empty():
			var normal: Vector3 = result["normal"]
			if absf(normal.y) < 0.35:
				return normal.normalized()
	return Vector3.ZERO


func _set_collision_height(height: float, center_y: float) -> void:
	if collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		capsule.height = height
	collision_shape.position.y = center_y


func _update_camera(delta: float) -> void:
	var speed_factor := clampf(planar_speed / CHRONOSTEP_SPEED, 0.0, 1.0)
	var target_height := 1.22 if is_sliding else 1.55
	target_height -= landing_visual * 0.17
	var bob_x := movement_sway * 0.022
	var bob_y := absf(cos(move_cycle)) * 0.018 * clampf(planar_speed / RUN_SPEED, 0.0, 1.0)
	camera.position.x = lerpf(camera.position.x, bob_x + camera_kick.x * 0.025, 1.0 - exp(-delta * 15.0))
	camera.position.y = lerpf(
		camera.position.y,
		target_height + bob_y + camera_kick.y * 0.035,
		1.0 - exp(-delta * 17.0)
	)
	var side_speed := global_transform.basis.x.dot(velocity)
	var target_roll := clampf(-side_speed * 0.0045, -0.05, 0.05)
	if is_sliding:
		target_roll += movement_sway * 0.035
	camera.rotation.z = lerpf(
		camera.rotation.z,
		target_roll + camera_kick.x * 0.012,
		1.0 - exp(-delta * 9.0)
	)
	camera.fov = lerpf(camera.fov, 79.0 + speed_factor * 9.0, 1.0 - exp(-delta * 8.0))


func _queue_attack(action: StringName) -> void:
	if combat_state == CombatState.IDLE:
		_start_attack(action)
	else:
		buffered_action = action
		attack_buffer = 0.25


func _attack() -> void:
	_queue_attack(&"blade" if dagger_state == DaggerState.HELD else &"fist")


func _dagger_attack() -> void:
	_queue_attack(&"blade")


func _unarmed_attack() -> void:
	_queue_attack(&"fist")


func _start_attack(action: StringName) -> void:
	if action == &"blade" and dagger_state != DaggerState.HELD:
		action = &"fist"
	if action == &"kick":
		combo_index = 0
	elif combo_window <= 0.0:
		combo_index = 0
	combat_action = action
	attack_data = _attack_definition(action)
	combat_state = CombatState.WINDUP
	combat_state_duration = float(attack_data["windup"])
	combat_state_time = combat_state_duration
	buffered_action = &""
	attack_buffer = 0.0
	play_sfx(&"blade_swing" if action == &"blade" else (&"kick" if action == &"kick" else &"fist_swing"))


func _attack_definition(action: StringName) -> Dictionary:
	if action == &"kick":
		return {"windup": 0.11, "active": 0.09, "recovery": 0.27, "damage": 7900, "force": 94.0, "reach": 3.35, "radius": 1.6, "launch": 6.8, "critical": false}
	if action == &"fist":
		var fists: Array[Dictionary] = [
			{"windup": 0.07, "active": 0.07, "recovery": 0.12, "damage": 4400, "force": 36.0, "reach": 2.9, "radius": 1.4, "launch": 0.0, "critical": false},
			{"windup": 0.06, "active": 0.08, "recovery": 0.13, "damage": 5300, "force": 44.0, "reach": 3.05, "radius": 1.45, "launch": 0.0, "critical": false},
			{"windup": 0.10, "active": 0.09, "recovery": 0.22, "damage": 8700, "force": 74.0, "reach": 3.2, "radius": 1.55, "launch": 3.8, "critical": true},
		]
		return fists[combo_index % fists.size()]
	var blades: Array[Dictionary] = [
		{"windup": 0.06, "active": 0.07, "recovery": 0.11, "damage": 6600, "force": 29.0, "reach": 4.0, "radius": 1.9, "launch": 0.0, "critical": false},
		{"windup": 0.055, "active": 0.075, "recovery": 0.13, "damage": 7800, "force": 38.0, "reach": 4.15, "radius": 1.95, "launch": 0.0, "critical": false},
		{"windup": 0.10, "active": 0.085, "recovery": 0.24, "damage": 13000, "force": 73.0, "reach": 4.35, "radius": 2.05, "launch": 3.0, "critical": true},
	]
	return blades[combo_index % blades.size()]


func _update_combat(delta: float) -> void:
	if combat_state == CombatState.IDLE:
		swing_visual = maxf(swing_visual - delta * 8.0, 0.0)
		punch_visual = maxf(punch_visual - delta * 8.0, 0.0)
		kick_visual = maxf(kick_visual - delta * 8.0, 0.0)
		return

	combat_state_time -= delta
	var phase := 1.0 - clampf(combat_state_time / maxf(combat_state_duration, 0.001), 0.0, 1.0)
	var visual := _attack_visual_progress(phase)
	swing_visual = visual if combat_action == &"blade" else 0.0
	punch_visual = visual if combat_action == &"fist" else 0.0
	kick_visual = visual if combat_action == &"kick" else 0.0

	while combat_state != CombatState.IDLE and combat_state_time <= 0.0:
		var overshoot := -combat_state_time
		if combat_state == CombatState.WINDUP:
			combat_state = CombatState.ACTIVE
			combat_state_duration = float(attack_data["active"])
			combat_state_time = combat_state_duration - overshoot
			_resolve_attack()
		elif combat_state == CombatState.ACTIVE:
			combat_state = CombatState.RECOVERY
			combat_state_duration = float(attack_data["recovery"])
			combat_state_time = combat_state_duration - overshoot
		else:
			combat_state = CombatState.IDLE
			combat_state_time = 0.0
			combo_window = 0.46
			if combat_action == &"blade" or combat_action == &"fist":
				combo_index = (combo_index + 1) % 3
			if buffered_action != &"" and attack_buffer > 0.0:
				var next := buffered_action
				_start_attack(next)


func _attack_visual_progress(phase: float) -> float:
	if combat_state == CombatState.WINDUP:
		return phase * 0.28
	if combat_state == CombatState.ACTIVE:
		return 0.28 + phase * 0.48
	return 0.76 + phase * 0.24


func _resolve_attack() -> void:
	var hit := _find_melee_target(float(attack_data["reach"]), float(attack_data["radius"]))
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider == null:
		return
	if collider.has_method("deflect"):
		collider.deflect(-camera.global_transform.basis.z)
		play_sfx(&"deflect")
		gain_watchfire(14.0)
		_request_impact(0.9, hit.get("position", collider.global_position))
		return
	if not collider.has_method("take_damage"):
		return

	var damage := int(attack_data["damage"])
	var force := float(attack_data["force"])
	var launch := float(attack_data["launch"])
	var critical := bool(attack_data["critical"])
	if watch_active:
		damage = int(float(damage) * 1.42)
		force *= 1.22
		critical = true
	var hit_position: Vector3 = hit.get("position", collider.global_position)
	collider.take_damage(damage, hit_position, critical, force, launch)
	play_sfx(&"dagger_hit" if combat_action == &"blade" else (&"kick" if combat_action == &"kick" else &"punch"))
	var meter_gain := 11.0 if critical else (9.0 if combat_action != &"blade" else 6.0)
	gain_watchfire(meter_gain)
	_request_impact(0.9 if critical else 0.58, hit_position)
	emit_signal("attack_landed", damage, critical)


func _cancel_recovery() -> void:
	if combat_state == CombatState.RECOVERY:
		combat_state = CombatState.IDLE
		combat_state_time = 0.0


func _find_melee_target(reach: float, sweep_radius: float) -> Dictionary:
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z
	var to := from + forward * reach
	var ray_query := PhysicsRayQueryParameters3D.create(from, to, 2 | 4)
	ray_query.exclude = [get_rid()]
	var ray_hit := get_world_3d().direct_space_state.intersect_ray(ray_query)
	if not ray_hit.is_empty():
		return ray_hit

	var sphere := SphereShape3D.new()
	sphere.radius = sweep_radius
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = sphere
	shape_query.transform = Transform3D(Basis.IDENTITY, from + forward * (reach * 0.54))
	shape_query.collision_mask = 2 | 4
	shape_query.exclude = [get_rid()]
	var candidates := get_world_3d().direct_space_state.intersect_shape(shape_query, 16)
	var best: Dictionary = {}
	var best_alignment := 0.08
	for candidate in candidates:
		var candidate_collider = candidate.get("collider")
		if not candidate_collider is Node3D:
			continue
		var offset: Vector3 = candidate_collider.global_position - from
		var distance := offset.length()
		if distance <= 0.001 or distance > reach + 0.8:
			continue
		var alignment := forward.dot(offset / distance)
		if alignment > best_alignment:
			best_alignment = alignment
			best = {
				"collider": candidate_collider,
				"position": candidate_collider.global_position + Vector3.UP * 0.8,
			}
	return best


func _handle_dagger_input() -> void:
	if dagger_state == DaggerState.HELD:
		_throw_dagger()
	elif dagger_entity != null and is_instance_valid(dagger_entity):
		if dagger_entity.begin_rewind():
			play_sfx(&"recall")


func _throw_dagger() -> void:
	if dagger_state != DaggerState.HELD:
		return
	var cast := DaggerThrowScript.new()
	cast.player = self
	cast.direction = -camera.global_transform.basis.z
	get_tree().current_scene.add_child(cast)
	cast.global_position = camera.global_position + cast.direction * 0.72
	cast.state_changed.connect(_on_dagger_state_changed)
	cast.returned.connect(_on_dagger_returned)
	dagger_entity = cast
	dagger_state = DaggerState.OUTBOUND
	play_sfx(&"throw")
	emit_signal("score_event", &"dagger_thrown", {
		"time": time_left,
		"cost": 0.0,
		"meter": watchfire,
	})


func request_dagger_rewind(path_length: float) -> bool:
	var distance_cost := clampf(path_length * 0.48, 6.0, 26.0)
	var recall_cost := DAGGER_RECALL_BASE_COST + distance_cost
	if not spend_watchfire(recall_cost):
		play_sfx(&"empty")
		emit_signal("score_event", &"dagger_rewind_denied", {
			"required": recall_cost,
			"meter": watchfire,
		})
		return false
	emit_signal("score_event", &"dagger_rewind_paid", {
		"cost": recall_cost,
		"meter": watchfire,
	})
	return true


func spend_watchfire(amount: float) -> bool:
	if watchfire + 0.001 < amount:
		return false
	watchfire = maxf(0.0, watchfire - amount)
	return true


func _on_dagger_state_changed(new_state: int) -> void:
	match new_state:
		DaggerThrowScript.State.OUTBOUND:
			dagger_state = DaggerState.OUTBOUND
		DaggerThrowScript.State.BALLISTIC:
			dagger_state = DaggerState.BALLISTIC
		DaggerThrowScript.State.STUCK:
			dagger_state = DaggerState.STUCK
		DaggerThrowScript.State.REWINDING:
			dagger_state = DaggerState.REWINDING
	emit_signal("score_event", &"dagger_state", {"state": dagger_state})


func _on_dagger_returned(via_recall: bool) -> void:
	dagger_entity = null
	dagger_state = DaggerState.HELD
	swing_visual = 0.42
	if via_recall:
		emit_signal("score_event", &"dagger_recovered", {
			"method": "rewind",
			"refund": 0.0,
			"meter": watchfire,
		})
	else:
		emit_signal("score_event", &"dagger_recovered", {
			"method": "pickup",
			"refund": 0.0,
			"meter": watchfire,
		})
	play_sfx(&"pickup")


func _check_dagger_pickup() -> void:
	if dagger_entity == null or not is_instance_valid(dagger_entity):
		return
	if dagger_entity.can_pick_up() and global_position.distance_to(dagger_entity.global_position) < 1.45:
		dagger_entity.pick_up()


func hurt(seconds_spent: float, maximum_lost: float, source_position: Vector3) -> bool:
	if not active or invulnerability > 0.0 or expired_once:
		return false
	invulnerability = 0.54
	watch_previous_time = time_left
	max_time = maxf(11.0, max_time - maximum_lost)
	time_left = clampf(time_left - seconds_spent, 0.0, max_time)
	wound_visual = 1.0
	var away := global_position - source_position
	if away.length_squared() > 0.001:
		var local_side := global_transform.basis.x.dot(away.normalized())
		camera_kick += Vector2(local_side, 0.7) * 0.8
	play_sfx(&"wound")
	emit_signal("rewound_wound", seconds_spent, maximum_lost)
	var game := get_parent()
	if game.has_method("request_wound_effect"):
		game.request_wound_effect(source_position)
	if time_left <= 0.0:
		_expire()
	return true


func restore_time(seconds: float) -> void:
	var before := time_left
	time_left = minf(max_time, time_left + seconds)
	var restored := time_left - before
	if restored > 0.01:
		watch_previous_time = before
		restore_visual = 1.0
		emit_signal("score_event", &"time_restored", {
			"amount": restored,
			"time": time_left,
			"maximum": max_time,
		})


func gain_watchfire(amount: float) -> void:
	watchfire = minf(MAX_WATCHFIRE, watchfire + amount)


func _request_impact(strength: float, at: Vector3) -> void:
	impact_visual = maxf(impact_visual, strength)
	camera_kick += Vector2(randf_range(-1.0, 1.0), -0.4) * strength
	var game := get_parent()
	if game.has_method("request_impact"):
		game.request_impact(strength, at)


func play_sfx(cue: StringName) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var path := ""
	var volume_db := -8.0
	var sound_pitch := 1.0
	match cue:
		&"dagger_hit":
			path = "res://assets/audio/impactMetal_medium_000.ogg"
			sound_pitch = randf_range(0.92, 1.08)
		&"deflect":
			path = "res://assets/audio/impactMetal_heavy_001.ogg"
			volume_db = -4.0
		&"punch":
			path = "res://assets/audio/impactPunch_medium_003.ogg"
			sound_pitch = randf_range(0.94, 1.06)
		&"kick":
			path = "res://assets/audio/impactPunch_heavy_000.ogg"
			volume_db = -4.0
			sound_pitch = 0.86
		&"blade_swing":
			path = "res://assets/audio/impactMetal_light_002.ogg"
			volume_db = -12.0
			sound_pitch = 1.32
		&"fist_swing":
			path = "res://assets/audio/impactPunch_medium_001.ogg"
			volume_db = -14.0
			sound_pitch = 1.2
		&"throw":
			path = "res://assets/audio/impactMetal_light_002.ogg"
			sound_pitch = 1.16
		&"recall":
			path = "res://assets/audio/impactMetal_light_000.ogg"
			sound_pitch = 0.82
		&"pickup":
			path = "res://assets/audio/impactMetal_light_000.ogg"
			volume_db = -11.0
			sound_pitch = 1.25
		&"empty":
			path = "res://assets/audio/impactMetal_light_000.ogg"
			volume_db = -15.0
			sound_pitch = 0.52
		&"wound":
			path = "res://assets/audio/impactGlass_heavy_001.ogg"
			volume_db = -3.5
			sound_pitch = 0.82
		&"watch":
			path = "res://assets/audio/impactBell_heavy_000.ogg"
			volume_db = -9.0
			sound_pitch = 0.72
		&"jump", &"land", &"slide":
			path = "res://assets/audio/footstep_concrete_001.ogg"
			volume_db = -13.0 if cue == &"jump" else -10.0
			sound_pitch = 1.2 if cue == &"jump" else (0.72 if cue == &"slide" else 0.86)
		&"step":
			path = "res://assets/audio/impactGlass_heavy_001.ogg"
			volume_db = -8.0
			sound_pitch = 0.64
	if path.is_empty():
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = sound_pitch
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()


func _expire() -> void:
	if expired_once:
		return
	expired_once = true
	time_left = 0.0
	watch_active = false
	emit_signal("expired")
