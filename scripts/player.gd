extends CharacterBody3D

signal expired
signal rewound_wound(seconds_spent: float, maximum_lost: float)
signal attack_landed(amount: int, critical: bool)
signal score_event(tag: StringName, payload: Dictionary)

const DaggerThrowScript = preload("res://scripts/dagger_throw.gd")

const SFX_BAION := preload("res://sounds/baion.wav")
const SFX_SWORD_DRAW := preload("res://sounds/sword-draw.wav")
const SFX_GUNSHOT := preload("res://sounds/gunshot.wav")
const SFX_HIT := preload("res://sounds/hit.ogg")
const SFX_RECALL := preload("res://sounds/recall.wav")

# Original purpose-built sounds (assets/audio/) — each has a clear role.
const SFX_BELL := preload("res://assets/audio/impactBell_heavy_000.ogg")
const SFX_GLASS := preload("res://assets/audio/impactGlass_heavy_001.ogg")
const SFX_METAL_MED := preload("res://assets/audio/impactMetal_medium_000.ogg")
const SFX_METAL_HVY := preload("res://assets/audio/impactMetal_heavy_001.ogg")
const SFX_METAL_LT := preload("res://assets/audio/impactMetal_light_000.ogg")
const SFX_PUNCH_MED := preload("res://assets/audio/impactPunch_medium_003.ogg")
const SFX_PUNCH_HVY := preload("res://assets/audio/impactPunch_heavy_000.ogg")
const SFX_FOOTSTEP := preload("res://assets/audio/footstep_concrete_001.ogg")

const STARTING_MAX_TIME := 60.0
const MAX_WATCHFIRE := 100.0
const WATCH_SLOW_BURN := 15.0
const WATCH_HOSTILE_SCALE := 0.115
const OVERCLOCK_HOSTILE_SCALE := 0.045
const OVERCLOCK_DURATION := 1.20
const DAGGER_RECALL_BASE_COST := 18.0
const RUN_SPEED := 10.8
const GROUND_ACCELERATION := 48.0
const GROUND_FRICTION := 31.0
const AIR_ACCELERATION := 15.0
const AIR_SPEED_LIMIT := 12.8
const JUMP_VELOCITY := 9.0
const SLAM_SPEED := 26.0
const SLAM_RADIUS := 4.4
const GRAVITY := 27.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.13
const SLIDE_DURATION := 0.72
const CHRONOSTEP_SPEED := 19.5
const CHRONOSTEP_DURATION := 0.16
const DEFLECT_ASSIST_ANGLE := 15.0
const KICK_ASSIST_ANGLE := 23.0
const REFLECT_ASSIST_RANGE := 34.0

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
var watch_entry_visual := 0.0
var overclock_timer := 0.0
var overclock_visual := 0.0
var watch_motion_visual := 0.0
var overclock_reason: StringName = &""
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
var stride_bob := 0.0
var movement_input := Vector2.ZERO
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
var slam_active := false
var _master_lowpass: AudioEffectLowPassFilter


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

	if DisplayServer.get_name() != "headless":
		var bus := AudioServer.get_bus_index("Master")
		if bus >= 0:
			_master_lowpass = AudioEffectLowPassFilter.new()
			_master_lowpass.cutoff_hz = 20500.0
			AudioServer.add_bus_effect(bus, _master_lowpass)


func set_active(value: bool) -> void:
	active = value
	if value:
		expired_once = false
	else:
		watch_active = false
		was_watch_active = false
		overclock_timer = 0.0
		overclock_visual = 0.0
		_sync_watchfire_shader()


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
	_update_combat(delta * get_player_combat_time_scale())
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
	watch_entry_visual = maxf(watch_entry_visual - delta * 4.8, 0.0)
	overclock_timer = maxf(overclock_timer - delta, 0.0)
	var overclock_target := 1.0 if is_watch_overclocked() else 0.0
	var overclock_response := 24.0 if overclock_target > overclock_visual else 10.0
	overclock_visual = lerpf(
		overclock_visual,
		overclock_target,
		1.0 - exp(-delta * overclock_response)
	)
	var motion_target := clampf(planar_speed / RUN_SPEED, 0.0, 1.35) if watch_active else 0.0
	watch_motion_visual = lerpf(
		watch_motion_visual,
		motion_target,
		1.0 - exp(-delta * (20.0 if watch_active else 8.0))
	)
	_sync_watchfire_shader()


