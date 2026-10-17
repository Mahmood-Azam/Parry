extends CharacterBody3D
const PROJECTILE := preload("res://mage_projectile.gd")
const ORB := preload("res://mage_orb_visual.gd")
const POSE := preload("res://assets/enemies/mage/mage_pose.gd")
const BURN := preload("res://enemy_burn.gd")
const FX := preload("res://combat_fx.gd")

signal health_changed(current: float, maximum: float)
signal died()
signal projectile_fired(projectile: Node3D)

@export var max_health := 85.0
@export var attack_damage := 18.0
@export var attack_range := 13.0
@export var attack_cooldown := 2.8
@export var windup_duration := 0.85
@export var move_speed := 1.8
@export var preferred_distance := 5.5
var attack_timer := 0.9
var current_health := 85.0
var is_dead := false
var is_boss := false
var is_attacking := false
var stun_remaining := 0.0
var windup_elapsed := 0.0
var recovery_remaining := 0.0
var burn_effect: Node3D
var target: Node3D
var cast_target: WeakRef
var player: Node3D
var orb: Node3D
var cast_label: Label3D
var health_bar: ProgressBar
var health_layer: CanvasLayer
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@onready var model: Node3D = $MageModel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("enemy")
	add_to_group("mage")
	current_health = max_health
	player = get_node_or_null("../Player")
	for animation in model.find_children("*", "AnimationPlayer", true, false):
		animation.stop()
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if rig != null:
		var pose := POSE.new()
		pose.controller = self
		rig.add_child(pose)
	orb = ORB.new()
	orb.name = "CastingOrb"
	orb.position = Vector3(0, 1.38, 0.66)
	add_child(orb)
	orb.hide()
	cast_label = Label3D.new()
	cast_label.position = Vector3(0, 2.5, 0)
	cast_label.text = "SHADOWKIN MAGE"
	cast_label.font_size = 28
	cast_label.pixel_size = 0.003
	cast_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cast_label.modulate = Color(0.85, 0.5, 1.0)
	add_child(cast_label)
	_setup_health_bar()

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	attack_timer = maxf(attack_timer - delta, 0.0)
	recovery_remaining = maxf(recovery_remaining - delta, 0.0)
	stun_remaining = maxf(stun_remaining - delta, 0.0)
	target = _preferred_target()
	var movement := Vector3.ZERO
	if stun_remaining <= 0.0 and is_instance_valid(target):
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance > 0.01:
			rotation.y = rotate_toward(rotation.y, atan2(to_target.x, to_target.z), delta * 4.0)
		if is_attacking:
			# A dash decoy can distract the caster during windup. Flight itself
			# still uses a single fixed direction chosen on release.
			cast_target = weakref(target)
			windup_elapsed += delta
			var progress := clampf(windup_elapsed / windup_duration, 0.0, 1.0)
			orb.scale = Vector3.ONE * lerpf(0.15, 1.0, smoothstep(0.0, 1.0, progress))
			if windup_elapsed >= windup_duration:
				_release_projectile()
		elif recovery_remaining <= 0.0:
			var clear := _has_line_of_sight(target)
			if distance <= attack_range and clear and attack_timer <= 0.0:
				_begin_cast(target)
			elif distance > preferred_distance or not clear:
				movement = to_target.normalized() * move_speed
			elif distance < 2.5:
				movement = -to_target.normalized() * move_speed * 0.5
	elif is_attacking:
		_cancel_cast()
	velocity.x = move_toward(velocity.x, movement.x, delta * 7.0)
	velocity.z = move_toward(velocity.z, movement.z, delta * 7.0)
	velocity.y = -0.1 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()

func _preferred_target() -> Node3D:
	var newest: Node3D = null
	var youngest := INF
	for decoy in get_tree().get_nodes_in_group("shadow_decoy"):
		if not is_instance_valid(decoy) or global_position.distance_to(decoy.global_position) > attack_range:
			continue
		var age: float = decoy.get_decoy_priority()
		if age < youngest:
			youngest = age
			newest = decoy
	if newest != null:
		return newest
	return player if is_instance_valid(player) and player.get("is_alive") != false else null

