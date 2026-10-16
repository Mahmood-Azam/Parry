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
signal parry_stun_requested(attacker: Node, duration: float, is_perfect: bool)

signal dash_started(direction: Vector3)
signal dash_finished()
signal attack_pressed()

var IDLE_SCENE: PackedScene = load("res://assets/animations/Lite Sword and Shield Pack/sword and shield idle.fbx")
var WALK_SCENE: PackedScene = load("res://assets/animations/Lite Sword and Shield Pack/sword and shield run.fbx")
var RUN_SCENE: PackedScene = load("res://assets/animations/Lite Sword and Shield Pack/sword and shield run (2).fbx")
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

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var min_camera_pitch: float = -55.0
@export var max_camera_pitch: float = 35.0
@export var camera_distance: float = 5.8
@export var camera_min_distance: float = 2.5
@export var camera_max_distance: float = 8.5
@export var camera_zoom_step: float = 0.5

# --- Weapon & Model Scale ---
@export_group("Visuals")
@export var sword_scale_factor: float = 0.55
@export var shield_scale_factor: float = 0.25

# --- Health Configuration ---
@export_group("Health")
@export var max_health: float = 100.0

# --- Parry Configuration ---
@export_group("Parry")
@export var parry_window: float = 0.22               ## Total duration of parry window in seconds.
@export var perfect_parry_window: float = 0.07       ## Portion of window that triggers a Perfect Parry.
@export var parry_cooldown: float = 0.30             ## Recovery penalty when a parry is missed.
@export var parry_max_angle: float = 80.0            ## Forward angle (deg) within which attacks can be parried.
@export var parry_stun_duration: float = 1.0         ## Stun requested from a successfully parried enemy.
@export var parry_hitbox_radius: float = 2.2         ## Distance around the player where parries can connect.
@export var block_damage_multiplier: float = 0.35    ## Damage received while holding Right Mouse.
@export var hit_stop_duration: float = 0.06         ## Brief freeze-frame after taking damage.
@export var hit_stop_time_scale: float = 0.05        ## Time scale used during the impact frame.
@export var hit_stun_duration: float = 0.28          ## How long controls are locked after a hit.

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
@onready var camera_arm: SpringArm3D = get_node_or_null("CameraPivot/SpringArm3D")
@onready var camera: Camera3D = get_node_or_null("CameraPivot/SpringArm3D/Camera3D")
@onready var parry_hitbox: Area3D = get_node_or_null("ParryHitbox")

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
var dash_invulnerability_timer: float = 0.0
var dash_direction: Vector3 = Vector3.FORWARD

var crouching := false
var last_animation := ""
var attack_start_basis := Basis.IDENTITY
var attack_last_root_motion_position := Vector3.ZERO
var attack_root_motion_tracks := {}
var camera_trauma: float = 0.0
var combat_feedback_label: Label
var combat_feedback_tween: Tween
var combat_stats_label: Label
var parry_flash: ColorRect
var hit_flash: ColorRect
var parry_sound: AudioStreamPlayer
var parry_audio_stream: AudioStream = preload("res://assets/audio/Parry.mp3")
var hit_stop_active: bool = false
var hit_stun_remaining: float = 0.0
var hit_reaction_elapsed: float = 0.0
var hit_reaction_base_rotation: Vector3
var hit_reaction_base_position: Vector3
var dash_elapsed: float = 0.0
var dash_base_rotation: Vector3
var dash_base_position: Vector3
var dash_base_scale: Vector3
var shadow_decoy_script: Script = preload("res://shadow_decoy.gd")
var locomotion_phase: float = 0.0
var locomotion_base_position: Vector3