func _update_watch(delta: float) -> void:
	watch_active = Input.is_action_pressed("watch") and watchfire > 0.0
	if watch_active:
		var burn_rate := WATCH_SLOW_BURN * (1.18 if is_watch_overclocked() else 1.0)
		watchfire = maxf(watchfire - burn_rate * delta, 0.0)
	if watch_active != was_watch_active:
		if watch_active:
			watch_entry_visual = 1.0
			camera.fov = maxf(camera.fov, 84.5)
			camera_kick += Vector2(0.0, -0.32)
			play_sfx(&"watch")
			play_sfx(&"watch_snap")
			var danger := _detect_last_instant_danger()
			if not danger.is_empty():
				_trigger_watch_overclock(
					StringName(danger.get("reason", "last_instant")),
					OVERCLOCK_DURATION,
					float(danger.get("score", 1.0))
				)
		else:
			overclock_timer = 0.0
			overclock_reason = &""
		emit_signal("score_event", &"watch_state", {
			"active": watch_active,
			"meter": watchfire,
			"time": time_left,
			"hostile_scale": get_hostile_time_scale(),
		})
		was_watch_active = watch_active
	# Witch time closes a global low-pass filter on the master bus so the whole
	# mix muffles; Overclock clamps it further for the "time being pulled" feel.
	if _master_lowpass != null:
		var target_cutoff := 20500.0 if not watch_active else (4800.0 if is_watch_overclocked() else 8400.0)
		_master_lowpass.cutoff_hz = lerpf(_master_lowpass.cutoff_hz, target_cutoff, 1.0 - exp(-delta * 12.0))
	_sync_watchfire_shader()


func is_watch_overclocked() -> bool:
	return watch_active and overclock_timer > 0.0


func get_hostile_time_scale() -> float:
	if not watch_active:
		return 1.0
	return OVERCLOCK_HOSTILE_SCALE if is_watch_overclocked() else WATCH_HOSTILE_SCALE


func get_player_time_dominance() -> float:
	if is_watch_overclocked():
		return 1.28
	if watch_active:
		return 1.09
	return 1.0


func get_player_combat_time_scale() -> float:
	if is_watch_overclocked():
		return 1.62
	if watch_active:
		return 1.18
	return 1.0


func _trigger_watch_overclock(
	reason: StringName,
	duration := OVERCLOCK_DURATION,
	danger_score := 1.0
) -> void:
	overclock_timer = maxf(overclock_timer, duration)
	overclock_reason = reason
	overclock_visual = maxf(overclock_visual, 0.42)
	watch_entry_visual = 1.0
	camera.fov = maxf(camera.fov, 88.0)
	camera_kick += Vector2(0.0, -0.55)
	play_sfx(&"overclock")
	emit_signal("score_event", &"watch_overclock", {
		"reason": reason,
		"duration": duration,
		"danger": danger_score,
		"hostile_scale": OVERCLOCK_HOSTILE_SCALE,
		"player_motion_scale": get_player_time_dominance(),
		"player_combat_scale": get_player_combat_time_scale(),
		"meter": watchfire,
		"time": time_left,
	})
	_sync_watchfire_shader()