func _has_line_of_sight(candidate: Node3D) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.38, candidate.global_position + Vector3.UP, 1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _begin_cast(candidate: Node3D) -> void:
	is_attacking = true
	windup_elapsed = 0.0
	cast_target = weakref(candidate)
	orb.scale = Vector3.ONE * 0.15
	orb.show()
	cast_label.text = "DARK ORB — PARRY"
	cast_label.modulate = Color(1.0, 0.55, 1.0)

func _release_projectile() -> void:
	var victim: Node3D = cast_target.get_ref() if cast_target != null else null
	var origin := orb.global_position
	var aim := victim.global_position + Vector3.UP if is_instance_valid(victim) else origin + global_basis.z * 8.0
	var projectile := PROJECTILE.new()
	projectile.name = "MageDarkOrb"
	projectile.direction = (aim - origin).normalized()
	projectile.damage = attack_damage
	projectile.caster = weakref(self)
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin
	projectile_fired.emit(projectile)
	FX.ring(get_tree().current_scene, origin, Color(0.7, 0.15, 1, 0.8), 0.65, projectile.direction)
	_cancel_cast()
	attack_timer = attack_cooldown
	recovery_remaining = 0.45

func _cancel_cast() -> void:
	is_attacking = false
	orb.hide()
	cast_label.text = "SHADOWKIN MAGE"
	cast_label.modulate = Color(0.85, 0.5, 1.0)

func take_damage(amount: float, _attacker: Node = null) -> bool:
	if is_dead or amount <= 0.0:
		return false
	current_health = maxf(current_health - amount, 0.0)
	preload("res://combat_impact.gd").hit(self, _attacker, amount)
	health_bar.value = current_health
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		_die()
	return true

func apply_stun(duration: float = 1.0) -> void:
	if is_dead:
		return
	stun_remaining = maxf(stun_remaining, duration)
	attack_timer = maxf(attack_timer, duration + 0.5)
	_cancel_cast()
	FX.ring(get_tree().current_scene, global_position + Vector3.UP * 1.6, Color(0.6, 0.75, 1.0), 0.6)

func apply_burn(duration: float = 3.0, dps: float = 6.0, heat: float = 0.5, attacker: Node = null) -> void:
	if is_dead or duration <= 0.0 or dps <= 0.0:
		return
	if not is_instance_valid(burn_effect):
		burn_effect = BURN.new()
		burn_effect.name = "BurnStatus"
		add_child(burn_effect)
	burn_effect.ignite(duration, dps, heat, attacker)

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	_cancel_cast()
	remove_from_group("enemy")
	remove_from_group("mage")
	collision_layer = 0
	collision_mask = 0
	$CollisionShape3D.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	health_bar.hide()
	cast_label.hide()
	FX.burst(get_tree().current_scene, global_position + Vector3.UP, Color(0.6, 0.15, 0.9), 65, 0.7, true)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var tween := create_tween()
		tween.tween_property(mesh, "transparency", 1.0, 1.0)
	var sink := create_tween()
	sink.tween_property(model, "position:y", -0.35, 1.2)
	died.emit()
	get_tree().create_timer(1.4, false).timeout.connect(queue_free)

func _setup_health_bar() -> void:
	health_layer = CanvasLayer.new()
	add_child(health_layer)
	health_bar = ProgressBar.new()
	health_bar.show_percentage = false
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.size = Vector2(105, 10)
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.6, 0.1, 0.8)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.04, 0.02, 0.07, 0.9)
	health_bar.add_theme_stylebox_override("fill", fill)
	health_bar.add_theme_stylebox_override("background", background)
	health_layer.add_child(health_bar)

func _process(_delta: float) -> void:
	if is_dead:
		return
	var camera := get_viewport().get_camera_3d()
	var center := global_position + Vector3.UP * 2.28
	health_bar.visible = camera != null and not camera.is_position_behind(center) and camera.global_position.distance_to(center) < 22.0
	if health_bar.visible:
		health_bar.position = camera.unproject_position(center) - Vector2(52.5, 0)
