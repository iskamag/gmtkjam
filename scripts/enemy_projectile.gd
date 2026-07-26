extends Area3D

enum Style {
	NEEDLE,
	SEAL,
	BLADE,
}

var player: CharacterBody3D
var game: Node3D
var direction := Vector3.FORWARD
var speed := 10.0
var time_damage := 7.0
var max_damage := 1.2
var lifetime := 6.0
var style := Style.NEEDLE
var deflected := false
var deflected_damage := 15600
var kicked := false
var kick_flash := 0.0

const KICK_MIN_SPEED := 36.0
const KICK_SPEED_MULTIPLIER := 2.65
const KICK_DAMAGE := 28500

var visual_root: Node3D
var silhouette: Node3D
var ghosts: Array[Node3D] = []
var visual_phase := 0.0

var iron_material: StandardMaterial3D
var rust_material: StandardMaterial3D
var edge_material: StandardMaterial3D
var ghost_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	monitorable = true

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.32
	collision.shape = shape
	add_child(collision)

	_build_materials()
	visual_root = Node3D.new()
	visual_root.name = "ProjectileVisual"
	add_child(visual_root)
	silhouette = Node3D.new()
	silhouette.name = "Silhouette"
	visual_root.add_child(silhouette)

	match style:
		Style.SEAL:
			_build_seal()
		Style.BLADE:
			_build_blade()
		_:
			_build_needle()

	_build_time_ghosts()
	_orient_visual()