func _detect_last_instant_danger() -> Dictionary:
	if not is_inside_tree():
		return {}
	var space := get_world_3d().direct_space_state
	var target := global_position + Vector3.UP * 0.85

	# Projectiles earn Overclock only when their current path will actually pass
	# through the player's body soon. Merely standing near a bullet is not enough.
	var projectile_sphere := SphereShape3D.new()
	projectile_sphere.radius = 6.5
	var projectile_query := PhysicsShapeQueryParameters3D.new()
	projectile_query.shape = projectile_sphere
	projectile_query.transform = Transform3D(Basis.IDENTITY, target)
	projectile_query.collision_mask = 4
	projectile_query.collide_with_areas = true
	projectile_query.collide_with_bodies = false
	projectile_query.exclude = [get_rid()]
	for candidate in space.intersect_shape(projectile_query, 24):
		var threat = candidate.get("collider")
		if not threat is Area3D or not threat.has_method("deflect"):
			continue
		var projectile_direction: Vector3 = threat.get("direction")
		var projectile_speed: float = float(threat.get("speed"))
		if projectile_direction.length_squared() < 0.001 or projectile_speed <= 0.0:
			continue
		var projectile_velocity := projectile_direction.normalized() * projectile_speed
		var to_player: Vector3 = target - threat.global_position
		var arrival := to_player.dot(projectile_velocity) / projectile_velocity.length_squared()
		if arrival < 0.0 or arrival > 0.62:
			continue
		var closest := (to_player - projectile_velocity * arrival).length()
		if closest <= 1.02:
			return {
				"reason": &"last_instant",
				"score": clampf(1.35 - arrival, 0.75, 1.35),
			}

	# A committed close-range strike provides the same skill check. This keeps
	# the system useful in melee rooms rather than making it projectile-only.
	var enemy_sphere := SphereShape3D.new()
	enemy_sphere.radius = 4.6
	var enemy_query := PhysicsShapeQueryParameters3D.new()
	enemy_query.shape = enemy_sphere
	enemy_query.transform = Transform3D(Basis.IDENTITY, target)
	enemy_query.collision_mask = 2
	enemy_query.collide_with_areas = false
	enemy_query.collide_with_bodies = true
	enemy_query.exclude = [get_rid()]
	for candidate in space.intersect_shape(enemy_query, 16):
		var threat = candidate.get("collider")
		if not threat is CharacterBody3D or not threat.has_method("take_damage"):
			continue
		var remaining_windup: float = float(threat.get("windup"))
		if remaining_windup > 0.015 and remaining_windup <= 0.30:
			return {
				"reason": &"last_instant",
				"score": clampf(1.28 - remaining_windup, 0.82, 1.28),
			}
	return {}


func _sync_watchfire_shader() -> void:
	if not is_inside_tree():
		return
	var game := get_parent()
	if game == null:
		return
	var hud = game.get("hud")
	if hud == null:
		return
	var material = hud.get("post_material")
	if not material is ShaderMaterial:
		return
	material.set_shader_parameter("time_snap", watch_entry_visual)
	material.set_shader_parameter("overclock", overclock_visual)
	material.set_shader_parameter("time_motion", watch_motion_visual)