func _ready() -> void:
	current_health = max_health
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	if camera_pivot != null:
		camera_pivot.rotation.x = 0.0
	if camera != null:
		camera.current = true
	if camera_arm != null:
		camera_arm.spring_length = camera_distance
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	_ensure_input_actions()
	_setup_parry_hitbox()
	_setup_combat_feedback()
	_setup_parry_audio()
	_setup_combat_stats()
	_setup_weapon_mounts()
	locomotion_base_position = character.position
	
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
		"dash": KEY_Q,
		"parry": KEY_F,
	}
	for action_name in key_bindings:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var has_key := false
		for existing_event in InputMap.action_get_events(action_name):
			if existing_event is InputEventKey and existing_event.physical_keycode == key_bindings[action_name]:
				has_key = true
				break
		if not has_key:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = key_bindings[action_name]
			InputMap.action_add_event(action_name, key_event)
		
	var mouse_bindings := {"attack": MOUSE_BUTTON_LEFT, "block": MOUSE_BUTTON_RIGHT}
	for action_name in mouse_bindings:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var has_mouse := false
		for existing_event in InputMap.action_get_events(action_name):
			if existing_event is InputEventMouseButton and existing_event.button_index == mouse_bindings[action_name]:
				has_mouse = true
				break
		if not has_mouse:
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = mouse_bindings[action_name]
			InputMap.action_add_event(action_name, mouse_event)
	_force_exclusive_key_binding("sprint", KEY_SHIFT)
	_force_exclusive_key_binding("crouch", KEY_CTRL)


func _force_exclusive_key_binding(action_name: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey:
			InputMap.action_erase_event(action_name, existing_event)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, key_event)


func _setup_combat_feedback() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CombatFeedbackLayer"
	add_child(layer)
	parry_flash = ColorRect.new()
	parry_flash.name = "ParryFlash"
	parry_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parry_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parry_flash.color = Color(1.0, 0.82, 0.2, 0.0)
	layer.add_child(parry_flash)
	hit_flash = ColorRect.new()
	hit_flash.name = "HitFlash"
	hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit_flash.color = Color(1.0, 0.08, 0.04, 0.0)
	layer.add_child(hit_flash)
	combat_feedback_label = Label.new()
	combat_feedback_label.name = "ParryIndicator"
	combat_feedback_label.text = ""
	combat_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combat_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	combat_feedback_label.add_theme_font_size_override("font_size", 32)
	combat_feedback_label.add_theme_color_override("font_color", Color.WHITE)
	combat_feedback_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.04, 0.9))
	combat_feedback_label.add_theme_constant_override("shadow_offset_x", 3)
	combat_feedback_label.add_theme_constant_override("shadow_offset_y", 3)
	combat_feedback_label.set_anchors_preset(Control.PRESET_CENTER)
	combat_feedback_label.position = Vector2(-240.0, 90.0)
	combat_feedback_label.size = Vector2(480.0, 64.0)
	combat_feedback_label.modulate.a = 0.0
	layer.add_child(combat_feedback_label)


func _setup_parry_audio() -> void:
	parry_sound = AudioStreamPlayer.new()
	parry_sound.name = "ParrySound"
	parry_sound.stream = parry_audio_stream
	parry_sound.volume_db = 0.0
	add_child(parry_sound)


func _setup_parry_hitbox() -> void:
	if parry_hitbox == null:
		parry_hitbox = Area3D.new()
		parry_hitbox.name = "ParryHitbox"
		parry_hitbox.collision_layer = 0
		parry_hitbox.collision_mask = (1 << 4) | (1 << 5)
		var shape_node := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = parry_hitbox_radius
		shape_node.shape = sphere
		parry_hitbox.add_child(shape_node)
		add_child(parry_hitbox)
	else:
		var shape_node := parry_hitbox.get_child(0) as CollisionShape3D
		if shape_node != null and shape_node.shape is SphereShape3D:
			(shape_node.shape as SphereShape3D).radius = parry_hitbox_radius
	parry_hitbox.monitoring = false


func _set_parry_hitbox_active(active: bool) -> void:
	if parry_hitbox != null:
		parry_hitbox.monitoring = active
		parry_hitbox.monitorable = active


