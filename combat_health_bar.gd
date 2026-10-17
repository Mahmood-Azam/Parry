extends ProgressBar
## Compact shared styling and a delayed damage trail, with no per-hit tweens.
var trail: ProgressBar
var hold := 0.0
var previous := 0.0
@export var bar_height := 6.0
@export var fill_tint := Color(0.78, 0.13, 0.12)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_percentage = false
	custom_minimum_size = Vector2(0, bar_height)
	_style(self, fill_tint, true)
	trail = ProgressBar.new()
	trail.show_percentage = false
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style(trail, Color(1.0, 0.54, 0.22, 0.7), false)
	trail.max_value = max_value
	trail.value = value
	add_child(trail)
	trail.show_behind_parent = true
	previous = value
	value_changed.connect(_changed)
	# ProgressBar's default theme clamps pre-tree sizes to ~27px. Reapply only
	# after our thin styles replace it; otherwise "6px" bars remain chunky.
	size.y = bar_height

func _style(bar: ProgressBar, tint: Color, border: bool) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.018, 0.014, 0.022, 0.95) if border else Color.TRANSPARENT
	background.border_color = Color(0.42, 0.32, 0.26, 0.85)
	background.set_border_width_all(1 if border else 0)
	background.set_corner_radius_all(2)
	# Leave the trail visible through the parent track.
	if border:
		background.bg_color.a = 0.75
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)

func _changed(new_value: float) -> void:
	if new_value < previous:
		hold = 0.22
	else:
		trail.value = new_value
	previous = new_value

func _process(delta: float) -> void:
	trail.max_value = max_value
	hold = maxf(hold - delta, 0.0)
	if hold <= 0.0:
		trail.value = move_toward(trail.value, value, max_value * delta * 1.6)
