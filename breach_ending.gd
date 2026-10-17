extends Node3D
## Reverse the breach in-engine, then return to a collision-checked field spawn.
signal finished
const FIELD := Vector3(18, 0, -55)
const AUDIO := preload("res://breach_audio.gd")
const FX := preload("res://combat_fx.gd")
const NUST_IMPACT := preload("res://assets/cinematics/ending/nust_impact.ogv")
const IMPACT_DURATION := 3.8 # Source clip duration; decoder length can be unavailable.
const IMPACT_FADE_SECONDS := 0.7
var player: CharacterBody3D
var world: Node3D
var elapsed := 0.0
var duration := 11.0
var completed := false
var reversal_started := false
var rebuilt := false
var explosion_rewinding := false
var frozen: Array = []
var hidden_hud: Array = []
var lighting: Array = []
var sunlight: Array = []
var camera: Camera3D
var old_camera: WeakRef
var old_invulnerable := false
var overlay: CanvasLayer
var fade: ColorRect
var title: Label
var subtitle: Label
var spawn_point := FIELD
var impact_video: VideoStreamPlayer
var video_started := false
var video_elapsed := 0.0
var video_fade := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	old_invulnerable = player.is_invulnerable
	player.is_invulnerable = true
	for actor in [player, get_parent().get_node("EncounterDirector")]:
		frozen.append([weakref(actor), actor.process_mode])
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	get_parent().get_node("EncounterDirector").message_label.hide()
	for group in ["enemy", "mage_projectile", "combat_projectile", "shadow_decoy"]:
		for actor in get_tree().get_nodes_in_group(group):
			frozen.append([weakref(actor), actor.process_mode])
			actor.process_mode = Node.PROCESS_MODE_DISABLED
	for hud: CanvasLayer in get_parent().find_children("*", "CanvasLayer", true, false):
		if hud == get_parent().menu_layer:
			continue
		hidden_hud.append([weakref(hud), hud.visible])
		hud.hide()
	var active_camera := get_viewport().get_camera_3d()
	if active_camera != null:
		old_camera = weakref(active_camera)
	camera = Camera3D.new()
	camera.fov = 58
	camera.far = 500
	add_child(camera)
	camera.make_current()
	_reset_player()
	spawn_point = find_field_spawn()
	player.global_position = spawn_point # Move BEFORE the roof collision returns.
	_prepare_daylight()
	_build_overlay()
	world.cinematic = true
	world.gate.set_collision_enabled(false)
	world.meteor.show()
	world.meteor_trail.emitting = true
	FX.ring(self, world.gate_point + Vector3.UP * 3.5, Color(0.55, 0.82, 1.0), 5.0, Vector3.BACK)
	var sound := AudioStreamPlayer.new()
	sound.stream = AUDIO.cue("portal")
	sound.volume_db = -7
	sound.pitch_scale = 0.72
	add_child(sound)
	sound.play()
	create_tween().tween_property(sound, "pitch_scale", 1.45, 3.5)
	_update_timeline(0)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func find_field_spawn() -> Vector3:
	var space := get_world_3d().direct_space_state
	var body := player.get_node("CollisionShape3D") as CollisionShape3D
	for offset in [Vector3.ZERO, Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3)]:
		var point: Vector3 = FIELD + offset
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3, point - Vector3.UP * 4, 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.8:
			continue
		point = hit.position + Vector3.UP * 0.04
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body.shape
		query.transform = Transform3D(Basis.IDENTITY, point + body.position)
		query.collision_mask = 1
		query.margin = 0.005
		if space.intersect_shape(query, 1).is_empty():
			return point
	push_warning("Ending field fallback used; no clear candidate was found")
	return Vector3(35, 0.2, -64)

func _reset_player() -> void:
	player.velocity = Vector3.ZERO
	player.is_dashing = false
	player.is_parrying = false
	player.blocking = false
	player.attacking = false
	player.is_attacking = false
	player.attack_requested = false
	player.attack_combo_queued = false
	player.attack_combo_phase = 0
	player.hit_stun_remaining = 0
	player.is_fire_channeling = false
	player.fire_channel_charge = 0
	player.jump_requested = false
	player.jump_buffer_remaining = 0
	player.camera_trauma = 0
	player.camera_step_offset = 0
	player.camera.h_offset = 0
	player.camera.v_offset = 0
	player.camera_target_yaw = 0
	player.camera_pivot.rotation = Vector3.ZERO
	player.character.rotation = Vector3(0, PI, 0)
	player.character.position = player.locomotion_base_position
	player._set_parry_hitbox_active(false)
	player._set_sword_guard_pose(false)
	player.last_animation = ""
	player.animation_player.speed_scale = 1
	player._play("Idle")
	player.animation_player.advance(0)
	player.motion_fx_last_position = player.global_position

