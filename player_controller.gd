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
var WALK_SCENE: PackedScene = load("res://assets/player/samurai/animations/Sword And Shield Walk.fbx")
var RUN_SCENE: PackedScene = load("res://assets/player/samurai/animations/Sword And Shield Run.fbx")
var IMPACT_SCENE: PackedScene = load("res://assets/player/samurai/animations/Sword And Shield Impact.fbx")
var JUMP_SCENE: PackedScene = load("res://assets/player/samurai/animations/Jump.fbx")
var ATTACK_SCENE: PackedScene = load("res://assets/player/samurai/animations/One Hand Sword Combo.fbx")
const SWORD_GUARD_SCRIPT = preload("res://sword_guard_pose.gd")
const COMBAT_FX = preload("res://combat_fx.gd")
const SWORD_TRAIL_SCRIPT = preload("res://sword_trail.gd")
const GROUNDING_SCRIPT = preload("res://locomotion_grounding.gd")
const FLAME_AURA_SCRIPT = preload("res://flame_aura.gd")
const CHARGE_AURA_SCRIPT = preload("res://charge_energy_aura.gd")
const ULTIMATE_SCRIPT = preload("res://ultimate_controller.gd")
var JUMP_ATTACK_SCENE: PackedScene = load("res://assets/animations/Lite Sword and Shield Pack/sword and shield attack (2).fbx")
var SWORD_SCENE: PackedScene = load("res://assets/player/weapons/crystal/crystal_elemental_sword.glb")
var FIRE_AIR_SLASH_SCRIPT: Script = preload("res://fire_air_slash.gd")

# --- Movement Configuration ---
@export_group("Movement")
@export var walk_speed: float = 3.8
@export var run_speed: float = 6.2
@export var jump_velocity: float = 4.6
@export var turn_speed: float = 12.0
@export var stopping_friction: float = 45.0
@export var movement_acceleration: float = 28.0
@export var movement_deceleration: float = 42.0
@export var crouch_speed_multiplier: float = 0.45
@export var block_speed_multiplier: float = 0.55
@export var jump_buffer_time: float = 0.14
@export var jump_coyote_time: float = 0.12

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var min_camera_pitch: float = -55.0
@export var max_camera_pitch: float = 35.0
@export var camera_distance: float = 5.8
@export var camera_min_distance: float = 2.5
@export var camera_max_distance: float = 8.5
@export var camera_zoom_step: float = 0.5
@export var camera_rotation_smoothing: float = 20.0
@export var camera_zoom_smoothing: float = 12.0

# --- Weapon & Model Scale ---
@export_group("Visuals")
@export var sword_scale_factor: float = 0.55
@export var shield_scale_factor: float = 0.25
@export var crystal_sword_scale: float = 0.20
@export var crystal_sword_grip_offset: Vector3 = Vector3.ZERO
## Wrist-to-palm offset in the Mixamo right-hand bone's local coordinates.
@export var crystal_sword_palm_position: Vector3 = Vector3(-0.015, 0.13, 0.025)
@export_range(-180.0, 180.0, 1.0) var crystal_sword_roll_degrees: float = 0.0

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
@export var parries_for_riposte: int = 3             ## Successful parries before the attacker takes automatic damage.
@export var parry_riposte_damage: float = 20.0
@export var block_damage_multiplier: float = 0.35    ## Damage received while holding Right Mouse.
@export var hit_stop_duration: float = 0.06         ## Brief freeze-frame after taking damage.
@export var hit_stop_time_scale: float = 0.05        ## Time scale used during the impact frame.
@export var hit_stun_duration: float = 0.28          ## How long controls are locked after a hit.
@export var locomotion_blend_time: float = 0.14      ## Blend time between idle, walk, and run.
@export var combat_blend_time: float = 0.045        ## Short blend for attacks, parries, and hit reactions.
@export var jump_animation_speed_scale: float = 1.85 ## The imported jump clip is authored longer than the gameplay arc.
@export var attack_combo_phases: int = 3
@export var attack_combo_transition_lead: float = 0.18 ## End each phase slightly early for a cleaner state transition.
@export var attack_animation_speed_scale: float = 2.15
@export var player_attack_damage: float = 18.0
@export var player_attack_stun_duration: float = 0.55
@export var player_attack_range: float = 5.2
@export_range(0.0, 1.0, 0.01) var player_attack_hit_fraction: float = 0.55
@export_group("Fire Meter")
@export var fire_meter_max: float = 100.0
@export var fire_per_parry: float = 35.0
@export var fire_attack_cost: float = 25.0
@export var fire_drain_per_second: float = 5.0
@export var fire_full_hold_duration: float = 5.0
@export var fire_slash_damage: float = 55.0
@export var fire_slash_speed: float = 18.0
@export var fire_slash_lifetime: float = 1.2
@export var fire_channel_drain_per_second: float = 32.0

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
var parry_chain_count: int = 0

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
var camera_target_yaw: float = 0.0
var camera_target_pitch: float = 0.0
var camera_target_distance: float = 5.8
var camera_unlocked: bool = false
var show_controls_hud: bool = true
var combat_feedback_label: Label
var combat_feedback_tween: Tween
var combat_stats_label: Label
var fire_meter_bar: ProgressBar
var fire_charge_label: Label
var fill_fire_button: Button
var parry_flash: ColorRect
var hit_flash: ColorRect
var parry_sound: AudioStreamPlayer
var parry_debug_ring: MeshInstance3D
var parry_debug_material: StandardMaterial3D
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
var jump_buffer_remaining: float = 0.0
var jump_coyote_remaining: float = 0.0
var jump_key_was_down: bool = false
var jump_requested: bool = false
var attack_combo_phase: int = 0
var attack_combo_queued: bool = false
var attack_phase_hit: int = 0
var attack_requested: bool = false
var attack_mouse_was_down: bool = false
var fire_meter: float = 0.0
var fire_full_hold_remaining: float = 0.0
var fire_was_full := false
var is_fire_channeling: bool = false
var fire_channel_charge: float = 0.0
var is_using_ultimate := false
var ultimate_power := 0.0
var ultimate_charging := false
var ultimate_kind := ""
var ultimate_controller: Node
var fire_effect_root: Node3D
var body_fire_effect: Node3D
var sword_guard_pose: SkeletonModifier3D
var motion_fx_last_position := Vector3.ZERO
var motion_fx_step_distance := 0.0
var motion_fx_grounded := false
var motion_fx_vertical_speed := 0.0
var motion_fx_left_foot := false
var motion_fx_dash_time := 0.0


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
		camera_target_distance = camera_distance
	if camera_pivot != null:
		camera_target_yaw = camera_pivot.rotation.y
		camera_target_pitch = camera_pivot.rotation.x
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	_ensure_input_actions()
	_setup_parry_hitbox()
	_setup_combat_feedback()
	_setup_parry_audio()
	_setup_combat_stats()
	ultimate_controller = ULTIMATE_SCRIPT.new()
	ultimate_controller.name = "UltimateController"
	add_child(ultimate_controller)
	_setup_weapon_mounts()
	_setup_fire_blade_effect.call_deferred()
	locomotion_base_position = character.position
	
	_import_mixamo_clip(IDLE_SCENE, "Idle", true, true)
	_import_mixamo_clip(WALK_SCENE, "Walk", true, true)
	_import_mixamo_clip(RUN_SCENE, "Run", true, true)
	_import_mixamo_clip(IMPACT_SCENE, "Impact", false, true)
	_import_mixamo_clip(JUMP_SCENE, "Jump", false, true)
	_import_mixamo_clip(ATTACK_SCENE, "Attack", false, true)
	# Keep the idle torso/legs; the guard modifier poses both arms around the sword.
	_import_mixamo_clip(IDLE_SCENE, "Block", true, true)
	_import_mixamo_clip(JUMP_ATTACK_SCENE, "JumpAttack", false, true)
	
	animation_player.animation_finished.connect(_on_animation_finished)
	_play("Idle")
	_align_weapon_mounts()
	motion_fx_last_position = global_position
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
		"fill_fire": KEY_R,
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
		
	var mouse_bindings := {"attack": MOUSE_BUTTON_LEFT, "block": MOUSE_BUTTON_RIGHT, "fire_channel": MOUSE_BUTTON_MIDDLE}
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
	_setup_parry_debug_ring()


