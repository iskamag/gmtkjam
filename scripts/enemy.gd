extends CharacterBody3D

signal died(enemy: Node, reward: float, was_boss: bool)
signal damaged(amount: int, world_position: Vector3, critical: bool)
signal phase_changed(phase: int)

const ProjectileScript = preload("res://scripts/enemy_projectile.gd")

enum Kind {
	MELEE,
	RANGED,
	ELITE,
	BOSS,
}

var kind: int = Kind.MELEE
var player: CharacterBody3D
var game: Node3D

var health := 26000
var maximum_health := 26000
var reward := 7.0
var move_speed := 4.4
var attack_cooldown := 0.8
var windup := 0.0
var pending_attack := &""
var alive := true
var flash := 0.0
var phase := 1
var visual_root: Node3D
var body_materials: Array[StandardMaterial3D] = []
var body_base_colors: Dictionary = {}
var visual_time := 0.0
var spawn_position := Vector3.ZERO
var stagger := 0.0
var stunned := 0.0
var guard := 0.0
var strafe_bias := 1.0
var hit_lean := Vector3.ZERO
var hit_squash := 0.0
var role_name: StringName = &"ARREARS CONDUCTOR"

var body_collision: CollisionShape3D
var manifesting := false
var manifest_requested := false
var manifest_delay := 0.0
var manifest_elapsed := 0.0
var manifest_duration := 0.82
var manifest_depth := 0.8
var manifest_ring: MeshInstance3D
var manifest_shadow: MeshInstance3D
var manifest_ring_material: StandardMaterial3D
var manifest_shadow_material: StandardMaterial3D

var attack_commit_direction := Vector3.ZERO
var attack_commit_speed := 0.0
var cut_flash := 0.0
var weapon_pivot: Node3D
var signal_halo: Node3D
var accent_materials: Array[StandardMaterial3D] = []
var accent_base_colors: Dictionary = {}


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_configure_kind()
	_build_body()
	spawn_position = global_position
	strafe_bias = -1.0 if get_instance_id() % 2 == 0 else 1.0
	if kind == Kind.ELITE:
		guard = 100.0
	if manifest_requested:
		_start_manifest()
	else:
		# Every summoned debt gets an entrance even when its caller does not
		# explicitly choreograph one. Call begin_manifest() again after adding
		# the node to author a longer delay or a deeper rise.
		begin_manifest(0.04 * float(get_instance_id() % 3), 0.8)


func begin_manifest(delay: float = 0.0, rise_depth: float = 0.8) -> void:
	manifest_requested = true
	manifest_delay = maxf(delay, 0.0)
	manifest_depth = maxf(rise_depth, 4.0 if kind == Kind.BOSS else 0.65)
	manifest_duration = (
		1.38
		if kind == Kind.BOSS
		else 1.02 if kind == Kind.ELITE else 0.84 if kind == Kind.RANGED else 0.74
	)
	if not is_node_ready() or not is_instance_valid(visual_root):
		return
	_start_manifest()


func _start_manifest() -> void:
	manifesting = true
	manifest_elapsed = -manifest_delay
	velocity = Vector3.ZERO
	windup = 0.0
	pending_attack = &""
	attack_cooldown = manifest_delay + manifest_duration + 0.45
	collision_layer = 0
	if is_instance_valid(body_collision):
		body_collision.set_deferred("disabled", true)
	if is_instance_valid(visual_root):
		visual_root.visible = manifest_delay <= 0.0
		visual_root.position = Vector3(0.0, -manifest_depth, 0.0)
	if is_instance_valid(manifest_ring):
		manifest_ring.visible = true
		manifest_ring.scale = Vector3.ONE * 0.18
	if is_instance_valid(manifest_shadow):
		manifest_shadow.visible = true
		manifest_shadow.scale = Vector3.ONE * 0.42