func _prepare_daylight() -> void:
	var campus := get_parent().get_node("CampusMap")
	for light: DirectionalLight3D in campus.find_children("*", "DirectionalLight3D", true, false):
		sunlight.append([weakref(light), light.light_color, light.light_energy])
	var nights: Array = []
	for node: WorldEnvironment in campus.find_children("*", "WorldEnvironment", true, false):
		if node.environment != null:
			nights.append([node, node.environment])
	world._restore_daylight()
	for state in nights:
		var node: WorldEnvironment = state[0]
		var day := node.environment
		var night: Environment = state[1]
		var live := night.duplicate(true) as Environment
		node.environment = live
		lighting.append([weakref(node), live, night, day])
	_update_lighting(0)

func _update_lighting(daylight: float) -> void:
	for state in sunlight:
		var light: DirectionalLight3D = state[0].get_ref()
		if is_instance_valid(light):
			light.light_energy = lerpf(state[2], 1.4, daylight)
			light.light_color = state[1].lerp(Color(1, 0.91, 0.76), daylight)
	for state in lighting:
		var live: Environment = state[1]
		var night: Environment = state[2]
		var day: Environment = state[3]
		for property in ["ambient_light_color", "fog_light_color"]:
			live.set(property, night.get(property).lerp(day.get(property), daylight))
		for property in ["ambient_light_energy", "fog_density", "fog_sky_affect", "adjustment_saturation"]:
			live.set(property, lerpf(night.get(property), day.get(property), daylight))
		if live.sky != null and live.sky.sky_material is ProceduralSkyMaterial:
			for property in ["sky_top_color", "sky_horizon_color", "ground_horizon_color", "ground_bottom_color"]:
				live.sky.sky_material.set(property, night.sky.sky_material.get(property).lerp(day.sky.sky_material.get(property), daylight))

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 35
	add_child(overlay)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(fade)
	for bottom in [false, true]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
		bar.offset_top = -50 if bottom else 0
		bar.offset_bottom = 0 if bottom else 50
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(bar)
	title = Label.new()
	title.text = "YOU SAVED FAST SUCCESSFULLY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.position = Vector2(-480, -55)
	title.size = Vector2(960, 60)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.87, 0.57))
	overlay.add_child(title)
	subtitle = Label.new()
	subtitle.text = "The meteor has been redirected to NUST."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	subtitle.position = Vector2(-480, 20)
	subtitle.size = Vector2(960, 45)
	subtitle.add_theme_font_size_override("font_size", 23)
	overlay.add_child(subtitle)

func _process(delta: float) -> void:
	if completed:
		return
	if video_started:
		video_elapsed += delta
		_update_impact_fade()
		# Natural completion is primary; a broken decoder must not trap a win.
		if video_elapsed > 8.0:
			push_warning("NUST ending video timed out; continuing to the result screen")
			finish()
		return
	elapsed += delta
	_update_timeline(delta)
	if elapsed >= duration:
		_begin_impact_video()

func _begin_impact_video() -> void:
	if video_started or completed:
		return
	video_started = true
	_finalize_world()
	title.hide()
	subtitle.hide()
	fade.color.a = 1.0
	var aspect := AspectRatioContainer.new()
	aspect.name = "NUSTImpactFrame"
	aspect.ratio = 16.0 / 9.0
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(aspect)
	impact_video = VideoStreamPlayer.new()
	impact_video.name = "NUSTMeteorImpact"
	impact_video.expand = true
	impact_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	impact_video.stream = NUST_IMPACT
	impact_video.bus = &"Master"
	impact_video.finished.connect(_impact_video_finished)
	aspect.add_child(impact_video)
	impact_video.play()
	impact_video.modulate.a = 0.0

func _update_impact_fade() -> void:
	if not is_instance_valid(impact_video):
		return
	var length := impact_video.get_stream_length()
	if length <= 0.0:
		length = IMPACT_DURATION
	# Use decoded playback time, not wall time: slow loading must not fade early.
	var position_seconds := impact_video.stream_position
	video_fade = maxf(video_fade, smoothstep(length - IMPACT_FADE_SECONDS, length - 0.06, position_seconds))
	impact_video.modulate.a = smoothstep(0, 0.12, position_seconds) * (1.0 - video_fade)
	impact_video.volume_db = linear_to_db(maxf(0.0001, 1.0 - video_fade))

func _impact_video_finished() -> void:
	# Hold full black briefly before revealing the paused result screen.
	video_fade = 1.0
	impact_video.modulate.a = 0.0
	impact_video.volume_db = -80.0
	var outro := create_tween()
	outro.tween_interval(0.12)
	outro.tween_callback(finish)