func _physics_process(delta: float) -> void:
	var hostile_scale := 1.0
	if not deflected:
		if is_instance_valid(player) and player.has_method("get_hostile_time_scale"):
			hostile_scale = player.get_hostile_time_scale()
		elif is_instance_valid(game):
			hostile_scale = game.get_hostile_time_scale()
	var step_delta := delta * hostile_scale
	lifetime -= step_delta
	if lifetime <= 0.0:
		queue_free()
		return

	_animate_visual(delta, hostile_scale)

	var from := global_position
	var to := from + direction * speed * step_delta
	# Returned shots still collide with the world. Aim assist only promises a
	# clear launch line; it must not turn walls and encounter gates intangible.
	var mask := (1 | 2) if deflected else 1
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.exclude = [get_rid()]
	if is_instance_valid(player) and deflected:
		query.exclude.append(player.get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider = hit.get("collider")
		if deflected and collider != null and collider.has_method("take_damage"):
			collider.take_damage(deflected_damage, hit.get("position", to), true)
		elif not deflected and collider == player:
			player.hurt(time_damage, max_damage, global_position)
		queue_free()
		return

	global_position = to
	if not deflected and is_instance_valid(player) and global_position.distance_to(player.global_position + Vector3.UP * 0.8) < 0.62:
		player.hurt(time_damage, max_damage, global_position)
		queue_free()


func deflect(new_direction: Vector3) -> void:
	if deflected:
		return
	deflected = true
	collision_layer = 0
	direction = new_direction.normalized()
	speed *= 1.75
	lifetime = 2.5
	edge_material.albedo_color = Color(0.88, 0.83, 0.68)
	edge_material.emission = Color(0.64, 0.50, 0.25)
	edge_material.emission_energy_multiplier = 1.65
	rust_material.albedo_color = Color(0.62, 0.48, 0.25)
	rust_material.emission = Color(0.44, 0.30, 0.11)
	rust_material.emission_energy_multiplier = 1.45
	_orient_visual()


func is_kickable_projectile() -> bool:
	return not deflected and not is_queued_for_deletion()


func kick(new_direction: Vector3) -> bool:
	if not is_kickable_projectile() or new_direction.length_squared() < 0.001:
		return false
	deflected = true
	kicked = true
	collision_layer = 0
	kick_flash = 1.0
	direction = new_direction.normalized()
	speed = maxf(speed * KICK_SPEED_MULTIPLIER, KICK_MIN_SPEED)
	deflected_damage = maxi(deflected_damage, KICK_DAMAGE)
	lifetime = 3.0

	# A kicked shot reads as blunt, violent momentum rather than the cleaner
	# brass glint of an ordinary blade deflection.
	edge_material.albedo_color = Color(0.95, 0.88, 0.70)
	edge_material.emission = Color(0.88, 0.52, 0.16)
	edge_material.emission_energy_multiplier = 3.4
	rust_material.albedo_color = Color(0.72, 0.28, 0.10)
	rust_material.emission = Color(0.82, 0.24, 0.055)
	rust_material.emission_energy_multiplier = 3.0
	ghost_material.albedo_color = Color(0.95, 0.58, 0.18, 0.20)
	ghost_material.emission = Color(0.92, 0.36, 0.08)
	ghost_material.emission_energy_multiplier = 1.8
	_orient_visual()
	return true


func empower_deflection(multiplier := 1.55) -> void:
	if not deflected:
		return
	deflected_damage = int(float(deflected_damage) * multiplier)
	speed *= 1.22
	edge_material.emission_energy_multiplier = 2.15
	rust_material.emission_energy_multiplier = 1.85


func _build_materials() -> void:
	iron_material = StandardMaterial3D.new()
	iron_material.albedo_color = Color(0.055, 0.063, 0.064)
	iron_material.metallic = 0.72
	iron_material.roughness = 0.58

	rust_material = StandardMaterial3D.new()
	rust_material.albedo_color = Color(0.43, 0.23, 0.18)
	rust_material.metallic = 0.38
	rust_material.roughness = 0.7
	rust_material.emission_enabled = true
	rust_material.emission = Color(0.24, 0.09, 0.055)
	rust_material.emission_energy_multiplier = 1.15

	edge_material = StandardMaterial3D.new()
	edge_material.albedo_color = Color(0.76, 0.72, 0.61)
	edge_material.metallic = 0.2
	edge_material.roughness = 0.45
	edge_material.emission_enabled = true
	edge_material.emission = Color(0.38, 0.29, 0.17)
	edge_material.emission_energy_multiplier = 1.25

	ghost_material = StandardMaterial3D.new()
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.albedo_color = Color(0.43, 0.31, 0.51, 0.13)
	ghost_material.emission_enabled = true
	ghost_material.emission = Color(0.25, 0.15, 0.31)
	ghost_material.emission_energy_multiplier = 0.65


func _build_needle() -> void:
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.075, 0.78, 0.055)
	_add_mesh(shaft, iron_material, Vector3(0.0, -0.04, 0.0))

	var inset := BoxMesh.new()
	inset.size = Vector3(0.018, 0.64, 0.064)
	_add_mesh(inset, edge_material, Vector3(-0.022, -0.065, -0.005))

	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.125
	tip.height = 0.31
	tip.radial_segments = 4
	_add_mesh(tip, rust_material, Vector3(0.0, 0.50, 0.0))

	var tip_edge := CylinderMesh.new()
	tip_edge.top_radius = 0.0
	tip_edge.bottom_radius = 0.05
	tip_edge.height = 0.14
	tip_edge.radial_segments = 4
	_add_mesh(tip_edge, edge_material, Vector3(0.0, 0.655, 0.0))

	var counterweight := BoxMesh.new()
	counterweight.size = Vector3(0.16, 0.16, 0.07)
	_add_mesh(counterweight, rust_material, Vector3(0.0, -0.44, 0.0), Vector3(0.0, 0.0, PI * 0.25))