func _update_manifest(delta: float) -> void:
	manifest_elapsed += delta
	var waiting := manifest_elapsed < 0.0
	var progress := clampf(manifest_elapsed / manifest_duration, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var pulse := 0.5 + sin(visual_time * 12.0) * 0.5
	var ring_size := (
		2.25
		if kind == Kind.BOSS
		else 1.48 if kind == Kind.ELITE else 1.05
	)

	if is_instance_valid(manifest_ring):
		var prelude := clampf((manifest_elapsed + 0.22) / 0.22, 0.0, 1.0)
		manifest_ring.scale = Vector3.ONE * ring_size * (
			0.25 + prelude * 0.75 + pulse * 0.035
		)
		manifest_ring.rotation.y += delta * (0.55 if kind == Kind.BOSS else 1.15)
	if is_instance_valid(manifest_shadow):
		var shadow_scale := lerpf(0.48, ring_size * 0.86, maxf(progress, 0.1))
		manifest_shadow.scale = Vector3.ONE * shadow_scale
	if is_instance_valid(manifest_ring_material):
		manifest_ring_material.emission_energy_multiplier = 0.4 + pulse * 0.55
	if is_instance_valid(manifest_shadow_material):
		var shadow_alpha := 0.46 if waiting else lerpf(0.52, 0.13, progress)
		manifest_shadow_material.albedo_color.a = shadow_alpha

	if waiting:
		if is_instance_valid(visual_root):
			visual_root.visible = false
		return

	if is_instance_valid(visual_root):
		# The silhouette is initially only a sliver above the ground. The boss
		# travels far enough that its buried mass reads before its identity.
		visual_root.visible = progress > 0.035
		var tremor := sin(progress * PI * 8.0) * (1.0 - progress)
		visual_root.position = Vector3(
			tremor * (0.10 if kind == Kind.BOSS else 0.035),
			lerpf(-manifest_depth, 0.0, eased),
			0.0
		)
		visual_root.rotation.y = (1.0 - eased) * (
			0.34 if kind == Kind.BOSS else -0.16 * strafe_bias
		)

	if progress < 1.0:
		return

	manifesting = false
	manifest_requested = false
	visual_root.position = Vector3.ZERO
	visual_root.rotation = Vector3.ZERO
	collision_layer = 2
	if is_instance_valid(body_collision):
		body_collision.set_deferred("disabled", false)
	if is_instance_valid(manifest_ring):
		manifest_ring.visible = false
	if is_instance_valid(manifest_shadow):
		manifest_shadow.visible = false
	attack_cooldown = maxf(attack_cooldown, 0.42)
	if is_instance_valid(game):
		var burst_color := (
			Color(0.49, 0.39, 0.58)
			if kind == Kind.RANGED
			else Color(0.62, 0.48, 0.29)
		)
		game.spawn_burst(
			global_position + Vector3.UP * (1.6 if kind == Kind.BOSS else 0.3),
			burst_color,
			20 if kind == Kind.BOSS else 7
		)


func _physics_process(delta: float) -> void:
	if not alive:
		return

	var hostile_scale := 1.0
	if is_instance_valid(player) and player.has_method("get_hostile_time_scale"):
		hostile_scale = player.get_hostile_time_scale()
	elif is_instance_valid(game):
		hostile_scale = game.get_hostile_time_scale()
	var local_delta := delta * hostile_scale
	visual_time += local_delta
	if manifesting:
		_update_manifest(delta)
		return
	if not is_instance_valid(player) or not player.active:
		return

	flash = max(flash - local_delta * 5.0, 0.0)
	attack_cooldown -= local_delta
	stagger = maxf(stagger - local_delta * 11.0, 0.0)
	stunned = maxf(stunned - local_delta, 0.0)
	hit_lean = hit_lean.lerp(Vector3.ZERO, 1.0 - exp(-local_delta * 9.0))
	hit_squash = maxf(hit_squash - local_delta * 6.0, 0.0)
	cut_flash = maxf(cut_flash - local_delta * 7.5, 0.0)

	if not is_on_floor():
		velocity.y -= 24.0 * local_delta
	else:
		velocity.y = min(velocity.y, 0.0)

	var to_player := player.global_position - global_position
	var flat_to_player := Vector3(to_player.x, 0.0, to_player.z)
	var distance := flat_to_player.length()
	if distance > 0.01:
		look_at(global_position + flat_to_player, Vector3.UP)

	if stunned > 0.0:
		windup = 0.0
		pending_attack = &""
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * local_delta)
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * local_delta)
	elif windup > 0.0:
		var previous := windup
		windup -= local_delta
		if pending_attack == &"melee" and windup <= 0.18:
			velocity.x = attack_commit_direction.x * attack_commit_speed
			velocity.z = attack_commit_direction.z * attack_commit_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * local_delta)
			velocity.z = move_toward(velocity.z, 0.0, 18.0 * local_delta)
		if previous > 0.0 and windup <= 0.0:
			_resolve_attack()
	else:
		_choose_motion(flat_to_player, distance, local_delta)
		if attack_cooldown <= 0.0:
			_consider_attack(distance)

	move_and_slide()
	_update_visual(distance, local_delta)


