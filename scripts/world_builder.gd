class_name WorldBuilder
extends RefCounted

# All static, once-per-run world/level/carriage construction used by main.gd.
# Split out so main.gd holds runtime logic only and level geometry is findable.
# Runtime updaters (_update_prologue_exterior, _update_deterioration, _open_gate)
# stay in main.gd and read back the members populated here (prologue_shell,
# prologue_window_motion, encounter_gates, ghost_materials, world_environment_resource).

const EnemyScript = preload("res://scripts/enemy.gd")
const WorldAestheticScript = preload("res://scripts/world_aesthetic.gd")
const PackNightShader = preload("res://shaders/pack_night_material.gdshader")

const ALBEDO_PATH := "res://assets/generated/building_albedo.png"
const NORMAL_PATH := "res://assets/generated/building_normal.png"

# Cache of shared textured materials keyed by tint color, so every building
# reuses the same generated albedo+normal textures instead of a flat color.
static var _building_materials: Dictionary = {}


# Bake procedural noise textures (albedo + normal) to res://assets/generated/.
# Run once via `godot --headless -- --gen-textures` whenever you want to
# re-roll the surface. Buildings pick them up automatically on next export.
static func generate_textures() -> void:
	var size := 512
	var base := FastNoiseLite.new()
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX
	base.frequency = 0.018
	base.fractal_octaves = 5
	base.fractal_lacunarity = 2.2
	base.fractal_gain = 0.5
	base.seed = 2718

	var fine := FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_PERLIN
	fine.frequency = 0.11
	fine.fractal_octaves = 3
	fine.seed = 1618

	var albedo := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var height := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var h: float = base.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var grit: float = fine.get_noise_2d(float(x) * 1.3, float(y) * 1.3) * 0.5 + 0.5
			var stain := clampf(h * 0.7 + grit * 0.3, 0.0, 1.0)
			# Warm grungy concrete: darker in pits, dusty on ridges.
			var v := 0.18 + stain * 0.30
			var r := v + grit * 0.03
			var g := v
			var b := v - grit * 0.02
			albedo.set_pixel(x, y, Color(r, g, b, 1.0))
			height.set_pixel(x, y, Color(h, h, h, 1.0))

	# Derive a tangent-space normal map from the height field.
	var normal := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var strength := 2.4
	for y in size:
		for x in size:
			var xl := height.get_pixel((x - 1 + size) % size, y).r
			var xr := height.get_pixel((x + 1) % size, y).r
			var yu := height.get_pixel(x, (y - 1 + size) % size).r
			var yd := height.get_pixel(x, (y + 1) % size).r
			var nx := (xl - xr) * strength
			var ny := (yu - yd) * strength
			var nz := 1.0
			var l := sqrt(nx * nx + ny * ny + nz * nz)
			normal.set_pixel(x, y, Color(nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5, nz / l * 0.5 + 0.5, 1.0))

	DirAccess.make_dir_recursive_absolute("res://assets/generated")
	albedo.save_png(ALBEDO_PATH)
	normal.save_png(NORMAL_PATH)
	# Invalidate the material cache so a re-roll actually takes effect.
	_building_materials.clear()
	print("WorldBuilder: wrote %s and %s" % [ALBEDO_PATH, NORMAL_PATH])


static func _building_material(tint: Color) -> Material:
	if _building_materials.has(tint):
		return _building_materials[tint]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	if ResourceLoader.exists(ALBEDO_PATH):
		mat.albedo_texture = load(ALBEDO_PATH)
	if ResourceLoader.exists(NORMAL_PATH):
		mat.normal_enabled = true
		mat.normal_texture = load(NORMAL_PATH)
		mat.normal_scale = 0.85
	mat.roughness = 0.82
	mat.metallic = 0.06
	mat.uv1_scale = Vector3(2.0, 3.0, 2.0)
	_building_materials[tint] = mat
	return mat


# Build the entire world under main.world_root. Used by the --export-world
# path to author scenes/world.tscn, which main.gd then loads at runtime so
# the level and encounter trigger zones become editor-editable nodes.
static func build_all(main) -> void:
	main.world_root = Node3D.new()
	main.world_root.name = "World"
	main.add_child(main.world_root)
	build_world(main)
	build_level(main)
	build_encounter_zones(main)


# Build only the train carriage interior into main.world_root. Used by
# --export-train to author scenes/train.tscn, a standalone scene that loads
# on boot as the main menu and unloads after the crash into world.tscn.
static func build_train(main) -> void:
	main.world_root = Node3D.new()
	main.world_root.name = "Train"
	main.add_child(main.world_root)
	build_world(main)
	build_prologue_shell(main)


# Pack main.world_root into a .tscn at the given path.
static func export_scene_at(main, path: String) -> Error:
	_set_owners(main.world_root)
	var packed := PackedScene.new()
	var err := packed.pack(main.world_root)
	if err != OK:
		push_error("WorldBuilder.export_scene_at: pack failed with error %d" % err)
		return err
	return ResourceSaver.save(packed, path)


# Pack main.world_root into a .tscn. Run once via `godot --headless -- --export-world`.
static func export_scene(main, path: String) -> Error:
	_set_owners(main.world_root)
	var packed := PackedScene.new()
	var err := packed.pack(main.world_root)
	if err != OK:
		push_error("WorldBuilder.export_scene: pack failed with error %d" % err)
		return err
	return ResourceSaver.save(packed, path)