func _setup_combat_stats() -> void:
	var layer := get_node_or_null("CombatFeedbackLayer") as CanvasLayer
	if layer == null:
		return
	combat_stats_label = Label.new()
	combat_stats_label.name = "CombatStats"
	combat_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	combat_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	combat_stats_label.add_theme_font_size_override("font_size", 18)
	combat_stats_label.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0, 0.95))
	combat_stats_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.04, 0.9))
	combat_stats_label.add_theme_constant_override("shadow_offset_x", 2)
	combat_stats_label.add_theme_constant_override("shadow_offset_y", 2)
	combat_stats_label.position = Vector2(24.0, 18.0)
	combat_stats_label.size = Vector2(520.0, 124.0)
	layer.add_child(combat_stats_label)
	_update_combat_stats()


func _update_combat_stats() -> void:
	if combat_stats_label == null:
		return
	var parry_state := "READY"
	if is_parrying:
		parry_state = "ACTIVE %.2fs" % maxf(parry_window - parry_timer, 0.0)
	elif blocking:
		parry_state = "BLOCKING (%.0f%% DAMAGE)" % (block_damage_multiplier * 100.0)
	elif parry_cooldown_timer > 0.0:
		parry_state = "RECOVERY %.2fs" % parry_cooldown_timer
	var dash_state := "READY" if dash_cooldown_timer <= 0.0 else "COOLDOWN %.2fs" % dash_cooldown_timer
	combat_stats_label.text = "HP: %d / %d\nPARRY: %s  |  PERFECT: %.2fs / %.2fs  |  RANGE: %.1fm\nSHADOW: %s\n\nWASD Move   |   Shift Sprint   |   Ctrl Crouch   |   Space Jump\nF Parry   |   RMB Parry -> Block   |   Q Shadow Dash   |   LMB Attack" % [
		roundi(current_health), roundi(max_health), parry_state, perfect_parry_window, parry_window, parry_hitbox_radius, dash_state
	]


func _show_combat_feedback(message: String, color: Color) -> void:
	if combat_feedback_label == null:
		return
	if combat_feedback_tween != null and combat_feedback_tween.is_valid():
		combat_feedback_tween.kill()
	combat_feedback_label.text = message
	combat_feedback_label.add_theme_color_override("font_color", color)
	combat_feedback_label.scale = Vector2(0.82, 0.82)
	combat_feedback_label.modulate.a = 1.0
	combat_feedback_tween = create_tween().set_parallel(true)
	combat_feedback_tween.tween_property(combat_feedback_label, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_BACK)
	combat_feedback_tween.tween_property(combat_feedback_label, "modulate:a", 0.0, 0.65).set_delay(0.35)