func _choose_motion(flat_to_player: Vector3, distance: float, delta: float) -> void:
	var desired := Vector3.ZERO
	if kind == Kind.RANGED:
		if distance > 12.0:
			desired = flat_to_player.normalized() * move_speed
		elif distance < 6.2:
			desired = -flat_to_player.normalized() * move_speed * 0.92
		else:
			# Signal Witnesses choose a side and hold it. They do not oscillate
			# like turrets on a sine wave.
			var tangent := flat_to_player.normalized().cross(Vector3.UP)
			desired = tangent * move_speed * 0.42 * strafe_bias
	elif kind == Kind.BOSS:
		var phase_speed := move_speed * (1.0 + float(phase - 1) * 0.13)
		if distance > 6.4:
			desired = flat_to_player.normalized() * phase_speed
		elif distance < 3.5:
			desired = -flat_to_player.normalized() * move_speed * 0.22
	else:
		if distance > 5.1:
			desired = flat_to_player.normalized() * move_speed
		elif distance > 2.65:
			var approach := flat_to_player.normalized() * move_speed * 0.28
			var orbit := flat_to_player.normalized().cross(Vector3.UP) * move_speed * 0.32 * strafe_bias
			desired = approach + orbit
		else:
			desired = -flat_to_player.normalized() * move_speed * 0.22

	velocity.x = move_toward(velocity.x, desired.x, 15.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 15.0 * delta)


func _consider_attack(distance: float) -> void:
	if kind == Kind.RANGED and distance < 22.0:
		_begin_attack(&"shot", 0.48, 1.22)
	elif kind == Kind.BOSS:
		if distance < 4.1:
			_begin_attack(&"heavy", 0.56, 1.10)
		else:
			_begin_attack(&"volley", 0.68, 1.34 if phase == 1 else (1.18 if phase == 2 else 1.02))
	elif distance < (4.25 if kind == Kind.ELITE else 4.05):
		_begin_attack(&"melee", 0.42 if kind == Kind.MELEE else 0.50, 0.96 if kind == Kind.MELEE else 1.08)


func _begin_attack(which: StringName, delay: float, recovery: float) -> void:
	pending_attack = which
	windup = delay
	attack_cooldown = recovery
	if which == &"melee" and is_instance_valid(player):
		attack_commit_direction = player.global_position - global_position
		attack_commit_direction.y = 0.0
		if attack_commit_direction.length_squared() > 0.001:
			attack_commit_direction = attack_commit_direction.normalized()
		attack_commit_speed = 12.8 if kind == Kind.MELEE else 10.4
	for material in body_materials:
		material.emission_enabled = true
		material.emission = Color(0.76, 0.55, 0.28)
		material.emission_energy_multiplier = 0.8


func _resolve_attack() -> void:
	match pending_attack:
		&"melee":
			cut_flash = 1.0
			if global_position.distance_to(player.global_position) < (
				3.55 if kind == Kind.ELITE else 3.25
			) and _has_clear_line_to_player():
				player.hurt(
					11.5 if kind == Kind.ELITE else 8.5,
					2.25 if kind == Kind.ELITE else 1.5,
					global_position
				)
		&"heavy":
			if (
				global_position.distance_to(player.global_position) < 4.25
				and _has_clear_line_to_player()
			):
				player.hurt(15.0, 3.6, global_position)
			if is_instance_valid(game):
				game.spawn_burst(global_position + Vector3.UP * 0.35, Color(0.55, 0.37, 0.18), 14)
		&"shot":
			# A narrow three-seal rake is readable as a single decision: cut
			# one back, or commit to moving through the gap.
			for offset in [-0.075, 0.0, 0.075]:
				_fire_at_player(15.5, 8.0, 1.45, offset, &"SEAL")
		&"volley":
			_fire_boss_pattern()
	pending_attack = &""