func _build_seal() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.205
	ring.outer_radius = 0.315
	ring.rings = 12
	ring.ring_segments = 6
	_add_mesh(ring, rust_material, Vector3.ZERO, Vector3(PI * 0.5, 0.0, 0.0))

	var center := CylinderMesh.new()
	center.top_radius = 0.18
	center.bottom_radius = 0.18
	center.height = 0.045
	center.radial_segments = 12
	_add_mesh(center, iron_material, Vector3.ZERO, Vector3(PI * 0.5, 0.0, 0.0))

	var stamp_vertical := BoxMesh.new()
	stamp_vertical.size = Vector3(0.055, 0.29, 0.065)
	_add_mesh(stamp_vertical, edge_material, Vector3(0.0, 0.0, -0.035))

	var stamp_cross := BoxMesh.new()
	stamp_cross.size = Vector3(0.24, 0.045, 0.07)
	_add_mesh(stamp_cross, edge_material, Vector3(0.0, -0.055, -0.038), Vector3(0.0, 0.0, -0.18))

	for side in [-1.0, 1.0]:
		var notch := BoxMesh.new()
		notch.size = Vector3(0.12, 0.045, 0.07)
		_add_mesh(notch, iron_material, Vector3(side * 0.31, 0.0, 0.0), Vector3(0.0, 0.0, side * 0.24))


func _build_blade() -> void:
	var center := BoxMesh.new()
	center.size = Vector3(0.72, 0.105, 0.05)
	_add_mesh(center, iron_material, Vector3.ZERO)

	var left_cut := BoxMesh.new()
	left_cut.size = Vector3(0.43, 0.085, 0.055)
	_add_mesh(left_cut, rust_material, Vector3(-0.31, -0.045, 0.0), Vector3(0.0, 0.0, -0.18))

	var right_cut := BoxMesh.new()
	right_cut.size = Vector3(0.43, 0.085, 0.055)
	_add_mesh(right_cut, rust_material, Vector3(0.31, -0.045, 0.0), Vector3(0.0, 0.0, 0.18))

	var upper_edge := BoxMesh.new()
	upper_edge.size = Vector3(0.74, 0.025, 0.07)
	_add_mesh(upper_edge, edge_material, Vector3(0.0, 0.075, -0.008))

	for side in [-1.0, 1.0]:
		var point := CylinderMesh.new()
		point.top_radius = 0.0
		point.bottom_radius = 0.09
		point.height = 0.22
		point.radial_segments = 4
		_add_mesh(
			point,
			edge_material,
			Vector3(side * 0.49, -0.065, 0.0),
			Vector3(0.0, 0.0, -side * PI * 0.5)
		)


func _add_mesh(
	mesh: PrimitiveMesh,
	material: StandardMaterial3D,
	local_position: Vector3,
	local_rotation := Vector3.ZERO
) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = local_position
	instance.rotation = local_rotation
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	silhouette.add_child(instance)


func _build_time_ghosts() -> void:
	for index in 2:
		var ghost := silhouette.duplicate() as Node3D
		ghost.name = "HistoryGhost%d" % (index + 1)
		ghost.position.z = 0.24 + float(index) * 0.23
		ghost.scale = Vector3.ONE * (0.94 - float(index) * 0.08)
		ghost.visible = false
		_set_ghost_material(ghost)
		visual_root.add_child(ghost)
		ghosts.append(ghost)


func _set_ghost_material(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = ghost_material
	for child in node.get_children():
		_set_ghost_material(child)


func _animate_visual(delta: float, hostile_scale: float) -> void:
	visual_phase += delta
	kick_flash = maxf(kick_flash - delta * 5.2, 0.0)
	silhouette.scale = Vector3.ONE * (1.0 + kick_flash * 0.34)
	match style:
		Style.SEAL:
			silhouette.rotation.z = visual_phase * 5.5
		Style.BLADE:
			silhouette.rotation.z = visual_phase * 1.35
		_:
			silhouette.rotation.z = visual_phase * 2.8

	var show_history := kicked or (not deflected and hostile_scale < 0.72)
	for index in ghosts.size():
		var ghost := ghosts[index]
		ghost.visible = show_history
		ghost.rotation.z = silhouette.rotation.z - float(index + 1) * 0.24


func _orient_visual() -> void:
	if not is_instance_valid(visual_root) or direction.length_squared() < 0.0001:
		return
	# Projectile geometry is authored in the local XY plane. Keep local -Z on
	# the actual travel vector so spinning seals and blades neither billboard
	# toward the camera nor appear to climb when travelling horizontally.
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.96:
		up = Vector3.RIGHT
	visual_root.basis = Basis.looking_at(direction.normalized(), up)