func _show_parry_flash(is_perfect: bool) -> void:
	if parry_flash == null:
		return
	var flash_color := Color(1.0, 0.82, 0.2, 0.24) if is_perfect else Color(0.25, 0.75, 1.0, 0.18)
	parry_flash.color = flash_color
	var tween := create_tween()
	tween.tween_property(parry_flash, "color:a", 0.0, 0.18)


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

	if hit_stun_remaining > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		hit_reaction_elapsed += delta
		_update_hit_reaction_pose()
		move_and_slide()
		return
	_process_screen_shake(delta)
	_update_combat_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
		return
	if event is InputEventMouseButton and event.pressed:
		if camera_arm != null and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_arm.spring_length = clamp(camera_arm.spring_length - camera_zoom_step, camera_min_distance, camera_max_distance)
			return
		if camera_arm != null and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_arm.spring_length = clamp(camera_arm.spring_length + camera_zoom_step, camera_min_distance, camera_max_distance)
			return
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if camera_pivot != null:
			camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
			camera_pivot.rotation.x = clamp(
				camera_pivot.rotation.x - event.relative.y * mouse_sensitivity,
				deg_to_rad(min_camera_pitch),
				deg_to_rad(max_camera_pitch)
			)
	if event.is_action_pressed("parry") and is_alive:
		try_start_parry()
		return
	if event.is_action_pressed("block") and is_alive:
		# Right Mouse starts with the same short parry as F. Holding it after
		# the window transitions into the safer, reduced-damage block.
		try_start_parry()


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	
	if not is_alive:
		if not is_on_floor():
			velocity.y -= gravity * delta
			move_and_slide()
		return

	# Resolve parries from the attacker's animation contact window rather than
	# waiting for a damage callback. This makes the mechanic deterministic even
	# if the enemy animation and physics tick do not land on the same frame.
	if is_parrying:
		_check_active_parry_contacts()

	_face_camera_direction(delta)

	if is_dashing:
		dash_elapsed += delta
		_update_dash_pose()
		animation_player.speed_scale = 1.35
		_play("Run")
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
		move_and_slide()
		return

	if attacking:
		_reset_locomotion_pose(delta)
		_apply_attack_root_motion()
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	# Right Mouse is an indefinite block. F starts the short, timed parry window.
	var wants_block := Input.is_action_pressed("block")
	if wants_block and not blocking and not attacking and not is_parrying:
		_start_block()
	elif not wants_block and blocking and not is_parrying:
		_end_block()

	# Handle Crouch input
	var wants_crouch := Input.is_key_pressed(KEY_CTRL)
	if wants_crouch != crouching:
		crouching = wants_crouch
		_set_crouch_pose(crouching)
		if not attacking and not blocking:
			last_animation = ""
			_play("Idle")

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_vector.length_squared() < 0.001:
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# Movement is relative to the camera's yaw, as expected in a third-person controller.
	var move_basis := camera_pivot.global_transform.basis if camera_pivot != null else global_transform.basis
	var direction := (move_basis * Vector3(input_vector.x, 0.0, input_vector.y))
	direction.y = 0.0
	direction = direction.normalized()
	var moving := direction.length_squared() > 0.001
	var sprinting := Input.is_key_pressed(KEY_SHIFT) and not crouching and not blocking

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
	_update_locomotion_pose(delta, moving, sprinting)

	if not attacking and not blocking and not is_dashing and is_on_floor():
		if crouching or not moving:
			animation_player.speed_scale = 1.0
			_play("Idle")
		else:
			animation_player.speed_scale = 1.0 if sprinting else 0.72
			_play("Run" if sprinting else "Walk")


func _face_camera_direction(delta: float) -> void:
	if camera_pivot == null or character == null:
		return
	var camera_forward := -camera_pivot.global_transform.basis.z
	camera_forward.y = 0.0
	if camera_forward.length_squared() < 0.001:
		return
	var target_yaw := atan2(camera_forward.x, camera_forward.z)
	character.rotation.y = rotate_toward(character.rotation.y, target_yaw, turn_speed * delta)


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
		animation_player.play(animation_name, 0.16)


func _setup_dash_roll_animation() -> void:
	var library := animation_player.get_animation_library("")
	if library == null or library.has_animation("DashRoll"):
		return
	var roll := Animation.new()
	roll.length = dash_duration
	roll.loop_mode = Animation.LOOP_NONE
	_add_roll_bone_track(roll, "Skeleton3D:mixamorig_Hips", 1.0)
	_add_roll_bone_track(roll, "Skeleton3D:mixamorig_Spine", 0.72)
	_add_roll_bone_track(roll, "Skeleton3D:mixamorig_Spine1", 0.54)
	_add_roll_bone_track(roll, "Skeleton3D:mixamorig_Spine2", 0.36)
	_add_roll_bone_track(roll, "Skeleton3D:mixamorig_Neck", 0.22)
	library.add_animation("DashRoll", roll)


func _add_roll_bone_track(animation: Animation, track_path: String, influence: float) -> void:
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath(track_path))
	var axis := Vector3(0.0, 0.0, 1.0)
	animation.track_insert_key(track, 0.0, Quaternion.IDENTITY)
	animation.track_insert_key(track, dash_duration * 0.5, Quaternion(axis, PI * influence))
	animation.track_insert_key(track, dash_duration, Quaternion(axis, TAU * influence))


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == "DashRoll":
		last_animation = ""
	elif animation_name in ["Attack", "JumpAttack"]:
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
	if not is_alive or is_parrying or is_dashing or attacking or parry_cooldown_timer > 0.0:
		return false
	if blocking:
		_end_block()
	blocking = true
	is_parrying = true
	parry_timer = 0.0
	_set_parry_hitbox_active(true)
	last_animation = ""
	_play("Block")
	emit_signal("parry_started")
	return true


