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
var visual_time := 0.0
var spawn_position := Vector3.ZERO
var stagger := 0.0
var stunned := 0.0
var guard := 0.0
var strafe_bias := 1.0
var hit_lean := Vector3.ZERO
var hit_squash := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_configure_kind()
	_build_body()
	spawn_position = global_position
	strafe_bias = -1.0 if get_instance_id() % 2 == 0 else 1.0
	if kind == Kind.ELITE:
		guard = 100.0


func _physics_process(delta: float) -> void:
	if not alive or not is_instance_valid(player) or not player.active:
		return

	var hostile_scale := 1.0
	if is_instance_valid(game):
		hostile_scale = game.get_hostile_time_scale()
	var local_delta := delta * hostile_scale
	visual_time += local_delta
	flash = max(flash - local_delta * 5.0, 0.0)
	attack_cooldown -= local_delta
	stagger = maxf(stagger - local_delta * 11.0, 0.0)
	stunned = maxf(stunned - local_delta, 0.0)
	hit_lean = hit_lean.lerp(Vector3.ZERO, 1.0 - exp(-local_delta * 9.0))
	hit_squash = maxf(hit_squash - local_delta * 6.0, 0.0)

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
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * local_delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * local_delta)
		if previous > 0.0 and windup <= 0.0:
			_resolve_attack()
	else:
		_choose_motion(flat_to_player, distance, local_delta)
		if attack_cooldown <= 0.0:
			_consider_attack(distance)

	move_and_slide()
	_update_visual(distance)


func _choose_motion(flat_to_player: Vector3, distance: float, delta: float) -> void:
	var desired := Vector3.ZERO
	if kind == Kind.RANGED:
		if distance > 10.0:
			desired = flat_to_player.normalized() * move_speed
		elif distance < 5.0:
			desired = -flat_to_player.normalized() * move_speed * 0.85
		else:
			desired = global_transform.basis.x * sin(visual_time * 1.7) * move_speed * 0.45
	elif kind == Kind.BOSS:
		if distance > 5.2:
			desired = flat_to_player.normalized() * move_speed
		else:
			desired = global_transform.basis.x * sin(visual_time * 1.4) * move_speed * 0.55
	else:
		if distance > 4.5:
			desired = flat_to_player.normalized() * move_speed
		elif distance > 2.25:
			var approach := flat_to_player.normalized() * move_speed * 0.42
			var orbit := flat_to_player.normalized().cross(Vector3.UP) * move_speed * 0.72 * strafe_bias
			desired = approach + orbit
		else:
			desired = -flat_to_player.normalized() * move_speed * 0.35

	velocity.x = move_toward(velocity.x, desired.x, 12.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 12.0 * delta)


func _consider_attack(distance: float) -> void:
	if kind == Kind.RANGED and distance < 18.0:
		_begin_attack(&"shot", 0.5, 1.7)
	elif kind == Kind.BOSS:
		if distance < 3.1:
			_begin_attack(&"heavy", 0.62, 1.25)
		else:
			_begin_attack(&"volley", 0.72, 1.55)
	elif distance < (2.7 if kind == Kind.ELITE else 2.15):
		_begin_attack(&"melee", 0.42 if kind == Kind.MELEE else 0.52, 1.05)


func _begin_attack(which: StringName, delay: float, recovery: float) -> void:
	pending_attack = which
	windup = delay
	attack_cooldown = recovery
	for material in body_materials:
		material.emission_enabled = true
		material.emission = Color(0.76, 0.55, 0.28)
		material.emission_energy_multiplier = 0.8


func _resolve_attack() -> void:
	match pending_attack:
		&"melee":
			if global_position.distance_to(player.global_position) < 2.65:
				player.hurt(
					7.2 if kind == Kind.ELITE else 5.2,
					1.65 if kind == Kind.ELITE else 1.0,
					global_position
				)
		&"heavy":
			if global_position.distance_to(player.global_position) < 3.8:
				player.hurt(10.5, 2.4, global_position)
			if is_instance_valid(game):
				game.spawn_burst(global_position + Vector3.UP * 0.35, Color(0.55, 0.37, 0.18), 14)
		&"shot":
			_fire_at_player(10.0, 7.0, 1.25)
		&"volley":
			_fire_boss_pattern()
	pending_attack = &""