func _has_clear_line_to_player() -> bool:
	if not is_inside_tree() or not is_instance_valid(player):
		return false
	var from := global_position + Vector3.UP * 0.9
	var to := player.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid(), player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _fire_at_player(
	speed: float,
	time_damage: float,
	max_damage: float,
	angular_offset: float = 0.0,
	style_name: StringName = &"NEEDLE"
) -> void:
	if not is_instance_valid(player):
		return
	var projectile := ProjectileScript.new()
	projectile.player = player
	projectile.game = game
	projectile.speed = speed
	projectile.time_damage = time_damage
	projectile.max_damage = max_damage
	var origin := global_position + Vector3.UP * (1.15 if kind != Kind.BOSS else 2.1)
	var target := player.global_position + Vector3.UP * 0.9
	var flight_time := clampf(origin.distance_to(target) / maxf(speed, 1.0), 0.0, 0.72)
	var player_motion := Vector3(player.velocity.x, 0.0, player.velocity.z)
	target += player_motion * flight_time * (0.42 if kind == Kind.BOSS else 0.58)
	var direction := (target - origin).normalized()
	if absf(angular_offset) > 0.001:
		direction = direction.rotated(Vector3.UP, angular_offset)
	projectile.direction = direction
	_set_projectile_style(projectile, style_name)
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin


func _fire_boss_pattern() -> void:
	if phase == 1:
		for offset in [-0.30, -0.15, 0.0, 0.15, 0.30]:
			_fire_at_player(13.0, 8.5, 1.55, offset, &"BLADE")
	elif phase == 2:
		# The old ring started above head height with a positive Y component,
		# so its cross-shaped seals visibly sailed upward. These are now a low,
		# descending clock-face cut that actually contests the arena floor.
		for index in 12:
			var angle := TAU * float(index) / 12.0
			_fire_direction(
				_boss_ring_direction(angle),
				11.5,
				&"SEAL",
				0.82
			)
		for offset in [-0.18, 0.0, 0.18]:
			_fire_at_player(14.5, 9.0, 1.7, offset, &"BLADE")
	else:
		for offset in [-0.42, -0.28, -0.14, 0.0, 0.14, 0.28, 0.42]:
			_fire_at_player(17.0, 10.0, 1.9, offset, &"BLADE")


func _boss_ring_direction(angle: float) -> Vector3:
	return Vector3(cos(angle), -0.065, sin(angle)).normalized()


func _fire_direction(
	shot_direction: Vector3,
	shot_speed: float,
	style_name: StringName = &"NEEDLE",
	origin_height: float = 1.15
) -> void:
	var projectile := ProjectileScript.new()
	projectile.player = player
	projectile.game = game
	projectile.speed = shot_speed
	projectile.time_damage = 9.0
	projectile.max_damage = 1.7
	projectile.direction = shot_direction
	_set_projectile_style(projectile, style_name)
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + Vector3.UP * origin_height


func _set_projectile_style(projectile: Node, style_name: StringName) -> void:
	# enemy_projectile.gd owns the visual enum. Looking the property up keeps
	# this enemy script compatible with older cooked builds during iteration.
	var style_value := 0
	match style_name:
		&"SEAL":
			style_value = 1
		&"BLADE":
			style_value = 2
	for property_data in projectile.get_property_list():
		var property_name := StringName(property_data.get("name", ""))
		if property_name == &"style":
			projectile.set("style", style_value)
			return


