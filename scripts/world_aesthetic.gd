extends Node3D

# The town's look is built as a separate layer so the user can replace meshes
# without disturbing traversal or encounters. Its rules come from the sourced
# reference board: wet rail infrastructure, isolated sodium light, dead-section
# green, oxidized steel, and one broken public clock.

const ASPHALT_DIFF = preload("res://assets/textures/polyhaven/worn_asphalt_diff_1k.jpg")
const ASPHALT_NORMAL = preload("res://assets/textures/polyhaven/worn_asphalt_nor_gl_1k.jpg")
const ASPHALT_ARM = preload("res://assets/textures/polyhaven/worn_asphalt_arm_1k.jpg")

var player: CharacterBody3D
var time_archive_materials: Array[StandardMaterial3D] = []
var time_archive_lights: Array[OmniLight3D] = []
var time_archive_visual := 0.0


func bind(player_node: CharacterBody3D) -> void:
	player = player_node


func _ready() -> void:
	name = "ReturnRoadArtDirection"
	_build_wet_route()
	_build_catenary()
	_build_signal_grammar()
	_build_broken_station_clock()
	_build_brutalist_horizon()
	_build_rain()


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		var game := get_parent()
		if game != null:
			var candidate = game.get("player")
			if candidate is CharacterBody3D:
				player = candidate
	var target := 0.0
	if is_instance_valid(player) and player.watch_active:
		target = 0.62 + player.overclock_visual * 0.38
	time_archive_visual = move_toward(
		time_archive_visual,
		target,
		delta * (8.5 if target > time_archive_visual else 4.5)
	)
	for material in time_archive_materials:
		var archive_color := Color(0.31, 0.10, 0.38, time_archive_visual * 0.46)
		material.albedo_color = archive_color
		material.emission = Color(0.26, 0.055, 0.34) * time_archive_visual
		material.emission_energy_multiplier = 1.0 + time_archive_visual * 2.4
	for archive_light in time_archive_lights:
		archive_light.light_energy = time_archive_visual * 2.2


func _build_wet_route() -> void:
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.24, 0.25, 0.22)
	asphalt.albedo_texture = ASPHALT_DIFF
	asphalt.normal_enabled = true
	asphalt.normal_texture = ASPHALT_NORMAL
	asphalt.normal_scale = 0.68
	asphalt.ao_enabled = true
	asphalt.ao_texture = ASPHALT_ARM
	asphalt.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	asphalt.roughness = 0.62
	asphalt.roughness_texture = ASPHALT_ARM
	asphalt.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	asphalt.metallic = 0.12
	asphalt.metallic_texture = ASPHALT_ARM
	asphalt.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	asphalt.uv1_scale = Vector3(5.5, 14.0, 5.5)
	_add_box(Vector3(0.0, 0.015, -4.5), Vector3(17.8, 0.025, 73.0), asphalt)

	var shoulder := _material(Color(0.095, 0.10, 0.09), 0.96, 0.02)
	for side in [-1.0, 1.0]:
		_add_box(
			Vector3(side * 10.9, 0.025, -4.5),
			Vector3(3.8, 0.05, 73.0),
			shoulder
		)

	# Reflections are localized around practical lights. The road remains dark
	# rather than turning into a global glossy cyberpunk surface.
	var puddle := StandardMaterial3D.new()
	puddle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle.albedo_color = Color(0.30, 0.29, 0.22, 0.16)
	puddle.metallic = 0.72
	puddle.roughness = 0.12
	puddle.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for data in [
		[Vector3(-3.8, 0.04, 8.8), Vector2(3.5, 1.1), -0.14],
		[Vector3(4.6, 0.04, -2.5), Vector2(2.1, 4.6), 0.08],
		[Vector3(-4.9, 0.04, -17.2), Vector2(3.2, 1.5), -0.05],
		[Vector3(3.5, 0.04, -29.0), Vector2(4.0, 1.2), 0.16],
	]:
		_add_plane(data[0], data[1], data[2], puddle)

	var stripe_material := _material(Color(0.48, 0.42, 0.27), 0.85, 0.04)
	for z in range(12, -36, -7):
		_add_box(Vector3(0.0, 0.045, float(z)), Vector3(0.13, 0.018, 2.3), stripe_material)

	# Sodium pools establish the visual rhythm used by combat rooms.
	for data in [
		[Vector3(-8.2, 0.0, 10.0), 1.0],
		[Vector3(8.2, 0.0, -3.0), -1.0],
		[Vector3(-8.2, 0.0, -16.0), 1.0],
		[Vector3(8.2, 0.0, -29.0), -1.0],
	]:
		_build_sodium_lamp(data[0], data[1])


