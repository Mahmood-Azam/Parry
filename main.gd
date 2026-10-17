extends Node3D

var menu_layer: CanvasLayer
var title_background: TextureRect
var overlay: ColorRect
var home_panel: PanelContainer
var options_panel: PanelContainer
var death_panel: PanelContainer
var victory_panel: PanelContainer
var death_request_id: int = 0
const START_GAME_META := "shadowborn_start_game"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_menu()
	if get_tree().root.has_meta(START_GAME_META):
		get_tree().root.remove_meta(START_GAME_META)
		_continue_game()
	else:
		_show_home()


func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.name = "FrontEndLayer"
	menu_layer.layer = 20
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)
	overlay = ColorRect.new()
	overlay.name = "MenuOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.015, 0.02, 0.045, 0.58)
	title_background = TextureRect.new()
	title_background.name = "ShadowBornTitleArt"
	title_background.texture = load("res://assets/ui/shadowborn_title_background.png")
	title_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	title_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(title_background)
	menu_layer.add_child(overlay)

	home_panel = _make_panel("SHADOWBORN", true)
	var home_box := home_panel.get_node("Margin/VBox") as VBoxContainer
	var lore := Label.new()
	lore.text = "Parry the darkness. Ignite the blade."
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.add_theme_font_size_override("font_size", 16)
	lore.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	home_box.add_child(lore)
	_add_button(home_box, "NEW GAME", Callable(self, "_new_game"))
	_add_button(home_box, "CONTINUE", Callable(self, "_continue_game"))
	_add_button(home_box, "OPTIONS", Callable(self, "_show_options"))
	_add_button(home_box, "QUIT", Callable(self, "_quit_game"))
	menu_layer.add_child(home_panel)

	options_panel = _make_panel("OPTIONS", true)
	options_panel.position = Vector2(46.0, -305.0)
	options_panel.size = Vector2(450.0, 610.0)
	var options_box := options_panel.get_node("Margin/VBox") as VBoxContainer
	var controls := Label.new()
	controls.text = "WASD  Move\nSHIFT  Sprint\nSPACE  Jump\nF / RMB  Parry, then Block\nQ  Shadow Dash\nLMB  Fire Attack\nMMB Hold  Channel remaining fire\nRelease MMB  Launch charged air slash\nR  Fill fire instantly\n\nParry three times to trigger an automatic riposte."
	controls.add_theme_font_size_override("font_size", 18)
	controls.add_theme_color_override("font_color", Color(0.82, 0.87, 0.98))
	options_box.add_child(controls)
	controls.add_theme_font_size_override("font_size", 14)
	options_box.add_theme_constant_override("separation", 8)
	DisplaySettings.create_controls(options_box)
	var quality_picker := OptionButton.new()
	quality_picker.add_item("Performance — sparse grass")
	quality_picker.add_item("Balanced")
	quality_picker.add_item("High — dense vegetation")
	var map := get_node("CampusMap")
	quality_picker.selected = map.quality
	quality_picker.item_selected.connect(map.apply_quality)
	options_box.add_child(quality_picker)
	_add_button(options_box, "BACK", Callable(self, "_show_home"))
	menu_layer.add_child(options_panel)

	death_panel = _make_panel("YOU DIED", true)
	var death_box := death_panel.get_node("Margin/VBox") as VBoxContainer
	var death_text := Label.new()
	death_text.text = "The shadow claims you. Try again."
	death_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_text.add_theme_font_size_override("font_size", 18)
	death_text.add_theme_color_override("font_color", Color(0.85, 0.82, 0.92))
	death_box.add_child(death_text)
	_add_button(death_box, "RESPAWN", Callable(self, "_respawn"))
	_add_button(death_box, "HOME", Callable(self, "_show_home"))
	menu_layer.add_child(death_panel)
	victory_panel = _make_panel("DAWN BREAKS", true)
	var victory_box := victory_panel.get_node("Margin/VBox") as VBoxContainer
	var victory_text := Label.new()
	victory_text.text = "The Ash Warden has fallen.\nBlock D is free of shadow."
	victory_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	victory_text.add_theme_font_size_override("font_size", 20)
	victory_box.add_child(victory_text)
	_add_button(victory_box, "EXPLORE", _continue_game)
	_add_button(victory_box, "NEW GAME", _new_game)
	_add_button(victory_box, "HOME", _show_home)
	menu_layer.add_child(victory_panel)


