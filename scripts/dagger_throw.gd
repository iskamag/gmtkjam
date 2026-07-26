extends Node3D

signal returned(via_recall: bool)
signal state_changed(new_state: int)

enum State {
	OUTBOUND,
	BALLISTIC,
	STUCK,
	REWINDING,
}

const LAUNCH_SPEED := 43.0
const GUIDANCE_WINDOW := 0.58
const GRAVITY := 24.0
const REWIND_SPEED := 72.0
const PATH_SPACING := 0.24

var player: CharacterBody3D
var direction := Vector3.FORWARD
var velocity := Vector3.ZERO
var state: int = State.OUTBOUND
var flight_time := 0.0
var guided_time := 0.0
var path: Array[Vector3] = []
var path_index := 0
var outbound_hits: Dictionary = {}
var rewind_hits: Dictionary = {}
var spin := 0.0
var recalled := false
var trail_mesh: MeshInstance3D
var trail_material: StandardMaterial3D


func _ready() -> void:
	velocity = direction.normalized() * LAUNCH_SPEED
	path.append(global_position)
	_build_dagger()
	_build_trail()
	emit_signal("state_changed", state)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return

	match state:
		State.OUTBOUND:
			_process_outbound(delta)
		State.BALLISTIC:
			_process_ballistic(delta)
		State.STUCK:
			pass
		State.REWINDING:
			_process_rewind(delta)

	if state == State.OUTBOUND or state == State.BALLISTIC:
		_orient_to_velocity()
	elif state == State.REWINDING:
		spin += delta * 24.0
		rotation.z = spin
	_update_trail()


func begin_rewind() -> bool:
	if state == State.REWINDING:
		return false
	if not player.request_dagger_rewind(_measure_rewind_path()):
		return false
	recalled = true
	state = State.REWINDING
	path_index = path.size() - 1
	rewind_hits.clear()
	emit_signal("state_changed", state)
	return true


func can_pick_up() -> bool:
	return state == State.STUCK or state == State.BALLISTIC


func pick_up() -> void:
	_finish_return(false)


func _process_outbound(delta: float) -> void:
	flight_time += delta
	guided_time += delta
	var guiding := Input.is_action_pressed("throw_dagger") and guided_time < GUIDANCE_WINDOW
	if guiding:
		var desired: Vector3 = -player.camera.global_transform.basis.z
		var speed := velocity.length()
		var steered := velocity.normalized().slerp(desired, clampf(delta * 9.5, 0.0, 1.0))
		velocity = steered.normalized() * speed
	else:
		state = State.BALLISTIC
		emit_signal("state_changed", state)
	_process_flight_segment(delta, false)


func _measure_rewind_path() -> float:
	var total := 0.0
	var previous := global_position
	for index in range(path.size() - 1, -1, -1):
		total += previous.distance_to(path[index])
		previous = path[index]
	total += previous.distance_to(player.camera.global_position)
	return total


func _process_ballistic(delta: float) -> void:
	flight_time += delta
	velocity.y -= GRAVITY * delta
	_process_flight_segment(delta, true)


func _process_flight_segment(delta: float, can_embed_in_enemy: bool) -> void:
	var from := global_position
	var to := from + velocity * delta
	# Use a sphere shape (radius 0.6) swept along the flight path so the
	# dagger connects with enemies more reliably than a thin ray.
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	var shape_params := PhysicsShapeQueryParameters3D.new()
	shape_params.shape = sphere
	shape_params.collision_mask = 1 | 2
	shape_params.exclude = [player.get_rid()]
	# Check at the midpoint of the segment.
	shape_params.transform = Transform3D(Basis.IDENTITY, from.lerp(to, 0.5))
	var hits := space.intersect_shape(shape_params, 8)
	var hit_collider = null
	var hit_position: Vector3 = to
	if not hits.is_empty():
		# Closest hit.
		var best_dist := INF
		for entry in hits:
			var d: float = global_position.distance_to(entry.position)
			if d < best_dist:
				best_dist = d
				hit_collider = entry.collider
				hit_position = entry.position
	# Also raycast for environment collisions (walls etc.) that shape might miss.
	var ray_query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	ray_query.exclude = [player.get_rid()]
	var ray_hit := space.intersect_ray(ray_query)
	if not ray_hit.is_empty():
		var ray_collider = ray_hit.get("collider")
		if ray_collider == hit_collider or hit_collider == null:
			if hit_collider == null:
				hit_collider = ray_collider
				hit_position = ray_hit.get("position", to)
	if hit_collider != null and hit_collider.has_method("take_damage"):
		var id: int = hit_collider.get_instance_id()
		if not outbound_hits.has(id):
			outbound_hits[id] = true
			hit_collider.take_damage(14500, hit_position, true, 62.0, 4.5)
			player.play_sfx(&"dagger_hit")
			player._request_impact(1.0, hit_position)
		global_position = to
		velocity *= 0.78
		if can_embed_in_enemy and velocity.length() < 17.0:
			global_position = hit_position
			_set_stuck()
			return
	elif hit_collider != null:
		global_position = hit_position
		_set_stuck()
		return
	else:
		global_position = to

	_record_path()
	if flight_time > 3.5 and global_position.y < -4.0:
		global_position = player.global_position + Vector3.UP * 0.4
		_set_stuck()