func _build_sodium_lamp(at: Vector3, arm_direction: float) -> void:
	var steel := _material(Color(0.17, 0.17, 0.15), 0.56, 0.66)
	var lamp := Node3D.new()
	lamp.position = at
	add_child(lamp)
	_add_box_to(lamp, Vector3.ZERO + Vector3.UP * 3.25, Vector3(0.13, 6.5, 0.13), steel)
	_add_box_to(
		lamp,
		Vector3(arm_direction * 0.65, 6.42, 0.0),
		Vector3(1.3, 0.10, 0.10),
		steel
	)
	var amber := _emissive_material(Color(0.86, 0.47, 0.16), 3.8)
	_add_box_to(
		lamp,
		Vector3(arm_direction * 1.26, 6.32, 0.0),
		Vector3(0.42, 0.14, 0.25),
		amber
	)
	var light := OmniLight3D.new()
	light.position = Vector3(arm_direction * 1.12, 5.7, 0.0)
	light.light_color = Color(1.0, 0.49, 0.19)
	light.light_energy = 2.65
	light.omni_range = 8.8
	light.omni_attenuation = 1.55
	light.shadow_enabled = false
	lamp.add_child(light)


func _build_catenary() -> void:
	var oxidized := _material(Color(0.24, 0.14, 0.09), 0.72, 0.58)
	var wire := _material(Color(0.055, 0.058, 0.052), 0.48, 0.80)
	var wire_points_left: Array[Vector3] = []
	var wire_points_right: Array[Vector3] = []
	for z in range(18, -42, -10):
		for side in [-1.0, 1.0]:
			var x: float = float(side) * 10.4
			_add_box(Vector3(x, 3.65, float(z)), Vector3(0.18, 7.3, 0.18), oxidized)
			_add_box(Vector3(x - side * 1.15, 7.12, float(z)), Vector3(2.3, 0.12, 0.12), oxidized)
		wire_points_left.append(Vector3(-9.25, 7.03, float(z)))
		wire_points_right.append(Vector3(9.25, 7.03, float(z)))
	for index in range(wire_points_left.size() - 1):
		_add_cylinder_between(wire_points_left[index], wire_points_left[index + 1], 0.026, wire)
		_add_cylinder_between(wire_points_right[index], wire_points_right[index + 1], 0.026, wire)
		_add_cylinder_between(
			wire_points_left[index] + Vector3(0.0, -0.48, 0.0),
			wire_points_right[index] + Vector3(0.0, -0.48, 0.0),
			0.018,
			wire
		)


