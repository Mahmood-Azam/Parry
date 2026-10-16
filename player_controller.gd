class_name PlayerController
extends CharacterBody3D

## Signals for external systems (Dev 2 Heat/Time, Dev 3 Enemies, Dev 4 UI)
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

var IDLE_SCENE: PackedScene = load("res://assets/animations/Lite Sword and Shield Pack/sword and shield idle.fbx")
var WALK_SCENE: PackedScene = load("res://assets/animations/Lite Sword and Shield Pack/sword and shield strafe.fbx")
var RUN_SCENE: PackedScene = load("res://assets/animations/Lite Sword and Shield Pack/sword and shield run.fbx")
var ATTACK_SCENE: PackedScene = load("res://assets/animations/Lite Sword and Shield Pack/sword and shield attack.fbx")
var BLOCK_SCENE: PackedScene = load("res://assets/animations/Lite Sword and Shield Pack/sword and shield block idle.fbx")
var JUMP_ATTACK_SCENE: PackedScene = load("res://assets/animations/Lite Sword and Shield Pack/sword and shield attack (2).fbx")
var SWORD_SCENE: PackedScene = load("res://assets/player/weapons/sword/low-poly-sword/source/LP_Sword2.fbx")
var SHIELD_SCENE: PackedScene = load("res://assets/player/weapons/shield/shield_of_the_iron_star.glb")

# --- Movement Configuration ---
@export_group("Movement")
@export var walk_speed: float = 3.8
@export var run_speed: float = 6.2
@export var jump_velocity: float = 4.6
@export var turn_speed: float = 12.0
@export var stopping_friction: float = 45.0
@export var crouch_speed_multiplier: float = 0.45
@export var block_speed_multiplier: float = 0.25

# --- Weapon & Model Scale ---
@export_group("Visuals")
@export var sword_scale_factor: float = 0.55
@export var shield_scale_factor: float = 0.25

# --- Health Configuration ---
@export_group("Health")
@export var max_health: float = 100.0

# --- Parry Configuration ---
@export_group("Parry")
@export var parry_window: float = 0.35               ## Total duration of parry window in seconds.
@export var perfect_parry_window: float = 0.12       ## Portion of window that triggers a Perfect Parry.
@export var parry_cooldown: float = 0.45             ## Recovery penalty when a parry is missed.
@export var parry_max_angle: float = 75.0            ## Forward angle (deg) within which attacks can be parried.

# --- Shadow Dash Configuration ---
@export_group("Shadow Dash")
@export var dash_speed: float = 15.0
@export var dash_duration: float = 0.22
@export var dash_cooldown: float = 0.90
@export var dash_invulnerability_time: float = 0.22

# --- Node References ---
@onready var character: Node3D = $WarriorKnight
@onready var animation_player: AnimationPlayer = $WarriorKnight/AnimationPlayer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var camera_pivot: Node3D = get_node_or_null("CameraPivot")
@onready var camera: Camera3D = get_node_or_null("CameraPivot/SpringArm3D/Camera3D")

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- Runtime States ---
var current_health: float = 100.0
var is_alive: bool = true
var is_invulnerable: bool = false

var attacking := false
var is_attacking: bool = false
var blocking := false
var is_parrying: bool = false
var parry_timer: float = 0.0
var parry_cooldown_timer: float = 0.0

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector3 = Vector3.FORWARD

var crouching := false
var last_animation := ""
var attack_start_basis := Basis.IDENTITY
var attack_last_root_motion_position := Vector3.ZERO
var attack_root_motion_tracks := {}
var camera_trauma: float = 0.0


func _ready() -> void:
	current_health = max_health
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	
	_ensure_input_actions()
	_setup_weapon_mounts()
	
	_import_mixamo_clip(IDLE_SCENE, "Idle", true, true)
	_import_mixamo_clip(WALK_SCENE, "Walk", true, true)
	_import_mixamo_clip(RUN_SCENE, "Run", true, true)
	_import_mixamo_clip(ATTACK_SCENE, "Attack", false, true)
	_import_mixamo_clip(BLOCK_SCENE, "Block", true)
	_import_mixamo_clip(JUMP_ATTACK_SCENE, "JumpAttack", false, true)
	
	animation_player.animation_finished.connect(_on_animation_finished)
	_play("Idle")
	_align_weapon_mounts.call_deferred()
	emit_signal("health_changed", current_health, max_health)