func _read_action_inputs() -> void:
	if Input.is_action_just_pressed("jump"):
		jump_buffer = JUMP_BUFFER_TIME
	if Input.is_action_just_pressed("attack"):
		if not is_on_floor() and not slam_active:
			slam_active = true
			# Clear any pending combat so the rocket jump doesn't also trigger
			# a melee swing (the "attack plays twice" bug).
			combat_state = CombatState.IDLE
			combat_state_time = 0.0
			buffered_action = &""
			attack_buffer = 0.0
			_rocket_jump()
		else:
			_queue_attack(&"blade" if dagger_state == DaggerState.HELD else &"fist")
	if Input.is_action_just_pressed("kick"):
		if not is_on_floor():
			slam_active = true
			velocity.y = -SLAM_SPEED
			camera_kick.y -= 0.15
		else:
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
	movement_input = input
	var direction := (global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var time_dominance := get_player_time_dominance()

	# Resolve the ordinary vertical state before movement actions. Jump, wall-kick,
	# and slide-jump must be allowed to overwrite it later in this frame.
	if not grounded and chronostep_timer <= 0.0:
		velocity.y -= GRAVITY * delta
	elif grounded:
		velocity.y = minf(velocity.y, -0.5)

	if chronostep_timer > 0.0:
		chronostep_timer -= delta
		var step_steer := chronostep_direction
		if direction != Vector3.ZERO:
			step_steer = step_steer.slerp(direction, delta * 4.2).normalized()
		chronostep_direction = step_steer
		horizontal = step_steer * CHRONOSTEP_SPEED * sqrt(time_dominance)
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
			horizontal = horizontal.move_toward(
				direction * RUN_SPEED * time_dominance,
				GROUND_ACCELERATION * time_dominance * delta
			)
		else:
			horizontal = horizontal.move_toward(Vector3.ZERO, GROUND_FRICTION * delta)
	else:
		if direction != Vector3.ZERO:
			horizontal = horizontal.move_toward(
				direction * AIR_SPEED_LIMIT * time_dominance,
				AIR_ACCELERATION * time_dominance * delta
			)

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

	var fall_speed := absf(velocity.y)
	_was_on_floor = is_on_floor()
	move_and_slide()
	if not _was_on_floor and is_on_floor():
		landing_visual = clampf(fall_speed / 12.0, 0.25, 1.0)
		camera_kick.y -= landing_visual * 0.55
		if slam_active:
			_slam_impact(fall_speed)
			slam_active = false
		else:
			play_sfx(&"land")

	planar_speed = Vector2(velocity.x, velocity.z).length()
	var local_side_speed := global_transform.basis.x.dot(velocity)
	var local_forward_speed := -global_transform.basis.z.dot(velocity)
	var stride_amount := clampf(
		(absf(local_forward_speed) + absf(local_side_speed) * 0.16) / RUN_SPEED,
		0.0,
		1.2
	)
	if is_on_floor() and stride_amount > 0.06 and not is_sliding:
		move_cycle += delta * planar_speed * 0.47
	var stride_target := sin(move_cycle * 2.0) * stride_amount if is_on_floor() and not is_sliding else 0.0
	stride_bob = lerpf(stride_bob, stride_target, 1.0 - exp(-delta * 24.0))
	var stable_strafe := clampf(local_side_speed / RUN_SPEED, -1.0, 1.0)
	movement_sway = lerpf(movement_sway, stable_strafe, 1.0 - exp(-delta * 30.0))
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
	var bob_x := movement_sway * 0.010
	var bob_y := stride_bob * 0.013
	camera.position.x = lerpf(camera.position.x, bob_x + camera_kick.x * 0.025, 1.0 - exp(-delta * 30.0))
	camera.position.y = lerpf(
		camera.position.y,
		target_height + bob_y + camera_kick.y * 0.035,
		1.0 - exp(-delta * 28.0)
	)
	var side_speed := global_transform.basis.x.dot(velocity)
	var target_roll := clampf(-side_speed * 0.0032, -0.035, 0.035)
	if is_sliding:
		target_roll *= 0.72
	camera.rotation.z = lerpf(
		camera.rotation.z,
		target_roll + camera_kick.x * 0.012,
		1.0 - exp(-delta * 30.0)
	)
	var time_fov := 2.0 if watch_active else 0.0
	if is_watch_overclocked():
		time_fov = 5.5
	camera.fov = lerpf(
		camera.fov,
		79.0 + speed_factor * 9.0 + time_fov,
		1.0 - exp(-delta * (15.0 if watch_active else 8.0))
	)


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
	var hit: Dictionary = {}
	if combat_action == &"kick":
		# The foot owns its projectile interaction. A body in the center ray
		# must not steal a kick from a hostile shot crossing the wider sweep.
		hit = _find_kickable_projectile(
			float(attack_data["reach"]),
			float(attack_data["radius"])
		)
	if hit.is_empty():
		hit = _find_melee_target(float(attack_data["reach"]), float(attack_data["radius"]))
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider == null:
		return
	if collider.has_method("deflect"):
		if combat_action == &"kick" and collider.has_method("kick"):
			var raw_aim := -camera.global_transform.basis.z
			var expected_speed := maxf(
				float(collider.get("speed")) * 2.65,
				36.0
			)
			var aim := _assisted_reflect_direction(
				collider,
				raw_aim,
				KICK_ASSIST_ANGLE,
				expected_speed
			)
			if not bool(collider.kick(aim)):
				return
			var reward := 22.0
			gain_watchfire(reward)
			play_sfx(&"projectile_kick")
			var contact: Vector3 = hit.get("position", collider.global_position)
			_request_impact(1.42, contact)
			emit_signal("score_event", &"projectile_kicked", {
				"speed": float(collider.get("speed")),
				"damage": int(collider.get("deflected_damage")),
				"aim_assisted": aim.dot(raw_aim) < 0.9995,
				"watchfire_reward": reward,
				"meter": watchfire,
				"time": time_left,
			})
			return
		var perfect_deflect := watch_active
		var raw_deflect_aim := -camera.global_transform.basis.z
		var deflect_aim := _assisted_reflect_direction(
			collider,
			raw_deflect_aim,
			DEFLECT_ASSIST_ANGLE,
			float(collider.get("speed")) * 1.75
		)
		if combat_action == &"kick": collider.deflect(deflect_aim)
		if perfect_deflect:
			_trigger_watch_overclock(&"perfect_deflect", OVERCLOCK_DURATION + 0.28, 1.4)
			if collider.has_method("empower_deflection"):
				collider.empower_deflection(1.55)
		play_sfx(&"deflect")
		gain_watchfire(20.0 if perfect_deflect else 14.0)
		_request_impact(1.25 if perfect_deflect else 0.9, hit.get("position", collider.global_position))
		return
	if not collider.has_method("take_damage"):
		return

	var damage := int(attack_data["damage"])
	var force := float(attack_data["force"])
	var launch := float(attack_data["launch"])
	var critical := bool(attack_data["critical"])
	if is_watch_overclocked():
		damage = int(float(damage) * 2.12)
		force *= 1.62
		launch += 2.4
		critical = true
	elif watch_active:
		damage = int(float(damage) * 1.42)
		force *= 1.25
		critical = true
	var hit_position: Vector3 = hit.get("position", collider.global_position)
	collider.take_damage(damage, hit_position, critical, force, launch)
	play_sfx(&"dagger_hit" if combat_action == &"blade" else (&"kick" if combat_action == &"kick" else &"punch"))
	var meter_gain := _melee_watchfire_reward(critical, combat_action)
	gain_watchfire(meter_gain)
	if is_watch_overclocked():
		overclock_timer = maxf(overclock_timer, 0.34)
		emit_signal("score_event", &"overclock_hit", {
			"damage": damage,
			"remaining": overclock_timer,
			"reason": overclock_reason,
		})
	var impact_strength := 0.72
	if combat_action == &"kick":
		impact_strength = 1.02
	elif critical:
		impact_strength = 1.08
	if is_watch_overclocked():
		impact_strength = 1.32
	_request_impact(impact_strength, hit_position)
	emit_signal("attack_landed", damage, critical)


func _melee_watchfire_reward(critical: bool, action: StringName) -> float:
	# Watchfire is an earned burst, not a self-sustaining stance. Ordinary hits
	# made while hostile time is arrested keep their damage advantage but cannot
	# refill the meter faster than it burns. Projectile returns and eliminations
	# remain the deliberate ways to extend a strong sequence.
	if watch_active:
		return 0.0
	return 11.0 if critical else (9.0 if action != &"blade" else 6.0)


func _cancel_recovery() -> void:
	if combat_state == CombatState.RECOVERY:
		combat_state = CombatState.IDLE
		combat_state_time = 0.0


func _find_melee_target(reach: float, sweep_radius: float) -> Dictionary:
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z
	var to := from + forward * reach
	# World geometry participates in the primary cast so a target cannot be
	# struck through a barrier merely because combat lives on another layer.
	var ray_query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4)
	ray_query.exclude = [get_rid()]
	ray_query.collide_with_areas = true
	ray_query.collide_with_bodies = true
	var ray_hit := get_world_3d().direct_space_state.intersect_ray(ray_query)
	if not ray_hit.is_empty():
		return ray_hit

	var sphere := SphereShape3D.new()
	sphere.radius = sweep_radius
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = sphere
	shape_query.transform = Transform3D(Basis.IDENTITY, from + forward * (reach * 0.54))
	shape_query.collision_mask = 2 | 4
	shape_query.collide_with_areas = true
	shape_query.collide_with_bodies = true
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
		var contact: Vector3 = candidate_collider.global_position + Vector3.UP * 0.8
		if not _melee_path_clear(from, contact, candidate_collider):
			continue
		var alignment := forward.dot(offset / distance)
		if alignment > best_alignment:
			best_alignment = alignment
			best = {
				"collider": candidate_collider,
				"position": contact,
			}
	return best