# pack() only serializes descendants whose owner is the scene root. Children
# added in code have owner == null, so assign ownership recursively before
# saving. Every descendant must share the SAME owner (the scene root), not its
# immediate parent, or pack() skips it.
static func _set_owners(scene_root: Node) -> void:
	_recurse_owner(scene_root, scene_root)


static func _recurse_owner(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.set_owner(scene_root)
		# Do not recurse into instanced sub-scenes (loaded .glb/.fbx props).
		# Stealing ownership of their children forces pack() to inline them,
		# which the editor warns about and renders as fallback-white.
		if child.scene_file_path.is_empty():
			_recurse_owner(child, scene_root)


static func build_world(main) -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()

	# The exterior needs depth, not a coloured ceiling. This static sky shader
	# builds several broad cloud strata plus a sparse, subordinate star field.
	# It avoids panorama dependencies and features unavailable to WebGL 2.
	var night_sky := Sky.new()
	night_sky.radiance_size = Sky.RADIANCE_SIZE_256
	var night_sky_shader := Shader.new()
	night_sky_shader.code = """
shader_type sky;

float sky_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float sky_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = sky_hash(cell);
	float b = sky_hash(cell + vec2(1.0, 0.0));
	float c = sky_hash(cell + vec2(0.0, 1.0));
	float d = sky_hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float sky_fbm(vec2 p) {
	float value = 0.0;
	float weight = 0.52;
	for (int octave = 0; octave < 4; octave++) {
		value += sky_noise(p) * weight;
		p = p * 2.03 + vec2(17.13, 9.71);
		weight *= 0.48;
	}
	return value;
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	float upward = clamp(direction.y, 0.0, 1.0);
	float horizon = exp(-abs(direction.y) * 7.5);
	vec2 sphere = vec2(
		atan(direction.z, direction.x) * 0.15915494,
		asin(clamp(direction.y, -1.0, 1.0)) * 0.31830989
	);

	vec3 zenith = vec3(0.006, 0.010, 0.017);
	vec3 middle = vec3(0.018, 0.025, 0.031);
	vec3 ash_horizon = vec3(0.082, 0.086, 0.082);
	vec3 colour = mix(middle, zenith, pow(upward, 0.58));
	colour = mix(colour, ash_horizon, horizon * 0.62);

	// A low, heavy weather deck and a finer high layer move in different
	// directions visually, despite being static. Neither reads as purple fog.
	float low_noise = sky_fbm(sphere * vec2(4.2, 10.5) + vec2(3.7, 1.2));
	float low_strata = smoothstep(0.40, 0.62, low_noise + horizon * 0.17);
	low_strata *= smoothstep(-0.10, 0.22, direction.y);
	low_strata *= 1.0 - smoothstep(0.54, 0.92, direction.y);
	vec3 low_cloud = vec3(0.105, 0.108, 0.102);
	colour = mix(colour, low_cloud, low_strata * 0.70);

	float high_noise = sky_fbm(sphere * vec2(10.0, 24.0) + vec2(-8.4, 4.1));
	float high_strata = smoothstep(0.49, 0.68, high_noise);
	high_strata *= smoothstep(0.08, 0.42, direction.y);
	high_strata *= 1.0 - smoothstep(0.76, 0.99, direction.y);
	colour += vec3(0.044, 0.047, 0.046) * high_strata * 0.78;

	// Tiny old-ivory stars establish scale without a moon/sun billboard dot.
	vec2 star_grid = sphere * vec2(520.0, 260.0);
	vec2 star_cell = floor(star_grid);
	vec2 star_local = fract(star_grid) - vec2(0.5);
	float star_seed = sky_hash(star_cell);
	float star_shape = 1.0 - smoothstep(0.012, 0.055, length(star_local));
	float star = step(0.9905, star_seed) * star_shape;
	star *= smoothstep(0.10, 0.38, direction.y);
	star *= 1.0 - clamp(low_strata + high_strata * 0.8, 0.0, 1.0);
	colour += vec3(0.50, 0.47, 0.38) * star;

	if (direction.y < 0.0) {
		float ground_depth = clamp(-direction.y, 0.0, 1.0);
		vec3 ground = mix(
			vec3(0.040, 0.043, 0.042),
			vec3(0.008, 0.009, 0.010),
			pow(ground_depth, 0.32)
		);
		colour = mix(colour, ground, smoothstep(0.0, 0.16, ground_depth));
	}

	COLOR = colour;
}
"""
	var night_sky_material := ShaderMaterial.new()
	night_sky_material.shader = night_sky_shader
	night_sky.sky_material = night_sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = night_sky
	environment.background_energy_multiplier = 0.90
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Cool ash fill reveals forms; the warmer values remain attached to actual
	# service lamps, train practicals, hits, and the broken watch.
	environment.ambient_light_color = Color(0.39, 0.43, 0.45)
	environment.ambient_light_energy = 0.84
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.glow_enabled = true
	environment.glow_intensity = 0.36
	environment.glow_bloom = 0.045
	environment.glow_hdr_threshold = 1.18
	environment.glow_hdr_scale = 1.10
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.02
	environment.adjustment_contrast = 1.065
	environment.adjustment_saturation = 0.82
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.098, 0.105, 0.104)
	environment.fog_light_energy = 0.66
	environment.fog_density = 0.0105
	environment.fog_sky_affect = 0.48
	main.world_environment_resource = environment
	world_environment.environment = environment
	world_environment.name = "MoonlitRailEnvironment"
	main.world_root.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "ColdMoonKey"
	sun.rotation_degrees = Vector3(-43.0, -31.0, 0.0)
	sun.light_color = Color(0.66, 0.72, 0.75)
	sun.light_energy = 1.08
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	main.world_root.add_child(sun)

	for data in [
		[Vector3(-11.0, 3.5, 4.0), Color(1.0, 0.73, 0.43), 3.4, 13.5],
		[Vector3(10.0, 2.5, -17.0), Color(0.68, 0.75, 0.76), 2.25, 14.0],
		[Vector3(0.0, 5.5, -31.0), Color(1.0, 0.61, 0.34), 4.6, 15.5],
	]:
		var light := OmniLight3D.new()
		light.position = data[0]
		light.light_color = data[1]
		light.light_energy = data[2]
		light.omni_range = data[3]
		light.omni_attenuation = 1.45
		light.shadow_enabled = false
		main.world_root.add_child(light)