func _record_path() -> void:
	if path.is_empty() or path[-1].distance_to(global_position) >= PATH_SPACING:
		path.append(global_position)
	if path.size() > 320:
		path.remove_at(0)


func _process_rewind(delta: float) -> void:
	var distance_budget := REWIND_SPEED * delta
	var safety := 0
	while distance_budget > 0.001 and safety < 32:
		safety += 1
		var target: Vector3
		if path_index >= 0:
			target = path[path_index]
		else:
			target = player.camera.global_position - player.camera.global_transform.basis.z * 0.28
		var distance := global_position.distance_to(target)
		if distance <= 0.08:
			if path_index >= 0:
				path_index -= 1
				continue
			_finish_return(true)
			return
		var travel := minf(distance, distance_budget)
		var from := global_position
		var to := global_position.move_toward(target, travel)
		_damage_rewind_segment(from, to)
		global_position = to
		distance_budget -= travel
		if travel >= distance - 0.001 and path_index >= 0:
			path_index -= 1


func _damage_rewind_segment(from: Vector3, to: Vector3) -> void:
	if from.distance_squared_to(to) < 0.0001:
		return
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
	var position: Vector3 = hit.get("position", to)
	collider.take_damage(19600, position, true, 86.0, 5.8)
	player.play_sfx(&"deflect")
	player._request_impact(1.15, position)


func _set_stuck() -> void:
	if state == State.STUCK:
		return
	state = State.STUCK
	velocity = Vector3.ZERO
	_record_path()
	player.play_sfx(&"pickup")
	emit_signal("state_changed", state)


func _finish_return(via_recall: bool) -> void:
	emit_signal("returned", via_recall)
	queue_free()


func _orient_to_velocity() -> void:
	if velocity.length_squared() < 0.01:
		return
	var up := Vector3.UP
	if absf(velocity.normalized().dot(up)) > 0.96:
		up = Vector3.RIGHT
	look_at(global_position + velocity.normalized(), up)
	spin += get_physics_process_delta_time() * 13.0
	rotate_object_local(Vector3(0.0, 0.0, 1.0), spin * 0.08)


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


func _build_trail() -> void:
	trail_mesh = MeshInstance3D.new()
	trail_mesh.name = "TimeCutTrail"
	trail_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail_mesh)
	trail_material = StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.vertex_color_use_as_albedo = true
	trail_material.albedo_color = Color.WHITE


func _update_trail() -> void:
	if not is_instance_valid(trail_mesh):
		return
	var points: Array[Vector3] = []
	if state == State.REWINDING:
		points.append(global_position)
		var lower := maxi(path_index - 12, 0)
		for index in range(path_index, lower - 1, -1):
			if index >= 0 and index < path.size():
				points.append(path[index])
	else:
		var lower := maxi(path.size() - 12, 0)
		for index in range(lower, path.size()):
			points.append(path[index])
		points.append(global_position)
	if points.size() < 2:
		trail_mesh.mesh = null
		return

	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, trail_material)
	for index in points.size():
		var point := points[index]
		var tangent: Vector3
		if index == 0:
			tangent = points[1] - point
		else:
			tangent = point - points[index - 1]
		tangent = tangent.normalized()
		var side := tangent.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		var life := float(index) / float(maxi(points.size() - 1, 1))
		var alpha := life * (0.72 if state == State.REWINDING else 0.38)
		var color := (
			Color(0.73, 0.48, 0.82, alpha)
			if state == State.REWINDING
			else Color(0.72, 0.68, 0.55, alpha)
		)
		var width := (0.035 + life * 0.065) * (1.45 if state == State.REWINDING else 1.0)
		immediate.surface_set_color(color)
		immediate.surface_add_vertex(to_local(point + side * width))
		immediate.surface_set_color(color)
		immediate.surface_add_vertex(to_local(point - side * width))
	immediate.surface_end()
	trail_mesh.mesh = immediate


func _add_box(size: Vector3, at: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	add_child(instance)