func _melee_path_clear(from: Vector3, to: Vector3, candidate: Node3D) -> bool:
	var cover_query := PhysicsRayQueryParameters3D.create(from, to, 1)
	cover_query.exclude = [get_rid(), candidate.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(cover_query).is_empty()


func _find_kickable_projectile(reach: float, sweep_radius: float) -> Dictionary:
	if not is_inside_tree():
		return {}
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z
	var sphere := SphereShape3D.new()
	sphere.radius = sweep_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, from + forward * (reach * 0.54))
	query.collision_mask = 4
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = [get_rid()]

	var best: Dictionary = {}
	var best_score := -INF
	for candidate in get_world_3d().direct_space_state.intersect_shape(query, 24):
		var projectile = candidate.get("collider")
		if (
			not projectile is Node3D
			or not projectile.has_method("kick")
			or not projectile.has_method("is_kickable_projectile")
			or not bool(projectile.is_kickable_projectile())
		):
			continue
		var offset: Vector3 = projectile.global_position - from
		var distance := offset.length()
		if distance <= 0.001 or distance > reach + 0.8:
			continue
		if not _melee_path_clear(from, projectile.global_position, projectile):
			continue
		var alignment := forward.dot(offset / distance)
		if alignment < 0.12:
			continue
		# Favor the shot nearest the crosshair, with a small bias toward the
		# imminent close contact when several projectiles overlap the sweep.
		var score := alignment * 2.0 - distance / maxf(reach, 0.001) * 0.22
		if score > best_score:
			best_score = score
			best = {
				"collider": projectile,
				"position": projectile.global_position,
			}
	return best


