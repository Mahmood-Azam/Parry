extends Node3D
## Collision is swept along each physics step, including the parry volume.
## Reflection uses the player model's facing at the instant of the parry.
const ORB := preload("res://mage_orb_visual.gd")
const EXPLOSION := preload("res://fireball_explosion.gd")
const FX := preload("res://combat_fx.gd")
var direction := Vector3.FORWARD
var speed := 7.0
var damage := 18.0
var lifetime := 6.0
var explosion_damage := 75.0
var explosion_radius := 3.6
var reflected := false
var finished := false
var age := 0.0
var caster: WeakRef
var source_player: WeakRef
var visual: Node3D
var sphere := SphereShape3D.new()
var hit_targets: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("mage_projectile")
	direction = direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD
	sphere.radius = 0.24
	visual = ORB.new()
	add_child(visual)

func _physics_process(delta: float) -> void:
	if finished:
		return
	age += delta
	if age >= lifetime:
		_detonate() if reflected else _dissipate()
		return
	var start := global_position
	var motion := direction * speed * delta
	var world_fraction := _world_fraction(start, motion)
	var target: Node3D
	var target_fraction := INF
	if reflected:
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(enemy) or not enemy is Node3D or enemy.get("is_dead") == true:
				continue
			var contact := _sphere_contact(start, motion, enemy.global_position + Vector3.UP * 0.95, 0.65)
			if contact < target_fraction:
				target_fraction = contact
				target = enemy
	else:
		for group in ["player", "shadow_decoy"]:
			for candidate in get_tree().get_nodes_in_group(group):
				if not is_instance_valid(candidate) or not candidate is Node3D or candidate.get("is_alive") == false:
					continue
				var radius := 0.64
				if candidate.get("is_parrying") == true and candidate.call("is_facing_attack", self, _attack_data()):
					radius = minf(float(candidate.get("parry_hitbox_radius")), 1.5)
				var contact := _sphere_contact(start, motion, candidate.global_position + Vector3.UP * 1.0, radius)
				if contact < target_fraction:
					target_fraction = contact
					target = candidate
	if target != null and target_fraction < world_fraction:
		global_position = start + motion * target_fraction
		if reflected:
			_detonate()
		else:
			target.call("take_damage", damage, self, "magic", _attack_data())
			# The player's normal damage reception invokes on_parried synchronously.
			if not reflected:
				_dissipate()
		return
	if world_fraction <= 1.0:
		global_position = start + motion * maxf(world_fraction - 0.01, 0.0)
		_detonate() if reflected else _dissipate()
		return
	global_position += motion

func _attack_data() -> Dictionary:
	return {"attack_name": "Shadow Orb", "direction": direction, "origin": global_position, "projectile": true}

func on_parried(player: Node3D, is_perfect: bool) -> void:
	if reflected or finished:
		return
	reflected = true
	source_player = weakref(player)
	var facing: Vector3 = player.character.global_basis.z
	facing.y = 0.0
	direction = facing.normalized() if facing.length_squared() > 0.001 else Vector3.FORWARD
	speed = 14.0
	lifetime = 1.65
	age = 0.0
	explosion_damage = 90.0 if is_perfect else 75.0
	# Keep the actual contact point: teleporting out of the guard could skip a wall.
	visual.set_fiery(true)
	visual.scale = Vector3.ONE * 1.25
	FX.ring(get_parent(), global_position, Color(1.0, 0.55, 0.08), 1.0, direction)
	player.call("_show_combat_feedback", "FIREBALL RETURN", Color(1.0, 0.55, 0.1))

func _world_fraction(start: Vector3, motion: Vector3) -> float:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = motion
	query.collision_mask = 1 # Level geometry only; actors use swept contacts above.
	query.collide_with_areas = false
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return 0.0
	var fractions := space.cast_motion(query)
	return fractions[0] if fractions.size() == 2 and fractions[0] < 1.0 else INF

func _sphere_contact(start: Vector3, motion: Vector3, center: Vector3, radius: float) -> float:
	var offset := start - center
	var c := offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var a := motion.length_squared()
	if a < 0.000001:
		return INF
	var b := offset.dot(motion)
	var discriminant := b * b - a * c
	if discriminant < 0.0:
		return INF
	var fraction := (-b - sqrt(discriminant)) / a
	return fraction if fraction >= 0.0 and fraction <= 1.0 else INF

func _detonate() -> void:
	if finished:
		return
	finished = true
	var effect := EXPLOSION.new()
	effect.position = global_position
	effect.radius = explosion_radius
	get_tree().current_scene.add_child(effect)
	var source: Node = source_player.get_ref() if source_player != null else null
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or not enemy is Node3D or enemy.get("is_dead") == true:
			continue
		var center: Vector3 = enemy.global_position + Vector3.UP * 0.95
		var distance := global_position.distance_to(center)
		if distance > explosion_radius:
			continue
		# Blast cannot pass through walls or sealed doors.
		var ray := PhysicsRayQueryParameters3D.create(global_position, center, 1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		hit_targets[enemy.get_instance_id()] = true
		var falloff := lerpf(1.0, 0.4, clampf(distance / explosion_radius, 0.0, 1.0))
		enemy.call("take_damage", explosion_damage * falloff, source)
		if enemy.get("is_dead") == true:
			continue
		if enemy.has_method("apply_burn"):
			enemy.call("apply_burn", 3.0, 6.0, 0.85, source)
		if enemy.has_method("apply_stun"):
			enemy.call("apply_stun", 0.7)
	queue_free()

func _dissipate() -> void:
	if finished:
		return
	finished = true
	FX.burst(get_tree().current_scene, global_position, Color(0.65, 0.15, 1), 20, 0.5)
	queue_free()
