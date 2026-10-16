class_name Player
extends CharacterBody3D

## Signals for external systems (Dev 2 Heat/Time, Dev 4 UI)
signal health_changed(current_health: float, max_health: float)
signal damaged(amount: float, attacker: Node)
signal damage_evaded(amount: float, attacker: Node)
signal died()

signal parry_started()
signal parry_success(attacker: Node, is_perfect: bool, attack_data: Dictionary)
signal parry_failed()

signal dash_started(direction: Vector3)
signal dash_finished()
signal attack_pressed()

# --- Movement Configuration ---
@export_group("Movement")
@export var move_speed: float = 6.0
@export var acceleration: float = 34.0               ## Startup acceleration for responsive movement.
@export var friction: float = 40.0                   ## General deceleration.
@export var stopping_friction: float = 65.0          ## High stopping friction to eliminate unwanted sliding.
@export var turn_friction_multiplier: float = 2.4    ## Sharp braking multiplier when reversing directions.
@export var rotation_speed: float = 16.0
@export var gravity: float = 20.0

# --- Health Configuration ---
@export_group("Health")
@export var max_health: float = 100.0

# --- Attack Configuration ---
@export_group("Combat")
@export var attack_duration: float = 0.32            ## Duration of attack swing lock before next action.

# --- Parry Configuration ---
@export_group("Parry")
@export var parry_window: float = 0.35               ## Total duration of parry window in seconds.
@export var perfect_parry_window: float = 0.12       ## First portion of the window that triggers a Perfect Parry.
@export var parry_cooldown: float = 0.45             ## Recovery cooldown incurred when a parry is missed/whiffed.

# --- Shadow Dash Configuration ---
@export_group("Shadow Dash")
@export var dash_speed: float = 16.0
@export var dash_duration: float = 0.22
@export var dash_cooldown: float = 0.90
@export var dash_invulnerability_time: float = 0.22