func _ensure_input_actions() -> void:
	var key_bindings := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_backward": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"jump_attack": KEY_X,
		"crouch": KEY_CTRL,
		"sprint": KEY_SHIFT,
		"dash": KEY_SPACE,
		"parry": KEY_F,
	}
	for action_name in key_bindings:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var key_event := InputEventKey.new()
		key_event.physical_keycode = key_bindings[action_name]
		InputMap.action_add_event(action_name, key_event)
		
	var mouse_bindings := {"attack": MOUSE_BUTTON_LEFT, "block": MOUSE_BUTTON_RIGHT, "parry": MOUSE_BUTTON_RIGHT}
	for action_name in mouse_bindings:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = mouse_bindings[action_name]
		InputMap.action_add_event(action_name, mouse_event)


func _setup_weapon_mounts() -> void:
	var skeleton := character.get_node_or_null("Skeleton3D") as Skeleton3D
	if skeleton == null:
		push_error("Player knight has no Skeleton3D; cannot attach weapons.")
		return
	var right_socket := skeleton.get_node_or_null("RightHandSocket") as BoneAttachment3D
	if right_socket == null:
		right_socket = BoneAttachment3D.new()
		right_socket.name = "RightHandSocket"
		right_socket.bone_name = "mixamorig_RightHand"
		skeleton.add_child(right_socket)
	var left_socket := skeleton.get_node_or_null("LeftHandSocket") as BoneAttachment3D
	if left_socket == null:
		left_socket = BoneAttachment3D.new()
		left_socket.name = "LeftHandSocket"
		left_socket.bone_name = "mixamorig_LeftHand"
		skeleton.add_child(left_socket)
	if right_socket.get_node_or_null("Sword") == null:
		var sword := SWORD_SCENE.instantiate()
		sword.name = "Sword"
		right_socket.add_child(sword)
	if left_socket.get_node_or_null("Shield") == null:
		var shield := SHIELD_SCENE.instantiate()
		shield.name = "Shield"
		left_socket.add_child(shield)


func _align_weapon_mounts() -> void:
	await get_tree().create_timer(0.25).timeout
	var skeleton := character.get_node_or_null("Skeleton3D") as Skeleton3D
	if skeleton == null:
		return
	var right_socket := skeleton.get_node_or_null("RightHandSocket") as BoneAttachment3D
	var left_socket := skeleton.get_node_or_null("LeftHandSocket") as BoneAttachment3D
	if right_socket == null or left_socket == null:
		return

	var sword := right_socket.get_node_or_null("Sword") as Node3D
	var sword_mesh := sword.find_child("LP_Sword", true, false) as MeshInstance3D if sword != null else null
	if sword != null and sword_mesh != null and sword_mesh.mesh != null:
		var source_sword_axis := (sword.global_basis.inverse() * sword_mesh.global_basis * Vector3.RIGHT).normalized()
		var source_sword_normal := (sword.global_basis.inverse() * sword_mesh.global_basis * Vector3.BACK).normalized()
		var source_sword_side := source_sword_normal.cross(source_sword_axis).normalized()
		var source_sword_basis := Basis(source_sword_axis, source_sword_side, source_sword_normal)
		var sword_direction := Vector3(0.0, -0.2, 0.98).normalized()
		var target_sword_axis := (right_socket.global_basis.inverse() * character.global_basis * sword_direction).normalized()
		var target_sword_normal := (right_socket.global_basis.inverse() * character.global_basis * Vector3.BACK).normalized()
		target_sword_normal = (target_sword_normal - target_sword_axis * target_sword_normal.dot(target_sword_axis)).normalized()
		var target_sword_side := target_sword_normal.cross(target_sword_axis).normalized()
		var target_sword_basis := Basis(-target_sword_axis, -target_sword_side, target_sword_normal)
		var sword_center_in_root := sword.to_local(sword_mesh.global_transform * sword_mesh.mesh.get_aabb().get_center())
		
		# Proportional sword scaling
		var scale_v := Vector3.ONE * sword_scale_factor
		sword.scale = scale_v
		sword.quaternion = (target_sword_basis * source_sword_basis.inverse()).get_rotation_quaternion()
		var sword_half_length := sword_mesh.mesh.get_aabb().size.x * sword_mesh.scale.x * sword_scale_factor * 0.5
		var sword_center_offset := target_sword_axis * sword_half_length
		sword.position = sword_center_offset - sword.quaternion * (sword_center_in_root * sword_scale_factor)

	var shield := left_socket.get_node_or_null("Shield") as Node3D
	var shield_mesh := shield.find_child("Object_4", true, false) as MeshInstance3D if shield != null else null
	if shield != null and shield_mesh != null and shield_mesh.mesh != null:
		var source_shield_normal := (shield.global_basis.inverse() * shield_mesh.global_basis * Vector3.UP).normalized()
		var source_shield_up := (shield.global_basis.inverse() * shield_mesh.global_basis * Vector3.BACK).normalized()
		var source_shield_right := source_shield_up.cross(source_shield_normal).normalized()
		var source_shield_basis := Basis(source_shield_right, source_shield_up, source_shield_normal)
		var target_shield_normal := (left_socket.global_basis.inverse() * character.global_basis * Vector3.BACK).normalized()
		var target_shield_up := (left_socket.global_basis.inverse() * character.global_basis * Vector3.UP).normalized()
		var target_shield_right := target_shield_up.cross(target_shield_normal).normalized()
		var target_shield_basis := Basis(target_shield_right, target_shield_up, target_shield_normal)
		var shield_center_in_root := shield.to_local(shield_mesh.global_transform * shield_mesh.mesh.get_aabb().get_center())
		
		var shield_scale := Vector3.ONE * shield_scale_factor
		shield.scale = shield_scale
		shield.quaternion = (target_shield_basis * source_shield_basis.inverse()).get_rotation_quaternion()
		var shield_center_world := left_socket.global_position + character.global_basis * Vector3(-0.22, 0.0, 0.12)
		var shield_center_in_socket := left_socket.to_local(shield_center_world)
		shield.position = shield_center_in_socket - shield.quaternion * (shield_center_in_root * shield.scale)


