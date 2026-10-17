extends CharacterBody3D
const BURN_EFFECT := preload("res://enemy_burn.gd")
var burn_effect: Node3D

var DEATH_SCENE: PackedScene = load("res://assets/enemies/animations/Falling Back Death.fbx")

@export var move_speed: float = 2.6
@export var movement_acceleration: float = 10.0
@export var stopping_friction: float = 14.0
@export var attack_range: float = 1.45
@export var attack_cooldown: float = 2.15
@export var turn_speed: float = 8.0
@export var attack_alignment_angle: float = 20.0
@export var attack_damage: float = 15.0
@export_range(0.0, 1.0, 0.01) var attack_hit_time: float = 0.30 ## Animation-normalized contact point for the visible strike.
@export var parry_contact_lead: float = 0.12 ## How early the visible strike can be parried.
@export var parry_contact_linger: float = 0.10 ## How long the contact remains parryable.
@export var attack_hit_range_padding: float = 0.25
@export var default_parry_stun_duration: float = 1.0
@export var attack_animation_speed_scale: float = 0.88
@export var max_health: float = 100.0
@export var health_bar_height: float = 2.2
@export var show_debug_hitboxes: bool = false ## Enable only when debugging combat ranges.
@export var death_dissolve_duration: float = 1.35
@export var is_boss: bool = false
var enraged: bool = false
@export var aggro_range: float = 18.0
@export var leash_range: float = 28.0
@export var three_hit_combo: bool = true
@export_range(0.0, 1.0) var triple_attack_chance := 0.45
@export var close_attack_recovery := 0.90 ## Breathing room between patterns; strike cadence stays unchanged.
var combo_length := 1
var awareness := preload("res://enemy_awareness.gd").new()
var combo_step := 0
var combo_parries := 0
var last_parried_step := -1
var combo_victim: WeakRef
var combo_hint: HBoxContainer

@onready var player_target: Node3D = get_node_or_null("../Player") as Node3D
@onready var animation_player: AnimationPlayer = $SkeletonModel/AnimationPlayer
@onready var skeleton_model: Node3D = $SkeletonModel

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var attack_timer: float = 0.0
var is_attacking: bool = false
var attack_has_hit: bool = false
var stun_remaining: float = 0.0
var current_health: float = 100.0
var is_dead: bool = false
var health_bar: ProgressBar
var health_bar_layer: CanvasLayer
var current_animation: StringName = &""
var target: Node3D
var debug_body_mesh: MeshInstance3D
var debug_attack_mesh: MeshInstance3D
var debug_attack_ring: MeshInstance3D
var debug_state_label: Label3D
var debug_body_material: StandardMaterial3D
var debug_attack_material: StandardMaterial3D
var attack_sound: AudioStreamPlayer
var boss_aura: Node3D
var attack_audio_stream: AudioStream = preload("res://assets/audio/Attack.mp3")
var stun_pose_elapsed: float = 0.0
var stun_pose_base_rotation: Vector3
var stun_pose_base_position: Vector3

signal health_changed(current: float, maximum: float)
signal died()