func _setup_parry_debug_ring() -> void:
	if parry_debug_ring != null:
		return
	parry_debug_ring = MeshInstance3D.new()
	parry_debug_ring.name = "ParryRangeIndicator"
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(parry_hitbox_radius - 0.035, 0.02)
	ring.outer_radius = parry_hitbox_radius + 0.035
	ring.rings = 64
	ring.ring_segments = 8
	parry_debug_ring.mesh = ring
	parry_debug_ring.position = Vector3(0.0, 0.035, 0.0)
	parry_debug_material = StandardMaterial3D.new()
	parry_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	parry_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	parry_debug_material.albedo_color = Color(0.3, 0.8, 1.0, 0.48)
	parry_debug_material.emission_enabled = true
	parry_debug_material.emission = Color(0.15, 0.55, 1.0)
	parry_debug_material.emission_energy_multiplier = 1.6
	parry_debug_ring.material_override = parry_debug_material
	parry_debug_ring.visible = false
	add_child(parry_debug_ring)


func _set_parry_hitbox_active(active: bool) -> void:
	if parry_hitbox != null:
		parry_hitbox.monitoring = active
		parry_hitbox.monitorable = active
	if parry_debug_ring != null:
		parry_debug_ring.visible = active or blocking
		if active:
			parry_debug_material.albedo_color = Color(1.0, 0.82, 0.2, 0.62)
			parry_debug_material.emission = Color(1.0, 0.55, 0.08)
		else:
			parry_debug_material.albedo_color = Color(0.3, 0.8, 1.0, 0.48)
			parry_debug_material.emission = Color(0.15, 0.55, 1.0)


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
	combat_stats_label.size = Vector2(620.0, 155.0)
	layer.add_child(combat_stats_label)
	fire_meter_bar = ProgressBar.new()
	fire_meter_bar.name = "FireMeter"
	fire_meter_bar.position = Vector2(24.0, 132.0)
	fire_meter_bar.size = Vector2(360.0, 18.0)
	fire_meter_bar.min_value = 0.0
	fire_meter_bar.max_value = fire_meter_max
	fire_meter_bar.value = fire_meter
	fire_meter_bar.show_percentage = false
	var fire_background := StyleBoxFlat.new()
	fire_background.bg_color = Color(0.08, 0.04, 0.03, 0.9)
	fire_background.border_color = Color(0.45, 0.16, 0.04, 0.95)
	fire_background.set_border_width_all(2)
	fire_background.corner_radius_top_left = 5
	fire_background.corner_radius_top_right = 5
	fire_background.corner_radius_bottom_left = 5
	fire_background.corner_radius_bottom_right = 5
	var fire_fill := StyleBoxFlat.new()
	fire_fill.bg_color = Color(1.0, 0.22, 0.025, 0.98)
	fire_fill.border_color = Color(1.0, 0.72, 0.1, 0.95)
	fire_fill.set_border_width_all(1)
	fire_fill.corner_radius_top_left = 5
	fire_fill.corner_radius_top_right = 5
	fire_fill.corner_radius_bottom_left = 5
	fire_fill.corner_radius_bottom_right = 5
	fire_meter_bar.add_theme_stylebox_override("background", fire_background)
	fire_meter_bar.add_theme_stylebox_override("fill", fire_fill)
	layer.add_child(fire_meter_bar)
	fire_charge_label = Label.new()
	fire_charge_label.name = "SlashCharge"
	fire_charge_label.position = Vector2(398.0, 128.0)
	fire_charge_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(fire_charge_label)
	fill_fire_button = Button.new()
	fill_fire_button.name = "FillFireButton"
	fill_fire_button.text = "FILL FIRE  [R]"
	fill_fire_button.tooltip_text = "Instantly refill fire for combat practice."
	fill_fire_button.focus_mode = Control.FOCUS_NONE
	fill_fire_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fill_fire_button.position = Vector2(-185.0, 18.0)
	fill_fire_button.size = Vector2(165.0, 34.0)
	fill_fire_button.add_theme_color_override("font_color", Color(1.0, 0.66, 0.24))
	fill_fire_button.pressed.connect(_fill_fire_meter)
	layer.add_child(fill_fire_button)
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
	var controls_text := "\n\nWASD Move   |   Shift Sprint   |   Ctrl Crouch   |   Space Jump\nF Parry   |   RMB Parry -> Block   |   Q Shadow Dash   |   LMB Attack\nMMB Hold: Channel Fire   |   Release: Air Slash\nE Ultimate: Inferno   |   G Ultimate: Focused Strike\nV Free Camera   |   P Kill All   |   O Collect Relic\nH Show/Hide Controls   |   R Fill Fire" if show_controls_hud else ""
	combat_stats_label.text = "HP: %d / %d\nPARRY: %s  |  PERFECT: %.2fs / %.2fs  |  RANGE: %.1fm\nFIRE: %d / %d  |  BLADE: %s  |  RIPOSTE: %d/%d\nSHADOW: %s  |  CAMERA: %s%s" % [
		roundi(current_health), roundi(max_health), parry_state, perfect_parry_window, parry_window, parry_hitbox_radius,
		roundi(fire_meter), roundi(fire_meter_max), "CHARGING" if is_fire_channeling else ("IGNITED" if fire_meter > 0.0 else "COLD"), parry_chain_count, parries_for_riposte, dash_state, "FREE" if camera_unlocked else "FOLLOW", controls_text
	]
	if fire_meter_bar != null:
		fire_meter_bar.max_value = fire_meter_max
		fire_meter_bar.value = fire_meter
	if fire_charge_label != null:
		fire_charge_label.visible = is_fire_channeling or fire_full_hold_remaining > 0.0
		var charge_ratio := clampf(fire_channel_charge / maxf(fire_meter_max, 1.0), 0.0, 1.0)
		var heat := "WHITE HOT" if charge_ratio >= 0.8 else ("HOT" if charge_ratio >= 0.4 else "EMBER")
		fire_charge_label.text = "SLASH: %d%%  |  %s  |  Release MMB" % [roundi(charge_ratio * 100.0), heat]
		fire_charge_label.modulate = Color(1.0, 0.25, 0.04).lerp(Color(1.0, 0.96, 0.83), charge_ratio)
		if not is_fire_channeling and fire_full_hold_remaining > 0.0:
			fire_charge_label.text = "FULL FIRE  |  Decay in %.1fs" % fire_full_hold_remaining
			fire_charge_label.modulate = Color(1.0,0.82,0.26)
	if fill_fire_button != null:
		fill_fire_button.disabled = not is_alive or is_using_ultimate


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
	# The crystal elemental weapon replaces the previous sword-and-shield
	# loadout; remove any legacy shield instance left by an older scene state.
	var legacy_shield := left_socket.get_node_or_null("Shield")
	if legacy_shield != null:
		legacy_shield.queue_free()
	var grounding := GROUNDING_SCRIPT.new()
	grounding.name = "LocomotionGrounding"
	grounding.set("controller", self)
	skeleton.add_child(grounding)
	sword_guard_pose = SWORD_GUARD_SCRIPT.new()
	sword_guard_pose.name = "SwordGuardPose"
	sword_guard_pose.set("controller", self)
	skeleton.add_child(sword_guard_pose)
	var trail := SWORD_TRAIL_SCRIPT.new()
	trail.name = "FireSwordTrail"
	trail.set("controller", self)
	add_child(trail)


