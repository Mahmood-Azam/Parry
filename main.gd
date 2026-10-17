extends Node3D

var menu_layer: CanvasLayer
var title_background: TextureRect
var overlay: ColorRect
var home_panel: PanelContainer
var options_panel: PanelContainer
var death_panel: PanelContainer
var victory_panel: PanelContainer
var death_request_id: int = 0
var breach_world: Node3D
var opening_intro: Node3D
var ending_intro: Node3D
var ending_completed := false
const START_GAME_META := "shadowborn_start_game"
const BREACH_RESOURCE := "res://breach_world.gd"
var session_started := false
var opening_loading := false
var loading_label: Label
var breach_script: Script
var menu_atmosphere: Control
var menu_theme: Theme
var title_font: SystemFont
var free_camera: Node3D
var game_music: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_menu()
	_setup_game_music()
	var text_policy := preload("res://gameplay_text_policy.gd").new()
	text_policy.name = "MinimalGameplayHUD"
	add_child(text_policy)
	# Load the large cinematic dependencies while the title screen is visible.
	ResourceLoader.load_threaded_request(BREACH_RESOURCE, "Script", true)
	if get_tree().root.has_meta(START_GAME_META):
		var start_mode: Variant = get_tree().root.get_meta(START_GAME_META)
		get_tree().root.remove_meta(START_GAME_META)
		if start_mode is String and start_mode == "intro":
			_show_home()
			_start_new_game_intro.call_deferred()
		elif start_mode is String and start_mode == "boss":
			_show_home()
			_start_last_boss_test.call_deferred()
		else:
			_continue_game()
	else:
		_show_home()