func _ready() -> void:
	awareness.home = global_position
	awareness.aggro_range = aggro_range
	awareness.leash_range = leash_range
	# Derived creatures keep their own attack patterns.
	three_hit_combo = three_hit_combo and not is_boss and get_script().resource_path == "res://assets/enemies/skeleton/skeleton_enemy.gd"
	current_health = max_health
	add_to_group("enemy")
	target = player_target
	stun_pose_base_rotation = skeleton_model.rotation
	stun_pose_base_position = skeleton_model.position
	_setup_attack_audio()
	_setup_debug_hitboxes()
	_setup_health_bar()
	_import_death_animation()
	for animation_name in [&"Lesha_idle", &"Lesha_walk"]:
		if animation_player.has_animation(animation_name):
			animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	animation_player.animation_finished.connect(_on_animation_finished)
	_play(&"Lesha_idle")
	if is_boss:
		boss_aura = preload("res://boss_aura.gd").new() as Node3D
		boss_aura.name = "BossAura"
		boss_aura.call("configure", Color(0.64, 0.28, 1.0), 1.85, 0.82)
		add_child(boss_aura)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if stun_remaining > 0.0:
		stun_remaining = maxf(stun_remaining - delta, 0.0)
		stun_pose_elapsed += delta
		is_attacking = false
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * 8.0 * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		_update_stun_pose()
		_play(&"Lesha_idle")
		move_and_slide()
		if stun_remaining <= 0.0:
			skeleton_model.rotation = stun_pose_base_rotation
			skeleton_model.position = stun_pose_base_position
		return

	if not is_attacking or not is_instance_valid(target):
		target = _get_preferred_target()
	if not is_attacking and not awareness.can_engage(self, target):
		_return_home(delta)
		return
	if target == null or not is_instance_valid(target):
		velocity.x = move_toward(velocity.x, 0.0, stopping_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, stopping_friction * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	attack_timer = maxf(attack_timer - delta, 0.0)
	var target_center := _get_target_center()
	var to_target := target_center - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var facing_target := false
	if distance > 0.05:
		var desired_yaw := atan2(to_target.x, to_target.z)
		if not is_attacking or not attack_has_hit:
			rotation.y = rotate_toward(rotation.y, desired_yaw, turn_speed * delta)
		facing_target = global_transform.basis.z.dot(to_target.normalized()) >= cos(deg_to_rad(attack_alignment_angle))

	# Once a swing starts, finish the attack animation even if the player dashes
	# out of range. Only an idle enemy should abandon pursuit for distance.
	if distance > attack_range and not is_attacking:
		is_attacking = false
		var direction := awareness.pursuit_direction(self, to_target.normalized())
		velocity.x = move_toward(velocity.x, direction.x * move_speed, movement_acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, movement_acceleration * delta)
		_play(&"Lesha_walk")
	else:
		velocity.x = move_toward(velocity.x, 0.0, stopping_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, stopping_friction * delta)
		if is_attacking:
			_process_attack_hit()
			# Trim the long recovery tail, but never skip the visible contact.
			if three_hit_combo and animation_player.current_animation_position >= animation_player.current_animation_length * 0.78:
				_finish_combo_strike()
		if not is_attacking and attack_timer <= 0.0 and facing_target and _target_in_sight():
			_begin_combo()
		elif not is_attacking:
			_play(&"Lesha_idle")

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()

func _play(animation_name: StringName, restart: bool = false) -> void:
	if not animation_player.has_animation(animation_name):
		return
	if restart or current_animation != animation_name:
		current_animation = animation_name
		animation_player.play(animation_name, 0.1)

func _begin_combo() -> void:
	combo_step = 0
	combo_parries = 0
	last_parried_step = -1
	combo_victim = null
	combo_length = 3 if three_hit_combo and randf() < triple_attack_chance else 1
	_start_strike()

func _start_strike() -> void:
	is_attacking = true
	if is_instance_valid(boss_aura):
		boss_aura.call("charge")
	attack_has_hit = false
	attack_timer = attack_cooldown
	var clip := animation_player.get_animation(&"Lesha_attack_1")
	# Contact-to-contact cadence ~0.5s, first strike has a readable windup.
	animation_player.speed_scale = clip.length / (0.88 if combo_step == 0 else 0.64) if three_hit_combo else attack_animation_speed_scale
	if attack_sound != null:
		attack_sound.play()
	_play(&"Lesha_attack_1", true)
	# Playing the same clip again does not rewind an already-playing animation.
	animation_player.seek(0.0, true)

func _finish_combo_strike() -> void:
	if not is_attacking:
		return
	if three_hit_combo and combo_step < combo_length - 1:
		combo_step += 1
		_start_strike()
	else:
		is_attacking = false
		attack_has_hit = false
		animation_player.speed_scale = 1.0
		attack_timer = close_attack_recovery if three_hit_combo else attack_cooldown
		current_animation = &""
		_play(&"Lesha_idle")

## Returns true when the combo owns the parry response (no full stun mid-chain).
func on_parried(defender: Node, _perfect: bool) -> bool:
	if not three_hit_combo or combo_length != 3 or is_dead or not is_attacking:
		return false
	if last_parried_step == combo_step:
		return true
	attack_has_hit = true
	last_parried_step = combo_step
	if combo_victim != null and combo_victim.get_ref() != defender:
		combo_parries = 0
	combo_victim = weakref(defender)
	combo_parries += 1
	_spawn_stun_effect()
	if combo_step == 2 and combo_parries == 3:
		apply_burn(1.4, 1.0, 1.0, defender)
		take_damage(current_health, defender)
		if defender.has_method("_show_combat_feedback"):
			defender.call("_show_combat_feedback", "TRIPLE PARRY — INCINERATED", Color(1, 0.55, 0.12))
	return true

func _return_home(delta: float) -> void:
	var direction := awareness.return_direction(self)
	velocity.x = move_toward(velocity.x, direction.x * move_speed, movement_acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * move_speed, movement_acceleration * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	animation_player.speed_scale = 1.0
	if direction.length_squared() > 0.01:
		rotation.y = rotate_toward(rotation.y, atan2(direction.x, direction.z), turn_speed * delta)
		_play(&"Lesha_walk")
	else:
		_play(&"Lesha_idle")
	move_and_slide()

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"FallingDeath":
		return
	if animation_name == &"Lesha_attack_1":
		if three_hit_combo:
			_finish_combo_strike()
			return
		is_attacking = false
		attack_has_hit = false
		animation_player.speed_scale = 1.0
		current_animation = &""


func apply_burn(duration: float = 3.0, dps: float = 6.0, heat: float = 0.5, attacker: Node = null) -> void:
	if is_dead or duration <= 0.0 or dps <= 0.0:
		return
	if not is_instance_valid(burn_effect):
		burn_effect = BURN_EFFECT.new()
		burn_effect.name = "BurnStatus"
		add_child(burn_effect)
	burn_effect.ignite(duration, dps, heat, attacker)


func apply_stun(duration: float = -1.0) -> void:
	if is_dead:
		return
	var requested_duration := default_parry_stun_duration if duration < 0.0 else duration
	stun_remaining = maxf(stun_remaining, requested_duration)
	stun_pose_elapsed = 0.0
	# Repeated hits during a stun must not turn the temporary sway into the
	# next resting pose; that accumulated tilt made the Ash Warden lean sideways.
	is_attacking = false
	attack_has_hit = true
	if three_hit_combo:
		# The stun already provides a punish window; do not add another long wait.
		attack_timer = minf(attack_timer, close_attack_recovery)
	velocity.x = 0.0
	velocity.z = 0.0
	animation_player.speed_scale = 1.0
	_play(&"Lesha_idle", true)
	_spawn_stun_effect()


func _spawn_stun_effect() -> void:
	var effect := Node3D.new()
	effect.name = "ParryStunEffect"
	get_tree().current_scene.add_child(effect)
	effect.global_position = global_position + Vector3.UP * 1.35

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.20
	torus.outer_radius = 0.28
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.4, 0.85, 1.0, 0.9)
	material.emission_enabled = true
	material.emission = Color(0.2, 0.6, 1.0)
	material.emission_energy_multiplier = 3.0
	ring.material_override = material
	effect.add_child(ring)

	var light := OmniLight3D.new()
	light.light_color = Color(0.25, 0.65, 1.0)
	light.light_energy = 4.0
	light.omni_range = 2.4
	effect.add_child(light)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(effect, "scale", Vector3.ONE * 2.4, 0.28).set_trans(Tween.TRANS_BACK)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.28)
	tween.tween_property(light, "light_energy", 0.0, 0.28)
	get_tree().create_timer(0.38).timeout.connect(effect.queue_free)