func _setup_fire_blade_effect() -> void:
	if fire_effect_root != null:
		return
	fire_effect_root = FLAME_AURA_SCRIPT.new()
	fire_effect_root.name = "BladeFireEffect"
	fire_effect_root.set("controller", self)
	fire_effect_root.set("kind", "sword")
	add_child(fire_effect_root)
	body_fire_effect = CHARGE_AURA_SCRIPT.new()
	body_fire_effect.name = "ChargeBodyFlames"
	body_fire_effect.set("controller", self)
	add_child(body_fire_effect)


func _get_blade_extreme_point(mesh_instance: MeshInstance3D, origin: Vector3) -> Vector3:
	var local_aabb := mesh_instance.get_aabb()
	var best_point := mesh_instance.global_transform * local_aabb.get_center()
	var best_distance := -INF
	for x in [local_aabb.position.x, local_aabb.end.x]:
		for y in [local_aabb.position.y, local_aabb.end.y]:
			for z in [local_aabb.position.z, local_aabb.end.z]:
				var world_point := mesh_instance.global_transform * Vector3(x, y, z)
				var distance := world_point.distance_squared_to(origin)
				if distance > best_distance:
					best_distance = distance
					best_point = world_point
	return best_point


func _update_fire_blade_effect() -> void:
	if fire_effect_root != null:
		fire_effect_root.call("refresh")
	if body_fire_effect != null:
		body_fire_effect.call("refresh")


func _add_fire_meter(amount: float) -> void:
	if amount <= 0.0:
		return
	fire_meter = clampf(fire_meter + amount, 0.0, fire_meter_max)
	if fire_meter >= fire_meter_max:
		fire_full_hold_remaining = fire_full_hold_duration
		fire_was_full = true
	_update_fire_blade_effect()
	_update_combat_stats()
	_show_combat_feedback("PARRY  +FIRE", Color(1.0, 0.38, 0.06))
	if ultimate_controller != null:
		ultimate_controller.add_fire(amount)


func _find_first_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


func _align_weapon_mounts() -> void:
	# Fit once in bone-local space. Animations move the hand and sword together.
	var skeleton := character.get_node_or_null("Skeleton3D") as Skeleton3D
	var socket := skeleton.get_node_or_null("RightHandSocket") as BoneAttachment3D if skeleton != null else null
	if socket == null:
		return
	var sword := socket.get_node_or_null("Sword") as Node3D
	if sword == null:
		return
	var handle := sword.find_child("HandleLP", true, false) as Node3D
	var blade := sword.find_child("BladeLP", true, false) as Node3D
	var handle_mesh := _find_first_mesh(handle) if handle != null else null
	var blade_mesh := _find_first_mesh(blade) if blade != null else null
	if handle_mesh == null or blade_mesh == null:
		push_error("Crystal sword is missing its handle or blade mesh.")
		return
	var handle_in_sword := sword.global_transform.affine_inverse() * handle_mesh.global_transform
	var blade_in_sword := sword.global_transform.affine_inverse() * blade_mesh.global_transform
	var grip_center := handle_in_sword * handle_mesh.get_aabb().get_center()
	var source_axis := -(handle_in_sword.basis * Vector3.BACK).normalized()
	var source_normal := (blade_in_sword.basis * Vector3.UP).normalized()
	source_normal = (source_normal - source_axis * source_normal.dot(source_axis)).normalized()
	var source_basis := Basis(source_axis, source_normal.cross(source_axis).normalized(), source_normal)
	var normal := Vector3.FORWARD.rotated(Vector3.RIGHT, deg_to_rad(crystal_sword_roll_degrees))
	var palm_basis := Basis(Vector3.RIGHT, normal.cross(Vector3.RIGHT), normal)
	sword.basis = (palm_basis * source_basis.inverse()) * crystal_sword_scale
	sword.position = crystal_sword_palm_position + crystal_sword_grip_offset - sword.basis * grip_center


func _set_sword_guard_pose(active: bool) -> void:
	if sword_guard_pose != null:
		sword_guard_pose.set("guard_active", active)


