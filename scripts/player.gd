extends CharacterBody3D

signal expired
signal rewound_wound(seconds_spent: float, maximum_lost: float)
signal attack_landed(amount: int, critical: bool)
signal score_event(tag: StringName, payload: Dictionary)

const DaggerThrowScript = preload("res://scripts/dagger_throw.gd")

const STARTING_MAX_TIME := 60.0
const MAX_WATCHFIRE := 100.0
const WALK_SPEED := 9.5
const AIR_SPEED := 7.4
const JUMP_VELOCITY := 8.7
const GRAVITY := 25.0

enum DaggerState {
	HELD,
	OUTBOUND,
	STUCK,
	REWINDING,
}

var time_left := 54.0
var max_time := STARTING_MAX_TIME
var watchfire := 42.0
var watch_active := false
var active := false

var camera: Camera3D
var dagger_state: int = DaggerState.HELD
var dagger_entity: Node3D

var pitch := 0.0
var attack_cooldown := 0.0
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


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1

	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)

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
	invulnerability = maxf(invulnerability - delta, 0.0)
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	combo_window = maxf(combo_window - delta, 0.0)
	swing_visual = maxf(swing_visual - delta * 4.5, 0.0)
	punch_visual = maxf(punch_visual - delta * 5.8, 0.0)
	kick_visual = maxf(kick_visual - delta * 4.2, 0.0)
	wound_visual = maxf(wound_visual - delta * 2.7, 0.0)
	restore_visual = maxf(restore_visual - delta * 3.5, 0.0)

	if not active:
		return

	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0:
		_expire()
		return

	watch_active = Input.is_action_pressed("watch") and watchfire > 0.0
	if watch_active:
		watchfire = maxf(watchfire - 24.0 * delta, 0.0)
	if watch_active != was_watch_active:
		if watch_active:
			play_sfx(&"watch")
		emit_signal("score_event", &"watch_state", {
			"active": watch_active,
			"meter": watchfire,
			"time": time_left,
		})
		was_watch_active = watch_active

	if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
		_attack()
	if Input.is_action_just_pressed("throw_dagger"):
		_handle_dagger_input()
	if dagger_entity != null and is_instance_valid(dagger_entity):
		if dagger_entity.can_pick_up() and global_position.distance_to(dagger_entity.global_position) < 1.45:
			dagger_entity.pick_up()

	_move(delta)


func _move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var target_speed := WALK_SPEED if is_on_floor() else AIR_SPEED
	var target := direction * target_speed
	var acceleration := 38.0 if is_on_floor() else 13.0
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	move_and_slide()


func _attack() -> void:
	if dagger_state == DaggerState.HELD:
		_dagger_attack()
	else:
		_unarmed_attack()


func _dagger_attack() -> void:
	if combo_window <= 0.0:
		combo_index = 0
	else:
		combo_index = (combo_index + 1) % 3

	var damage_values := [6800, 8300, 13200]
	var force_values := [24.0, 31.0, 58.0]
	var damage: int = damage_values[combo_index]
	var force: float = force_values[combo_index]
	var critical := combo_index == 2
	attack_cooldown = 0.21 if combo_index < 2 else 0.34
	combo_window = 0.46
	swing_visual = 1.0

	var hit := _find_melee_target(4.2, 2.05)
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider != null and collider.has_method("deflect"):
		collider.deflect(-camera.global_transform.basis.z)
		play_sfx(&"deflect")
		gain_watchfire(14.0)
		emit_signal("score_event", &"projectile_deflected", {"time": time_left})
	elif collider != null and collider.has_method("take_damage"):
		var hit_position: Vector3 = hit.get("position", collider.global_position)
		collider.take_damage(damage, hit_position, critical, force)
		play_sfx(&"dagger_hit")
		gain_watchfire(8.0 if not critical else 15.0)
		emit_signal("attack_landed", damage, critical)