func _fire_at_player(speed: float, time_damage: float, max_damage: float, angular_offset: float = 0.0) -> void:
	if not is_instance_valid(player):
		return
	var projectile := ProjectileScript.new()
	projectile.player = player
	projectile.game = game
	projectile.speed = speed
	projectile.time_damage = time_damage
	projectile.max_damage = max_damage
	var target := player.global_position + Vector3.UP * 0.9
	var origin := global_position + Vector3.UP * (1.15 if kind != Kind.BOSS else 2.1)
	var direction := (target - origin).normalized()
	if absf(angular_offset) > 0.001:
		direction = direction.rotated(Vector3.UP, angular_offset)
	projectile.direction = direction
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin


func _fire_boss_pattern() -> void:
	if phase == 1:
		for offset in [-0.28, -0.14, 0.0, 0.14, 0.28]:
			_fire_at_player(9.0, 7.0, 1.15, offset)
	elif phase == 2:
		for index in 9:
			var angle := TAU * float(index) / 9.0
			_fire_direction(Vector3(cos(angle), 0.025, sin(angle)).normalized(), 8.0)
	else:
		for offset in [-0.42, -0.28, -0.14, 0.0, 0.14, 0.28, 0.42]:
			_fire_at_player(12.0, 8.0, 1.4, offset)


func _fire_direction(shot_direction: Vector3, shot_speed: float) -> void:
	var projectile := ProjectileScript.new()
	projectile.player = player
	projectile.game = game
	projectile.speed = shot_speed
	projectile.time_damage = 7.5
	projectile.max_damage = 1.35
	projectile.direction = shot_direction
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + Vector3.UP * 1.6


func take_damage(
	amount: int,
	hit_position: Vector3,
	critical: bool = false,
	stagger_force: float = 30.0,
	launch_force: float = 0.0
) -> void:
	if not alive:
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
	queue_free()


func _die() -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	emit_signal("died", self, reward, kind == Kind.BOSS)
	queue_free()


func _configure_kind() -> void:
	match kind:
		Kind.MELEE:
			health = 23500
			reward = 7.0
			move_speed = 5.0
		Kind.RANGED:
			health = 20500
			reward = 8.0
			move_speed = 3.7
		Kind.ELITE:
			health = 47000
			reward = 13.0
			move_speed = 5.4
		Kind.BOSS:
			health = 148000
			reward = 60.0
			move_speed = 3.35
	maximum_health = health


func _build_body() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.75 if kind == Kind.BOSS else 0.46
	shape.height = 3.7 if kind == Kind.BOSS else 1.85
	collision.shape = shape
	collision.position.y = 1.85 if kind == Kind.BOSS else 0.92
	add_child(collision)

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
			instance.scale = Vector3.ONE * 2.5
		else:
			instance.scale = Vector3.ONE * 1.35
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

	if kind == Kind.RANGED:
		_add_role_mark(Vector3(0.0, 1.35, 0.23), Color(0.61, 0.39, 0.18))
	elif kind == Kind.ELITE:
		_add_role_mark(Vector3(0.0, 1.7, 0.25), Color(0.70, 0.66, 0.49))
	elif kind == Kind.BOSS:
		_add_role_mark(Vector3(0.0, 3.15, 0.55), Color(0.75, 0.57, 0.31), 0.42)


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


func _update_visual(distance: float) -> void:
	if not is_instance_valid(visual_root):
		return
	var bob_scale := 0.025 if kind != Kind.BOSS else 0.06
	visual_root.position = Vector3(
		hit_lean.x,
		sin(visual_time * (4.0 if kind != Kind.BOSS else 2.0)) * bob_scale - hit_squash * 0.11,
		hit_lean.z
	)
	visual_root.scale = Vector3(
		1.0 + hit_squash * 0.14,
		1.0 - hit_squash * 0.20,
		1.0 + hit_squash * 0.14
	)
	var telegraph := windup > 0.0
	for material in body_materials:
		var base := _kind_color()
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

	if distance > 28.0:
		velocity.x *= 1.01
		velocity.z *= 1.01
