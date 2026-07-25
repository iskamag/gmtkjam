extends Node3D

signal returned
signal state_changed(new_state: int)

enum State {
	OUTBOUND,
	STUCK,
	REWINDING,
}

var player: CharacterBody3D
var direction := Vector3.FORWARD
var state: int = State.OUTBOUND
var outbound_speed := 24.0
var rewind_speed := 38.0
var outbound_time := 0.0
var path: Array[Vector3] = []
var path_index := 0
var outbound_hits: Dictionary = {}
var rewind_hits: Dictionary = {}
var spin := 0.0


func _ready() -> void:
	path.append(global_position)
	_build_dagger()
	emit_signal("state_changed", state)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return

	match state:
		State.OUTBOUND:
			_process_outbound(delta)
		State.STUCK:
			rotation.z = sin(Time.get_ticks_msec() * 0.006) * 0.025
		State.REWINDING:
			_process_rewind(delta)

	spin += delta * (13.0 if state != State.STUCK else 0.0)
	rotation.z = spin


func begin_rewind() -> void:
	if state == State.REWINDING:
		return
	state = State.REWINDING
	path_index = path.size() - 1
	emit_signal("state_changed", state)


func can_pick_up() -> bool:
	return state == State.STUCK or state == State.OUTBOUND


func pick_up() -> void:
	_finish_return()


func _process_outbound(delta: float) -> void:
	outbound_time += delta
	var aim: Vector3 = -player.camera.global_transform.basis.z
	var steering := clampf(delta * 3.8, 0.0, 1.0)
	direction = direction.slerp(aim, steering).normalized()

	var from := global_position
	var to := from + direction * outbound_speed * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider != null and collider.has_method("take_damage"):
			var id: int = collider.get_instance_id()
			if not outbound_hits.has(id):
				outbound_hits[id] = true
				collider.take_damage(14200, hit.get("position", to), false, 34.0)
				player.play_sfx(&"dagger_hit")
				player.gain_watchfire(7.0)
			global_position = to
		else:
			global_position = hit.get("position", to)
			_set_stuck()
			return
	else:
		global_position = to

	if path.is_empty() or path[-1].distance_to(global_position) > 0.22:
		path.append(global_position)
	if outbound_time >= 1.65:
		_set_stuck()


func _process_rewind(delta: float) -> void:
	if path_index >= 0:
		var target: Vector3 = path[path_index]
		var from := global_position
		var to := global_position.move_toward(target, rewind_speed * delta)
		_damage_rewind_segment(from, to)
		global_position = to
		if global_position.distance_to(target) < 0.09:
			path_index -= 1
	else:
		var target: Vector3 = player.camera.global_position - player.camera.global_transform.basis.z * 0.28
		var from := global_position
		var to := global_position.move_toward(target, rewind_speed * delta)
		_damage_rewind_segment(from, to)
		global_position = to
		if global_position.distance_to(target) < 0.65:
			_finish_return()


func _damage_rewind_segment(from: Vector3, to: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider == null or not collider.has_method("take_damage"):
		return
	var id: int = collider.get_instance_id()
	if rewind_hits.has(id):
		return
	rewind_hits[id] = true
	collider.take_damage(18800, hit.get("position", to), true, 68.0)
	player.play_sfx(&"deflect")
	player.gain_watchfire(11.0)


func _set_stuck() -> void:
	if state == State.STUCK:
		return
	state = State.STUCK
	player.play_sfx(&"pickup")
	emit_signal("state_changed", state)


func _finish_return() -> void:
	emit_signal("returned")
	queue_free()


func _build_dagger() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.67, 0.65, 0.57)
	steel.metallic = 0.72
	steel.roughness = 0.34

	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.075, 0.052, 0.037)
	leather.roughness = 0.92

	_add_box(Vector3(0.08, 0.025, 0.62), Vector3(0.0, 0.0, -0.22), steel)
	_add_box(Vector3(0.29, 0.052, 0.075), Vector3(0.0, 0.0, 0.12), steel)
	_add_box(Vector3(0.11, 0.11, 0.34), Vector3(0.0, 0.0, 0.32), leather)


func _add_box(size: Vector3, at: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	add_child(instance)