# --- Camera & Look Configuration ---
@export_group("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var camera_distance: float = 4.5             ## Third-person camera distance behind player.
@export var min_pitch: float = -65.0                 ## Maximum look down angle in degrees.
@export var max_pitch: float = 45.0                  ## Maximum look up angle in degrees.

# --- Node References ---
@onready var visual_root: Node3D = $Visuals
@onready var character_mesh: MeshInstance3D = $Visuals/CharacterMesh
@onready var sword_mesh: MeshInstance3D = $Visuals/SwordMesh
@onready var parry_aura: MeshInstance3D = $Visuals/ParryAura
@onready var clash_sparks: CPUParticles3D = $Visuals/ClashSparks
@onready var clash_light: OmniLight3D = $Visuals/ClashLight
@onready var parry_shockwave: MeshInstance3D = $Visuals/ParryShockwave
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

# --- Runtime States ---
var current_health: float = 100.0
var is_alive: bool = true
var is_invulnerable: bool = false

# Attack state
var is_attacking: bool = false
var attack_timer: float = 0.0
var attack_combo_step: int = 0

# Parry state
var is_parrying: bool = false
var parry_timer: float = 0.0
var parry_cooldown_timer: float = 0.0

# Dash state
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector3 = Vector3.FORWARD

# Camera screen shake
var camera_trauma: float = 0.0

# Visual feedback
var _original_material: StandardMaterial3D
var _hit_flash_timer: float = 0.0


func _ready() -> void:
	current_health = max_health
	emit_signal("health_changed", current_health, max_health)
	
	# Setup mouse capture
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if spring_arm:
		spring_arm.spring_length = camera_distance
		
	if parry_aura:
		parry_aura.visible = false
	if parry_shockwave:
		parry_shockwave.visible = false
	if clash_light:
		clash_light.light_energy = 0.0
		
	# Cache material for hit flash
	if character_mesh and character_mesh.get_surface_override_material(0):
		_original_material = character_mesh.get_surface_override_material(0).duplicate()


func _exit_tree() -> void:
	# Guarantee normal time scale on scene changes
	Engine.time_scale = 1.0


func _unhandled_input(event: InputEvent) -> void:
	# Mouse lock / unlock toggle
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	if not is_alive:
		return

	# Camera rotation
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_handle_camera_rotation(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clamp(camera_distance - 0.35, 2.2, 7.0)
			if spring_arm:
				spring_arm.spring_length = camera_distance
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clamp(camera_distance + 0.35, 2.2, 7.0)
			if spring_arm:
				spring_arm.spring_length = camera_distance

	# Action inputs
	if event.is_action_pressed("parry"):
		try_start_parry()
	elif event.is_action_pressed("dash"):
		try_start_dash()
	elif event.is_action_pressed("attack"):
		try_start_attack()


func _process(delta: float) -> void:
	_process_screen_shake(delta)


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	
	if not is_alive:
		# Apply gravity on death
		if not is_on_floor():
			velocity.y -= gravity * delta
			move_and_slide()
		return

	if is_dashing:
		_process_dash_movement(delta)
	else:
		_process_regular_movement(delta)

	move_and_slide()


# --- Movement Processing ---
func _process_regular_movement(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Get input vector relative to camera
	var input_vector := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		input_vector.y -= 1.0
	if Input.is_action_pressed("move_backward"):
		input_vector.y += 1.0
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1.0
	input_vector = input_vector.normalized()

	# Reduce speed slightly during defensive parry stance or active swing
	var speed_multiplier := 1.0
	if is_parrying:
		speed_multiplier = 0.35
	elif is_attacking:
		speed_multiplier = 0.65

	# Convert 2D input to 3D movement relative to camera yaw
	var cam_yaw: float = camera_pivot.rotation.y
	var move_dir := Vector3.ZERO
	if input_vector.length_squared() > 0.001:
		var rotated := input_vector.rotated(-cam_yaw)
		move_dir = Vector3(rotated.x, 0.0, rotated.y).normalized()

	var target_velocity_xz := move_dir * (move_speed * speed_multiplier)
	var current_velocity_xz := Vector3(velocity.x, 0.0, velocity.z)

	# Precise friction logic: eliminate sliding and ensure sharp braking
	if move_dir.length_squared() > 0.001:
		var accel_rate := acceleration
		# If user suddenly reverses direction, apply sharp turn braking
		if current_velocity_xz.dot(target_velocity_xz) < 0.0:
			accel_rate = acceleration * turn_friction_multiplier
		current_velocity_xz = current_velocity_xz.move_toward(target_velocity_xz, accel_rate * delta)
	else:
		# Released keys: apply strong stopping friction
		current_velocity_xz = current_velocity_xz.move_toward(Vector3.ZERO, stopping_friction * delta)
		# Snap to zero to eliminate ice-skating micro-drifts
		if current_velocity_xz.length_squared() < 0.05:
			current_velocity_xz = Vector3.ZERO

	velocity.x = current_velocity_xz.x
	velocity.z = current_velocity_xz.z

	# Turn mesh smoothly towards moving direction
	if move_dir.length_squared() > 0.01:
		var target_angle := atan2(-move_dir.x, -move_dir.z)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_angle, rotation_speed * delta)


func _process_dash_movement(_delta: float) -> void:
	# Maintain dash velocity in dash direction, keeping current Y
	velocity.x = dash_direction.x * dash_speed
	velocity.z = dash_direction.z * dash_speed


# --- Camera Handling & Screen Shake ---
func _handle_camera_rotation(relative_motion: Vector2) -> void:
	camera_pivot.rotate_y(-relative_motion.x * mouse_sensitivity)
	spring_arm.rotate_x(-relative_motion.y * mouse_sensitivity)
	var pitch_rad := spring_arm.rotation.x
	spring_arm.rotation.x = clamp(pitch_rad, deg_to_rad(min_pitch), deg_to_rad(max_pitch))


func _add_camera_trauma(amount: float) -> void:
	camera_trauma = clamp(camera_trauma + amount, 0.0, 1.0)


func _process_screen_shake(delta: float) -> void:
	if not camera:
		return
	if camera_trauma > 0.0:
		camera_trauma = max(0.0, camera_trauma - delta * 3.5)
		var shake := camera_trauma * camera_trauma * 0.18
		camera.h_offset = randf_range(-shake, shake)
		camera.v_offset = randf_range(-shake, shake)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


# --- Attack Combo Mechanics ---
func try_start_attack() -> bool:
	if not is_alive or is_dashing or is_parrying:
		return false

	is_attacking = true
	attack_timer = attack_duration

	# Alternate 2-hit combo animations
	if anim_player:
		if attack_combo_step == 0:
			anim_player.play("attack_1")
			attack_combo_step = 1
		else:
			anim_player.play("attack_2")
			attack_combo_step = 0

	emit_signal("attack_pressed")
	return true


# --- Parry Mechanics ---
func try_start_parry() -> bool:
	if not is_alive or is_parrying or is_dashing or parry_cooldown_timer > 0.0:
		return false

	is_parrying = true
	parry_timer = 0.0
	is_attacking = false # Cancel swing into parry
	
	if anim_player:
		anim_player.play("parry_stance")
		
	if parry_aura:
		parry_aura.visible = true
	
	emit_signal("parry_started")
	return true


func _end_parry(missed: bool) -> void:
	is_parrying = false
	if parry_aura:
		parry_aura.visible = false
		
	if missed:
		parry_cooldown_timer = parry_cooldown
		if anim_player:
			anim_player.play("RESET")
		emit_signal("parry_failed")
	else:
		parry_cooldown_timer = 0.1


# --- Shadow Dash Mechanics ---
func try_start_dash() -> bool:
	if not is_alive or is_dashing or dash_cooldown_timer > 0.0:
		return false

	if is_parrying:
		_end_parry(false)
	is_attacking = false

	var input_vector := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		input_vector.y -= 1.0
	if Input.is_action_pressed("move_backward"):
		input_vector.y += 1.0
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1.0

	var cam_yaw: float = camera_pivot.rotation.y
	if input_vector.length_squared() > 0.001:
		var rotated := input_vector.normalized().rotated(-cam_yaw)
		dash_direction = Vector3(rotated.x, 0.0, rotated.y).normalized()
	else:
		dash_direction = -visual_root.global_transform.basis.z.normalized()
		dash_direction.y = 0.0
		if dash_direction.length_squared() < 0.001:
			dash_direction = -camera_pivot.global_transform.basis.z.normalized()
			dash_direction.y = 0.0
		dash_direction = dash_direction.normalized()

	is_dashing = true
	is_invulnerable = true
	dash_timer = 0.0
	dash_cooldown_timer = dash_cooldown

	_set_shadow_visual(true)
	emit_signal("dash_started", dash_direction)
	return true


func _end_dash() -> void:
	is_dashing = false
	is_invulnerable = false
	_set_shadow_visual(false)
	
	# Stop post-dash sliding by damping velocity back down to normal movement speed
	velocity.x = dash_direction.x * (move_speed * 0.7)
	velocity.z = dash_direction.z * (move_speed * 0.7)
	
	emit_signal("dash_finished")


# --- Damage & Combat Interface ---
func take_damage(amount: float, attacker: Node = null, attack_type: String = "melee", attack_data: Dictionary = {}) -> bool:
	if not is_alive:
		return false

	# 1. Check Invulnerability (Shadow Dash)
	if is_invulnerable:
		emit_signal("damage_evaded", amount, attacker)
		return false

	# 2. Check Parry
	if is_parrying:
		var is_perfect: bool = (parry_timer <= perfect_parry_window)
		_end_parry(false)
		
		# Visceral audio/visual impact feedback
		_trigger_parry_feedback(is_perfect)
		
		emit_signal("parry_success", attacker, is_perfect, attack_data)
		return false

	# 3. Apply Damage
	current_health = clamp(current_health - amount, 0.0, max_health)
	emit_signal("damaged", amount, attacker)
	emit_signal("health_changed", current_health, max_health)
	_trigger_hit_flash()
	_add_camera_trauma(0.35)

	if current_health <= 0.0:
		_die()

	return true


func heal(amount: float) -> void:
	if not is_alive or amount <= 0.0:
		return
	current_health = clamp(current_health + amount, 0.0, max_health)
	emit_signal("health_changed", current_health, max_health)


func _die() -> void:
	is_alive = false
	is_parrying = false
	is_dashing = false
	is_attacking = false
	Engine.time_scale = 1.0
	if parry_aura:
		parry_aura.visible = false
	if anim_player:
		anim_player.play("RESET")
	emit_signal("died")


# --- Timers and Updates ---
func _update_timers(delta: float) -> void:
	# Attack timer
	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0.0:
			is_attacking = false

	# Parry timer
	if is_parrying:
		parry_timer += delta
		if parry_timer >= parry_window:
			_end_parry(true) # Missed parry
	elif parry_cooldown_timer > 0.0:
		parry_cooldown_timer -= delta

	# Dash timer
	if is_dashing:
		dash_timer += delta
		if dash_timer >= dash_duration:
			_end_dash()
	elif dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta

	# Hit flash timer
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0 and character_mesh and _original_material:
			character_mesh.set_surface_override_material(0, _original_material)


# --- Visual Feedbacks & Satisfaction Effects ---
func _trigger_hit_flash() -> void:
	if character_mesh:
		var flash_mat := StandardMaterial3D.new()
		flash_mat.albedo_color = Color(1.0, 0.15, 0.15)
		flash_mat.emission_enabled = true
		flash_mat.emission = Color(1.0, 0.1, 0.1)
		flash_mat.emission_energy_multiplier = 2.0
		character_mesh.set_surface_override_material(0, flash_mat)
		_hit_flash_timer = 0.12


func _trigger_parry_feedback(is_perfect: bool) -> void:
	# 1. Screen Shake Impact
	_add_camera_trauma(0.58 if is_perfect else 0.28)

	# 2. Explosive Clash Sparks
	if clash_sparks:
		clash_sparks.restart()
		clash_sparks.emitting = true

	# 3. Dynamic Clash Light Burst
	if clash_light:
		clash_light.light_color = Color(1.0, 0.88, 0.3) if is_perfect else Color(0.35, 0.8, 1.0)
		clash_light.light_energy = 9.0 if is_perfect else 4.5
		var light_tween := create_tween()
		light_tween.tween_property(clash_light, "light_energy", 0.0, 0.14)

	# 4. Expanding Shockwave Ring
	if parry_shockwave:
		var shock_mat := parry_shockwave.get_surface_override_material(0)
		if not shock_mat and parry_shockwave.mesh and parry_shockwave.mesh.material:
			shock_mat = parry_shockwave.mesh.material.duplicate()
			parry_shockwave.set_surface_override_material(0, shock_mat)
		elif shock_mat:
			shock_mat = shock_mat.duplicate()
			parry_shockwave.set_surface_override_material(0, shock_mat)

		if shock_mat:
			shock_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.95) if is_perfect else Color(0.3, 0.85, 1.0, 0.8)

		parry_shockwave.visible = true
		parry_shockwave.scale = Vector3(0.2, 0.2, 0.2)
		var max_scale := Vector3(3.2, 3.2, 3.2) if is_perfect else Vector3(2.2, 2.2, 2.2)
		var wave_tween := create_tween()
		wave_tween.tween_property(parry_shockwave, "scale", max_scale, 0.18)
		if shock_mat:
			wave_tween.parallel().tween_property(shock_mat, "albedo_color:a", 0.0, 0.18)
		wave_tween.tween_callback(func():
			parry_shockwave.visible = false
			parry_shockwave.scale = Vector3.ONE
		)

	# 5. Sekiro-Style Micro Hit-Stop (tactile pause on deflection)
	if is_perfect:
		_trigger_hit_stop(0.06)
	else:
		_trigger_hit_stop(0.02)

	# 6. Reset Sword Animation
	if anim_player:
		anim_player.play("RESET")


func _trigger_hit_stop(real_seconds: float) -> void:
	Engine.time_scale = 0.05
	# ignore_time_scale=true ensures the timer fires in real time
	var timer := get_tree().create_timer(real_seconds, true, false, true)
	timer.timeout.connect(func():
		Engine.time_scale = 1.0
	)


func _set_shadow_visual(active: bool) -> void:
	if not character_mesh:
		return
	if active:
		var shadow_mat := StandardMaterial3D.new()
		shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow_mat.albedo_color = Color(0.08, 0.08, 0.14, 0.45) # Dark phantom shadow
		shadow_mat.emission_enabled = true
		shadow_mat.emission = Color(0.2, 0.1, 0.4)
		shadow_mat.emission_energy_multiplier = 1.5
		character_mesh.set_surface_override_material(0, shadow_mat)
	else:
		if _original_material:
			character_mesh.set_surface_override_material(0, _original_material)
		else:
			character_mesh.set_surface_override_material(0, null)