static func build_level(main) -> void:
	var asphalt := Color(0.075, 0.079, 0.078)
	var concrete := Color(0.22, 0.22, 0.205)
	var soot := Color(0.105, 0.105, 0.10)
	var rust := Color(0.25, 0.145, 0.075)
	var old_gold := Color(0.37, 0.31, 0.19)

	# Named containers keep the scene tree navigable instead of hundreds of
	# flat MeshInstance3D siblings.
	var level := Node3D.new()
	level.name = "Level"
	main.world_root.add_child(level)
	var floor_node := Node3D.new(); floor_node.name = "Floor"; level.add_child(floor_node)
	var walls_node := Node3D.new(); walls_node.name = "Walls"; level.add_child(walls_node)
	var cover_node := Node3D.new(); cover_node.name = "Cover"; level.add_child(cover_node)
	var buildings_node := Node3D.new(); buildings_node.name = "Buildings"; level.add_child(buildings_node)
	var props_node := Node3D.new(); props_node.name = "Props"; level.add_child(props_node)

	# Arena floor: wider than the old corridor (30×36 instead of 19×58).
	_add_static_box(main, Vector3(0.0, -0.5, -4.0), Vector3(30.0, 1.0, 42.0), asphalt, floor_node)
	_add_visual_box(main, Vector3(0.0, -0.48, -4.0), Vector3(28.0, 0.02, 40.0), concrete.darkened(0.15), floor_node)

	# High perimeter walls (9m) — baion can't escape the arena.
	var wall_h := 9.0
	for side in [-1.0, 1.0]:
		_add_static_box(main, Vector3(side * 15.5, wall_h * 0.5, -4.0), Vector3(1.0, wall_h, 42.0), soot, walls_node)
	# End walls with passages.
	_add_static_box(main, Vector3(-8.0, wall_h * 0.5, 17.0), Vector3(15.0, wall_h, 1.0), soot, walls_node)
	_add_static_box(main, Vector3(8.0, wall_h * 0.5, 17.0), Vector3(15.0, wall_h, 1.0), soot, walls_node)
	_add_static_box(main, Vector3(-8.0, wall_h * 0.5, -25.0), Vector3(15.0, wall_h, 1.0), soot, walls_node)
	_add_static_box(main, Vector3(8.0, wall_h * 0.5, -25.0), Vector3(15.0, wall_h, 1.0), soot, walls_node)

	# Cover scattered as combat islands, not corridor lanes.
	for obstacle in [
		[Vector3(-7.0, 0.72, 8.0), Vector3(3.0, 1.45, 1.4), rust],
		[Vector3(7.0, 0.52, 2.0), Vector3(3.4, 1.05, 1.6), soot],
		[Vector3(0.0, 0.65, -4.0), Vector3(4.0, 1.3, 1.2), concrete],
		[Vector3(-8.0, 0.58, -12.0), Vector3(2.7, 1.15, 3.0), soot],
		[Vector3(8.0, 0.74, -16.0), Vector3(2.4, 1.48, 3.2), rust],
		[Vector3(0.0, 0.6, -20.0), Vector3(5.0, 1.2, 1.0), concrete],
	]:
		_add_static_box(main, obstacle[0], obstacle[1], obstacle[2], cover_node)

	# Props.
	for prop in [
		["res://assets/kenney/crate-color.glb", Vector3(-10.0, 0.0, 10.0), Vector3(2.0, 2.0, 2.0), Vector3(0.0, 0.4, 0.0), rust],
		["res://assets/kenney/crate-color.glb", Vector3(10.0, 0.0, -8.0), Vector3(2.3, 2.3, 2.3), Vector3(0.0, -0.3, 0.0), rust],
		["res://assets/kenney/pipe.glb", Vector3(-13.0, 2.2, -2.0), Vector3(2.0, 5.0, 2.0), Vector3(0.0, 0.0, PI * 0.5), soot],
		["res://assets/kenney/weapon-sword.glb", Vector3(0.0, 0.1, -18.0), Vector3(4.2, 4.2, 4.2), Vector3(0.0, 0.0, PI), Color(0.16, 0.16, 0.145)],
	]:
		_add_asset(main, prop[0], prop[1], prop[2], prop[3], prop[4])

	# Apocalypse kit — gives the arena a sense of place.
	_add_optional_pack_asset(main, "res://assets/user_pack/SM_Train_Speed_Derailment_Apocalypse.fbx", Vector3(-9.0, 0.02, 14.0), Vector3.ONE, Vector3(-0.06, 1.26, 0.13), Color(0.74, 0.70, 0.61))
	_add_optional_pack_asset(main, "res://assets/user_pack/SM_Building_House_Modern_Apocalypse_A.fbx", Vector3(-13.0, 0.0, -4.0), Vector3.ONE * 1.12, Vector3(0.0, 0.58, 0.0), Color(0.60, 0.59, 0.53))
	_add_optional_pack_asset(main, "res://assets/user_pack/SM_Building_Cafe_Apocalypse.fbx", Vector3(13.0, 0.0, -12.0), Vector3.ONE * 1.05, Vector3(0.0, -0.64, 0.0), Color(0.60, 0.57, 0.49))
	for rubble_data in [
		[Vector3(-6.0, 0.0, 6.0), Vector3(0.9, 0.9, 0.9), 0.4],
		[Vector3(8.0, 0.0, -2.0), Vector3(1.2, 1.2, 1.2), -0.8],
		[Vector3(-9.0, 0.0, -18.0), Vector3(1.4, 1.4, 1.4), 1.1],
	]:
		_add_optional_pack_asset(main, "res://assets/user_pack/SM_Rubble_Concrete_Apocalypse_A.fbx", rubble_data[0], rubble_data[1], Vector3(0.0, rubble_data[2], 0.0), Color(0.58, 0.56, 0.50))
	for lamp_data in [
		[Vector3(-7.0, 0.0, 4.0), 0.15],
		[Vector3(7.0, 0.0, -6.0), PI + 0.1],
		[Vector3(-7.0, 0.0, -16.0), -0.08],
	]:
		_add_optional_pack_asset(main, "res://assets/user_pack/SM_Lamp_Road_Apocalypse_A.fbx", lamp_data[0], Vector3.ONE, Vector3(0.0, lamp_data[1], 0.0), Color(0.52, 0.50, 0.43))

	# A few building facades behind the walls for depth (limited count for perf).
	var facade_colors: Array[Color] = [concrete, soot, concrete.darkened(0.08), rust.darkened(0.45)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 91337
	for side in [-1.0, 1.0]:
		var z := 14.0
		for _i in 3:
			var depth := rng.randf_range(5.0, 7.0)
			var width := rng.randf_range(4.5, 6.0)
			var height := rng.randf_range(7.0, 12.0)
			var x: float = side * rng.randf_range(18.0, 22.0)
			var col: Color = facade_colors[rng.randi() % facade_colors.size()]
			_add_building(main, Vector3(x, 0.0, z), Vector2(width, depth), height, col)
			z -= depth + rng.randf_range(2.0, 4.0)

	# Encounter gates at arena chokepoints.
	main.encounter_gates.append(_create_encounter_gate(main, 6.0))
	main.encounter_gates.append(_create_encounter_gate(main, -14.0))
	var art_direction := WorldAestheticScript.new()
	art_direction.name = "ReturnRoadArtDirection"
	main.world_root.add_child(art_direction)
	build_prologue_shell(main)


static func build_prologue_shell(main) -> void:
	var shell := Node3D.new()
	shell.name = "LastServiceCarriage"
	shell.position = Vector3(0.0, 0.0, 16.0)
	main.world_root.add_child(shell)
	main.prologue_shell = shell

	var upholstery := Color(0.255, 0.125, 0.070)
	var upholstery_wear := Color(0.37, 0.205, 0.092)
	var train_metal := Color(0.37, 0.355, 0.305)
	var inner_metal := Color(0.19, 0.18, 0.155)
	var tarnished_brass := Color(0.44, 0.33, 0.15)
	var tunnel_black := Color(0.012, 0.016, 0.017)

	# A complete carriage volume. The end bulkheads are intentionally opaque:
	# before the wreck, no angle can expose the combat level outside.
	_add_child_visual_box(shell, Vector3(0.0, -0.08, 0.0), Vector3(5.5, 0.16, 10.6), inner_metal, 0.66, 0.34)
	_add_child_visual_box(shell, Vector3(0.0, 3.18, 0.0), Vector3(4.8, 0.16, 10.6), inner_metal, 0.62, 0.38)
	_add_child_visual_box(shell, Vector3(-2.52, 2.91, 0.0), Vector3(0.55, 0.52, 10.6), train_metal.darkened(0.18), 0.58, 0.42)
	_add_child_visual_box(shell, Vector3(2.52, 2.91, 0.0), Vector3(0.55, 0.52, 10.6), train_metal.darkened(0.18), 0.58, 0.42)
	_add_child_visual_box(shell, Vector3(0.0, 1.55, -5.18), Vector3(5.5, 3.25, 0.18), train_metal, 0.62, 0.35)
	_add_child_visual_box(shell, Vector3(0.0, 1.55, 5.18), Vector3(5.5, 3.25, 0.18), train_metal.darkened(0.08), 0.62, 0.35)
	_add_child_visual_box(
		shell,
		Vector3(0.0, 0.012, 0.0),
		Vector3(1.58, 0.022, 9.65),
		Color(0.13, 0.12, 0.105),
		0.97,
		0.0
	)
	for floor_seam_z in [-3.2, -1.6, 0.0, 1.6, 3.2]:
		_add_child_visual_box(
			shell,
			Vector3(0.0, 0.026, floor_seam_z),
			Vector3(1.54, 0.012, 0.022),
			Color(0.34, 0.29, 0.19),
			0.78,
			0.18
		)

	# Recessed end doors and their battered ceremonial route marks.
	for end_z in [-5.075, 5.075]:
		_add_child_visual_box(shell, Vector3(0.0, 1.48, end_z), Vector3(1.82, 2.68, 0.035), inner_metal, 0.58, 0.40)
		_add_child_visual_box(shell, Vector3(-0.97, 1.48, end_z), Vector3(0.06, 2.76, 0.055), tarnished_brass, 0.48, 0.62)
		_add_child_visual_box(shell, Vector3(0.97, 1.48, end_z), Vector3(0.06, 2.76, 0.055), tarnished_brass, 0.48, 0.62)
		_add_child_emissive_box(
			shell,
			Vector3(0.0, 2.48, end_z - signf(end_z) * 0.021),
			Vector3(0.56, 0.055, 0.028),
			Color(0.48, 0.29, 0.12),
			0.72
		)

	# Side walls are built around real window openings rather than hiding an
	# unbroken wall behind black rectangles.
	for side in [-1.0, 1.0]:
		_add_child_visual_box(
			shell,
			Vector3(side * 2.69, 0.42, 0.0),
			Vector3(0.17, 0.94, 10.6),
			train_metal.darkened(0.08)
		)
		_add_child_visual_box(
			shell,
			Vector3(side * 2.69, 2.76, 0.0),
			Vector3(0.17, 0.84, 10.6),
			train_metal.darkened(0.15)
		)
		for pillar_z in [-5.0, -2.55, 0.0, 2.55, 5.0]:
			_add_child_visual_box(
				shell,
				Vector3(side * 2.69, 1.62, pillar_z),
				Vector3(0.19, 1.52, 0.22),
				inner_metal
			)
		for window_z in [-3.78, -1.28, 1.28, 3.78]:
			_add_child_glass_box(
				shell,
				Vector3(side * 2.71, 1.63, window_z),
				Vector3(0.025, 1.31, 2.17)
			)
			# Thin reflected tubes make the windows read as glass while the
			# dedicated tunnel remains visible through them.
			_add_child_emissive_box(
				shell,
				Vector3(side * 2.665, 1.92, window_z - side * 0.42),
				Vector3(0.018, 0.42, 0.026),
				Color(0.42, 0.40, 0.33),
				0.34
			)

	for light_z in [-3.65, -1.22, 1.22, 3.65]:
		_add_child_emissive_box(
			shell,
			Vector3(0.0, 3.055, light_z),
			Vector3(2.3, 0.045, 0.22),
			Color(0.82, 0.77, 0.62),
			2.05
		)
		var practical := OmniLight3D.new()
		practical.position = Vector3(0.0, 2.72, light_z)
		practical.light_color = Color(0.83, 0.79, 0.67)
		practical.light_energy = 3.55
		practical.omni_range = 5.2
		practical.shadow_enabled = false
		shell.add_child(practical)

	# One low fill makes the seat fabric, scratched rails, and abandoned case
	# readable from the starting position. It is still motivated by the ceiling
	# fluorescents rather than behaving like a film-set key light.
	var carriage_fill := OmniLight3D.new()
	carriage_fill.position = Vector3(0.0, 1.38, 2.45)
	carriage_fill.light_color = Color(0.68, 0.64, 0.53)
	carriage_fill.light_energy = 1.65
	carriage_fill.omni_range = 5.8
	carriage_fill.shadow_enabled = false
	shell.add_child(carriage_fill)

	# Seats face the aisle, leaving a strong central sightline to the sealed
	# door. Empty places, one abandoned case, and a hanging coat imply a last
	# service without needing dialogue or a cutaway.
	for side in [-1.0, 1.0]:
		for seat_z in [-3.55, -1.18, 1.18, 3.55]:
			_add_child_visual_box(
				shell,
				Vector3(side * 2.08, 0.49, seat_z),
				Vector3(0.94, 0.36, 1.45),
				upholstery,
				0.97,
				0.0
			)
			_add_child_visual_box(
				shell,
				Vector3(side * 2.42, 1.08, seat_z),
				Vector3(0.24, 1.35, 1.43),
				upholstery.darkened(0.16),
				0.98,
				0.0
			)
			_add_child_visual_box(
				shell,
				Vector3(side * 2.285, 1.11, seat_z),
				Vector3(0.018, 0.92, 0.032),
				upholstery_wear.darkened(0.12),
				0.99,
				0.0
			)
			_add_child_visual_box(
				shell,
				Vector3(side * 1.57, 0.56, seat_z - 0.69),
				Vector3(0.10, 0.52, 0.09),
				tarnished_brass,
				0.46,
				0.62
			)

		# Luggage rack, overhead rail, and hanging handles make looking up and
		# behind as authored as the initial aisle composition.
		_add_child_visual_box(
			shell,
			Vector3(side * 2.18, 2.43, 0.0),
			Vector3(0.07, 0.07, 9.2),
			tarnished_brass,
			0.44,
			0.66
		)
		for handle_z in [-3.6, -1.8, 0.0, 1.8, 3.6]:
			_add_child_visual_box(
				shell,
				Vector3(side * 1.74, 2.18, handle_z),
				Vector3(0.035, 0.48, 0.035),
				tarnished_brass,
				0.44,
				0.66
			)
			_add_child_visual_box(
				shell,
				Vector3(side * 1.74, 1.94, handle_z),
				Vector3(0.22, 0.035, 0.035),
				tarnished_brass,
				0.44,
				0.66
			)

	# A worn case and discarded coat break the perfect procedural repetition.
	_add_child_visual_box(shell, Vector3(-1.76, 0.22, 2.15), Vector3(0.58, 0.38, 0.92), upholstery_wear)
	_add_child_visual_box(shell, Vector3(-1.76, 0.44, 2.15), Vector3(0.22, 0.06, 0.36), tarnished_brass)
	_add_child_visual_box(shell, Vector3(2.37, 1.38, -1.18), Vector3(0.16, 1.12, 1.12), Color(0.078, 0.072, 0.063))
	_add_child_visual_box(shell, Vector3(2.14, 1.62, -1.18), Vector3(0.42, 0.16, 1.18), Color(0.078, 0.072, 0.063))
	_add_child_visual_box(
		shell,
		Vector3(2.592, 2.56, 1.30),
		Vector3(0.024, 0.34, 0.66),
		Color(0.64, 0.61, 0.50),
		0.90,
		0.0
	)
	for notice_line in [-0.19, -0.06, 0.08]:
		_add_child_visual_box(
			shell,
			Vector3(2.575, 2.56 + notice_line, 1.30),
			Vector3(0.012, 0.018, 0.48),
			Color(0.15, 0.13, 0.095),
			0.90,
			0.0
		)

	# A small analogue route diagram repeats the watch motif without becoming
	# glowing sci-fi signage.
	_add_child_visual_box(shell, Vector3(-2.575, 2.64, 0.0), Vector3(0.025, 0.29, 3.65), inner_metal)
	for mark_z in [-1.45, -0.72, 0.0, 0.72, 1.45]:
		_add_child_emissive_box(
			shell,
			Vector3(-2.586, 2.64, mark_z),
			Vector3(0.019, 0.105, 0.045),
			Color(0.49, 0.28, 0.12),
			0.62
		)

	# The windows look into a dedicated opaque service tunnel, never the combat
	# map. Repeating buttresses and amber maintenance lamps slide past it.
	for side in [-1.0, 1.0]:
		_add_child_visual_box(
			shell,
			Vector3(side * 4.05, 1.58, 0.0),
			Vector3(0.34, 3.65, 24.0),
			tunnel_black
		)
		_add_child_visual_box(
			shell,
			Vector3(side * 3.72, 0.30, 0.0),
			Vector3(0.44, 0.58, 24.0),
			Color(0.055, 0.051, 0.043)
		)
	var window_motion := Node3D.new()
	window_motion.name = "SealedPassingTunnel"
	shell.add_child(window_motion)
	main.prologue_window_motion = window_motion
	for bar_index in range(9):
		var bar_z := -12.0 + float(bar_index) * 3.0
		for side in [-1.0, 1.0]:
			var buttress := _add_child_visual_box_return(
				window_motion,
				Vector3(side * 3.65, 1.58, bar_z),
				Vector3(0.55, 3.42, 0.32),
				Color(0.115, 0.105, 0.085)
			)
			buttress.set_meta("travel_z", bar_z)
			if bar_index % 2 == 0:
				var lamp := _add_child_emissive_box_return(
					window_motion,
					Vector3(side * 3.43, 2.10, bar_z + 0.62),
					Vector3(0.035, 0.17, 0.54),
					Color(0.74, 0.39, 0.13),
					1.9
				)
				lamp.set_meta("travel_z", bar_z + 0.62)

	shell.visible = false


# Encounter trigger zones and spawn markers are authored as scene nodes so
# designers can move encounters and spawns in the editor. main.gd reads them
# back into encounter_definitions / boss_reinforcement_definitions at runtime.
static func build_encounter_zones(main) -> void:
	var encounters: Array = [
		{
			"trigger_z": 12.0,
			"title": "THE ARREARS",
			"subtitle": "The train brought an old collector with it.",
			"threat": 0.35,
			"spawns": [
				[Vector3(-5.0, 0.05, 8.0), EnemyScript.Kind.MELEE],
				[Vector3(5.0, 0.05, 6.0), EnemyScript.Kind.MELEE],
				[Vector3(8.0, 0.05, 2.0), EnemyScript.Kind.RANGED],
			],
		},
		{
			"trigger_z": -2.0,
			"title": "THE SIGNAL WITNESS",
			"subtitle": "Read the timetable. Break the buried guard.",
			"threat": 0.70,
			"spawns": [
				[Vector3(-7.0, 0.05, -6.0), EnemyScript.Kind.MELEE],
				[Vector3(7.0, 0.05, -8.0), EnemyScript.Kind.MELEE],
				[Vector3(-2.0, 0.05, -10.0), EnemyScript.Kind.ELITE],
				[Vector3(9.0, 0.05, -12.0), EnemyScript.Kind.RANGED],
			],
		},
		{
			"trigger_z": -18.0,
			"title": "THE UNFINISHED",
			"subtitle": "The first thing you postponed rises to meet the last.",
			"threat": 1.0,
			"spawns": [
				[Vector3(0.0, 0.05, -22.0), EnemyScript.Kind.BOSS],
			],
		},
	]
	for index in encounters.size():
		var data: Dictionary = encounters[index]
		var zone := Area3D.new()
		zone.name = "Encounter%d" % index
		zone.position = Vector3(0.0, 0.0, float(data["trigger_z"]))
		zone.set_meta("title", data["title"])
		zone.set_meta("subtitle", data["subtitle"])
		zone.set_meta("threat", data["threat"])
		var shape := BoxShape3D.new()
		shape.size = Vector3(33.0, 5.0, 0.48)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = 2.5
		zone.add_child(collision)
		var spawn_index := 0
		for spawn in data["spawns"]:
			var marker := Marker3D.new()
			marker.position = Vector3(spawn[0]) - zone.position
			marker.set_meta("kind", spawn[1])
			marker.name = "Spawn_%s_%d" % [_kind_tag(spawn[1]), spawn_index]
			zone.add_child(marker)
			spawn_index += 1
		main.world_root.add_child(zone)

	var boss := Node3D.new()
	boss.name = "BossReinforcements"
	var phases: Dictionary = {
		2: [
			[Vector3(-7.0, 0.05, -20.0), EnemyScript.Kind.MELEE],
			[Vector3(7.0, 0.05, -20.0), EnemyScript.Kind.MELEE],
		],
		3: [
			[Vector3(0.0, 0.05, -22.5), EnemyScript.Kind.ELITE],
		],
	}
	for phase in [2, 3]:
		var phase_node := Node3D.new()
		phase_node.name = "Phase%d" % phase
		var spawn_index := 0
		for spawn in phases[phase]:
			var marker := Marker3D.new()
			marker.position = Vector3(spawn[0])
			marker.set_meta("kind", spawn[1])
			marker.name = "Spawn_%s_%d" % [_kind_tag(spawn[1]), spawn_index]
			phase_node.add_child(marker)
			spawn_index += 1
		boss.add_child(phase_node)
	main.world_root.add_child(boss)


static func _kind_tag(kind: int) -> String:
	match kind:
		EnemyScript.Kind.MELEE: return "Melee"
		EnemyScript.Kind.RANGED: return "Ranged"
		EnemyScript.Kind.ELITE: return "Elite"
		EnemyScript.Kind.BOSS: return "Boss"
	return "Spawn"


static func _create_encounter_gate(main, z_position: float) -> StaticBody3D:
	var gate := StaticBody3D.new()
	gate.position = Vector3(0.0, 0.0, z_position)
	gate.collision_layer = 1
	gate.collision_mask = 0
	gate.name = "EncounterSeal_%d" % int(z_position)
	gate.add_to_group("encounter_gate", true)
	main.world_root.add_child(gate)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(33.0, 5.0, 0.48)
	collision.shape = shape
	collision.position.y = 2.5
	gate.add_child(collision)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.13, 0.12, 0.105)
	material.metallic = 0.42
	material.roughness = 0.63
	for x in range(-15, 16, 2):
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.18, 5.2, 0.30)
		bar.mesh = bar_mesh
		bar.position = Vector3(float(x), 2.6, 0.0)
		bar.material_override = material
		gate.add_child(bar)
	for y in [0.8, 4.4]:
		var brace := MeshInstance3D.new()
		var brace_mesh := BoxMesh.new()
		brace_mesh.size = Vector3(32.0, 0.24, 0.36)
		brace.mesh = brace_mesh
		brace.position = Vector3(0.0, y, 0.0)
		brace.material_override = material
		gate.add_child(brace)
	return gate