func _assisted_reflect_direction(
	projectile: Node3D,
	requested_direction: Vector3,
	max_angle_degrees: float,
	expected_speed: float
) -> Vector3:
	if (
		not is_inside_tree()
		or not is_instance_valid(camera)
		or not is_instance_valid(projectile)
		or requested_direction.length_squared() < 0.001
	):
		return requested_direction.normalized()

	var requested := requested_direction.normalized()
	var origin := projectile.global_position
	var view_origin := camera.global_position
	var search := SphereShape3D.new()
	search.radius = REFLECT_ASSIST_RANGE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = search
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = 2
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid(), projectile.get_rid()]

	# Selection is based on the player's crosshair, not merely proximity to the
	# projectile. A tight cone keeps an intentional shot into empty space from
	# being bent toward an enemy off-screen.
	var minimum_alignment := cos(deg_to_rad(max_angle_degrees))
	var best_score := -INF
	var best_direction := requested
	for candidate_data in get_world_3d().direct_space_state.intersect_shape(query, 24):
		var candidate = candidate_data.get("collider")
		if (
			not candidate is CharacterBody3D
			or not candidate.has_method("take_damage")
			or not bool(candidate.get("alive"))
		):
			continue
		var aim_height := 2.15 if int(candidate.get("kind")) == 3 else 1.0
		var target_point: Vector3 = candidate.global_position + Vector3.UP * aim_height
		var view_offset := target_point - view_origin
		var distance := origin.distance_to(target_point)
		if view_offset.length_squared() < 0.001 or distance > REFLECT_ASSIST_RANGE:
			continue
		var alignment := requested.dot(view_offset.normalized())
		if alignment < minimum_alignment:
			continue

		var cover_query := PhysicsRayQueryParameters3D.create(
			origin,
			target_point,
			1
		)
		cover_query.exclude = [get_rid(), projectile.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(cover_query).is_empty():
			continue

		var lead_time := clampf(
			distance / maxf(expected_speed, 1.0),
			0.0,
			0.62
		)
		var target_velocity := Vector3(
			candidate.velocity.x,
			0.0,
			candidate.velocity.z
		)
		var assisted_point := target_point + target_velocity * lead_time * 0.58
		var assisted_direction := (assisted_point - origin).normalized()
		if assisted_direction.dot(requested) < cos(deg_to_rad(max_angle_degrees + 5.0)):
			continue
		var score := alignment * 5.0 - distance / REFLECT_ASSIST_RANGE * 0.28
		if score > best_score:
			best_score = score
			best_direction = assisted_direction
	return best_direction


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
	invulnerability = 0.38
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
	var to_contact := at - camera.global_position
	var contact_side := 0.0
	if to_contact.length_squared() > 0.0001:
		contact_side = clampf(camera.global_transform.basis.x.dot(to_contact.normalized()), -1.0, 1.0)
	camera_kick += Vector2(-contact_side * 0.72, -0.40) * strength
	var game := get_parent()
	if game.has_method("request_impact"):
		game.request_impact(strength, at)


# Stomp (baion): airborne kick thrusts the player down; on landing, an AoE
# ground-hit plays baion.wav with random pitch.
func _slam_impact(fall_speed: float) -> void:
	var strength := clampf(fall_speed / 20.0, 0.7, 1.6)
	_play_stream(SFX_BAION, 0.0, randf_range(0.82, 1.0))
	camera_kick.y -= strength * 0.8
	camera_kick.x += randf_range(-0.15, 0.15) * strength
	_request_impact(strength, global_position)
	var game := get_parent()
	if game != null and game.has_method("apply_slam"):
		game.apply_slam(global_position, SLAM_RADIUS, int(18.0 * strength), 3.0 * strength, 4.0 * strength)
	emit_signal("score_event", &"stomp", {"strength": strength})


# Rocket jump (dash): airborne slash explodes at the ground below and
# launches the player up + away from the blast. Damages enemies in the radius,
# plays the annotated hit sound with random pitch.
func _rocket_jump() -> void:
	# Find the ground point directly under the player for the blast origin.
	var blast := global_position - Vector3.UP * 1.0
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position - Vector3.UP * 6.0, collision_mask
	)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		blast = hit["position"]
	var strength := 1.0
	# Dash reuses the blade-swing sound; baion is reserved for the stomp.
	_play_stream(SFX_SWORD_DRAW, -3.0, randf_range(0.7, 0.9))
	camera_kick.y += strength * 0.7
	camera_kick.x += randf_range(-0.15, 0.15) * strength
	_request_impact(strength, blast)
	# Launch the player: strong up boost plus a nudge away from the blast.
	velocity.y = maxf(velocity.y, 0.0) + 16.5
	var away := (global_position - blast)
	away.y = 0.0
	if away.length_squared() > 0.01:
		velocity.x += away.normalized().x * 4.0
		velocity.z += away.normalized().z * 4.0
	var game := get_parent()
	if game != null and game.has_method("apply_slam"):
		game.apply_slam(blast, SLAM_RADIUS, 14, 3.2, 4.5)
	emit_signal("score_event", &"rocket_jump", {"strength": strength})