func _build_signal_grammar() -> void:
	var dark_steel := _material(Color(0.075, 0.08, 0.072), 0.52, 0.80)
	var old_white := _material(Color(0.53, 0.51, 0.42), 0.86, 0.08)
	for data in [
		[Vector3(-11.6, 0.0, 4.8), Color(0.65, 0.12, 0.055), 7.6],
		[Vector3(11.0, 0.0, -12.4), Color(0.70, 0.39, 0.09), 6.7],
		[Vector3(-11.4, 0.0, -27.0), Color(0.18, 0.30, 0.17), 7.2],
	]:
		var holder := Node3D.new()
		holder.position = data[0]
		add_child(holder)
		_add_box_to(holder, Vector3(0.0, data[2] * 0.5, 0.0), Vector3(0.18, data[2], 0.18), dark_steel)
		_add_box_to(holder, Vector3(0.0, data[2] - 0.3, 0.0), Vector3(0.84, 1.08, 0.34), dark_steel)
		var lens := MeshInstance3D.new()
		var lens_mesh := SphereMesh.new()
		lens_mesh.radius = 0.22
		lens_mesh.height = 0.44
		lens.mesh = lens_mesh
		lens.position = Vector3(0.0, data[2] - 0.22, 0.20)
		lens.material_override = _emissive_material(data[1], 5.0)
		holder.add_child(lens)
		_add_box_to(holder, Vector3(0.0, data[2] - 1.25, 0.02), Vector3(0.62, 0.44, 0.08), old_white)
		var signal_light := OmniLight3D.new()
		signal_light.position = lens.position
		signal_light.light_color = data[1]
		signal_light.light_energy = 1.1
		signal_light.omni_range = 3.8
		signal_light.shadow_enabled = false
		holder.add_child(signal_light)

	# A low, almost colorless fog bed catches the practical signals without
	# becoming a backrooms haze.
	var mist := StandardMaterial3D.new()
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.albedo_color = Color(0.24, 0.27, 0.23, 0.055)
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for data in [
		[Vector3(0.0, 0.07, 2.0), Vector2(29.0, 10.0)],
		[Vector3(0.0, 0.075, -15.0), Vector2(31.0, 12.0)],
		[Vector3(0.0, 0.08, -31.0), Vector2(34.0, 10.0)],
	]:
		_add_plane(data[0], data[1], 0.0, mist)


func _build_broken_station_clock() -> void:
	var clock := Node3D.new()
	clock.name = "TheStationClock"
	clock.position = Vector3(10.7, 4.15, -23.5)
	clock.rotation.y = PI
	add_child(clock)

	var oxidized := _material(Color(0.23, 0.12, 0.075), 0.70, 0.64)
	var face := _material(Color(0.66, 0.64, 0.53), 0.92, 0.04)
	var void_material := _material(Color(0.025, 0.027, 0.024), 0.90, 0.0)
	_add_box_to(clock, Vector3(0.0, -2.1, 0.0), Vector3(0.32, 4.2, 0.32), oxidized)

	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 1.28
	disc_mesh.bottom_radius = 1.28
	disc_mesh.height = 0.16
	disc_mesh.radial_segments = 32
	disc.mesh = disc_mesh
	disc.rotation.x = PI * 0.5
	disc.material_override = face
	clock.add_child(disc)

	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var radius := 0.96
		var tick := MeshInstance3D.new()
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.065, 0.22 if index % 3 == 0 else 0.13, 0.035)
		tick.mesh = tick_mesh
		tick.position = Vector3(sin(angle) * radius, cos(angle) * radius, -0.11)
		tick.rotation.z = -angle
		tick.material_override = void_material
		clock.add_child(tick)
	_add_clock_hand(clock, 0.05, 0.72, -0.76, Color(0.035, 0.036, 0.032))
	_add_clock_hand(clock, 0.035, 0.96, 1.47, Color(0.035, 0.036, 0.032))
	_add_clock_hand(clock, 0.018, 1.02, -2.24, Color(0.48, 0.075, 0.035))

	# Missing glass and shifted shards make the damage structural, not a blood
	# decal or a UI icon.
	for data in [
		[Vector3(0.58, 0.42, -0.15), Vector3(0.58, 0.045, 0.04), -0.62],
		[Vector3(0.37, -0.08, -0.15), Vector3(0.92, 0.035, 0.04), 0.28],
		[Vector3(-0.28, -0.43, -0.15), Vector3(0.66, 0.035, 0.04), -0.94],
	]:
		var shard := MeshInstance3D.new()
		var shard_mesh := BoxMesh.new()
		shard_mesh.size = data[1]
		shard.mesh = shard_mesh
		shard.position = data[0]
		shard.rotation.z = data[2]
		shard.material_override = void_material
		clock.add_child(shard)

	for radius in [1.58, 1.95, 2.42]:
		var archive := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = radius - 0.025
		ring.outer_radius = radius + 0.025
		ring.rings = 32
		ring.ring_segments = 5
		archive.mesh = ring
		archive.rotation.x = PI * 0.5
		var archive_material := _time_archive_material()
		archive.material_override = archive_material
		time_archive_materials.append(archive_material)
		clock.add_child(archive)
	var archive_light := OmniLight3D.new()
	archive_light.position = Vector3(0.0, 0.0, -0.3)
	archive_light.light_color = Color(0.46, 0.12, 0.58)
	archive_light.omni_range = 6.0
	archive_light.shadow_enabled = false
	archive_light.light_energy = 0.0
	clock.add_child(archive_light)
	time_archive_lights.append(archive_light)


