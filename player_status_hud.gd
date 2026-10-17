extends Panel
## Compact readable essentials; fire/ultimate still share one layered reserve.
var controller: CharacterBody3D
var health_bar: ProgressBar
var fire_bar: ProgressBar
var health_label: Label
var fire_label: Label
var ultimate_label: Label
var dash_label: Label
var parry_label: Label
var dash_bar: ProgressBar

func _ready() -> void:
	name = "PlayerStatusHUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(20, 20)
	size = Vector2(276, 166)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.025, 0.022, 0.035, 0.86)
	frame.border_color = Color(0.43, 0.30, 0.20, 0.8)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(7)
	frame.shadow_color = Color(0, 0, 0, 0.25)
	frame.shadow_size = 5
	add_theme_stylebox_override("panel", frame)
	health_label = _label("HealthStatus", Vector2(16, 9), 14, Color(0.96, 0.88, 0.85))
	health_bar = preload("res://combat_health_bar.gd").new()
	health_bar.name = "PlayerHealth"
	health_bar.bar_height = 8
	health_bar.position = Vector2(16, 34)
	health_bar.size = Vector2(244, 8)
	health_bar.max_value = controller.max_health
	health_bar.value = controller.current_health
	add_child(health_bar)
	fire_label = _label("FireStatus", Vector2(16, 49), 14, Color(1, 0.65, 0.31))
	fire_bar = preload("res://layered_fire_meter.gd").new()
	fire_bar.name = "FireMeter"
	fire_bar.position = Vector2(16, 74)
	fire_bar.size = Vector2(244, 10)
	add_child(fire_bar)
	ultimate_label = _label("UltimateStatus", Vector2(16, 91), 12, Color(0.77, 0.64, 0.93))
	dash_label = _label("DashStatus", Vector2(16, 112), 13, Color(0.62, 0.83, 0.96))
	dash_bar = ProgressBar.new()
	dash_bar.show_percentage = false
	dash_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.13, 0.19)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.44, 0.70, 0.88)
	dash_bar.add_theme_stylebox_override("background", track)
	dash_bar.add_theme_stylebox_override("fill", fill)
	dash_bar.max_value = 1
	add_child(dash_bar)
	dash_bar.position = Vector2(208, 121)
	dash_bar.size = Vector2(52, 4)
	parry_label = _label("GuardStatus", Vector2(16, 138), 12, Color(0.76, 0.77, 0.83))
	refresh()

func _label(label_name: String, at: Vector2, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	add_child(label)
	return label

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	if health_bar == null or not is_instance_valid(controller):
		return
	health_bar.max_value = controller.max_health
	health_bar.value = controller.current_health
	health_label.text = "HEALTH:  %d / %d" % [ceili(controller.current_health), ceili(controller.max_health)]
	health_label.modulate = Color(1, 0.53, 0.47) if controller.current_health <= controller.max_health * 0.25 else Color.WHITE
	var capacity: float = controller.fire_meter_max * 2.0
	fire_label.text = "FIRE METER:  %d / %d" % [floori(controller.fire_meter), roundi(capacity)]
	fire_bar.set_reserve(controller.fire_meter, controller.fire_meter_max, controller.is_using_ultimate)
	var ready: bool = controller.fire_meter >= capacity - 0.001
	ultimate_label.text = "ULTIMATE READY  [E / G]" if ready else "ULTIMATE: %d%%" % floori(controller.fire_meter / maxf(capacity, 1) * 100)
	if controller.is_fire_channeling:
		ultimate_label.text = "SLASH CHARGE: %d%%  [Release MMB]" % floori(controller.fire_channel_charge / maxf(controller.fire_meter_max, 1) * 100)
	ultimate_label.modulate = Color(1, 0.88, 0.6) if ready else Color.WHITE
	var cooldown: float = controller.dash_cooldown_timer
	dash_label.text = "[Q] SHADOW:  %.1fs" % cooldown if cooldown > 0.0 else "[Q] SHADOW:  READY"
	dash_label.modulate.a = 0.65 if cooldown > 0 else 1.0
	dash_bar.value = clampf(1.0 - cooldown / maxf(controller.dash_cooldown, 0.01), 0, 1)
	var guard := "READY"
	if controller.hit_stun_remaining > 0:
		guard = "STAGGERED"
	elif controller.is_parrying:
		guard = "PARRYING"
	elif controller.blocking:
		guard = "BLOCKING"
	elif controller.parry_cooldown_timer > 0:
		guard = "RECOVERING"
	parry_label.text = "[RMB / F] GUARD:  " + guard