func _update_stun_pose() -> void:
	if skeleton_model == null:
		return
	var shake := sin(stun_pose_elapsed * 42.0) * 0.10
	var sway := sin(stun_pose_elapsed * 19.0) * 0.16
	var hands_up_recoil := sin(minf(stun_pose_elapsed * 8.0, PI * 0.5)) * 0.12
	skeleton_model.rotation = stun_pose_base_rotation + Vector3(-hands_up_recoil + shake * 0.25, sway, shake)
	skeleton_model.position = stun_pose_base_position + Vector3(shake * 0.06, abs(sin(stun_pose_elapsed * 24.0)) * 0.045, 0.0)


## The player uses this instead of relying only on the damage callback. This
## keeps parry timing attached to the attack animation while making the clash
## reliable even when physics and animation advance on different frames.
func is_attack_in_parry_window() -> bool:
	if not is_attacking or attack_has_hit or current_animation != &"Lesha_attack_1":
		return false
	if not _target_in_sight():
		return false
	var attack_animation := animation_player.get_animation(&"Lesha_attack_1")
	if attack_animation == null or attack_animation.length <= 0.0:
		return false
	var normalized_position := animation_player.current_animation_position / attack_animation.length
	return normalized_position >= attack_hit_time - parry_contact_lead and normalized_position <= attack_hit_time + parry_contact_linger