var _sfx_pool: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE := 12


func play_sfx(cue: StringName) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var stream: AudioStream = null
	var volume_db := -8.0
	var sound_pitch := 1.0
	match cue:
		&"dagger_hit":
			stream = SFX_METAL_MED; sound_pitch = randf_range(0.92, 1.08)
		&"deflect":
			stream = SFX_METAL_HVY; volume_db = -4.0; sound_pitch = randf_range(0.8, 0.95)
		&"punch":
			stream = SFX_PUNCH_MED; sound_pitch = randf_range(0.94, 1.06)
		&"kick":
			stream = SFX_PUNCH_HVY; volume_db = -4.0; sound_pitch = 0.86
		&"projectile_kick":
			stream = SFX_METAL_HVY; volume_db = -2.0; sound_pitch = 0.68
		&"blade_swing":
			stream = SFX_SWORD_DRAW; volume_db = -10.0; sound_pitch = randf_range(1.1, 1.4)
		&"fist_swing":
			stream = SFX_PUNCH_MED; volume_db = -14.0; sound_pitch = 1.2
		&"throw":
			stream = SFX_GUNSHOT; sound_pitch = randf_range(0.9, 1.2)
		&"recall":
			stream = SFX_RECALL; sound_pitch = randf_range(0.78, 0.88)
		&"pickup":
			stream = SFX_METAL_LT; volume_db = -11.0; sound_pitch = 1.25
		&"empty":
			stream = SFX_METAL_LT; volume_db = -15.0; sound_pitch = 0.52
		&"wound":
			stream = SFX_GLASS; volume_db = -3.5; sound_pitch = 0.82
		&"watch":
			stream = SFX_BELL; volume_db = -7.0; sound_pitch = 0.58
		&"watch_snap":
			stream = SFX_GLASS; volume_db = -11.0; sound_pitch = 1.72
		&"overclock":
			stream = SFX_METAL_HVY; volume_db = -8.0; sound_pitch = 0.47
		&"jump", &"land":
			stream = SFX_FOOTSTEP; volume_db = -13.0 if cue == &"jump" else -10.0
			sound_pitch = 1.2 if cue == &"jump" else 0.86
		&"slide":
			stream = SFX_FOOTSTEP; volume_db = -10.0; sound_pitch = 0.72
		&"step":
			stream = SFX_FOOTSTEP; volume_db = -14.0; sound_pitch = randf_range(0.5, 0.7)
		&"train":
			stream = SFX_FOOTSTEP; volume_db = -20.0; sound_pitch = 0.48
		&"memory":
			stream = SFX_BELL; volume_db = -16.0; sound_pitch = 1.62
		&"crash":
			stream = SFX_METAL_HVY; volume_db = -1.5; sound_pitch = 0.58
		&"hit":
			stream = SFX_HIT; volume_db = -6.0; sound_pitch = randf_range(0.95, 1.18)
		_:
			return
	_play_stream(stream, volume_db, sound_pitch)


func _play_stream(stream: AudioStream, volume_db: float, sound_pitch: float) -> void:
	if stream == null:
		return
	if watch_active:
		sound_pitch *= 0.52 if is_watch_overclocked() else 0.68
		volume_db -= 1.5
	# Grab a free node from the pool (or create one if needed).
	var voice: AudioStreamPlayer = null
	for node in _sfx_pool:
		if not node.playing:
			voice = node
			break
	if voice == null:
		if _sfx_pool.size() >= SFX_POOL_SIZE:
			voice = _sfx_pool[0]
		else:
			voice = AudioStreamPlayer.new()
			_sfx_pool.append(voice)
			add_child(voice)
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = sound_pitch
	voice.play()


func _expire() -> void:
	if expired_once:
		return
	expired_once = true
	time_left = 0.0
	watch_active = false
	overclock_timer = 0.0
	overclock_visual = 0.0
	_sync_watchfire_shader()
	emit_signal("expired")
