class_name OwlCompanion
extends Node3D

signal intro_finished
signal visit_finished
signal orbit_finished
signal story_finished

const OWL_SCENE := preload("res://assets/npc/owl/owl.glb")
const ORBIT_RADIUS := 1.4
const ORBIT_HEIGHT := 2.35

var player: Node3D
var model: Node3D
var animation_player: AnimationPlayer
var bubble: PanelContainer
var speech: Label
var hint: Label
var state := "hidden"
var is_intro := false
var elapsed := 0.0
var line_index := 0
var dialogue_lines: Array[String] = []
var dialogue_durations: Array[float] = []
var orbit_duration := 2.8
var orbit_start := 0.0
var hold_offset := Vector3.ZERO
var intro_seen := false
var saved_physics := true
var saved_input := true
var saved_unhandled := true
var poof_node: Node3D
var fade_tween: Tween
var story_camera: Camera3D
var previous_camera: Camera3D
var camera_from := Vector3.ZERO
var camera_to := Vector3.ZERO
var camera_elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	model = OWL_SCENE.instantiate() as Node3D
	model.name = "OwlModel"
	model.scale = Vector3.ONE * 0.022
	add_child(model)
	animation_player = model.get_node("AnimationPlayer") as AnimationPlayer
	var wing_clip := animation_player.get_animation("CINEMA_4D_Principal")
	wing_clip.loop_mode = Animation.LOOP_LINEAR
	animation_player.play("CINEMA_4D_Principal")
	model.hide()
	_build_bubble()

func _build_bubble() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "OwlDialogueLayer"
	canvas.layer = 12
	add_child(canvas)
	bubble = PanelContainer.new()
	bubble.name = "SpeechBubble"
	bubble.custom_minimum_size = Vector2(225, 0)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.085, 0.16, 0.94)
	style.border_color = Color(0.48, 0.85, 0.97, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 11
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 9
	bubble.add_theme_stylebox_override("panel", style)
	canvas.add_child(bubble)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 5)
	bubble.add_child(rows)
	speech = Label.new()
	speech.name = "Speech"
	speech.custom_minimum_size.x = 280
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	speech.add_theme_font_size_override("font_size", 17)
	rows.add_child(speech)
	hint = Label.new()
	hint.name = "Hint"
	hint.add_theme_color_override("font_color", Color(0.52, 0.85, 0.98))
	hint.add_theme_font_size_override("font_size", 13)
	rows.add_child(hint)
	bubble.hide()

func start_story(target: Node3D, lines: Array[String], durations: Array[float]) -> void:
	if lines.is_empty() or lines.size() != durations.size():
		return
	_interrupt_current()
	player = target
	is_intro = true
	dialogue_lines = lines.duplicate()
	dialogue_durations = durations.duplicate()
	orbit_duration = 2.8
	_lock_player()
	_start_story_camera()
	_start_orbit()

func call_owl(target: Node3D, message: String) -> bool:
	if not intro_seen or state != "hidden":
		return false
	player = target
	is_intro = false
	dialogue_lines = [message]
	dialogue_durations = [4.0]
	orbit_duration = 2.3
	_start_orbit()
	return true

func _interrupt_current() -> void:
	if is_intro and state != "hidden":
		_unlock_player()
	if is_instance_valid(fade_tween):
		fade_tween.kill()
	if is_instance_valid(poof_node):
		poof_node.queue_free()
	_end_story_camera()
	poof_node = null
	state = "hidden"

func _start_orbit() -> void:
	state = "orbit"
	elapsed = 0.0
	var camera := get_viewport().get_camera_3d()
	var toward_camera := camera_to - player.global_position if is_intro and is_instance_valid(story_camera) else (camera.global_position - player.global_position if camera else Vector3(1, 0, 1))
	toward_camera.y = 0.0
	if toward_camera.length_squared() < 0.01:
		toward_camera = Vector3(1, 0, 1)
	hold_offset = toward_camera.normalized() * ORBIT_RADIUS
	orbit_start = atan2(hold_offset.z, hold_offset.x)
	model.show()
	model.scale = Vector3.ONE * 0.022
	bubble.hide()
	_update_orbit(0.0)

func _process(delta: float) -> void:
	if not is_instance_valid(player) or state == "hidden":
		return
	_update_story_camera(delta)
	elapsed += delta
	if state == "orbit":
		_update_orbit(minf(elapsed / orbit_duration, 1.0))
		if elapsed >= orbit_duration:
			orbit_finished.emit()
			line_index = 0
			_show_line(dialogue_lines[0])
	elif state == "line" and elapsed >= dialogue_durations[line_index]:
		line_index += 1
		if line_index < dialogue_lines.size():
			_show_line(dialogue_lines[line_index])
		else:
			if is_intro:
				intro_seen = true
				_unlock_player()
			_start_poof()
	elif state == "poof" and elapsed >= 0.65:
		state = "hidden"
		if is_instance_valid(poof_node):
			poof_node.queue_free()
		poof_node = null
		if is_intro:
			is_intro = false
			intro_finished.emit()
			story_finished.emit()
		else:
			visit_finished.emit()
	elif state == "line":
		global_position = player.global_position + hold_offset + Vector3.UP * (ORBIT_HEIGHT + sin(Time.get_ticks_msec() * 0.003) * 0.08)
		_update_bubble_position()