func _build_menu() -> void:
	_build_menu_theme()
	menu_layer = CanvasLayer.new()
	menu_layer.name = "FrontEndLayer"
	menu_layer.layer = 20
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)
	overlay = ColorRect.new()
	overlay.name = "MenuOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.008, 0.006, 0.012, 0.12)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_background = TextureRect.new()
	title_background.name = "ShadowBornTitleArt"
	title_background.texture = load("res://assets/ui/shadowborn_title_background.png")
	title_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	title_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(title_background)
	menu_atmosphere = preload("res://menu_atmosphere.gd").new()
	title_background.add_child(menu_atmosphere)
	menu_layer.add_child(overlay)

	home_panel = _make_panel("FAST in Flames", true)
	var home_box := home_panel.get_node("Margin/VBox") as VBoxContainer
	home_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	home_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	home_panel.size = Vector2(412, 520)
	var home_margin := home_panel.get_node("Margin") as MarginContainer
	for side in ["left", "right", "top", "bottom"]:
		home_margin.add_theme_constant_override("margin_" + side, 0)
	home_box.add_theme_constant_override("separation", 13)
	var kicker := Label.new()
	kicker.text = "F A S T   /   T H E   S H A D O W   B R E A C H"
	kicker.add_theme_font_size_override("font_size", 11)
	kicker.add_theme_color_override("font_color", Color(0.81, 0.58, 0.34))
	home_box.add_child(kicker)
	home_box.move_child(kicker, 0)
	var home_heading := home_box.get_node("PanelHeading") as Label
	home_heading.add_theme_font_size_override("font_size", 45)
	home_heading.add_theme_color_override("font_color", Color(0.97, 0.88, 0.70))
	var lore := Label.new()
	lore.text = "A blade born of fire. A soul bound to shadow.\nParry the darkness. Ignite the blade."
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.add_theme_font_size_override("font_size", 16)
	lore.add_theme_color_override("font_color", Color(0.72, 0.70, 0.67))
	home_box.add_child(lore)
	_add_button(home_box, "NEW GAME", Callable(self, "_new_game"))
	_add_button(home_box, "CONTINUE", Callable(self, "_continue_game"))
	_add_button(home_box, "TEST: LAST BOSS", Callable(self, "_skip_to_last_boss"))
	_add_button(home_box, "OPTIONS", Callable(self, "_show_options"))
	_add_button(home_box, "QUIT", Callable(self, "_quit_game"))
	var promise := Label.new()
	promise.text = "FIND THE RELICS. REVERSE THE BREACH."
	promise.add_theme_font_size_override("font_size", 11)
	promise.add_theme_color_override("font_color", Color(0.57, 0.48, 0.37))
	home_box.add_child(promise)
	menu_layer.add_child(home_panel)

	options_panel = _make_panel("OPTIONS", true)
	options_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	options_panel.offset_left = 46.0
	options_panel.offset_right = 546.0
	options_panel.offset_top = 24.0
	options_panel.offset_bottom = -24.0
	var options_box := options_panel.get_node("Margin/VBox") as VBoxContainer
	options_box.add_theme_constant_override("separation", 12)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options_box.add_child(scroll)
	var settings := VBoxContainer.new()
	settings.name = "Settings"
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_theme_constant_override("separation", 12)
	scroll.add_child(settings)
	DisplaySettings.create_volume_controls(settings)
	DisplaySettings.create_music_controls(settings)
	DisplaySettings.create_controls(settings)
	var quality_picker := OptionButton.new()
	quality_picker.add_item("Performance — sparse grass")
	quality_picker.add_item("Balanced")
	quality_picker.add_item("High — dense vegetation")
	var map := get_node("CampusMap")
	quality_picker.selected = map.quality
	quality_picker.item_selected.connect(map.apply_quality)
	settings.add_child(quality_picker)
	var distance_label := Label.new()
	distance_label.text = "RENDER DISTANCE"
	distance_label.add_theme_color_override("font_color", Color(1.0, 0.66, 0.3))
	settings.add_child(distance_label)
	var distance_picker := OptionButton.new()
	distance_picker.name = "RenderDistance"
	distance_picker.add_item("Near — best performance")
	distance_picker.add_item("Standard")
	distance_picker.add_item("Far")
	distance_picker.selected = map.render_distance
	distance_picker.item_selected.connect(map.apply_render_distance)
	settings.add_child(distance_picker)
	var controls_heading := Label.new()
	controls_heading.text = "CONTROLS"
	controls_heading.add_theme_font_size_override("font_size", 18)
	controls_heading.add_theme_color_override("font_color", Color(1.0, 0.66, 0.3))
	settings.add_child(controls_heading)
	var controls := Label.new()
	controls.name = "ControlsReference"
	controls.text = "WASD Move  |  Shift Sprint  |  Ctrl Crouch\nSpace Jump  |  X Jump Attack\nMouse Look  |  Scroll Wheel Zoom\nF Parry  |  RMB Parry, then hold to Block\nQ Shadow Dash  |  C Soul Steal\nLMB Fire Attack  |  MMB Hold: Channel Fire\nRelease MMB: Air Slash\nE Ultimate: Inferno (area blast)\nG Ultimate: Focused Strike\nO Collect Relic  |  V Free Camera\nFree Camera: WASD Fly  |  Space/Ctrl Up/Down\nShift Fast  |  V/Esc Return\nEsc Menu  |  F11 / Alt+Enter Fullscreen\n\nSoul Steal: shadow strikes nearby enemies in sequence,\nrestoring 10 health per hit (10s cooldown).\nFire: orange first layer, violet second layer.\nAttacks and decay spend the same reserve.\nFull violet unlocks E/G; an ultimate uses it all.\nThree amber marks: triple strike, parry all three.\n\nPractice: R Add 100 Fire  |  P Kill All"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_font_size_override("font_size", 15)
	controls.add_theme_color_override("font_color", Color(0.82, 0.87, 0.98))
	settings.add_child(controls)
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
	victory_panel = _make_panel("FAST SAVED", true)
	var victory_box := victory_panel.get_node("Margin/VBox") as VBoxContainer
	var victory_text := Label.new()
	victory_text.text = "You saved FAST successfully.\n\nThe meteor has been redirected to NUST."
	victory_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	victory_text.add_theme_font_size_override("font_size", 20)
	victory_box.add_child(victory_text)
	_add_button(victory_box, "EXPLORE", _continue_game)
	_add_button(victory_box, "NEW GAME", _new_game)
	_add_button(victory_box, "HOME", _show_home)
	menu_layer.add_child(victory_panel)
	_build_menu_details()
	get_viewport().size_changed.connect(_layout_menu_panels)
	_layout_menu_panels.call_deferred()