func take_damage(
	amount: int,
	hit_position: Vector3,
	critical: bool = false,
	stagger_force: float = 30.0,
	launch_force: float = 0.0
) -> void:
	if not alive or manifesting:
		return
	var applied_damage := amount
	if kind == Kind.ELITE and guard > 0.0 and stunned <= 0.0:
		if stagger_force < 55.0:
			applied_damage = int(float(amount) * 0.38)
			guard = maxf(guard - stagger_force * 0.62, 0.0)
			stagger_force *= 0.32
		else:
			guard = 0.0
			stunned = 1.3
			critical = true
	health -= applied_damage
	stagger += stagger_force
	flash = 1.0
	hit_squash = 1.0
	var away := global_position - player.global_position
	away.y = 0.0
	if away.length_squared() > 0.0001:
		var knockback := stagger_force * (0.055 if kind != Kind.BOSS else 0.012)
		velocity += away.normalized() * knockback
		hit_lean = away.normalized() * minf(stagger_force * 0.0028, 0.26)
	if launch_force > 0.0 and kind != Kind.BOSS:
		velocity.y = maxf(velocity.y, launch_force)
		stunned = maxf(stunned, 0.58 + launch_force * 0.055)
	if stagger >= (145.0 if kind == Kind.BOSS else 100.0):
		stagger = 0.0
		stunned = 0.48 if kind == Kind.BOSS else 1.05
		critical = true
	emit_signal("damaged", applied_damage, global_position + Vector3.UP * (2.5 if kind == Kind.BOSS else 1.65), critical)

	if kind == Kind.BOSS:
		var ratio := float(health) / float(maximum_health)
		if phase == 1 and ratio <= 0.66:
			phase = 2
			emit_signal("phase_changed", phase)
		elif phase == 2 and ratio <= 0.32:
			phase = 3
			emit_signal("phase_changed", phase)

	if health <= 0:
		_die()


func is_vulnerable() -> bool:
	return stunned > 0.0 or guard <= 0.0 and kind == Kind.ELITE


func vanish() -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	if is_instance_valid(body_collision):
		body_collision.set_deferred("disabled", true)
	queue_free()


func _die() -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	if is_instance_valid(body_collision):
		body_collision.set_deferred("disabled", true)
	emit_signal("died", self, reward, kind == Kind.BOSS)
	queue_free()


func _configure_kind() -> void:
	match kind:
		Kind.MELEE:
			role_name = &"ARREARS CONDUCTOR"
			health = 31500
			reward = 7.0
			move_speed = 6.3
		Kind.RANGED:
			role_name = &"SIGNAL WITNESS"
			health = 26500
			reward = 8.0
			move_speed = 4.6
		Kind.ELITE:
			role_name = &"BURIED RETAINER"
			health = 68000
			reward = 13.0
			move_speed = 6.0
		Kind.BOSS:
			role_name = &"UNFINISHED CHAMPION"
			health = 220000
			reward = 60.0
			move_speed = 4.3
	maximum_health = health


func _build_body() -> void:
	body_collision = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.75 if kind == Kind.BOSS else 0.46
	shape.height = 3.7 if kind == Kind.BOSS else 1.85
	body_collision.shape = shape
	body_collision.position.y = 1.85 if kind == Kind.BOSS else 0.92
	add_child(body_collision)

	visual_root = Node3D.new()
	visual_root.name = "DeferredBody"
	add_child(visual_root)

	var path := (
		"res://assets/kenney/figurine-large.glb"
		if kind == Kind.BOSS
		else "res://assets/kenney/figurine.glb"
	)
	var packed := load(path) as PackedScene
	if packed != null:
		var instance := packed.instantiate()
		visual_root.add_child(instance)
		if kind == Kind.BOSS:
			instance.scale = Vector3(2.25, 2.62, 2.12)
		elif kind == Kind.ELITE:
			instance.scale = Vector3(1.58, 1.42, 1.34)
		elif kind == Kind.RANGED:
			instance.scale = Vector3(1.06, 1.52, 1.03)
		else:
			instance.scale = Vector3(1.20, 1.42, 1.08)
		_tint_visual(instance, _kind_color())
	else:
		var fallback := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.45
		mesh.height = 1.8
		fallback.mesh = mesh
		fallback.position.y = 0.9
		visual_root.add_child(fallback)
		_tint_visual(fallback, _kind_color())

	_build_kind_silhouette()
	_build_manifestation_geometry()


func _build_kind_silhouette() -> void:
	match kind:
		Kind.RANGED:
			_build_signal_witness()
		Kind.ELITE:
			_build_buried_retainer()
		Kind.BOSS:
			_build_unfinished_champion()
		_:
			_build_arrears_conductor()