func take_damage(amount: float, _attacker: Node = null) -> bool:
	if is_dead or current_health <= 0.0 or amount <= 0.0:
		return false
	current_health = clampf(current_health - amount, 0.0, max_health)
	preload("res://combat_impact.gd").hit(self, _attacker, amount)
	if is_boss and not enraged and current_health > 0.0 and current_health <= max_health * 0.5:
		enraged = true
		if is_instance_valid(boss_aura):
			boss_aura.call("power_surge")
		move_speed *= 1.2
		attack_cooldown *= 0.72
		attack_animation_speed_scale *= 1.20
		attack_damage *= 1.2
		_spawn_stun_effect()
	if health_bar != null:
		health_bar.value = current_health
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		_die()
	return true


func _import_death_animation() -> void:
	if DEATH_SCENE == null or animation_player == null:
		return
	var source_root := DEATH_SCENE.instantiate()
	var source_player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player == null or not source_player.has_animation("mixamo_com"):
		source_root.queue_free()
		return
	var death_animation: Animation = source_player.get_animation("mixamo_com").duplicate(true)
	var rig := skeleton_model.find_child("Skeleton3D", true, false) as Skeleton3D
	for track_index in range(death_animation.get_track_count() - 1, -1, -1):
		var track_path := String(death_animation.track_get_path(track_index))
		var separator := track_path.find(":")
		if separator < 0:
			continue
		var bone_name := track_path.substr(separator + 1).replace("mixamorig:", "mixamorig_")
		if rig == null or rig.find_bone(bone_name) < 0:
			death_animation.remove_track(track_index)
			continue
		death_animation.track_set_path(track_index, NodePath("Skeleton3D:" + bone_name))
	if death_animation.get_track_count() == 0:
		source_root.queue_free()
		return # Incompatible rigs use the existing collapse/dissolve fallback.
	var library := animation_player.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		animation_player.add_animation_library("", library)
	if animation_player.has_animation("FallingDeath"):
		library.remove_animation("FallingDeath")
	library.add_animation("FallingDeath", death_animation)
	source_root.queue_free()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	if is_instance_valid(boss_aura):
		boss_aura.call("fade_out")
	remove_from_group("enemy")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	stun_remaining = 0.0
	is_attacking = false
	attack_has_hit = true
	if health_bar != null:
		health_bar.visible = false
	if animation_player.has_animation("FallingDeath"):
		animation_player.speed_scale = 1.0
		_play(&"FallingDeath", true)
	else:
		var fall_tween := create_tween()
		fall_tween.set_parallel(true)
		fall_tween.tween_property(skeleton_model, "rotation", skeleton_model.rotation + Vector3(-PI * 0.5, 0.0, 0.0), 0.7).set_trans(Tween.TRANS_QUAD)
		fall_tween.tween_property(skeleton_model, "position:y", skeleton_model.position.y - 0.45, 0.7)
	_spawn_death_dust()
	for mesh in skeleton_model.find_children("*", "MeshInstance3D", true, false):
		var visual := mesh as MeshInstance3D
		visual.transparency = 0.0
		var dissolve := create_tween()
		dissolve.tween_property(visual, "transparency", 1.0, death_dissolve_duration).set_delay(0.25)
	died.emit()
	get_tree().create_timer(death_dissolve_duration + 0.35).timeout.connect(queue_free)


func _spawn_death_dust() -> void:
	var dust := GPUParticles3D.new()
	dust.name = "DeathDust"
	dust.amount = 90
	dust.lifetime = 1.25
	dust.one_shot = true
	dust.explosiveness = 0.85
	dust.randomness = 0.55
	dust.position = global_position + Vector3.UP * 0.8
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(0.38, 0.8, 0.38)
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = 180.0
	process_material.initial_velocity_min = 0.35
	process_material.initial_velocity_max = 1.8
	process_material.gravity = Vector3(0.0, -2.2, 0.0)
	process_material.scale_min = 0.45
	process_material.scale_max = 1.2
	dust.process_material = process_material
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.035
	dust_mesh.height = 0.07
	var dust_material := StandardMaterial3D.new()
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.albedo_color = Color(0.12, 0.1, 0.14, 0.8)
	dust_material.emission_enabled = true
	dust_material.emission = Color(0.2, 0.08, 0.32, 1.0)
	dust_material.emission_energy_multiplier = 1.4
	dust_mesh.material = dust_material
	dust.draw_pass_1 = dust_mesh
	get_tree().current_scene.add_child(dust)
	dust.emitting = true
	get_tree().create_timer(1.8).timeout.connect(dust.queue_free)