func _make_panel(title: String, left_aligned: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = title.replace(" ", "") + "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT if left_aligned else Control.PRESET_CENTER)
	panel.position = Vector2(46.0, -220.0) if left_aligned else Vector2(-190.0, -220.0)
	panel.size = Vector2(420.0, 440.0) if left_aligned else Vector2(380.0, 440.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.025, 0.045, 0.91)
	style.border_color = Color(0.88, 0.29, 0.08, 0.88)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "VBox"
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", Color(1.0, 0.42, 0.12))
	heading.add_theme_constant_override("shadow_offset_x", 2)
	heading.add_theme_constant_override("shadow_offset_y", 2)
	heading.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	box.add_child(heading)
	return panel


func _add_button(parent: VBoxContainer, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", Color(0.86, 0.88, 0.94))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.74, 0.42))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.42, 0.12))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.08, 0.12, 0.72)
	normal.border_color = Color(0.23, 0.28, 0.38, 0.8)
	normal.set_border_width_all(1)
	normal.corner_radius_top_left = 3
	normal.corner_radius_top_right = 3
	normal.corner_radius_bottom_left = 3
	normal.corner_radius_bottom_right = 3
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.30, 0.10, 0.035, 0.82)
	hover.border_color = Color(1.0, 0.36, 0.10, 0.95)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.55, 0.16, 0.04, 0.9)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.pressed.connect(callback)
	parent.add_child(button)


func _set_menu_visible(panel: Control) -> void:
	# Pause first so the frame that reveals the menu cannot advance gameplay.
	get_tree().paused = true
	_set_gameplay_process_enabled(false)
	home_panel.visible = panel == home_panel
	options_panel.visible = panel == options_panel
	death_panel.visible = panel == death_panel
	victory_panel.visible = panel == victory_panel
	title_background.visible = true
	overlay.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _set_gameplay_process_enabled(enabled: bool) -> void:
	var gameplay_mode := Node.PROCESS_MODE_PAUSABLE if enabled else Node.PROCESS_MODE_DISABLED
	var player := get_node_or_null("Player")
	if player != null:
		player.process_mode = gameplay_mode
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			enemy.process_mode = gameplay_mode


func _show_home() -> void:
	_set_menu_visible(home_panel)


func _show_options() -> void:
	_set_menu_visible(options_panel)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if get_tree().paused:
			if options_panel.visible:
				_show_home()
			elif not death_panel.visible and get_node("Player").is_alive:
				_continue_game()
		else:
			_show_home()
		get_viewport().set_input_as_handled()


func show_victory() -> void:
	await get_tree().create_timer(2.0, false).timeout
	if is_inside_tree() and get_node("Player").is_alive:
		_set_menu_visible(victory_panel)


func show_death_screen(delay: float = 0.72) -> void:
	# Let the player death reaction finish before pausing and showing the menu.
	# The timer runs even if another system pauses the tree meanwhile.
	death_request_id += 1
	var request_id := death_request_id
	get_tree().paused = false
	overlay.visible = false
	home_panel.visible = false
	options_panel.visible = false
	death_panel.visible = false
	victory_panel.visible = false
	await get_tree().create_timer(maxf(delay, 0.0), true).timeout
	if request_id == death_request_id and is_inside_tree():
		_set_menu_visible(death_panel)


func _continue_game() -> void:
	_set_gameplay_process_enabled(true)
	get_tree().paused = false
	title_background.visible = false
	overlay.visible = false
	home_panel.visible = false
	options_panel.visible = false
	death_panel.visible = false
	victory_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _new_game() -> void:
	get_tree().root.set_meta(START_GAME_META, true)
	get_tree().paused = false
	get_tree().reload_current_scene()


func _respawn() -> void:
	get_tree().root.set_meta(START_GAME_META, true)
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit_game() -> void:
	get_tree().quit()
