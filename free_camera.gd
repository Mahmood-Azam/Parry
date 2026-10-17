extends Node3D
## A paused, independent camera for inspecting the campus.

var view: Camera3D
var previous_camera: Camera3D
var velocity := Vector3.ZERO
var look_sensitivity := 0.0025


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	view = Camera3D.new()
	view.name = "FreeCameraView"
	view.near = 0.05
	add_child(view)
	var layer := CanvasLayer.new()
	layer.name = "FreeCameraOverlay"
	layer.layer = 18
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.019, 0.018, 0.86)
	style.border_color = Color(0.48, 0.29, 0.15, 0.8)
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var hint := Label.new()
	hint.text = "FREE CAMERA  |  GAME PAUSED\nWASD Fly  |  Space/Ctrl Rise/Descend  |  Shift Faster\nV or Esc Return"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.91, 0.83, 0.7))
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	panel.add_child(hint)


func begin(source: Camera3D) -> void:
	previous_camera = source
	view.fov = source.fov
	view.global_transform = source.global_transform
	view.make_current()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func finish() -> void:
	if is_instance_valid(previous_camera) and previous_camera.is_inside_tree():
		previous_camera.make_current()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		view.rotation.y -= event.relative.x * look_sensitivity
		view.rotation.x = clampf(view.rotation.x - event.relative.y * look_sensitivity, -PI * 0.49, PI * 0.49)


func _process(delta: float) -> void:
	var input := Vector3(Input.get_axis("move_left", "move_right"), 0.0, Input.get_axis("move_forward", "move_backward"))
	input.y = (1.0 if Input.is_key_pressed(KEY_SPACE) else 0.0) - (1.0 if Input.is_key_pressed(KEY_CTRL) else 0.0)
	var direction := view.global_basis * Vector3(input.x, 0.0, input.z) + Vector3.UP * input.y
	direction = direction.normalized()
	var speed := 22.0 if Input.is_key_pressed(KEY_SHIFT) else 8.0
	velocity = velocity.lerp(direction * speed, 1.0 - exp(-12.0 * delta))
	view.global_position += velocity * delta