func _build_arrears_conductor() -> void:
	weapon_pivot = Node3D.new()
	weapon_pivot.name = "ArrearsLongBlade"
	weapon_pivot.position = Vector3(0.56, 1.33, -0.08)
	visual_root.add_child(weapon_pivot)
	_add_box_geometry(
		weapon_pivot,
		"LongBlade",
		Vector3(0.12, 1.62, 0.10),
		Vector3(0.0, -0.62, 0.0),
		Color(0.52, 0.50, 0.44),
		Vector3(0.0, 0.0, 0.10),
		true
	)
	_add_box_geometry(
		weapon_pivot,
		"BladeWear",
		Vector3(0.035, 1.38, 0.12),
		Vector3(-0.035, -0.60, -0.012),
		Color(0.37, 0.19, 0.13),
		Vector3(0.0, 0.0, 0.10),
		true
	)
	_add_box_geometry(
		weapon_pivot,
		"Crossguard",
		Vector3(0.46, 0.085, 0.16),
		Vector3(0.0, 0.19, 0.0),
		Color(0.25, 0.18, 0.12),
		Vector3.ZERO,
		true
	)
	_add_box_geometry(
		visual_root,
		"ConductorMantle",
		Vector3(0.88, 0.18, 0.45),
		Vector3(0.0, 1.38, 0.05),
		Color(0.14, 0.12, 0.10),
		Vector3(0.0, 0.0, -0.04)
	)


func _build_signal_witness() -> void:
	signal_halo = Node3D.new()
	signal_halo.name = "SignalClockHalo"
	signal_halo.position = Vector3(0.0, 1.62, 0.18)
	visual_root.add_child(signal_halo)

	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.38
	halo_mesh.outer_radius = 0.47
	halo_mesh.rings = 18
	halo_mesh.ring_segments = 6
	_add_primitive_geometry(
		signal_halo,
		"SignalRing",
		halo_mesh,
		Vector3.ZERO,
		Color(0.45, 0.30, 0.53),
		Vector3(PI * 0.5, 0.0, 0.0),
		true,
		0.72
	)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		_add_box_geometry(
			signal_halo,
			"SignalTick%02d" % index,
			Vector3(0.055, 0.15, 0.06),
			Vector3(cos(angle), sin(angle), -0.015) * 0.50,
			Color(0.64, 0.55, 0.38),
			Vector3(0.0, 0.0, -angle),
			true,
			0.48
		)
	_add_box_geometry(
		signal_halo,
		"MinuteHand",
		Vector3(0.045, 0.34, 0.075),
		Vector3(0.0, 0.13, -0.035),
		Color(0.71, 0.66, 0.53),
		Vector3(0.0, 0.0, 0.34),
		true,
		0.65
	)
	_add_box_geometry(
		visual_root,
		"WitnessStaff",
		Vector3(0.08, 1.42, 0.08),
		Vector3(-0.54, 0.77, -0.02),
		Color(0.28, 0.19, 0.14),
		Vector3(0.0, 0.0, -0.08),
		true
	)


func _build_buried_retainer() -> void:
	for index in 4:
		var plate_y := 0.70 + float(index) * 0.27
		var plate_rotation := (-0.035 if index % 2 == 0 else 0.035)
		_add_box_geometry(
			visual_root,
			"RetainerGuardPlate%02d" % index,
			Vector3(1.12 - float(index) * 0.07, 0.22, 0.19),
			Vector3(0.0, plate_y, -0.39),
			Color(0.40, 0.38, 0.32),
			Vector3(0.0, 0.0, plate_rotation)
		)
	for side in [-1.0, 1.0]:
		_add_box_geometry(
			visual_root,
			"RetainerShoulder%s" % ("L" if side < 0.0 else "R"),
			Vector3(0.52, 0.30, 0.58),
			Vector3(side * 0.58, 1.43, 0.0),
			Color(0.31, 0.29, 0.24),
			Vector3(0.0, 0.0, side * 0.13)
		)
	_add_box_geometry(
		visual_root,
		"BurialSeal",
		Vector3(0.23, 0.23, 0.08),
		Vector3(0.0, 1.15, -0.51),
		Color(0.72, 0.65, 0.46),
		Vector3(0.0, 0.0, PI * 0.25),
		true,
		0.42
	)