func _import_mixamo_clip(source_scene: PackedScene, clip_name: String, loop := false, remove_root_motion := false) -> void:
	if source_scene == null:
		return
	var source_root := source_scene.instantiate()
	var source_player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player != null and source_player.has_animation("mixamo_com"):
		var target_animation: Animation = source_player.get_animation("mixamo_com").duplicate(true)
		var root_motion_source: Animation
		var root_motion_track_index := -1
		for track_index in range(target_animation.get_track_count()):
			var track_path := String(target_animation.track_get_path(track_index))
			var bone_separator := track_path.find(":")
			if bone_separator >= 0:
				var bone_name := track_path.substr(bone_separator + 1)
				if bone_name == "mixamorig_Hips" and target_animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D:
					if target_animation.track_get_key_count(track_index) > 0:
						if clip_name in ["Attack", "JumpAttack"]:
							root_motion_source = target_animation.duplicate(true)
							root_motion_track_index = track_index
						var first_value = target_animation.track_get_key_value(track_index, 0)
						if remove_root_motion:
							for key_index in range(target_animation.track_get_key_count(track_index)):
								target_animation.track_set_key_value(track_index, key_index, first_value)
				target_animation.track_set_path(track_index, NodePath("Skeleton3D:" + bone_name))
		if root_motion_source != null and root_motion_track_index >= 0:
			root_motion_source.track_set_path(root_motion_track_index, NodePath("Skeleton3D:mixamorig_Hips"))
			attack_root_motion_tracks[clip_name] = {"animation": root_motion_source, "track": root_motion_track_index}
		if loop:
			target_animation.loop_mode = Animation.LOOP_LINEAR
		var library := animation_player.get_animation_library("")
		if library == null:
			library = AnimationLibrary.new()
			animation_player.add_animation_library("", library)
		if animation_player.has_animation(clip_name):
			library.remove_animation(clip_name)
		library.add_animation(clip_name, target_animation)
	source_root.queue_free()