func _update_timeline(delta: float) -> void:
	var impact: Vector3 = world.impact_point
	var approach := impact + Vector3(-18, 30, -20)
	if elapsed >= 1.2 and not reversal_started:
		reversal_started = true
		world.destruction.reverse_destruction(3.1)
	if elapsed >= 1.2 and not explosion_rewinding and world.explosion_player != null:
		explosion_rewinding = true
		world.explosion.show()
		world.explosion.position = impact + Vector3.UP
		world.explosion_player.play_backwards("Take 001")
		world.explosion_player.speed_scale = 1.6
	if elapsed < 1.2:
		world.meteor.position = world.rest_point.lerp(impact + Vector3.UP, smoothstep(0, 1.2, elapsed))
	elif elapsed < 4.6:
		var reverse_fall := pow(1.0 - smoothstep(1.2, 4.6, elapsed), 1.45)
		world.meteor.position = approach.lerp(impact + Vector3.UP, reverse_fall)
	else:
		world.meteor.position = approach.lerp(impact + Vector3(140, 110, -55), smoothstep(4.6, 7.7, elapsed))
	world.meteor.rotation -= Vector3(0.4, 0.8, 0.25) * delta
	world.meteor.scale = Vector3.ONE * lerpf(0.72, 1.0, smoothstep(0, 1.2, elapsed))
	world.meteor.visible = elapsed < 7.7
	world.meteor_trail.emitting = elapsed < 7.7
	world.gate.scale = Vector3.ONE * maxf(0.001, 1.0 - smoothstep(0.4, 2.2, elapsed))
	world.gate_motes.emitting = elapsed < 2.0
	if elapsed >= 4.3:
		world.explosion.hide()
		world.scorch.hide()
	_update_lighting(smoothstep(1.3, 6.7, elapsed))
	if elapsed < 4.6:
		camera.position = impact + Vector3(-18, 12, 24).lerp(Vector3(-15, 15, 29), smoothstep(0, 4.6, elapsed))
		camera.look_at(impact + Vector3.UP * 2)
	elif elapsed < 7.7:
		camera.position = impact + Vector3(-20, 14, 26)
		camera.look_at(world.meteor.position)
	else:
		camera.position = spawn_point + Vector3(4, 2.8, 6).lerp(Vector3(3, 2.2, 5), smoothstep(7.7, 10.6, elapsed))
		camera.look_at(spawn_point + Vector3.UP * 1.05)
	title.modulate.a = smoothstep(8.4, 9.0, elapsed)
	subtitle.modulate.a = smoothstep(8.9, 9.5, elapsed)
	fade.color.a = maxf(1.0 - smoothstep(0, 0.35, elapsed), smoothstep(8.1, 9.1, elapsed) * 0.7)

func finish() -> void:
	if completed:
		return
	completed = true
	if is_instance_valid(impact_video):
		impact_video.stop()
	_finalize_world()
	_restore_control()
	finished.emit()
	queue_free()

func _finalize_world() -> void:
	if not is_instance_valid(world):
		return
	world.destruction.restore_intact()
	world._restore_daylight()
	var campus := get_parent().get_node("CampusMap")
	# Graphics quality controls must target the restored daytime environment.
	for node: WorldEnvironment in campus.find_children("*", "WorldEnvironment", true, false):
		campus.environment = node.environment
		break
	world.gate.hide()
	world.gate.scale = Vector3.ONE
	world.meteor.hide()
	world.explosion.hide()
	world.scorch.hide()
	world.gate_motes.emitting = false
	world.meteor_trail.emitting = false
	world.cinematic = false
	rebuilt = true

func _restore_control() -> void:
	if not is_instance_valid(player):
		return
	if player.is_inside_tree():
		_reset_player()
		player.global_position = spawn_point
		player.motion_fx_last_position = spawn_point
	player.is_invulnerable = old_invulnerable
	player.suppress_jump_until_release = true
	for state in frozen:
		var actor: Node = state[0].get_ref()
		if is_instance_valid(actor):
			actor.process_mode = state[1]
	frozen.clear()
	for state in hidden_hud:
		var hud: CanvasLayer = state[0].get_ref()
		if is_instance_valid(hud):
			hud.visible = state[1]
	hidden_hud.clear()
	if old_camera != null and is_instance_valid(old_camera.get_ref()) and old_camera.get_ref().is_inside_tree():
		old_camera.get_ref().make_current()
	elif player.is_inside_tree():
		player.camera.make_current()

func _exit_tree() -> void:
	# A scene reload may interrupt any shot; never leave live actors locked.
	if not frozen.is_empty():
		if is_instance_valid(world) and world.is_inside_tree() and get_parent().is_inside_tree():
			_finalize_world()
		_restore_control()