func _build_unfinished_champion() -> void:
	_add_box_geometry(
		visual_root,
		"ChampionRightShoulder",
		Vector3(1.52, 0.62, 0.92),
		Vector3(1.02, 2.65, 0.04),
		Color(0.23, 0.20, 0.17),
		Vector3(0.08, -0.12, -0.18)
	)
	_add_box_geometry(
		visual_root,
		"ChampionBuriedBlade",
		Vector3(0.26, 3.25, 0.18),
		Vector3(1.43, 1.54, -0.06),
		Color(0.44, 0.42, 0.36),
		Vector3(0.0, 0.0, -0.22),
		true
	)
	for index in 3:
		_add_box_geometry(
			visual_root,
			"ChampionLeftShard%02d" % index,
			Vector3(0.32, 0.82 - float(index) * 0.13, 0.42),
			Vector3(
				-0.92 - float(index) * 0.20,
				2.25 + float(index) * 0.42,
				0.09
			),
			Color(0.18, 0.16, 0.14),
			Vector3(0.0, 0.0, 0.28 + float(index) * 0.17)
		)

	signal_halo = Node3D.new()
	signal_halo.name = "BrokenChampionHalo"
	signal_halo.position = Vector3(-0.28, 3.35, 0.26)
	signal_halo.rotation.z = -0.28
	visual_root.add_child(signal_halo)
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.62
	halo_mesh.outer_radius = 0.73
	halo_mesh.rings = 20
	halo_mesh.ring_segments = 7
	_add_primitive_geometry(
		signal_halo,
		"ChampionHistoryRing",
		halo_mesh,
		Vector3.ZERO,
		Color(0.48, 0.30, 0.21),
		Vector3(PI * 0.5, 0.0, 0.0),
		true,
		0.44
	)
	_add_box_geometry(
		visual_root,
		"ChampionChestFault",
		Vector3(0.12, 1.24, 0.10),
		Vector3(0.18, 2.00, -0.72),
		Color(0.68, 0.50, 0.29),
		Vector3(0.0, 0.0, -0.16),
		true,
		0.72
	)