func _build_menu_theme() -> void:
	menu_theme = Theme.new()
	var body_font := SystemFont.new()
	body_font.font_names = PackedStringArray(["Segoe UI", "Arial"])
	menu_theme.default_font = body_font
	menu_theme.default_font_size = 16
	title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["Georgia", "Times New Roman"])
	title_font.font_weight = 700
	for control in ["Label", "CheckButton", "OptionButton"]:
		menu_theme.set_color("font_color", control, Color(0.84, 0.81, 0.75))
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.055, 0.039, 0.031, 0.92)
	field.border_color = Color(0.34, 0.24, 0.15)
	field.set_border_width_all(1)
	field.content_margin_left = 12
	field.content_margin_right = 28
	field.content_margin_top = 8
	field.content_margin_bottom = 8
	menu_theme.set_stylebox("normal", "OptionButton", field)
	var hover := field.duplicate() as StyleBoxFlat
	hover.border_color = Color(0.89, 0.48, 0.18)
	menu_theme.set_stylebox("hover", "OptionButton", hover)
	menu_theme.set_stylebox("focus", "OptionButton", hover)
	menu_theme.set_stylebox("pressed", "OptionButton", hover)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(0.14, 0.10, 0.08)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	menu_theme.set_stylebox("slider", "HSlider", slider)
	var fill := slider.duplicate() as StyleBoxFlat
	fill.bg_color = Color(0.77, 0.35, 0.10)
	menu_theme.set_stylebox("grabber_area", "HSlider", fill)
	fill = fill.duplicate() as StyleBoxFlat
	fill.bg_color = Color(1, 0.65, 0.28)
	menu_theme.set_stylebox("grabber_area_highlight", "HSlider", fill)

func _build_menu_details() -> void:
	var chapter := Label.new()
	chapter.name = "MenuChapter"
	chapter.text = "C H A P T E R   0 1\nTHE SHADOW BREACH"
	chapter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chapter.position = Vector2(-420, 52)
	chapter.size = Vector2(356, 48)
	chapter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chapter.add_theme_font_size_override("font_size", 12)
	chapter.add_theme_color_override("font_color", Color(0.72, 0.65, 0.54, 0.8))
	chapter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_background.add_child(chapter)
	for right in [false, true]:
		var footer := Label.new()
		footer.text = "PARRY  /  IGNITE  /  SURVIVE" if not right else "THE FLAME REMEMBERS"
		footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT if right else Control.PRESET_BOTTOM_LEFT)
		footer.position = Vector2(-420 if right else 64, -48)
		footer.size = Vector2(356, 24)
		footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
		footer.add_theme_font_size_override("font_size", 11)
		footer.add_theme_color_override("font_color", Color(0.78, 0.66, 0.49, 0.95))
		footer.add_theme_color_override("font_outline_color", Color(0.015, 0.009, 0.006, 0.9))
		footer.add_theme_constant_override("outline_size", 4)
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_background.add_child(footer)

func _layout_menu_panels() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var width := minf(412, viewport.x - 80)
	home_panel.size.x = width
	home_panel.size.y = home_panel.get_combined_minimum_size().y
	home_panel.position = Vector2(64, maxf(42, (viewport.y - home_panel.size.y) * 0.46))
	options_panel.offset_right = minf(546, viewport.x - 30)


