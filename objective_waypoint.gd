extends Node3D
## One lightweight destination beacon + screen-edge pointer, never a pathfinder.
var player: CharacterBody3D
var caption := "OBJECTIVE"
var tint := Color(1.0, 0.65, 0.23)
var canvas: CanvasLayer
var badge: Control
var icon: Polygon2D
var label: Label
var ring: MeshInstance3D
var clock := 0.0
var offscreen := false

func _ready() -> void:
	name = "ObjectiveWaypoint"
	# Keep visibility in sync with pause menus, even when gameplay is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.57
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 2.0
	ring.material_override = material
	add_child(ring)
	canvas = CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	badge = Control.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(badge)
	icon = Polygon2D.new()
	icon.color = tint
	badge.add_child(icon)
	var outline := Line2D.new()
	outline.name = "Outline"
	outline.width = 3.0
	outline.default_color = Color(0.06, 0.035, 0.025)
	icon.add_child(outline)
	label = Label.new()
	label.position = Vector2(-130, 17)
	label.size = Vector2(260, 45)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_outline_color", Color(0.025, 0.02, 0.025))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	_process(0)

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var show_guide: bool = is_instance_valid(player) and player.is_alive and not get_tree().paused and camera == player.camera and player.process_mode != Node.PROCESS_MODE_DISABLED
	canvas.visible = show_guide
	ring.visible = show_guide
	if not show_guide:
		return
	clock += delta
	ring.scale = Vector3.ONE * (1.0 + sin(clock * 2.5) * 0.08)
	var screen := get_viewport().get_visible_rect().size
	var center := screen * 0.5
	var target := global_position + Vector3.UP * 1.5
	var local_target := camera.to_local(target)
	var projected := camera.unproject_position(target)
	var inset := Vector2(minf(150, screen.x * 0.24), minf(90, screen.y * 0.24))
	var bounds := Rect2(inset, screen - inset * 2.0)
	offscreen = camera.is_position_behind(target) or not bounds.has_point(projected)
	if offscreen:
		# Camera-local direction stays correct behind the camera (unproject flips).
		var direction := Vector2(local_target.x, -local_target.y)
		if local_target.z < 0:
			direction = projected - center
		if direction.length_squared() < 0.001:
			direction = Vector2.DOWN
		direction = direction.normalized()
		var extent := screen * 0.5 - inset
		var edge_distance := minf(extent.x / maxf(absf(direction.x), 0.001), extent.y / maxf(absf(direction.y), 0.001))
		badge.position = center + direction * edge_distance
		icon.polygon = PackedVector2Array([Vector2(13, 0), Vector2(-8, -9), Vector2(-3, 0), Vector2(-8, 9)])
		icon.rotation = direction.angle()
	else:
		badge.position = projected
		icon.polygon = PackedVector2Array([Vector2(0, -11), Vector2(9, 0), Vector2(0, 11), Vector2(-9, 0)])
		icon.rotation = 0
	var outline := icon.get_node("Outline") as Line2D
	outline.points = icon.polygon
	outline.closed = true
	var height := global_position.y - player.global_position.y
	var elevation := "  ABOVE" if height > 3.0 else ("  BELOW" if height < -3.0 else "")
	label.text = "%s\n%dm%s" % [caption, roundi(player.global_position.distance_to(global_position)), elevation]