func _add_box_geometry(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	at: Vector3,
	color: Color,
	rotation_value: Vector3 = Vector3.ZERO,
	accent: bool = false,
	emission_energy: float = 0.0
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_primitive_geometry(
		parent,
		node_name,
		mesh,
		at,
		color,
		rotation_value,
		accent,
		emission_energy
	)


func _add_primitive_geometry(
	parent: Node3D,
	node_name: String,
	mesh: PrimitiveMesh,
	at: Vector3,
	color: Color,
	rotation_value: Vector3 = Vector3.ZERO,
	accent: bool = false,
	emission_energy: float = 0.0
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rotation_value
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	material.metallic = 0.42 if accent else 0.24
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	instance.material_override = material
	parent.add_child(instance)
	if accent:
		accent_materials.append(material)
		accent_base_colors[material] = color
	else:
		body_materials.append(material)
		body_base_colors[material] = color
	return instance


func _build_manifestation_geometry() -> void:
	var radius := 2.15 if kind == Kind.BOSS else 1.35 if kind == Kind.ELITE else 0.92
	manifest_shadow_material = StandardMaterial3D.new()
	manifest_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	manifest_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	manifest_shadow_material.albedo_color = Color(0.018, 0.014, 0.018, 0.48)

	manifest_shadow = MeshInstance3D.new()
	manifest_shadow.name = "ManifestShadow"
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = radius
	shadow_mesh.bottom_radius = radius * 0.90
	shadow_mesh.height = 0.018
	shadow_mesh.radial_segments = 18
	manifest_shadow.mesh = shadow_mesh
	manifest_shadow.position.y = 0.012
	manifest_shadow.material_override = manifest_shadow_material
	manifest_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	manifest_shadow.visible = false
	add_child(manifest_shadow)

	manifest_ring_material = StandardMaterial3D.new()
	manifest_ring_material.albedo_color = (
		Color(0.34, 0.23, 0.40)
		if kind == Kind.RANGED
		else Color(0.39, 0.27, 0.17)
	)
	manifest_ring_material.emission_enabled = true
	manifest_ring_material.emission = manifest_ring_material.albedo_color
	manifest_ring_material.emission_energy_multiplier = 0.65
	manifest_ring_material.roughness = 0.82

	manifest_ring = MeshInstance3D.new()
	manifest_ring.name = "ManifestGroundRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius * 0.78
	ring_mesh.outer_radius = radius
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 6
	manifest_ring.mesh = ring_mesh
	manifest_ring.position.y = 0.035
	manifest_ring.material_override = manifest_ring_material
	manifest_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	manifest_ring.visible = false
	add_child(manifest_ring)

	for index in 6:
		var crack := MeshInstance3D.new()
		crack.name = "GroundFault%02d" % index
		var crack_mesh := BoxMesh.new()
		crack_mesh.size = Vector3(radius * 0.60, 0.018, 0.035)
		crack.mesh = crack_mesh
		var angle := TAU * float(index) / 6.0 + float(index % 2) * 0.17
		crack.position = Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.72
		crack.rotation.y = -angle
		crack.material_override = manifest_ring_material
		crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		manifest_ring.add_child(crack)


func _kind_color() -> Color:
	match kind:
		Kind.RANGED:
			return Color(0.19, 0.13, 0.085)
		Kind.ELITE:
			return Color(0.31, 0.29, 0.24)
		Kind.BOSS:
			return Color(0.12, 0.105, 0.085)
		_:
			return Color(0.10, 0.095, 0.085)


func _tint_visual(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.78
		material.metallic = 0.18
		node.material_override = material
		body_materials.append(material)
		body_base_colors[material] = color
	for child in node.get_children():
		_tint_visual(child, color)


func _add_role_mark(at: Vector3, color: Color, size: float = 0.18) -> void:
	var mark := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, size, 0.055)
	mark.mesh = mesh
	mark.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.55
	mark.material_override = material
	visual_root.add_child(mark)


func _update_visual(_distance: float, delta: float) -> void:
	if not is_instance_valid(visual_root):
		return
	var bob_scale := 0.025 if kind != Kind.BOSS else 0.06
	var attack_lean := 0.0
	if windup > 0.0:
		attack_lean = -0.10 if pending_attack == &"melee" else 0.045
	elif cut_flash > 0.0:
		attack_lean = 0.16 * cut_flash
	visual_root.position = Vector3(
		hit_lean.x,
		sin(visual_time * (4.0 if kind != Kind.BOSS else 2.0)) * bob_scale - hit_squash * 0.11,
		hit_lean.z
	)
	visual_root.rotation.x = lerp_angle(
		visual_root.rotation.x,
		attack_lean,
		1.0 - exp(-delta * 14.0)
	)
	visual_root.scale = Vector3(
		1.0 + hit_squash * 0.14,
		1.0 - hit_squash * 0.20,
		1.0 + hit_squash * 0.14
	)
	if is_instance_valid(weapon_pivot):
		var weapon_target := 0.10
		if pending_attack == &"melee" and windup > 0.0:
			weapon_target = -1.18 + windup * 0.62
		elif cut_flash > 0.0:
			weapon_target = 1.18 * cut_flash
		weapon_pivot.rotation.z = lerp_angle(
			weapon_pivot.rotation.z,
			weapon_target,
			0.34
		)
	if is_instance_valid(signal_halo):
		var halo_speed := 2.8 if windup > 0.0 else 0.42
		signal_halo.rotation.z += halo_speed * delta

	var telegraph := windup > 0.0
	for material in body_materials:
		var base: Color = body_base_colors.get(material, _kind_color())
		var response: float = maxf(flash, 0.42 if telegraph else 0.0)
		if stunned > 0.0:
			response = maxf(response, 0.58)
		if kind == Kind.ELITE and guard > 0.0:
			response = maxf(response, 0.12)
		material.albedo_color = base.lerp(Color(0.93, 0.75, 0.46), response)
		material.emission_enabled = telegraph or flash > 0.05 or stunned > 0.0
		if not material.emission_enabled:
			material.emission = Color.BLACK
		else:
			material.emission = Color(0.56, 0.37, 0.16) if telegraph else Color(0.65, 0.62, 0.5)
			material.emission_energy_multiplier = 0.75 + flash

	for material in accent_materials:
		var accent_base: Color = accent_base_colors.get(material, Color(0.58, 0.48, 0.32))
		var accent_response := maxf(flash, 0.32 if telegraph else 0.0)
		material.albedo_color = accent_base.lerp(Color(0.96, 0.82, 0.56), accent_response)
		material.emission_enabled = true
		material.emission = accent_base.lerp(Color(0.68, 0.42, 0.20), accent_response)
		material.emission_energy_multiplier = (
			0.42 + accent_response * 1.25 + sin(visual_time * 5.0) * 0.06
		)