static func _add_static_box(main, at: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> void:
	if parent == null:
		parent = main.world_root
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.metallic = 0.04
	mesh_instance.material_override = material
	body.add_child(mesh_instance)


static func _add_visual_box(main, at: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> void:
	if parent == null:
		parent = main.world_root
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


static func _add_ghost_box(main, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := _make_ghost_material(main, color)
	mesh_instance.material_override = material
	main.world_root.add_child(mesh_instance)


static func _add_ghost_asset(main, path: String, at: Vector3, asset_scale: Vector3, rotation: Vector3) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var holder := Node3D.new()
	holder.position = at
	holder.scale = asset_scale
	holder.rotation = rotation
	main.world_root.add_child(holder)
	var instance := packed.instantiate()
	holder.add_child(instance)
	# Tint is applied at runtime (see apply_runtime_tints) so the scene stores a
	# clean .glb instance without per-child material overrides, which the editor
	# would otherwise warn about and render as fallback-white.
	holder.set_meta("ghost_asset", true)
	holder.set_meta("ghost_color", Color(0.27, 0.21, 0.30))


static func _make_ghost_material(main, color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/deferred_history.gdshader")
	material.set_shader_parameter("history_color", color)
	material.set_shader_parameter("visibility", main.deterioration)
	material.set_shader_parameter("phase_seed", float(main.ghost_materials.size()) * 0.137)
	main.ghost_materials.append(material)
	return material


static func _apply_ghost_material(main, node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		node.material_override = _make_ghost_material(main, color)
	for child in node.get_children():
		_apply_ghost_material(main, child, color)


static func _add_child_visual_box(
	parent: Node3D,
	at: Vector3,
	size: Vector3,
	color: Color,
	roughness := 0.86,
	metallic := 0.08
) -> void:
	_add_child_visual_box_return(parent, at, size, color, roughness, metallic)


static func _add_child_visual_box_return(
	parent: Node3D,
	at: Vector3,
	size: Vector3,
	color: Color,
	roughness := 0.86,
	metallic := 0.08
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance


static func _add_child_glass_box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.065, 0.075, 0.072, 0.24)
	material.metallic = 0.16
	material.roughness = 0.26
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


static func _add_child_emissive_box(
	parent: Node3D,
	at: Vector3,
	size: Vector3,
	color: Color,
	energy: float
) -> void:
	_add_child_emissive_box_return(parent, at, size, color, energy)


static func _add_child_emissive_box_return(
	parent: Node3D,
	at: Vector3,
	size: Vector3,
	color: Color,
	energy: float
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.52
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance


static func _add_optional_pack_asset(
	main,
	path: String,
	at: Vector3,
	asset_scale: Vector3,
	rotation: Vector3,
	tint: Color
) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	return _add_asset(
		main,
		path,
		at,
		asset_scale,
		rotation,
		tint,
		"res://assets/user_pack/Atlas_Albedo_LPUP.png",
		"res://assets/user_pack/color-atlas-emission-night.png",
		"res://assets/user_pack/color-atlas-specular.png"
	)


static func _add_asset(
	main,
	path: String,
	at: Vector3,
	asset_scale: Vector3,
	rotation: Vector3,
	tint: Color,
	texture_path: String = "",
	emission_path: String = "",
	specular_path: String = ""
) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var holder := Node3D.new()
	holder.position = at
	holder.scale = asset_scale
	holder.rotation = rotation
	main.world_root.add_child(holder)
	var instance := packed.instantiate()
	holder.add_child(instance)
	# Tint is applied at runtime (see apply_runtime_tints) so the scene stores a
	# clean .glb/.fbx instance without per-child material overrides, which the
	# editor would otherwise warn about and render as fallback-white.
	holder.set_meta("asset_tint", tint)
	holder.set_meta("asset_textures", [texture_path, emission_path, specular_path])
	return holder


static func _tint_meshes(
	node: Node,
	tint: Color,
	texture: Texture2D = null,
	emission_texture: Texture2D = null,
	specular_texture: Texture2D = null
) -> void:
	if node is MeshInstance3D:
		var material: Material
		if texture != null and emission_texture != null and specular_texture != null:
			var night_material := ShaderMaterial.new()
			night_material.shader = PackNightShader
			night_material.set_shader_parameter("albedo_atlas", texture)
			night_material.set_shader_parameter("night_emission_atlas", emission_texture)
			night_material.set_shader_parameter("specular_atlas", specular_texture)
			night_material.set_shader_parameter("tint", tint)
			material = night_material
		else:
			var standard_material := StandardMaterial3D.new()
			standard_material.albedo_color = tint
			standard_material.albedo_texture = texture
			standard_material.roughness = 0.78
			standard_material.metallic = 0.18
			material = standard_material
		node.material_override = material
	for child in node.get_children():
		_tint_meshes(child, tint, texture, emission_texture, specular_texture)


# Called by main.gd after the world scene is loaded. Re-applies the night-mode
# tint / ghost shaders to instanced prop holders (SM_ apocalypse assets, kenney
# props, figurines) using metadata authored at build time. Keeping this runtime
# means the .tscn stores clean scene instances (no per-child overrides) which
# the editor opens without warnings or fallback-white materials.
static func apply_runtime_tints(main, root: Node) -> void:
	for holder in root.find_children("*", "Node3D", true):
		if holder.has_meta("asset_tint"):
			var tint: Color = holder.get_meta("asset_tint")
			var tex: Texture2D = null
			var emis: Texture2D = null
			var spec: Texture2D = null
			if holder.has_meta("asset_textures"):
				var paths: Array = holder.get_meta("asset_textures")
				if paths.size() > 0 and not String(paths[0]).is_empty() and ResourceLoader.exists(paths[0]):
					tex = load(paths[0]) as Texture2D
				if paths.size() > 1 and not String(paths[1]).is_empty() and ResourceLoader.exists(paths[1]):
					emis = load(paths[1]) as Texture2D
				if paths.size() > 2 and not String(paths[2]).is_empty() and ResourceLoader.exists(paths[2]):
					spec = load(paths[2]) as Texture2D
			_tint_meshes(holder, tint, tex, emis, spec)
		elif holder.has_meta("ghost_asset"):
			_apply_ghost_material(main, holder, holder.get_meta("ghost_color"))


# A modular building block: a collidable mass (so the player can wallkick and
# collide with it) topped by a parapet and grounded by a skirt. Uses a shared
# procedurally-generated noise material (albedo + normal) tinted per facade.
static func _add_building(main, base: Vector3, footprint: Vector2, height: float, color: Color) -> void:
	var mat := _building_material(color)
	# Collidable mass.
	var body := StaticBody3D.new()
	body.position = Vector3(base.x, height * 0.5, base.z)
	body.collision_layer = 1
	body.collision_mask = 0
	main.world_root.add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(footprint.x, height, footprint.y)
	col.shape = shape
	body.add_child(col)
	var mass := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(footprint.x, height, footprint.y)
	mass.mesh = mesh
	mass.material_override = mat
	body.add_child(mass)
	# Parapet + skirt (visual only).
	_add_visual_box(main, Vector3(base.x, height + 0.3, base.z), Vector3(footprint.x + 0.4, 0.6, footprint.y + 0.4), color.darkened(0.2))
	_add_visual_box(main, Vector3(base.x, 0.25, base.z), Vector3(footprint.x + 0.6, 0.5, footprint.y + 0.6), color.darkened(0.4))
