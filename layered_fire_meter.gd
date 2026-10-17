extends ProgressBar
## One track: orange fire first, then violet overfill drawn over the same area.
var overflow: ProgressBar
var reserve := 0.0
var unit := 100.0
var pulse_time := 0.0
var ready_color := Color(0.74, 0.43, 1.0)
var violet_style: StyleBoxFlat

func _ready() -> void:
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style(self, Color(1.0, 0.32, 0.035), true)
	overflow = ProgressBar.new()
	overflow.name = "UltimateOverlay"
	overflow.show_percentage = false
	overflow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style(overflow, ready_color, false)
	violet_style = overflow.get_theme_stylebox("fill") as StyleBoxFlat
	add_child(overflow)
	size.y = 10
	overflow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_reserve(reserve, unit)

func _style(bar: ProgressBar, tint: Color, track: bool) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.02, 0.045, 0.93) if track else Color.TRANSPARENT
	background.border_color = Color(0.39, 0.27, 0.19)
	background.set_border_width_all(1 if track else 0)
	background.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)

func set_reserve(amount: float, layer_capacity: float, ultimate_active: bool = false) -> void:
	reserve = maxf(amount, 0.0)
	unit = maxf(layer_capacity, 1.0)
	max_value = unit
	value = minf(reserve, unit)
	visible = not ultimate_active
	if overflow != null:
		overflow.max_value = unit
		overflow.value = clampf(reserve - unit, 0.0, unit)
		overflow.visible = reserve > unit

func _process(delta: float) -> void:
	pulse_time += delta
	if violet_style != null:
		var pulse := (0.5 + 0.5 * sin(pulse_time * 4.0)) * 0.22 if reserve >= unit * 2.0 - 0.001 else 0.0
		violet_style.bg_color = ready_color.lerp(Color(0.95, 0.86, 1), pulse)