func _unarmed_attack() -> void:
	if combo_window <= 0.0:
		combo_index = 0
	else:
		combo_index = (combo_index + 1) % 3

	var is_kick := combo_index == 2
	var damage := 9100 if is_kick else (4700 if combo_index == 0 else 5600)
	var force := 82.0 if is_kick else 36.0
	attack_cooldown = 0.38 if is_kick else 0.24
	combo_window = 0.52
	if is_kick:
		kick_visual = 1.0
	else:
		punch_visual = 1.0

	var hit := _find_melee_target(2.65 if not is_kick else 3.15, 1.55)
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider != null and collider.has_method("take_damage"):
		var hit_position: Vector3 = hit.get("position", collider.global_position)
		collider.take_damage(damage, hit_position, is_kick, force)
		play_sfx(&"kick" if is_kick else &"punch")
		gain_watchfire(14.0 if not is_kick else 20.0)
		emit_signal("attack_landed", damage, is_kick)


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
	var best_distance: float = INF
	for candidate in candidates:
		var collider = candidate.get("collider")
		if not collider is Node3D:
			continue
		var offset: Vector3 = collider.global_position - from
		var distance := offset.length()
		if distance <= 0.001 or distance > reach + 0.8:
			continue
		if forward.dot(offset / distance) < 0.12:
			continue
		if distance < best_distance:
			best_distance = distance
			best = {
				"collider": collider,
				"position": collider.global_position + Vector3.UP * 0.8,
			}
	return best


func _handle_dagger_input() -> void:
	if dagger_state == DaggerState.HELD:
		_throw_dagger()
	elif dagger_entity != null and is_instance_valid(dagger_entity):
		play_sfx(&"recall")
		dagger_entity.begin_rewind()


func _throw_dagger() -> void:
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
	emit_signal("score_event", &"dagger_thrown", {"time": time_left})


func _on_dagger_state_changed(new_state: int) -> void:
	match new_state:
		DaggerThrowScript.State.OUTBOUND:
			dagger_state = DaggerState.OUTBOUND
		DaggerThrowScript.State.STUCK:
			dagger_state = DaggerState.STUCK
		DaggerThrowScript.State.REWINDING:
			dagger_state = DaggerState.REWINDING
	emit_signal("score_event", &"dagger_state", {"state": dagger_state})


func _on_dagger_returned() -> void:
	dagger_entity = null
	dagger_state = DaggerState.HELD
	swing_visual = 0.42
	play_sfx(&"pickup")
	emit_signal("score_event", &"dagger_recovered", {"time": time_left})


func hurt(seconds_spent: float, maximum_lost: float, _source_position: Vector3) -> bool:
	if not active or invulnerability > 0.0 or expired_once:
		return false

	invulnerability = 0.54
	watch_previous_time = time_left
	max_time = maxf(11.0, max_time - maximum_lost)
	time_left = clampf(time_left - seconds_spent, 0.0, max_time)
	wound_visual = 1.0
	play_sfx(&"wound")
	emit_signal("rewound_wound", seconds_spent, maximum_lost)
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


func play_sfx(cue: StringName) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var path := ""
	var volume_db := -8.0
	var pitch := 1.0
	match cue:
		&"dagger_hit":
			path = "res://assets/audio/impactMetal_medium_000.ogg"
			pitch = randf_range(0.92, 1.08)
		&"deflect":
			path = "res://assets/audio/impactMetal_heavy_001.ogg"
			volume_db = -5.0
		&"punch":
			path = (
				"res://assets/audio/impactPunch_medium_001.ogg"
				if combo_index == 0
				else "res://assets/audio/impactPunch_medium_003.ogg"
			)
			pitch = randf_range(0.94, 1.06)
		&"kick":
			path = "res://assets/audio/impactPunch_heavy_000.ogg"
			volume_db = -5.0
			pitch = 0.86
		&"throw":
			path = "res://assets/audio/impactMetal_light_002.ogg"
			pitch = 1.16
		&"recall":
			path = "res://assets/audio/impactMetal_light_000.ogg"
			pitch = 0.82
		&"pickup":
			path = "res://assets/audio/impactMetal_light_000.ogg"
			volume_db = -11.0
			pitch = 1.25
		&"wound":
			path = "res://assets/audio/impactGlass_heavy_001.ogg"
			volume_db = -3.5
			pitch = 0.82
		&"watch":
			path = "res://assets/audio/impactBell_heavy_000.ogg"
			volume_db = -9.0
			pitch = 0.72
	if path.is_empty():
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
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