func _make_panel(title: String, left_aligned: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme = menu_theme
	panel.name = title.replace(" ", "").replace(":", "") + "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT if left_aligned else Control.PRESET_CENTER)
	panel.position = Vector2(46.0, -220.0) if left_aligned else Vector2(-190.0, -220.0)
	panel.size = Vector2(420.0, 440.0) if left_aligned else Vector2(380.0, 440.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.019, 0.018, 0.95)
	style.border_color = Color(0.48, 0.29, 0.15, 0.80)
	style.set_border_width_all(1)
	style.border_width_top = 2
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
	heading.name = "PanelHeading"
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.add_theme_font_override("font", title_font)
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", Color(0.95, 0.78, 0.53))
	heading.add_theme_constant_override("shadow_offset_x", 2)
	heading.add_theme_constant_override("shadow_offset_y", 2)
	heading.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	box.add_child(heading)
	var divider := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(0.62, 0.37, 0.17, 0.6)
	line.thickness = 1
	divider.add_theme_stylebox_override("separator", line)
	box.add_child(divider)
	return panel


func _add_button(parent: VBoxContainer, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.name = label.replace(" ", "") + "Button"
	button.text = label
	button.custom_minimum_size = Vector2(0.0, 52.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color(0.86, 0.88, 0.94))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.74, 0.42))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.42, 0.12))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.055, 0.040, 0.032, 0.67)
	normal.border_color = Color(0.33, 0.24, 0.16, 0.7)
	normal.set_border_width_all(1)
	normal.border_width_left = 3
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	normal.corner_radius_top_left = 3
	normal.corner_radius_top_right = 3
	normal.corner_radius_bottom_left = 3
	normal.corner_radius_bottom_right = 3
	if label == "NEW GAME":
		normal.bg_color = Color(0.17, 0.065, 0.022, 0.82)
		normal.border_color = Color(0.73, 0.40, 0.16, 0.86)
		button.add_theme_color_override("font_color", Color(1.0, 0.83, 0.61))
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.09, 0.028, 0.88)
	hover.border_color = Color(0.95, 0.51, 0.19, 0.95)
	hover.shadow_color = Color(1, 0.28, 0.025, 0.16)
	hover.shadow_size = 9
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.55, 0.16, 0.04, 0.9)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.pressed.connect(callback)
	parent.add_child(button)
	var arrow := Label.new()
	arrow.name = "HoverArrow"
	arrow.text = "\u203a"
	arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	arrow.position = Vector2(-32, -18)
	arrow.size = Vector2(18, 36)
	arrow.add_theme_font_size_override("font_size", 27)
	arrow.add_theme_color_override("font_color", Color(1, 0.63, 0.26))
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.modulate.a = 0
	button.add_child(arrow)
	var hover_state := {"tween": null}
	var animate_hover := func(active: bool) -> void:
		if hover_state.tween != null and hover_state.tween.is_valid():
			hover_state.tween.kill()
		var tween := button.create_tween().set_parallel(true)
		hover_state.tween = tween
		tween.tween_property(arrow, "modulate:a", 1.0 if active else 0.0, 0.16)
		tween.tween_property(arrow, "position:x", -28.0 if active else -34.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		menu_atmosphere.hover_heat = 1.0 if active else 0.0
	button.mouse_entered.connect(animate_hover.bind(true))
	button.mouse_exited.connect(animate_hover.bind(false))
	button.focus_entered.connect(animate_hover.bind(true))
	button.focus_exited.connect(animate_hover.bind(false))


func _set_menu_visible(panel: Control) -> void:
	_close_free_camera(false)
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
			enemy.process_mode = Node.PROCESS_MODE_DISABLED if enabled and is_instance_valid(player) and player.is_using_ultimate else gameplay_mode


func _show_home() -> void:
	_set_menu_visible(home_panel)


func _show_options() -> void:
	_set_menu_visible(options_panel)


func _input(event: InputEvent) -> void:
	if opening_loading:
		return
	if is_instance_valid(ending_intro):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
			ending_intro.finish()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(opening_intro):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
			opening_intro.finish()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		if is_instance_valid(free_camera):
			_close_free_camera()
		elif session_started and not get_tree().paused and not is_instance_valid(ending_intro):
			var player := get_node("Player")
			if player.is_alive and not player.is_using_ultimate and get_viewport().get_camera_3d() == player.camera:
				_open_free_camera()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_instance_valid(free_camera):
			_close_free_camera()
			get_viewport().set_input_as_handled()
			return
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
	if is_instance_valid(opening_intro) or is_instance_valid(ending_intro) or opening_loading:
		return
	_close_free_camera(false)
	session_started = true
	_ensure_breach_world()
	_set_gameplay_process_enabled(true)
	get_tree().paused = false
	title_background.visible = false
	overlay.visible = false
	home_panel.visible = false
	options_panel.visible = false
	death_panel.visible = false
	victory_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func play_ending() -> void:
	if is_instance_valid(ending_intro) or ending_completed:
		return
	_ensure_breach_world()
	for panel in [home_panel, options_panel, death_panel, victory_panel, title_background, overlay]:
		panel.hide()
	get_tree().paused = false
	ending_intro = preload("res://breach_ending.gd").new()
	ending_intro.name = "EndingCinematic"
	ending_intro.player = get_node("Player")
	ending_intro.world = breach_world
	ending_intro.finished.connect(_ending_finished)
	add_child(ending_intro)

func _ending_finished() -> void:
	ending_intro = null
	ending_completed = true
	_set_menu_visible(victory_panel)
	title_background.hide() # Keep the restored, sunny campus behind the result.


func _new_game() -> void:
	if opening_loading or is_instance_valid(opening_intro):
		return
	_close_free_camera(false)
	if not session_started:
		_start_new_game_intro()
		return
	get_tree().root.set_meta(START_GAME_META, "intro")
	get_tree().paused = false
	get_tree().reload_current_scene()


func _skip_to_last_boss() -> void:
	get_tree().root.set_meta(START_GAME_META, "boss")
	get_tree().paused = false
	get_tree().reload_current_scene()


func _start_last_boss_test() -> void:
	_continue_game()
	var player := get_node("Player") as CharacterBody3D
	var director := get_node("EncounterDirector")
	player.global_position = _find_clear_boss_test_spawn(player)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	director.relic_count = 3
	director.relic_phase = director.PHASE_PORTAL
	director.stage = director.STAGES.size() - 1
	director._insert_relics()


func _find_clear_boss_test_spawn(player: CharacterBody3D) -> Vector3:
	var collider := player.get_node("CollisionShape3D") as CollisionShape3D
	var candidates := [
		Vector3(53.0, 6.56, -95.0),
		Vector3(43.0, 6.56, -93.0),
		Vector3(53.0, 6.56, -99.0),
		Vector3(43.0, 6.56, -98.0),
	]
	for candidate: Vector3 in candidates:
		var floor_ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 2.0, candidate + Vector3.DOWN * 2.0, 1)
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_ray)
		if floor_hit.is_empty() or absf(floor_hit.position.y - candidate.y) > 0.45 or floor_hit.normal.y < 0.75:
			continue
		var position: Vector3 = floor_hit.position + Vector3.UP * 0.08
		var clearance := PhysicsShapeQueryParameters3D.new()
		clearance.shape = collider.shape
		clearance.transform = Transform3D(Basis.IDENTITY, position + collider.position)
		clearance.collision_mask = 1
		clearance.exclude = [player.get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(clearance, 1).is_empty():
			return position
	push_warning("No fully clear rooftop test spawn found")
	return Vector3(53.0, 6.7, -95.0)

func _start_new_game_intro() -> void:
	if opening_loading:
		return
	opening_loading = true
	loading_label = Label.new()
	loading_label.text = "ENTERING THE BREACH…"
	loading_label.position = Vector2(48, 650)
	loading_label.add_theme_color_override("font_color", Color(1, 0.65, 0.3))
	menu_layer.add_child(loading_label)
	# Paint feedback before constructing the cinematic nodes on the main thread.
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	while ResourceLoader.load_threaded_get_status(BREACH_RESOURCE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(BREACH_RESOURCE) == ResourceLoader.THREAD_LOAD_LOADED:
		breach_script = ResourceLoader.load_threaded_get(BREACH_RESOURCE)
	loading_label.queue_free()
	opening_loading = false
	session_started = true
	_begin_opening()


func _respawn() -> void:
	_close_free_camera(false)
	get_tree().root.set_meta(START_GAME_META, true)
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit_game() -> void:
	get_tree().quit()


func _setup_game_music() -> void:
	game_music = AudioStreamPlayer.new()
	game_music.name = "GameMusic"
	game_music.process_mode = Node.PROCESS_MODE_ALWAYS
	game_music.stream = preload("res://assets/audio/fast_rewind_score.wav")
	game_music.volume_db = linear_to_db(maxf(DisplaySettings.get_music_volume(), 0.0001))
	game_music.finished.connect(game_music.play)
	DisplaySettings.music_volume_changed.connect(_set_music_volume)
	add_child(game_music)
	game_music.play()


func _set_music_volume(percent: float) -> void:
	game_music.volume_db = linear_to_db(maxf(percent / 100.0, 0.0001))
	game_music.stream_paused = percent <= 0.0


func _open_free_camera() -> void:
	free_camera = preload("res://free_camera.gd").new()
	free_camera.name = "FreeCameraMode"
	add_child(free_camera)
	free_camera.call("begin", get_viewport().get_camera_3d())
	get_tree().paused = true


func _close_free_camera(resume: bool = true) -> void:
	if not is_instance_valid(free_camera):
		return
	free_camera.call("finish")
	free_camera.queue_free()
	free_camera = null
	if resume:
		get_tree().paused = false


func _ensure_breach_world() -> void:
	if is_instance_valid(breach_world):
		return
	breach_world = Node3D.new()
	breach_world.name = "ShadowBreach"
	breach_world.set_script(breach_script if breach_script != null else load(BREACH_RESOURCE))
	add_child(breach_world)


func _begin_opening() -> void:
	if is_instance_valid(opening_intro):
		return
	_ensure_breach_world()
	for panel in [home_panel, options_panel, death_panel, victory_panel, title_background, overlay]:
		panel.hide()
	_set_gameplay_process_enabled(false)
	get_tree().paused = false
	opening_intro = Node3D.new()
	opening_intro.name = "OpeningCinematic"
	opening_intro.set_script(load("res://breach_intro.gd"))
	opening_intro.player = get_node("Player")
	opening_intro.world = breach_world
	opening_intro.finished.connect(_opening_finished)
	add_child(opening_intro)


func _opening_finished() -> void:
	opening_intro = null
	_continue_game()