func _start_block() -> void:
	blocking = true
	last_animation = ""
	_play("Block")


func _end_block() -> void:
	blocking = false
	last_animation = ""
	_play("Idle")


func _end_parry(missed: bool) -> void:
	blocking = false
	is_parrying = false
	_set_parry_hitbox_active(false)
	last_animation = ""
	if missed:
		parry_cooldown_timer = parry_cooldown
		_play("Idle")
		_show_combat_feedback("PARRY MISSED", Color(0.75, 0.8, 0.9))
		emit_signal("parry_failed")
	else:
		parry_cooldown_timer = 0.1
		_play("Idle")


func _transition_parry_to_block() -> void:
	if not is_parrying:
		return
	is_parrying = false
	_set_parry_hitbox_active(false)
	blocking = true
	parry_timer = 0.0
	last_animation = ""
	_play("Block")


func _check_active_parry_contacts() -> void:
	if not is_parrying or not is_alive:
		return
	for candidate in get_tree().get_nodes_in_group("enemy"):
		if candidate == null or not is_instance_valid(candidate) or not candidate is Node3D:
			continue
		if not candidate.has_method("is_attack_in_parry_window"):
			continue
		var attacker := candidate as Node3D
		var to_attacker := attacker.global_position - global_position
		to_attacker.y = 0.0
		if to_attacker.length() > parry_hitbox_radius:
			continue
		if not is_facing_attack(attacker):
			continue
		if not bool(candidate.call("is_attack_in_parry_window")):
			continue
		_resolve_parry(attacker, {"attack_name": "Animation Contact", "origin": attacker.global_position})
		return


func _resolve_parry(attacker: Node, attack_data: Dictionary = {}) -> void:
	if not is_parrying:
		return
	var is_perfect: bool = parry_timer <= perfect_parry_window
	_end_parry(false)
	if parry_sound != null:
		parry_sound.play()
	_trigger_parry_feedback(is_perfect)
	_show_combat_feedback("PERFECT PARRY" if is_perfect else "PARRY", Color(1.0, 0.82, 0.2) if is_perfect else Color(0.35, 0.85, 1.0))
	_show_parry_flash(is_perfect)
	_spawn_parry_effect(attacker, is_perfect)
	emit_signal("parry_stun_requested", attacker, parry_stun_duration, is_perfect)
	if attacker != null and attacker.has_method("apply_stun"):
		attacker.call("apply_stun", parry_stun_duration)
	emit_signal("parry_success", attacker, is_perfect, attack_data)


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
		var move_basis := camera_pivot.global_transform.basis if camera_pivot != null else global_transform.basis
		dash_direction = move_basis * Vector3(input_vector.x, 0.0, input_vector.y)
		dash_direction.y = 0.0
		dash_direction = dash_direction.normalized()
	else:
		dash_direction = character.global_transform.basis.z.normalized()
		dash_direction.y = 0.0
		if dash_direction.length_squared() < 0.001:
			dash_direction = Vector3.FORWARD

	is_dashing = true
	is_invulnerable = true
	dash_timer = 0.0
	dash_elapsed = 0.0
	dash_base_rotation = character.rotation
	dash_base_position = character.position
	dash_base_scale = character.scale
	dash_invulnerability_timer = 0.0
	dash_cooldown_timer = dash_cooldown
	last_animation = ""
	_play("Run")
	emit_signal("dash_started", dash_direction)
	return true


func _end_dash() -> void:
	is_dashing = false
	is_invulnerable = false
	if character != null:
		character.rotation = dash_base_rotation
		character.position = dash_base_position
		character.scale = dash_base_scale
	velocity.x = 0.0
	velocity.z = 0.0
	_spawn_shadow_decoy()
	emit_signal("dash_finished")


func _update_dash_pose() -> void:
	if character == null:
		return
	var progress := clampf(dash_elapsed / maxf(dash_duration, 0.01), 0.0, 1.0)
	var bob := sin(progress * PI) * 0.16
	character.rotation = dash_base_rotation + Vector3(-0.22, 0.0, 0.0)
	character.position = dash_base_position + Vector3(0.0, bob, 0.0)


