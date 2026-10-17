extends Control
## Front-end-only motion; gameplay remains paused while this layer animates.
var elapsed := 0.0
var hover_heat := 0.0
var current_heat := 0.0
var pointer := Vector2.ZERO
var art_material: ShaderMaterial
var fire_material: ShaderMaterial
var embers: Array[CPUParticles2D] = []

func _ready() -> void:
	name = "MenuAtmosphere"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_material = ShaderMaterial.new()
	art_material.shader = preload("res://assets/ui/menu_art.gdshader")
	get_parent().material = art_material
	var fire := ColorRect.new()
	fire.name = "FlowingFire"
	fire.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fire_material = ShaderMaterial.new()
	fire_material.shader = preload("res://assets/ui/menu_fire.gdshader")
	fire.material = fire_material
	add_child(fire)
	_add_embers(64, 0.7, 48.0, 5.5)
	_add_embers(30, 1.35, 85.0, 4.0)
	var shade := TextureRect.new()
	shade.name = "ReadableMenuShade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.015, 0.012, 0.014, 0.83))
	gradient.set_color(1, Color(0, 0, 0, 0))
	gradient.add_point(0.30, Color(0.018, 0.013, 0.018, 0.65))
	gradient.add_point(0.56, Color(0.012, 0.012, 0.016, 0.05))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.RIGHT
	shade.texture = texture
	add_child(shade)
	resized.connect(_layout)
	visibility_changed.connect(_sync_visibility)
	_layout()
	_sync_visibility()

func _add_embers(count: int, particle_scale: float, speed: float, lifetime: float) -> void:
	var particles := CPUParticles2D.new()
	particles.name = "NearEmbers" if particle_scale > 1 else "FarEmbers"
	particles.amount = count
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.direction = Vector2(0.12, -1)
	particles.spread = 22
	particles.gravity = Vector2(8, -9)
	particles.initial_velocity_min = speed
	particles.initial_velocity_max = speed * 1.85
	particles.scale_amount_min = particle_scale * 0.5
	particles.scale_amount_max = particle_scale
	particles.angular_velocity_min = -35
	particles.angular_velocity_max = 35
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 0.75, 0.28, 0))
	gradient.set_color(1, Color(0.8, 0.08, 0.01, 0))
	gradient.add_point(0.08, Color(1, 0.75, 0.28, 0.95))
	gradient.add_point(0.4, Color(1, 0.29, 0.025, 0.8))
	particles.color_ramp = gradient
	var texture := GradientTexture2D.new()
	texture.width = 6
	texture.height = 14
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1, 0.5)
	var soft := Gradient.new()
	soft.set_color(0, Color.WHITE)
	soft.set_color(1, Color(1, 1, 1, 0))
	texture.gradient = soft
	particles.texture = texture
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	particles.material = glow
	add_child(particles)
	embers.append(particles)

func _layout() -> void:
	if size.y <= 0:
		return
	fire_material.set_shader_parameter("aspect", size.x / size.y)
	for particles in embers:
		particles.position = Vector2(size.x * 0.55, size.y + 12)
		particles.emission_rect_extents = Vector2(size.x * 0.57, 14)
	queue_redraw()

func _sync_visibility() -> void:
	var active := is_visible_in_tree()
	set_process(active)
	for particles in embers:
		particles.emitting = active
		particles.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

func _process(delta: float) -> void:
	elapsed += delta
	var mouse := get_viewport().get_mouse_position()
	var target := (mouse / size.max(Vector2.ONE) - Vector2.ONE * 0.5).clamp(Vector2.ONE * -0.5, Vector2.ONE * 0.5)
	pointer = pointer.lerp(target, 1.0 - exp(-delta * 2.8))
	current_heat = lerpf(current_heat, hover_heat, 1.0 - exp(-delta * 5.0))
	art_material.set_shader_parameter("menu_time", elapsed)
	art_material.set_shader_parameter("parallax", pointer)
	fire_material.set_shader_parameter("menu_time", elapsed)
	fire_material.set_shader_parameter("hover_heat", current_heat)

func _draw() -> void:
	var color := Color(0.67, 0.44, 0.24, 0.32)
	for x in [24.0, size.x - 24.0]:
		var direction := 1.0 if x < size.x * 0.5 else -1.0
		for y in [24.0, size.y - 24.0]:
			var vertical := 1.0 if y < size.y * 0.5 else -1.0
			draw_line(Vector2(x, y), Vector2(x + direction * 50, y), color, 1, true)
			draw_line(Vector2(x, y), Vector2(x, y + vertical * 24), color, 1, true)
	draw_line(Vector2(64, size.y - 62), Vector2(size.x - 64, size.y - 62), Color(0.67, 0.44, 0.24, 0.17), 1, true)