func _update_orbit(progress: float) -> void:
	var angle := orbit_start + progress * TAU
	var radius := ORBIT_RADIUS * smoothstep(0.0, 0.18, progress)
	global_position = player.global_position + Vector3(cos(angle) * radius, ORBIT_HEIGHT + sin(progress * TAU * 2.0) * 0.16, sin(angle) * radius)
	model.rotation.y = -angle - PI * 0.5

func _show_line(line: String) -> void:
	state = "line"
	elapsed = 0.0
	_show_bubble(line, "")

func _show_bubble(line: String, prompt: String) -> void:
	speech.text = line
	hint.text = prompt
	hint.visible = not prompt.is_empty()
	bubble.show()
	_update_bubble_position()

func _update_bubble_position() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if camera.is_position_behind(global_position + Vector3.UP * 0.8):
		bubble.hide()
		return
	bubble.show()
	var screen := camera.unproject_position(global_position + Vector3.UP * 0.8)
	var size := bubble.get_combined_minimum_size()
	bubble.position = Vector2(clampf(screen.x - size.x * 0.5, 12.0, get_viewport().get_visible_rect().size.x - size.x - 12.0), clampf(screen.y - size.y - 28.0, 12.0, get_viewport().get_visible_rect().size.y - size.y - 12.0))

func _start_poof() -> void:
	state = "poof"
	elapsed = 0.0
	bubble.hide()
	var center := global_position
	poof_node = Node3D.new()
	poof_node.name = "OwlPoof"
	get_parent().add_child(poof_node)
	poof_node.global_position = center
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.19
	ring.mesh = torus
	ring.rotation.x = PI * 0.5
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(0.55, 0.9, 1.0, 0.8)
	ring.material_override = ring_mat
	poof_node.add_child(ring)
	var ring_tween := create_tween()
	ring_tween.set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector3.ONE * 5.0, 0.5)
	ring_tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.5)
	for index in 12:
		var mote := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.035
		sphere.height = 0.07
		mote.mesh = sphere
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.5 + float(index % 3) * 0.13, 0.85, 1.0, 0.95)
		mote.material_override = material
		poof_node.add_child(mote)
		var angle := TAU * float(index) / 12.0
		var direction := Vector3(cos(angle), 0.25 + float(index % 4) * 0.17, sin(angle))
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(mote, "position", direction * 0.8, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(material, "albedo_color:a", 0.0, 0.55)
	fade_tween = create_tween()
	fade_tween.tween_property(model, "scale", Vector3.ONE * 0.003, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	fade_tween.tween_callback(model.hide)

func _lock_player() -> void:
	saved_physics = player.is_physics_processing()
	saved_input = player.is_processing_input()
	saved_unhandled = player.is_processing_unhandled_input()
	if player is CharacterBody3D:
		player.velocity = Vector3.ZERO
		var actor_animation := player.get_node_or_null("WarriorKnight/AnimationPlayer") as AnimationPlayer
		if actor_animation != null and actor_animation.has_animation("Idle"):
			actor_animation.speed_scale = 1.0
			player.set("last_animation", "")
			player.call("_play", "Idle")
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)

func _unlock_player() -> void:
	_end_story_camera()
	if not is_instance_valid(player):
		return
	player.set_physics_process(saved_physics)
	player.set_process_input(saved_input)
	player.set_process_unhandled_input(saved_unhandled)

func _exit_tree() -> void:
	if is_intro and state != "hidden":
		_unlock_player()
	_end_story_camera()

func _start_story_camera() -> void:
	previous_camera = get_viewport().get_camera_3d()
	if previous_camera == null:
		return
	var character := player.get_node_or_null("WarriorKnight") as Node3D
	var forward := character.global_basis.z if character != null else player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	var focus := player.global_position + Vector3.UP * 1.5
	camera_to = focus + forward * 3.4 + Vector3.UP * 0.35
	var ray := PhysicsRayQueryParameters3D.create(focus, camera_to, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		camera_to = focus.lerp(hit.position, 0.8)
	camera_from = previous_camera.global_position
	camera_elapsed = 0.0
	story_camera = Camera3D.new()
	story_camera.name = "OwlStoryCamera"
	story_camera.fov = previous_camera.fov
	story_camera.near = previous_camera.near
	get_parent().add_child(story_camera)
	story_camera.global_transform = previous_camera.global_transform
	story_camera.make_current()

func _update_story_camera(delta: float) -> void:
	if not is_instance_valid(story_camera):
		return
	camera_elapsed += delta
	var progress := smoothstep(0.0, 0.85, camera_elapsed)
	story_camera.global_position = camera_from.lerp(camera_to, progress)
	story_camera.look_at(player.global_position + Vector3.UP * 1.6)

func _end_story_camera() -> void:
	if is_instance_valid(previous_camera):
		previous_camera.make_current()
	if is_instance_valid(story_camera):
		story_camera.queue_free()
	story_camera = null
	previous_camera = null
