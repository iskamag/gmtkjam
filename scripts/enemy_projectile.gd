extends Area3D

var player: CharacterBody3D
var game: Node3D
var direction := Vector3.FORWARD
var speed := 10.0
var time_damage := 7.0
var max_damage := 1.2
var lifetime := 6.0
var deflected := false
var trail: Array[MeshInstance3D] = []


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	monitorable = true

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.22
	collision.shape = shape
	add_child(collision)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.57, 0.32)
	material.emission_enabled = true
	material.emission = Color(0.62, 0.33, 0.10)
	material.emission_energy_multiplier = 1.8
	material.roughness = 0.55

	for index in 4:
		var mote := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.13 - float(index) * 0.02
		mesh.height = 0.26 - float(index) * 0.04
		mesh.radial_segments = 7
		mesh.rings = 4
		mote.mesh = mesh
		mote.position = -direction * float(index) * 0.18
		mote.material_override = material
		add_child(mote)
		trail.append(mote)


func _physics_process(delta: float) -> void:
	var hostile_scale := 1.0
	if is_instance_valid(game) and not deflected:
		hostile_scale = game.get_hostile_time_scale()
	var step_delta := delta * hostile_scale
	lifetime -= step_delta
	if lifetime <= 0.0:
		queue_free()
		return

	var from := global_position
	var to := from + direction * speed * step_delta
	var mask := 2 if deflected else 1
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.exclude = [get_rid()]
	if is_instance_valid(player) and deflected:
		query.exclude.append(player.get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider = hit.get("collider")
		if deflected and collider != null and collider.has_method("take_damage"):
			collider.take_damage(15600, hit.get("position", to), true)
		elif not deflected and collider == player:
			player.hurt(time_damage, max_damage, global_position)
		queue_free()
		return

	global_position = to
	if not deflected and is_instance_valid(player) and global_position.distance_to(player.global_position + Vector3.UP * 0.8) < 0.62:
		player.hurt(time_damage, max_damage, global_position)
		queue_free()
		return

	for index in trail.size():
		trail[index].position = -direction * float(index) * 0.18


func deflect(new_direction: Vector3) -> void:
	if deflected:
		return
	deflected = true
	direction = new_direction.normalized()
	speed *= 1.75
	lifetime = 2.5
	for mote in trail:
		if mote.material_override is StandardMaterial3D:
			mote.material_override.albedo_color = Color(0.88, 0.83, 0.62)
			mote.material_override.emission = Color(0.78, 0.68, 0.36)