func _import_mixamo_clip(source_scene: PackedScene, clip_name: String, loop := false, remove_root_motion := false) -> void:
	if source_scene == null:
		return
	var source_root := source_scene.instantiate()
	var source_player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player != null and source_player.has_animation("mixamo_com"):
		var target_animation: Animation = source_player.get_animation("mixamo_com").duplicate(true)
		# These clips use the same Mixamo bone family as the player. Keep the
		# authored pose intact: applying a second rest-pose retarget here makes
		# compatible clips twist/fold on rigs whose bind pose differs slightly.
		# We still normalize the bone paths below and strip locomotion root motion.
		var root_motion_source: Animation
		var root_motion_track_index := -1
		var root_position_tracks_to_remove: Array[int] = []
		for track_index in range(target_animation.get_track_count()):
			var track_path := String(target_animation.track_get_path(track_index))
			var bone_separator := track_path.find(":")
			if bone_separator >= 0:
				# Mixamo exports use both `mixamorig:Hips` and `mixamorig_Hips`
				# depending on the FBX exporter. The player skeleton uses the
				# underscore form, so normalize before retargeting and root-motion
				# removal. Without this, hip translation leaks into the character,
				# making locomotion sink, bob, or drift sideways.
				var bone_name := track_path.substr(bone_separator + 1).replace("mixamorig:", "mixamorig_")
				var is_root_position := target_animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D and (
					bone_name == "mixamorig_Hips" or bone_name.to_lower().ends_with("hips") or bone_name.to_lower().ends_with("root")
				)
				if is_root_position:
					if target_animation.track_get_key_count(track_index) > 0:
						if clip_name in ["Attack", "JumpAttack"]:
							root_motion_source = target_animation.duplicate(true)
							root_motion_track_index = track_index
						if remove_root_motion:
							# Locomotion is driven by the CharacterBody3D. Removing the
							# source hip translation prevents source-model floor offsets
							# from moving the target mesh underground or sideways.
							root_position_tracks_to_remove.append(track_index)
				target_animation.track_set_path(track_index, NodePath("Skeleton3D:" + bone_name))
		for remove_index in range(root_position_tracks_to_remove.size() - 1, -1, -1):
			target_animation.remove_track(root_position_tracks_to_remove[remove_index])
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


func _process(_delta: float) -> void:
	if not is_alive:
		return

	if hit_stun_remaining > 0.0:
		return
	_process_screen_shake(_delta)
	_update_combat_stats()


func _input(event: InputEvent) -> void:
	if is_using_ultimate:
		return
	# Capture attack at the earliest input stage. This remains reliable when
	# the first click also changes mouse capture or when a Control consumes the
	# event before _unhandled_input receives it.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and fill_fire_button != null and fill_fire_button.get_global_rect().has_point(event.position):
			return
		attack_requested = true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			_begin_fire_channel()
		else:
			_release_fire_channel()