func _update_locomotion_pose(delta: float, moving: bool, sprinting: bool) -> void:
	if character == null or is_dashing or attacking or hit_stun_remaining > 0.0:
		return
	if moving and not blocking and not is_parrying:
		var cadence := 10.0 if sprinting else 6.4
		var stride_strength := 1.0 if sprinting else 0.58
		locomotion_phase += delta * cadence
		var step := sin(locomotion_phase)
		var bob := absf(step) * (0.18 if sprinting else 0.11)
		var side_sway := sin(locomotion_phase * 0.5) * (0.16 if sprinting else 0.09)
		var lateral_step := sin(locomotion_phase) * (0.055 if sprinting else 0.035)
		var forward_lean := -0.24 if sprinting else -0.09
		character.rotation.x = lerp(character.rotation.x, forward_lean + step * 0.025, delta * 12.0)
		character.rotation.z = lerp(character.rotation.z, side_sway * stride_strength, delta * 12.0)
		character.position = character.position.lerp(locomotion_base_position + Vector3(lateral_step, bob, 0.0), delta * 14.0)
	else:
		_reset_locomotion_pose(delta)


func _reset_locomotion_pose(delta: float) -> void:
	if character == null or is_dashing:
		return
	character.rotation.x = lerp(character.rotation.x, 0.0, delta * 12.0)
	character.rotation.z = lerp(character.rotation.z, 0.0, delta * 12.0)
	character.position = character.position.lerp(locomotion_base_position, delta * 14.0)


func _spawn_shadow_decoy() -> void:
	if shadow_decoy_script == null:
		return
	var decoy := Node3D.new()
	decoy.name = "ShadowDecoy"
	decoy.set_script(shadow_decoy_script)
	get_tree().current_scene.add_child(decoy)
	decoy.global_position = global_position


## Directional Parry: checks if the player is facing towards the incoming attack source within parry_max_angle degrees.
func is_facing_attack(attacker: Node = null, attack_data: Dictionary = {}) -> bool:
	var incoming_dir := Vector3.ZERO
	if attack_data.has("direction") and attack_data["direction"] is Vector3:
		incoming_dir = -attack_data["direction"]
	elif attacker != null and attacker is Node3D:
		if global_position.distance_to((attacker as Node3D).global_position) > parry_hitbox_radius:
			return false
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
func take_damage(amount: float, attacker: Node = null, _attack_type: String = "melee", attack_data: Dictionary = {}) -> bool:
	if not is_alive or amount <= 0.0:
		return false

	# 1. Shadow Dash Invulnerability
	if is_invulnerable:
		emit_signal("damage_evaded", amount, attacker)
		return false

	# 2. Parry Check (facing incoming attack)
	if is_parrying and is_facing_attack(attacker, attack_data):
		_resolve_parry(attacker, attack_data)
		return false

	# 3. Holding block reduces damage without consuming the block stance.
	var final_damage := amount * block_damage_multiplier if blocking else amount

	# 4. Take Damage
	current_health = clamp(current_health - final_damage, 0.0, max_health)
	_begin_hit_reaction()
	emit_signal("damaged", final_damage, attacker)
	emit_signal("health_changed", current_health, max_health)
	_add_camera_trauma(0.35)
	_trigger_hit_impact()

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
	if hit_stun_remaining > 0.0:
		hit_stun_remaining = maxf(hit_stun_remaining - delta, 0.0)
		if hit_stun_remaining <= 0.0:
			_end_hit_reaction()
	if is_parrying:
		parry_timer += delta
		if parry_timer >= parry_window:
			if Input.is_action_pressed("block"):
				_transition_parry_to_block()
			else:
				_end_parry(true)
	elif parry_cooldown_timer > 0.0:
		parry_cooldown_timer -= delta

	if is_dashing:
		dash_timer += delta
		dash_invulnerability_timer += delta
		if dash_invulnerability_timer >= dash_invulnerability_time:
			is_invulnerable = false
		if dash_timer >= dash_duration:
			_end_dash()
	elif dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta


func _trigger_parry_feedback(is_perfect: bool) -> void:
	_add_camera_trauma(0.55 if is_perfect else 0.25)


func _trigger_hit_impact() -> void:
	_add_camera_trauma(0.7)
	if hit_flash != null:
		hit_flash.color = Color(1.0, 0.08, 0.04, 0.28)
		var flash_tween := create_tween()
		flash_tween.tween_property(hit_flash, "color:a", 0.0, 0.16)
	if hit_stop_active:
		return
	hit_stop_active = true
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = hit_stop_time_scale
	await get_tree().create_timer(hit_stop_duration, true, false, true).timeout
	Engine.time_scale = previous_time_scale
	hit_stop_active = false


func _begin_hit_reaction() -> void:
	hit_stun_remaining = hit_stun_duration
	hit_reaction_elapsed = 0.0
	hit_reaction_base_rotation = character.rotation
	hit_reaction_base_position = character.position
	attacking = false
	is_attacking = false
	is_parrying = false
	_set_parry_hitbox_active(false)
	last_animation = ""
	_play("Idle")


func _update_hit_reaction_pose() -> void:
	if character == null:
		return
	var recoil := sin(minf(hit_reaction_elapsed * 11.0, PI * 0.5)) * 0.18
	var shake := sin(hit_reaction_elapsed * 48.0) * 0.07
	character.rotation = hit_reaction_base_rotation + Vector3(-recoil, 0.0, shake)
	character.position = hit_reaction_base_position + Vector3(shake * 0.05, abs(sin(hit_reaction_elapsed * 34.0)) * 0.035, 0.0)


func _end_hit_reaction() -> void:
	if character != null:
		character.rotation = hit_reaction_base_rotation
		character.position = hit_reaction_base_position


func _spawn_parry_effect(attacker: Node, is_perfect: bool) -> void:
	var effect := Node3D.new()
	effect.name = "ParryClashEffect"
	var effect_position := global_position + (character.global_transform.basis.z * 0.8) + Vector3.UP * 1.1
	if attacker is Node3D:
		effect_position = (global_position + (attacker as Node3D).global_position) * 0.5 + Vector3.UP * 1.0
	get_tree().current_scene.add_child(effect)
	effect.global_position = effect_position

	var burst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.82, 0.2, 0.95) if is_perfect else Color(0.3, 0.8, 1.0, 0.95)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 4.0
	burst.mesh = sphere
	burst.material_override = material
	effect.add_child(burst)

	var sparks := GPUParticles3D.new()
	sparks.name = "ParrySparks"
	sparks.amount = 64 if is_perfect else 46
	sparks.lifetime = 0.68
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	var spark_process := ParticleProcessMaterial.new()
	spark_process.direction = Vector3.UP
	spark_process.spread = 180.0
	spark_process.initial_velocity_min = 4.5 if is_perfect else 3.5
	spark_process.initial_velocity_max = 10.0 if is_perfect else 8.0
	spark_process.gravity = Vector3(0.0, -7.0, 0.0)
	spark_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spark_process.emission_sphere_radius = 0.12
	spark_process.scale_min = 0.45
	spark_process.scale_max = 1.35
	sparks.process_material = spark_process
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.035 if is_perfect else 0.028
	spark_mesh.height = spark_mesh.radius * 2.0
	spark_mesh.material = material
	sparks.draw_pass_1 = spark_mesh
	effect.add_child(sparks)
	sparks.emitting = true

	var light := OmniLight3D.new()
	light.light_color = material.albedo_color
	light.light_energy = 5.0 if is_perfect else 3.0
	light.omni_range = 3.5
	effect.add_child(light)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(effect, "scale", Vector3.ONE * (3.0 if is_perfect else 2.3), 0.22).set_trans(Tween.TRANS_BACK)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.22)
	tween.tween_property(light, "light_energy", 0.0, 0.22)
	get_tree().create_timer(0.55).timeout.connect(effect.queue_free)


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