func _process(delta: float) -> void:
	if not is_alive:
		return
	_process_screen_shake(delta)


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	
	if not is_alive:
		if not is_on_floor():
			velocity.y -= gravity * delta
			move_and_slide()
		return

	if is_dashing:
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
		move_and_slide()
		return

	if attacking:
		_apply_attack_root_motion()
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	# Handle Parry / Block input
	var wants_block := (Input.is_action_pressed("block") or Input.is_action_pressed("parry")) and parry_cooldown_timer <= 0.0
	if wants_block and not blocking and not attacking:
		try_start_parry()
	elif not wants_block and blocking:
		_end_parry(false)

	# Handle Crouch input
	var wants_crouch := Input.is_action_pressed("crouch")
	if wants_crouch != crouching:
		crouching = wants_crouch
		_set_crouch_pose(crouching)
		if not attacking and not blocking:
			last_animation = ""
			_play("Idle")

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_vector.length_squared() < 0.001:
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		
	var direction := Vector3(input_vector.x, 0.0, input_vector.y).normalized()
	var moving := direction.length_squared() > 0.001
	var sprinting := Input.is_action_pressed("sprint") and not crouching and not blocking

	if moving:
		var target_yaw := atan2(direction.x, direction.z)
		character.rotation.y = rotate_toward(character.rotation.y, target_yaw, turn_speed * delta)

	var speed := run_speed if sprinting else walk_speed
	if crouching:
		speed *= crouch_speed_multiplier
	if blocking:
		speed *= block_speed_multiplier
		
	if moving:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# Sharp stopping friction to prevent sliding
		velocity.x = move_toward(velocity.x, 0.0, stopping_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, stopping_friction * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# Attack triggers
	if Input.is_action_just_pressed("jump_attack") and not attacking and not blocking and not is_dashing:
		_begin_attack("JumpAttack")
		velocity.y = jump_velocity
	elif Input.is_action_just_pressed("attack") and not attacking and not blocking and not is_dashing:
		_begin_attack("Attack")

	# Shadow Dash trigger
	if Input.is_action_just_pressed("dash") and not is_dashing and dash_cooldown_timer <= 0.0:
		try_start_dash()

	move_and_slide()

	if not attacking and not blocking and not is_dashing and is_on_floor():
		if crouching or not moving:
			_play("Idle")
		else:
			_play("Run" if sprinting else "Walk")


func _set_crouch_pose(is_crouching: bool) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return
	var tween := create_tween().set_parallel(true)
	if is_crouching:
		tween.tween_property(character, "scale", Vector3(1.0, 0.72, 1.0), 0.16)
		tween.tween_property(capsule, "height", 1.25, 0.16)
		tween.tween_property(collision_shape, "position:y", 0.625, 0.16)
	else:
		tween.tween_property(character, "scale", Vector3.ONE, 0.16)
		tween.tween_property(capsule, "height", 1.8, 0.16)
		tween.tween_property(collision_shape, "position:y", 0.9, 0.16)


func _play(animation_name: String) -> void:
	if animation_player.has_animation(animation_name) and last_animation != animation_name:
		last_animation = animation_name
		animation_player.play(animation_name, 0.12)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name in ["Attack", "JumpAttack"]:
		_apply_attack_root_motion(animation_name)
		attacking = false
		is_attacking = false
		last_animation = ""
		_play("Block" if blocking else "Idle")


func _begin_attack(animation_name: String) -> void:
	attacking = true
	is_attacking = true
	attack_start_basis = character.global_basis
	var motion_data: Dictionary = attack_root_motion_tracks.get(animation_name, {})
	var source_animation: Animation = motion_data.get("animation") as Animation
	var track_index: int = motion_data.get("track", -1)
	attack_last_root_motion_position = source_animation.track_get_key_value(track_index, 0) if source_animation != null and track_index >= 0 else Vector3.ZERO
	_play(animation_name)
	emit_signal("attack_pressed")


func _apply_attack_root_motion(animation_name: StringName = "") -> void:
	var clip_name: String = String(animation_name) if animation_name != "" else String(animation_player.current_animation)
	var motion_data: Dictionary = attack_root_motion_tracks.get(clip_name, {})
	var source_animation: Animation = motion_data.get("animation") as Animation
	var track_index: int = motion_data.get("track", -1)
	if source_animation == null or track_index < 0:
		return
	var sample_time: float = source_animation.get_length() if animation_name != "" else animation_player.current_animation_position
	var key_count := source_animation.track_get_key_count(track_index)
	if key_count == 0:
		return
	var sampled_position: Vector3 = source_animation.track_get_key_value(track_index, 0)
	if sample_time >= source_animation.track_get_key_time(track_index, key_count - 1):
		sampled_position = source_animation.track_get_key_value(track_index, key_count - 1)
	else:
		for key_index in range(key_count - 1):
			var key_start_time := source_animation.track_get_key_time(track_index, key_index)
			var key_end_time := source_animation.track_get_key_time(track_index, key_index + 1)
			if sample_time <= key_end_time:
				var blend := inverse_lerp(key_start_time, key_end_time, sample_time)
				var key_start: Vector3 = source_animation.track_get_key_value(track_index, key_index)
				var key_end: Vector3 = source_animation.track_get_key_value(track_index, key_index + 1)
				sampled_position = key_start.lerp(key_end, blend)
				break
	var motion_delta := sampled_position - attack_last_root_motion_position
	motion_delta.y = 0.0
	global_position += attack_start_basis * motion_delta
	attack_last_root_motion_position = sampled_position


# --- Parry System ---
func try_start_parry() -> bool:
	if not is_alive or is_parrying or is_dashing or parry_cooldown_timer > 0.0:
		return false
	blocking = true
	is_parrying = true
	parry_timer = 0.0
	last_animation = ""
	_play("Block")
	emit_signal("parry_started")
	return true


func _end_parry(missed: bool) -> void:
	blocking = false
	is_parrying = false
	last_animation = ""
	if missed:
		parry_cooldown_timer = parry_cooldown
		_play("Idle")
		emit_signal("parry_failed")
	else:
		parry_cooldown_timer = 0.1
		_play("Idle")


# --- Shadow Dash ---
func try_start_dash() -> bool:
	if not is_alive or is_dashing or dash_cooldown_timer > 0.0:
		return false
	if is_parrying:
		_end_parry(false)
	attacking = false
	is_attacking = false

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_vector.length_squared() > 0.001:
		dash_direction = Vector3(input_vector.x, 0.0, input_vector.y).normalized()
	else:
		dash_direction = character.global_transform.basis.z.normalized()
		dash_direction.y = 0.0
		if dash_direction.length_squared() < 0.001:
			dash_direction = Vector3.FORWARD

	is_dashing = true
	is_invulnerable = true
	dash_timer = 0.0
	dash_cooldown_timer = dash_cooldown
	emit_signal("dash_started", dash_direction)
	return true


func _end_dash() -> void:
	is_dashing = false
	is_invulnerable = false
	emit_signal("dash_finished")


## Directional Parry: checks if the player is facing towards the incoming attack source within parry_max_angle degrees.
func is_facing_attack(attacker: Node = null, attack_data: Dictionary = {}) -> bool:
	var incoming_dir := Vector3.ZERO
	if attack_data.has("direction") and attack_data["direction"] is Vector3:
		incoming_dir = -attack_data["direction"]
	elif attacker != null and attacker is Node3D:
		incoming_dir = attacker.global_position - global_position
	elif attack_data.has("origin") and attack_data["origin"] is Vector3:
		incoming_dir = attack_data["origin"] - global_position
	else:
		return true

	var forward := character.global_transform.basis.z
	forward.y = 0.0
	incoming_dir.y = 0.0

	if incoming_dir.length_squared() < 0.001 or forward.length_squared() < 0.001:
		return true

	var forward_norm := forward.normalized()
	var attack_norm := incoming_dir.normalized()
	var dot := forward_norm.dot(attack_norm)
	var min_dot := cos(deg_to_rad(parry_max_angle))
	return dot >= min_dot


# --- Damage Reception & Combat Interface ---
func take_damage(amount: float, attacker: Node = null, attack_type: String = "melee", attack_data: Dictionary = {}) -> bool:
	if not is_alive:
		return false

	# 1. Shadow Dash Invulnerability
	if is_invulnerable:
		emit_signal("damage_evaded", amount, attacker)
		return false

	# 2. Parry Check (facing incoming attack)
	if is_parrying and is_facing_attack(attacker, attack_data):
		var is_perfect: bool = (parry_timer <= perfect_parry_window)
		_end_parry(false)
		_trigger_parry_feedback(is_perfect)
		emit_signal("parry_success", attacker, is_perfect, attack_data)
		return false

	# 3. Take Damage
	current_health = clamp(current_health - amount, 0.0, max_health)
	emit_signal("damaged", amount, attacker)
	emit_signal("health_changed", current_health, max_health)
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
	blocking = false
	is_dashing = false
	attacking = false
	is_attacking = false
	Engine.time_scale = 1.0
	emit_signal("died")


func _update_timers(delta: float) -> void:
	if is_parrying:
		parry_timer += delta
		if parry_timer >= parry_window:
			_end_parry(true)
	elif parry_cooldown_timer > 0.0:
		parry_cooldown_timer -= delta

	if is_dashing:
		dash_timer += delta
		if dash_timer >= dash_duration:
			_end_dash()
	elif dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta


func _trigger_parry_feedback(is_perfect: bool) -> void:
	_add_camera_trauma(0.55 if is_perfect else 0.25)
	# Tactile micro-pause on parry impact
	_trigger_hit_stop(0.06 if is_perfect else 0.02)


func _trigger_hit_stop(real_seconds: float) -> void:
	Engine.time_scale = 0.05
	var timer := get_tree().create_timer(real_seconds, true, false, true)
	timer.timeout.connect(func(): Engine.time_scale = 1.0)


func _add_camera_trauma(amount: float) -> void:
	camera_trauma = clamp(camera_trauma + amount, 0.0, 1.0)


func _process_screen_shake(delta: float) -> void:
	if not camera:
		return
	if camera_trauma > 0.0:
		camera_trauma = max(0.0, camera_trauma - delta * 3.5)
		var shake := camera_trauma * camera_trauma * 0.16
		camera.h_offset = randf_range(-shake, shake)
		camera.v_offset = randf_range(-shake, shake)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