func _setup_health_bar() -> void:
	health_bar_layer = CanvasLayer.new()
	health_bar_layer.name = "EnemyHealthBarLayer"
	add_child(health_bar_layer)
	health_bar = preload("res://combat_health_bar.gd").new()
	health_bar.name = "EnemyHealthBar"
	health_bar.show_percentage = false
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.bar_height = 4.0
	health_bar.size = Vector2(48.0, 4.0)
	health_bar_layer.add_child(health_bar)
	if three_hit_combo:
		combo_hint = HBoxContainer.new()
		combo_hint.position = Vector2(16.5, 7)
		combo_hint.add_theme_constant_override("separation", 3)
		combo_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for index in 3:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(3, 2)
			pip.color = Color(0.8, 0.49, 0.19, 0.7)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			combo_hint.add_child(pip)
		health_bar.add_child(combo_hint)


func _setup_attack_audio() -> void:
	# Use a global player so the cue is always audible while debugging combat.
	# The enemy's world-space hitbox remains separate from audio attenuation.
	attack_sound = AudioStreamPlayer.new()
	attack_sound.name = "AttackSound"
	attack_sound.stream = attack_audio_stream
	attack_sound.volume_db = 2.0
	add_child(attack_sound)


func _process(_delta: float) -> void:
	if is_dead:
		if health_bar != null:
			health_bar.visible = false
		if debug_body_mesh != null:
			debug_body_mesh.visible = false
		if debug_attack_mesh != null:
			debug_attack_mesh.visible = false
		if debug_attack_ring != null:
			debug_attack_ring.visible = false
		if debug_state_label != null:
			debug_state_label.visible = false
		return
	_update_debug_hitboxes()
	if combo_hint != null:
		combo_hint.visible = is_attacking and combo_length == 3
		for index in 3:
			combo_hint.get_child(index).color = Color(1, 0.85, 0.3) if index < combo_parries else Color(0.8, 0.49, 0.19, 0.7)
	if health_bar == null:
		return
	if is_boss:
		health_bar.hide() # The encounter director owns the persistent boss HUD.
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		health_bar.visible = false
		return
	var screen_position := camera.unproject_position(global_position + Vector3.UP * health_bar_height)
	health_bar.position = screen_position - Vector2(24.0, 2.0)
	health_bar.visible = not camera.is_position_behind(global_position) and camera.is_position_in_frustum(global_position) and camera.global_position.distance_to(global_position) < 25.0


func _setup_debug_hitboxes() -> void:
	if not show_debug_hitboxes:
		return

	# Body hitbox: matches SkeletonEnemy/CollisionShape3D.
	debug_body_mesh = MeshInstance3D.new()
	debug_body_mesh.name = "DEBUG_BodyHitbox"
	var body_capsule := CapsuleMesh.new()
	body_capsule.radius = 0.35
	body_capsule.height = 1.7
	debug_body_mesh.mesh = body_capsule
	debug_body_mesh.position = Vector3(0.0, 0.85, 0.0)
	debug_body_material = _make_debug_material(Color(0.15, 0.55, 1.0, 0.18))
	debug_body_mesh.material_override = debug_body_material
	debug_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(debug_body_mesh)

	# Attack hitbox: the same radius used by _process_attack_hit().
	debug_attack_mesh = MeshInstance3D.new()
	debug_attack_mesh.name = "DEBUG_AttackHitbox"
	var attack_sphere := SphereMesh.new()
	attack_sphere.radius = attack_range + attack_hit_range_padding
	attack_sphere.height = (attack_range + attack_hit_range_padding) * 2.0
	debug_attack_mesh.mesh = attack_sphere
	debug_attack_material = _make_debug_material(Color(1.0, 0.18, 0.08, 0.07))
	debug_attack_mesh.material_override = debug_attack_material
	debug_attack_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(debug_attack_mesh)

	# Ground ring makes the range readable even when the translucent sphere is
	# hidden inside the character model.
	debug_attack_ring = MeshInstance3D.new()
	debug_attack_ring.name = "DEBUG_AttackRange"
	var ring := TorusMesh.new()
	ring.inner_radius = attack_range + attack_hit_range_padding - 0.035
	ring.outer_radius = attack_range + attack_hit_range_padding + 0.035
	debug_attack_ring.mesh = ring
	debug_attack_ring.position = Vector3(0.0, 0.04, 0.0)
	debug_attack_ring.material_override = debug_attack_material
	debug_attack_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(debug_attack_ring)

	debug_state_label = Label3D.new()
	debug_state_label.name = "DEBUG_AttackState"
	debug_state_label.position = Vector3(0.0, 2.7, 0.0)
	debug_state_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_state_label.font_size = 32
	debug_state_label.outline_size = 8
	debug_state_label.modulate = Color.WHITE
	add_child(debug_state_label)


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 1.5
	material.no_depth_test = true
	return material