func _unhandled_input(event: InputEvent) -> void:
	if is_using_ultimate:
		return
	# Capture Space at the event boundary as well as through InputMap. This
	# prevents a jump press from being lost between render and physics ticks.
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_E or key_event.keycode == KEY_G:
			ultimate_controller.try_activate("area" if key_event.keycode == KEY_E else "focused")
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode == KEY_V:
			camera_unlocked = not camera_unlocked
			_show_combat_feedback("FREE CAMERA" if camera_unlocked else "CAMERA FOLLOW", Color(0.35, 0.8, 1.0))
			return
		if key_event.keycode == KEY_P:
			_kill_all_enemies()
			return
		if key_event.keycode == KEY_R:
			_fill_fire_meter()
			return
		if key_event.keycode == KEY_H:
			show_controls_hud = not show_controls_hud
			_update_combat_stats()
			return
		if key_event.physical_keycode == KEY_SPACE or key_event.keycode == KEY_SPACE:
			jump_buffer_remaining = jump_buffer_time
			jump_requested = true
			return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# The first click also captures the mouse; do not lose its attack input.
			attack_requested = true
		if camera_arm != null and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_target_distance = clamp(camera_target_distance - camera_zoom_step, camera_min_distance, camera_max_distance)
			return
		if camera_arm != null and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_target_distance = clamp(camera_target_distance + camera_zoom_step, camera_min_distance, camera_max_distance)
			return
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if camera_pivot != null:
			camera_target_yaw -= event.relative.x * mouse_sensitivity
			camera_target_pitch = clamp(
				camera_target_pitch - event.relative.y * mouse_sensitivity,
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


func _begin_fire_channel() -> void:
	if not is_alive or is_using_ultimate or is_fire_channeling or fire_meter <= 0.0:
		return
	if is_dashing or attacking or is_parrying or blocking or hit_stun_remaining > 0.0:
		return
	is_fire_channeling = true
	fire_full_hold_remaining = 0.0
	fire_channel_charge = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	attack_requested = false
	animation_player.speed_scale = 1.0
	last_animation = ""
	_play("Idle")
	_update_combat_stats()
	_show_combat_feedback("FIRE CHANNEL", Color(1.0, 0.35, 0.04))


func _update_passive_fire(delta: float) -> void:
	if is_fire_channeling:
		return
	var full := fire_meter >= fire_meter_max - 0.001
	if full and not fire_was_full:
		fire_full_hold_remaining = fire_full_hold_duration
	fire_was_full = full
	if not full:
		fire_full_hold_remaining = 0.0
	var protected_time := minf(fire_full_hold_remaining, delta)
	fire_full_hold_remaining = maxf(fire_full_hold_remaining - delta, 0.0)
	if fire_meter > 0.0 and fire_drain_per_second > 0.0:
		fire_meter = maxf(fire_meter - fire_drain_per_second * (delta - protected_time), 0.0)
	_update_fire_blade_effect()
	_update_combat_stats()


func _update_fire_channel(delta: float) -> void:
	# Transfer fire into the pending shot, even if the reserve reaches zero.
	# An empty meter keeps the stance held until the mouse button is released.
	var spent := minf(fire_meter, minf(fire_channel_drain_per_second * delta, maxf(fire_meter_max - fire_channel_charge, 0.0)))
	fire_meter = maxf(fire_meter - spent, 0.0)
	fire_channel_charge = minf(fire_channel_charge + spent, fire_meter_max)
	_update_fire_blade_effect()
	_update_combat_stats()


func _release_fire_channel() -> void:
	if not is_fire_channeling:
		return
	is_fire_channeling = false
	var spent_fire := fire_channel_charge
	fire_channel_charge = 0.0
	if spent_fire > 0.0:
		_fire_air_slash(spent_fire)
	else:
		_show_combat_feedback("NO CHARGE", Color(0.82, 0.82, 0.82))
	_update_combat_stats()


func _fire_air_slash(spent_fire: float) -> void:
	if sword_guard_pose != null:
		sword_guard_pose.call("play_release")
	var fire_ratio := clampf(spent_fire / maxf(fire_meter_max, 1.0), 0.0, 1.0)
	var slash_damage := fire_slash_damage * fire_ratio
	var direction := _get_fire_slash_direction()
	var slash := Node3D.new()
	slash.name = "FireAirSlash"
	slash.set_script(FIRE_AIR_SLASH_SCRIPT)
	slash.set("direction", direction)
	slash.set("damage", slash_damage)
	slash.set("source_player", self)
	slash.set("speed", fire_slash_speed)
	slash.set("lifetime", fire_slash_lifetime)
	slash.set("charge_ratio", fire_ratio)
	get_tree().current_scene.add_child(slash)
	var spawn_height := maxf(1.0, float(slash.get("slash_height")) * 0.5 + 0.12)
	slash.global_position = global_position + Vector3.UP * spawn_height + direction * 0.85
	# Node3D looks down -Z; invert the travel direction so the slash faces
	# toward the enemy while its projectile motion continues along +direction.
	slash.look_at(slash.global_position - direction, Vector3.UP)
	_update_fire_blade_effect()
	_update_combat_stats()
	_show_combat_feedback("FIRE SLASH", Color(1.0, 0.38, 0.04))


func _get_fire_slash_direction() -> Vector3:
	# Manual aim only. Free camera preserves the character's facing, while
	# follow camera fires along the current camera yaw, with no enemy selection.
	var forward := character.global_basis.z
	if not camera_unlocked and camera_pivot != null:
		forward = -camera_pivot.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD


func _physics_process(delta: float) -> void:
	if is_using_ultimate:
		velocity = Vector3.ZERO
		return
	_update_timers(delta)
	_update_camera(delta)
	_update_motion_effects(delta)
	var jump_key_down := Input.is_key_pressed(KEY_SPACE)
	var jump_pressed := Input.is_action_just_pressed("jump") or (jump_key_down and not jump_key_was_down)
	var attack_mouse_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var attack_mouse_pressed := attack_mouse_down and not attack_mouse_was_down
	var attack_pressed := attack_requested or attack_mouse_pressed or Input.is_action_just_pressed("attack")
	attack_mouse_was_down = attack_mouse_down
	attack_requested = false
	jump_key_was_down = jump_key_down
	if jump_pressed:
		jump_buffer_remaining = jump_buffer_time
		jump_requested = true
	if is_on_floor():
		jump_coyote_remaining = jump_coyote_time
	else:
		jump_coyote_remaining = maxf(jump_coyote_remaining - delta, 0.0)
	
	if not is_alive:
		if not is_on_floor():
			velocity.y -= gravity * delta
			move_and_slide()
		return

	_update_passive_fire(delta)

	# Middle mouse is a deliberate fire-channel stance: movement and combat
	# input are locked while the remaining meter burns down.
	if is_fire_channeling:
		_update_fire_channel(delta)
		_face_camera_direction(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		_play("Idle")
		move_and_slide()
		apply_floor_snap()
		return

	# Hit reactions own the physics tick. Keeping this before input sampling
	# prevents normal movement, jump, attack, or dash input from overriding the
	# intended control lock during the impact animation.
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
		apply_floor_snap()
		return

	# Resolve parries from the attacker's animation contact window rather than
	# waiting for a damage callback. This makes the mechanic deterministic even
	# if the enemy animation and physics tick do not land on the same frame.
	if is_parrying:
		_check_active_parry_contacts()

	_face_camera_direction(delta)

	# Resolve jump before locomotion/combat branches so a Space press cannot be
	# swallowed by an animation state or by the movement floor-snap pass.
	var jump_started := false
	if jump_requested and (is_on_floor() or jump_coyote_remaining > 0.0) and not blocking and not attacking and not is_dashing:
		velocity.y = jump_velocity
		jump_buffer_remaining = 0.0
		jump_coyote_remaining = 0.0
		jump_requested = false
		jump_started = true
		COMBAT_FX.burst(get_tree().current_scene, global_position + Vector3.UP * 0.04, Color(0.5, 0.45, 0.38, 0.5), 8, 0.55, true)
		animation_player.speed_scale = jump_animation_speed_scale
		last_animation = ""
		_play("Jump")

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
		if attack_pressed and attack_combo_phase > 0:
			_advance_attack_combo()
		_update_player_attack_hit()
		_update_attack_combo(delta)
		_reset_locomotion_pose(delta)
		_apply_attack_root_motion()
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		apply_floor_snap()
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
		velocity.x = move_toward(velocity.x, direction.x * speed, movement_acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, movement_acceleration * delta)
	else:
		# Controlled deceleration prevents both skating and abrupt animation snaps.
		var braking := maxf(stopping_friction, movement_deceleration)
		velocity.x = move_toward(velocity.x, 0.0, braking * delta)
		velocity.z = move_toward(velocity.z, 0.0, braking * delta)

	if not is_on_floor() or jump_started:
		velocity.y -= gravity * delta
	else:
		# Prevent stale upward velocity from being cancelled by floor snapping.
		velocity.y = minf(velocity.y, 0.0)

	# Attack triggers
	if Input.is_action_just_pressed("jump_attack") and not attacking and not blocking and not is_dashing:
		_begin_attack("JumpAttack")
		velocity.y = jump_velocity
	elif attack_pressed and not attacking and not blocking and not is_dashing:
		_begin_attack("Attack")

	# Shadow Dash trigger
	if Input.is_action_just_pressed("dash") and not is_dashing and dash_cooldown_timer <= 0.0:
		try_start_dash()

	move_and_slide()
	if not jump_started:
		apply_floor_snap()
	_update_locomotion_pose(delta, moving, sprinting)
	if not attacking and not is_dashing and is_on_floor():
		var planar_speed := Vector2(velocity.x, velocity.z).length()
		if planar_speed < 0.18:
			animation_player.speed_scale = 1.0
			_play("Block" if blocking else "Idle")
		else:
			var use_run := sprinting and not blocking and planar_speed > walk_speed * 0.85
			var gait_speed := clampf(planar_speed / run_speed, 0.45, 1.1) if use_run else clampf(planar_speed / walk_speed * 0.72, 0.32, 0.95)
			var backwards := character.global_basis.z.dot(Vector3(velocity.x, 0.0, velocity.z)) < -0.2
			animation_player.speed_scale = -gait_speed if backwards else gait_speed
			_play("Run" if use_run else "Walk")


func _face_camera_direction(delta: float) -> void:
	if camera_unlocked or camera_pivot == null or character == null:
		return
	var camera_forward := -camera_pivot.global_transform.basis.z
	camera_forward.y = 0.0
	if camera_forward.length_squared() < 0.001:
		return
	var target_yaw := atan2(camera_forward.x, camera_forward.z)
	character.rotation.y = rotate_toward(character.rotation.y, target_yaw, turn_speed * delta)


func _kill_all_enemies() -> void:
	var defeated := 0
	for candidate in get_tree().get_nodes_in_group("enemy"):
		if candidate == null or not is_instance_valid(candidate):
			continue
		if candidate.has_method("take_damage"):
			candidate.call("take_damage", 999999.0, self)
			defeated += 1
	_show_combat_feedback("KILL ALL  (%d)" % defeated, Color(1.0, 0.3, 0.12))


func _fill_fire_meter() -> void:
	if not is_alive or is_using_ultimate:
		return
	fire_meter = fire_meter_max
	fire_full_hold_remaining = fire_full_hold_duration
	fire_was_full = true
	_update_fire_blade_effect()
	_update_combat_stats()
	_show_combat_feedback("FIRE REFILLED", Color(1.0, 0.65, 0.18))
	COMBAT_FX.burst(get_tree().current_scene, global_position + Vector3.UP, Color(1.0, 0.42, 0.04), 18, 0.55)
	ultimate_controller.add_fire(fire_meter_max)


func _update_camera(delta: float) -> void:
	if camera_pivot != null:
		var rotation_weight := clampf(delta * camera_rotation_smoothing, 0.0, 1.0)
		camera_pivot.rotation.y = lerp_angle(camera_pivot.rotation.y, camera_target_yaw, rotation_weight)
		camera_pivot.rotation.x = lerp(camera_pivot.rotation.x, camera_target_pitch, rotation_weight)
	if camera_arm != null:
		var zoom_weight := clampf(delta * camera_zoom_smoothing, 0.0, 1.0)
		camera_arm.spring_length = lerp(camera_arm.spring_length, camera_target_distance, zoom_weight)


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
		var blend_time := combat_blend_time if animation_name in ["Attack", "Jump", "JumpAttack", "Block", "Impact"] else locomotion_blend_time
		animation_player.play(animation_name, blend_time)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == "DashRoll":
		last_animation = ""
	elif animation_name in ["Attack", "JumpAttack"]:
		_finish_attack(animation_name)


func _begin_attack(animation_name: String) -> void:
	if is_using_ultimate:
		return
	attacking = true
	is_attacking = true
	animation_player.speed_scale = 1.0
	if animation_name == "Attack":
		attack_combo_phase = 1
		attack_combo_queued = false
		attack_phase_hit = 0
		animation_player.speed_scale = attack_animation_speed_scale
	attack_start_basis = character.global_basis
	var motion_data: Dictionary = attack_root_motion_tracks.get(animation_name, {})
	var source_animation: Animation = motion_data.get("animation") as Animation
	var track_index: int = motion_data.get("track", -1)
	attack_last_root_motion_position = source_animation.track_get_key_value(track_index, 0) if source_animation != null and track_index >= 0 else Vector3.ZERO
	_play(animation_name)
	if animation_name == "Attack":
		animation_player.seek(0.0, true)
	emit_signal("attack_pressed")


func _attack_combo_phase_duration() -> float:
	if not animation_player.has_animation("Attack") or attack_combo_phases <= 0:
		return 0.0
	return animation_player.get_animation("Attack").length / float(attack_combo_phases)


func _advance_attack_combo() -> void:
	if not attacking or attack_combo_phase <= 0 or not animation_player.has_animation("Attack") or attack_combo_phase >= attack_combo_phases:
		return
	# Buffer one follow-up without seeking or restarting the playing swing.
	attack_combo_queued = true


func _update_attack_combo(_delta: float) -> void:
	if not attacking or attack_combo_phase <= 0 or not animation_player.has_animation("Attack"):
		return
	if not animation_player.is_playing():
		_finish_attack("Attack")
		return
	var phase_duration := _attack_combo_phase_duration()
	if phase_duration <= 0.0:
		return
	var phase_end := minf(phase_duration * float(attack_combo_phase), animation_player.get_animation("Attack").length)
	var transition_point := maxf(phase_end - attack_combo_transition_lead, 0.0)
	if animation_player.current_animation_position < transition_point:
		return
	if attack_combo_queued and attack_combo_phase < attack_combo_phases:
		# Continue the authored clip through its connecting motion. The previous
		# implementation paused and jumped over this motion, freezing every swing.
		attack_combo_phase += 1
		attack_phase_hit = 0
		attack_combo_queued = false
		emit_signal("attack_pressed")
	else:
		_finish_attack("Attack")


func _update_player_attack_hit() -> void:
	if not attacking or attack_combo_phase <= 0 or not animation_player.has_animation("Attack"):
		return
	if attack_phase_hit == attack_combo_phase:
		return
	var phase_duration := _attack_combo_phase_duration()
	if phase_duration <= 0.0:
		return
	var phase_start := phase_duration * float(attack_combo_phase - 1)
	var hit_time := phase_start + phase_duration * player_attack_hit_fraction
	if animation_player.current_animation_position < hit_time:
		return
	# Consume the contact point once even when the meter is empty. The attack
	# should finish cleanly instead of repeatedly trying to apply damage.
	attack_phase_hit = attack_combo_phase
	_process_player_attack_hit()


func _process_player_attack_hit() -> bool:
	if fire_meter <= 0.0:
		_show_combat_feedback("NO FIRE", Color(0.82, 0.82, 0.82))
		return false
	# Use whatever charge is available. A partially filled meter produces a
	# proportionally weaker hit instead of cancelling the attack entirely.
	var available_fire_ratio := clampf(fire_meter / maxf(fire_attack_cost, 0.001), 0.0, 1.0)
	var damage_from_fire := player_attack_damage * available_fire_ratio
	var fire_to_consume := minf(fire_attack_cost, fire_meter)
	var hit_confirmed := false
	for candidate in get_tree().get_nodes_in_group("enemy"):
		if candidate == null or not is_instance_valid(candidate) or not candidate is Node3D:
			continue
		var enemy := candidate as Node3D
		var enemy_center := enemy.global_position
		var enemy_collider := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if enemy_collider != null:
			enemy_center = enemy.to_global(enemy_collider.position)
		var to_enemy := enemy_center - global_position
		to_enemy.y = 0.0
		var distance := to_enemy.length()
		if distance > player_attack_range or distance < 0.01:
			continue
		if enemy.has_method("apply_stun"):
			enemy.call("apply_stun", player_attack_stun_duration)
		if enemy.has_method("take_damage"):
			enemy.call("take_damage", damage_from_fire, self)
		COMBAT_FX.burst(get_tree().current_scene, enemy_center + Vector3.UP * 0.25, Color(1.0, 0.48, 0.045), 26, 0.85)
		fire_meter = maxf(fire_meter - fire_to_consume, 0.0)
		_update_fire_blade_effect()
		_update_combat_stats()
		_show_combat_feedback("HIT", Color(1.0, 0.72, 0.25))
		_add_camera_trauma(0.18)
		hit_confirmed = true
		break
	return hit_confirmed


func _finish_attack(animation_name: StringName) -> void:
	# If the combo exits during phase 1 or 2, sample the current position. Using
	# the full clip here would apply several seconds of unused root motion and
	# visibly snap the player forward as they return to idle.
	if animation_name == "Attack":
		_apply_attack_root_motion()
	else:
		_apply_attack_root_motion(animation_name)
	attacking = false
	is_attacking = false
	attack_combo_phase = 0
	attack_combo_queued = false
	attack_phase_hit = 0
	animation_player.speed_scale = 1.0
	last_animation = ""
	_play("Block" if blocking else "Idle")


func _set_attack_root_motion_sample(sample_time: float) -> void:
	var motion_data: Dictionary = attack_root_motion_tracks.get("Attack", {})
	var source_animation: Animation = motion_data.get("animation") as Animation
	var track_index: int = motion_data.get("track", -1)
	if source_animation == null or track_index < 0 or source_animation.track_get_key_count(track_index) == 0:
		return
	var key_count := source_animation.track_get_key_count(track_index)
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
	attack_last_root_motion_position = sampled_position


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
	if not is_alive or is_using_ultimate or is_parrying or is_dashing or attacking or is_fire_channeling or parry_cooldown_timer > 0.0:
		return false
	if blocking:
		_end_block()
	blocking = true
	is_parrying = true
	animation_player.speed_scale = 1.0
	parry_timer = 0.0
	_set_parry_hitbox_active(true)
	last_animation = ""
	_play("Block")
	_set_sword_guard_pose(true)
	emit_signal("parry_started")
	return true


func _start_block() -> void:
	blocking = true
	animation_player.speed_scale = 1.0
	last_animation = ""
	_play("Block")
	_set_sword_guard_pose(true)
	_set_parry_hitbox_active(false)


func _end_block() -> void:
	blocking = false
	_set_sword_guard_pose(false)
	last_animation = ""
	_play("Idle")
	_set_parry_hitbox_active(false)


func _end_parry(missed: bool) -> void:
	blocking = false
	is_parrying = false
	_set_sword_guard_pose(false)
	_set_parry_hitbox_active(false)
	last_animation = ""
	if missed:
		parry_chain_count = 0
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
	_set_sword_guard_pose(true)


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
	_add_fire_meter(fire_per_parry + (10.0 if is_perfect else 0.0))
	parry_chain_count += 1
	if attacker != null and parry_chain_count >= maxi(parries_for_riposte, 1):
		if attacker.has_method("take_damage"):
			attacker.call("take_damage", parry_riposte_damage, self)
		parry_chain_count = 0
		_show_combat_feedback("RIPOSTE", Color(1.0, 0.3, 0.05))
		_add_camera_trauma(0.3)
	emit_signal("parry_stun_requested", attacker, parry_stun_duration, is_perfect)
	if attacker != null and attacker.has_method("apply_stun"):
		attacker.call("apply_stun", parry_stun_duration)
	emit_signal("parry_success", attacker, is_perfect, attack_data)
	if is_instance_valid(attacker) and attacker.has_method("on_parried"):
		attacker.call("on_parried", self, is_perfect)


# --- Shadow Dash ---
func try_start_dash() -> bool:
	if not is_alive or is_using_ultimate or is_dashing or dash_cooldown_timer > 0.0:
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
	# Spawn the after-image at dash start so it is immediately available as a
	# decoy target and visually tracks the beginning of the dash.
	_spawn_shadow_decoy()
	COMBAT_FX.burst(get_tree().current_scene, global_position + Vector3.UP * 0.7, Color(0.36, 0.22, 0.65, 0.65), 22, 0.7)
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
	emit_signal("dash_finished")


func _update_dash_pose() -> void:
	if character == null:
		return
	var progress := clampf(dash_elapsed / maxf(dash_duration, 0.01), 0.0, 1.0)
	var bob := sin(progress * PI) * 0.16
	character.rotation = dash_base_rotation + Vector3(-0.22, 0.0, 0.0)
	character.position = dash_base_position + Vector3(0.0, bob, 0.0)


func _update_motion_effects(delta: float) -> void:
	var grounded := is_on_floor()
	var displacement := global_position - motion_fx_last_position
	motion_fx_last_position = global_position
	if not is_alive:
		return
	if grounded and not motion_fx_grounded and motion_fx_vertical_speed < -1.5:
		COMBAT_FX.burst(get_tree().current_scene, global_position + Vector3.UP * 0.04, Color(0.5, 0.45, 0.38, 0.55), 16, 0.9, true)
	motion_fx_grounded = grounded
	motion_fx_vertical_speed = velocity.y
	if is_dashing:
		motion_fx_dash_time += delta
		if motion_fx_dash_time >= 0.045:
			motion_fx_dash_time = 0.0
			COMBAT_FX.burst(get_tree().current_scene, global_position + Vector3.UP * 0.6, Color(0.26, 0.16, 0.48, 0.45), 6, 0.35)
		return
	if not grounded or attacking or is_fire_channeling:
		motion_fx_step_distance = 0.0
		return
	displacement.y = 0.0
	motion_fx_step_distance += minf(displacement.length(), 0.25)
	var stride := 1.45 if Vector2(velocity.x, velocity.z).length() > walk_speed else 0.95
	if motion_fx_step_distance < stride:
		return
	motion_fx_step_distance = 0.0
	motion_fx_left_foot = not motion_fx_left_foot
	var skeleton := character.get_node("Skeleton3D") as Skeleton3D
	var foot_name := "mixamorig_LeftToeBase" if motion_fx_left_foot else "mixamorig_RightToeBase"
	var foot_index := skeleton.find_bone(foot_name)
	var foot_position := global_position
	if foot_index >= 0:
		foot_position = skeleton.to_global(skeleton.get_bone_global_pose(foot_index).origin)
	foot_position.y = global_position.y + 0.035
	COMBAT_FX.burst(get_tree().current_scene, foot_position, Color(0.46, 0.42, 0.36, 0.5), 6, 0.5, true)


func _update_locomotion_pose(delta: float, moving: bool, sprinting: bool) -> void:
	if character == null or is_dashing or attacking or hit_stun_remaining > 0.0:
		return
	if moving and not blocking and not is_parrying:
		var cadence := 10.0 if sprinting else 6.4
		locomotion_phase += delta * cadence
		var forward_lean := -0.12 if sprinting else -0.04
		character.rotation.x = lerp(character.rotation.x, forward_lean, delta * 12.0)
		character.rotation.z = lerp(character.rotation.z, 0.0, delta * 12.0)
		character.position = character.position.lerp(locomotion_base_position, delta * 14.0)
	else:
		_reset_locomotion_pose(delta)
	_enforce_visual_grounding(delta)


func _enforce_visual_grounding(delta: float) -> void:
	# Animation clips must not move the visual root below the CharacterBody3D's
	# floor contact. This also removes the last frame-to-frame roll drift from
	# imported run clips without fighting their actual limb animation.
	if character == null or is_dashing or attacking or hit_stun_remaining > 0.0:
		return
	character.position.y = lerp(character.position.y, locomotion_base_position.y, clampf(delta * 20.0, 0.0, 1.0))
	character.rotation.z = lerp(character.rotation.z, 0.0, clampf(delta * 20.0, 0.0, 1.0))


func _reset_locomotion_pose(delta: float) -> void:
	if character == null or is_dashing:
		return
	character.rotation.x = lerp(character.rotation.x, 0.0, delta * 12.0)
	character.rotation.z = lerp(character.rotation.z, 0.0, delta * 12.0)
	character.position = character.position.lerp(locomotion_base_position, delta * 14.0)


func _spawn_shadow_decoy() -> void:
	if shadow_decoy_script == null or character == null or get_tree().current_scene == null:
		return
	var decoy := Node3D.new()
	decoy.name = "ShadowDecoy"
	decoy.set_script(shadow_decoy_script)
	decoy.source_character = character
	get_tree().current_scene.add_child(decoy)
	decoy.global_position = global_position
	decoy.global_rotation = character.global_rotation


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
	var unparryable := bool(attack_data.get("unparryable", false))

	# 2. Parry Check (facing incoming attack)
	if is_parrying and not unparryable and is_facing_attack(attacker, attack_data):
		_resolve_parry(attacker, attack_data)
		return false

	# 3. Holding block reduces damage without consuming the block stance.
	var was_blocking := blocking and not unparryable
	var final_damage := amount * block_damage_multiplier if was_blocking else amount

	# 4. Take Damage
	parry_chain_count = 0
	current_health = clamp(current_health - final_damage, 0.0, max_health)
	_begin_hit_reaction(was_blocking)
	emit_signal("damaged", final_damage, attacker)
	emit_signal("health_changed", current_health, max_health)
	_add_camera_trauma(0.35)
	_show_combat_feedback("BLOCK" if was_blocking else "HIT", Color(0.35, 0.8, 1.0) if was_blocking else Color(1.0, 0.3, 0.2))
	_spawn_hit_effect(attacker, was_blocking)
	_trigger_hit_impact(was_blocking)

	if current_health <= 0.0:
		_die()

	return true


func heal(amount: float) -> void:
	if not is_alive or amount <= 0.0:
		return
	current_health = clamp(current_health + amount, 0.0, max_health)
	emit_signal("health_changed", current_health, max_health)


func _die() -> void:
	if not is_alive:
		return
	is_alive = false
	is_fire_channeling = false
	fire_channel_charge = 0.0
	_update_fire_blade_effect()
	_update_combat_stats()
	velocity = Vector3.ZERO
	parry_chain_count = 0
	is_parrying = false
	blocking = false
	is_dashing = false
	attacking = false
	is_attacking = false
	Engine.time_scale = 1.0
	if character != null:
		var death_rotation := character.rotation + Vector3(-PI * 0.5, 0.0, 0.0)
		var death_position := character.position + Vector3(0.0, -0.38, 0.0)
		var death_tween := create_tween().set_parallel(true)
		death_tween.tween_property(character, "rotation", death_rotation, 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		death_tween.tween_property(character, "position", death_position, 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	emit_signal("died")
	var main := get_tree().current_scene
	if main != null and main.has_method("show_death_screen"):
		main.call("show_death_screen")


func _update_timers(delta: float) -> void:
	jump_buffer_remaining = maxf(jump_buffer_remaining - delta, 0.0)
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


func _trigger_hit_impact(was_blocking: bool = false) -> void:
	_add_camera_trauma(0.32 if was_blocking else 0.7)
	if hit_flash != null:
		hit_flash.color = Color(0.05, 0.42, 1.0, 0.16) if was_blocking else Color(1.0, 0.08, 0.04, 0.28)
		var flash_tween := create_tween()
		flash_tween.tween_property(hit_flash, "color:a", 0.0, 0.10 if was_blocking else 0.16)
	if hit_stop_active:
		return
	hit_stop_active = true
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = hit_stop_time_scale
	await get_tree().create_timer(hit_stop_duration, true, false, true).timeout
	Engine.time_scale = previous_time_scale
	hit_stop_active = false


func _begin_hit_reaction(keep_blocking: bool = false) -> void:
	is_fire_channeling = false
	fire_channel_charge = 0.0
	_update_fire_blade_effect()
	_update_combat_stats()
	hit_stun_remaining = hit_stun_duration
	hit_reaction_elapsed = 0.0
	hit_reaction_base_rotation = character.rotation
	hit_reaction_base_position = character.position
	attacking = false
	is_attacking = false
	animation_player.speed_scale = 1.0
	is_parrying = false
	blocking = keep_blocking
	_set_sword_guard_pose(blocking)
	_set_parry_hitbox_active(false)
	last_animation = ""
	# Keep the hit reaction on the player's stable authored pose. The supplied
	# Impact FBX is useful as a reference but its bind pose can fold this rig;
	# the procedural recoil below provides the visible stun without moving the
	# character root through the floor.
	_play("Block" if blocking else "Idle")


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
	last_animation = ""
	_set_sword_guard_pose(blocking)
	_play("Block" if blocking else "Idle")


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
	sphere.radius = 0.30
	sphere.height = 0.60
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

	# A large expanding clash ring makes the successful parry readable even
	# when the sword models overlap or the camera is moving.
	var shockwave := MeshInstance3D.new()
	shockwave.name = "ParryShockwave"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.22
	ring.outer_radius = 0.34
	ring.rings = 48
	ring.ring_segments = 12
	shockwave.mesh = ring
	shockwave.rotation.x = PI * 0.5
	shockwave.material_override = material
	effect.add_child(shockwave)

	var sparks := GPUParticles3D.new()
	sparks.name = "ParrySparks"
	sparks.amount = 128 if is_perfect else 96
	sparks.lifetime = 0.82
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	var spark_process := ParticleProcessMaterial.new()
	spark_process.direction = Vector3.UP
	spark_process.spread = 180.0
	spark_process.initial_velocity_min = 6.0 if is_perfect else 4.5
	spark_process.initial_velocity_max = 14.0 if is_perfect else 11.0
	spark_process.gravity = Vector3(0.0, -8.0, 0.0)
	spark_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spark_process.emission_sphere_radius = 0.12
	spark_process.scale_min = 0.70
	spark_process.scale_max = 1.80
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
	light.light_energy = 9.0 if is_perfect else 6.0
	light.omni_range = 5.0
	effect.add_child(light)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(effect, "scale", Vector3.ONE * (4.8 if is_perfect else 3.8), 0.34).set_trans(Tween.TRANS_BACK)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.34)
	tween.tween_property(light, "light_energy", 0.0, 0.34)
	get_tree().create_timer(0.90).timeout.connect(effect.queue_free)


func _spawn_hit_effect(attacker: Node, was_blocking: bool) -> void:
	var effect := Node3D.new()
	effect.name = "HitImpactEffect"
	var effect_position := global_position + Vector3.UP * 1.0
	if attacker is Node3D:
		effect_position = (global_position + (attacker as Node3D).global_position) * 0.5 + Vector3.UP * 0.9
	get_tree().current_scene.add_child(effect)
	effect.global_position = effect_position

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.18, 0.55, 1.0, 0.9) if was_blocking else Color(1.0, 0.18, 0.06, 0.9)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 3.0

	var particles := GPUParticles3D.new()
	particles.name = "ImpactSparks"
	particles.amount = 22 if was_blocking else 30
	particles.lifetime = 0.32
	particles.one_shot = true
	particles.explosiveness = 1.0
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 150.0
	process_material.initial_velocity_min = 2.0
	process_material.initial_velocity_max = 5.0
	process_material.gravity = Vector3(0.0, -8.0, 0.0)
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.08
	process_material.scale_min = 0.3
	process_material.scale_max = 0.8
	particles.process_material = process_material
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	mesh.material = material
	particles.draw_pass_1 = mesh
	effect.add_child(particles)
	particles.emitting = true

	var light := OmniLight3D.new()
	light.light_color = material.albedo_color
	light.light_energy = 2.5 if was_blocking else 3.5
	light.omni_range = 2.0
	effect.add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.16)
	get_tree().create_timer(0.4).timeout.connect(effect.queue_free)


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