func _add_clock_hand(parent: Node3D, width: float, length: float, angle: float, color: Color) -> void:
	var hand := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, length, 0.045)
	hand.mesh = mesh
	hand.position = Vector3(sin(angle) * length * 0.5, cos(angle) * length * 0.5, -0.18)
	hand.rotation.z = -angle
	hand.material_override = _material(color, 0.78, 0.12)
	parent.add_child(hand)


func _build_brutalist_horizon() -> void:
	var concrete := _material(Color(0.14, 0.145, 0.13), 0.96, 0.02)
	var steel := _material(Color(0.065, 0.068, 0.061), 0.58, 0.72)
	# A modern rail gantry becomes a fantasy gate only by silhouette.
	for x in [-6.3, 6.3]:
		_add_box(Vector3(x, 5.7, -39.0), Vector3(1.4, 11.4, 2.1), concrete)
	_add_box(Vector3(0.0, 10.7, -39.0), Vector3(14.0, 1.35, 2.1), concrete)
	_add_box(Vector3(0.0, 8.25, -38.7), Vector3(10.7, 0.24, 0.34), steel)
	for x in [-4.2, 0.0, 4.2]:
		_add_box(Vector3(x, 6.0, -38.8), Vector3(0.16, 4.6, 0.24), steel)


func _build_rain() -> void:
	var rain := GPUParticles3D.new()
	rain.name = "ColdRain"
	rain.amount = 360
	rain.lifetime = 1.15
	rain.preprocess = 1.15
	rain.fixed_fps = 30
	rain.position = Vector3(0.0, 13.0, -5.0)
	rain.visibility_aabb = AABB(Vector3(-20.0, -16.0, -45.0), Vector3(40.0, 32.0, 90.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(17.0, 0.4, 43.0)
	process.direction = Vector3(0.12, -1.0, 0.06)
	process.spread = 2.5
	process.initial_velocity_min = 22.0
	process.initial_velocity_max = 28.0
	process.gravity = Vector3.ZERO
	rain.process_material = process
	var streak := BoxMesh.new()
	streak.size = Vector3(0.012, 0.52, 0.012)
	streak.material = _unshaded_alpha_material(Color(0.55, 0.58, 0.52, 0.18))
	rain.draw_pass_1 = streak
	add_child(rain)


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color.darkened(0.36), 0.46, 0.16)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _unshaded_alpha_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func _time_archive_material() -> StandardMaterial3D:
	var material := _unshaded_alpha_material(Color(0.31, 0.10, 0.38, 0.0))
	material.emission_enabled = true
	material.emission = Color.BLACK
	material.emission_energy_multiplier = 1.0
	return material


func _add_box(at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	add_child(mesh_instance)
	return mesh_instance


func _add_box_to(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_plane(at: Vector3, size: Vector2, yaw: float, material: Material) -> MeshInstance3D:
	var plane := MeshInstance3D.new()
	plane.position = at
	plane.rotation.y = yaw
	var mesh := PlaneMesh.new()
	mesh.size = size
	plane.mesh = mesh
	plane.material_override = material
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plane)
	return plane


func _add_cylinder_between(from: Vector3, to: Vector3, radius: float, material: Material) -> void:
	var direction := to - from
	var length := direction.length()
	if length < 0.001:
		return
	var cylinder := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 6
	cylinder.mesh = mesh
	cylinder.position = (from + to) * 0.5
	cylinder.quaternion = Quaternion(Vector3.UP, direction.normalized())
	cylinder.material_override = material
	add_child(cylinder)