func _update_debug_hitboxes() -> void:
	if not show_debug_hitboxes or debug_attack_material == null:
		return
	var parryable := is_attack_in_parry_window()
	var attack_progress := 0.0
	var attack_animation := animation_player.get_animation(&"Lesha_attack_1")
	if is_attacking and attack_animation != null and attack_animation.length > 0.0:
		attack_progress = clampf(animation_player.current_animation_position / attack_animation.length, 0.0, 1.0)
	var attack_color := Color(0.2, 1.0, 0.3, 0.28) if parryable else Color(1.0, 0.45, 0.08, 0.13) if is_attacking else Color(1.0, 0.18, 0.08, 0.07)
	debug_attack_material.albedo_color = attack_color
	debug_attack_material.emission = Color(attack_color.r, attack_color.g, attack_color.b, 1.0)
	if debug_state_label != null:
		if parryable:
			debug_state_label.text = "PARRY NOW %.0f%%" % (attack_progress * 100.0)
			debug_state_label.modulate = Color(0.25, 1.0, 0.35, 1.0)
		elif is_attacking:
			debug_state_label.text = "ATTACK %.0f%%" % (attack_progress * 100.0)
			debug_state_label.modulate = Color(1.0, 0.65, 0.15, 1.0)
		else:
			debug_state_label.text = "ATTACK RANGE"
			debug_state_label.modulate = Color(1.0, 0.25, 0.15, 0.85)


func _process_attack_hit() -> void:
	if attack_has_hit or target == null or not is_instance_valid(target):
		return
	if animation_player.current_animation != &"Lesha_attack_1":
		return
	var attack_animation := animation_player.get_animation(&"Lesha_attack_1")
	if attack_animation == null or attack_animation.length <= 0.0:
		return
	if animation_player.current_animation_position < attack_animation.length * attack_hit_time:
		return
	attack_has_hit = true
	if is_instance_valid(boss_aura):
		boss_aura.call("attack_splash")
	var center := _get_target_center()
	var offset := center - global_position
	var distance := Vector2(offset.x, offset.z).length()
	if distance > attack_range + attack_hit_range_padding or absf(offset.y - 0.9) > 1.4:
		return
	var sight := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, center, 1)
	if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
		return
	if target.has_method("take_damage"):
		target.call("take_damage", attack_damage, self, "melee", {
			"attack_name": "Skeleton Slash",
			"direction": global_position.direction_to(_get_target_center())
		})


func _get_target_center() -> Vector3:
	if target == null or not is_instance_valid(target):
		return global_position
	var target_collider := target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if target_collider != null:
		return target.to_global(target_collider.position)
	return target.global_position + Vector3.UP * 0.9

func _target_in_sight() -> bool:
	if not is_instance_valid(target):
		return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, _get_target_center(), 1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _get_preferred_target() -> Node3D:
	var newest_decoy: Node3D = null
	var newest_priority := -INF
	for candidate in get_tree().get_nodes_in_group("shadow_decoy"):
		if not candidate is Node3D or not is_instance_valid(candidate):
			continue
		var decoy := candidate as Node3D
		var priority := float(decoy.call("get_decoy_priority")) if decoy.has_method("get_decoy_priority") else 0.0
		if newest_decoy == null or priority > newest_priority:
			newest_decoy = decoy
			newest_priority = priority
	return newest_decoy if newest_decoy != null else player_target
