extends Node
## Add as an autoload named DisplaySettings, or as a persistent Node.
## Call create_controls(options_vbox) after this service has entered the tree.

signal fullscreen_changed(enabled: bool)
signal resolution_changed(description: String)

const SETTINGS_PATH := "user://shadowborn_settings.cfg"
const BASE_SIZE := Vector2i(1280, 720)
const POLL_SECONDS := 0.5

var _config := ConfigFile.new()
var _fullscreen := false
var _window: Window
var _windowed_size := BASE_SIZE
var _windowed_position := Vector2i.ZERO
var _screen := -1
var _native_size := Vector2i.ZERO
var _screen_count := -1
var _transition_id := 0
var _changing_mode := false
var _windowed_mode: Window.Mode = Window.MODE_WINDOWED
var _reported_fullscreen := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_window = get_tree().root
	# Keep the same logical canvas and aspect behavior as the project.
	# Native resolution affects window output, not a user-controlled UI scale.
	_window.content_scale_size = BASE_SIZE
	_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_windowed_size = _window.size
	_windowed_position = _window.position
	if _native_fullscreen():
		_windowed_size = BASE_SIZE
	elif _window.mode == Window.MODE_MAXIMIZED:
		_windowed_mode = Window.MODE_MAXIMIZED
	var error := _config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Display settings could not be loaded: %s" % error_string(error))
	var saved_value: Variant = _config.get_value("display", "fullscreen", true)
	_fullscreen = saved_value if saved_value is bool else false
	# A launch-time fullscreen request must not be undone by an old preference.
	# Project startup is native fullscreen so the editor cannot embed the game.
	# The saved windowed choice still wins unless explicitly overridden by CLI.
	if "--fullscreen" in OS.get_cmdline_args() or "-f" in OS.get_cmdline_args():
		_fullscreen = true
	elif "--windowed" in OS.get_cmdline_args() or "-w" in OS.get_cmdline_args():
		_fullscreen = false
	_changing_mode = true
	_poll_display()
	_apply_fullscreen()
	_changing_mode = false
	_reported_fullscreen = get_fullscreen()
	_window.focus_entered.connect(_restore_fullscreen_on_focus)
	var timer := Timer.new()
	timer.name = "DisplayRefreshTimer"
	timer.wait_time = POLL_SECONDS
	timer.timeout.connect(_poll_display)
	add_child(timer)
	timer.start()


func get_fullscreen() -> bool:
	return _fullscreen if _changing_mode or DisplayServer.get_name() == "headless" else _native_fullscreen()


func _native_fullscreen() -> bool:
	return is_instance_valid(_window) and _window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]


func set_fullscreen(enabled: bool) -> void:
	if Engine.is_embedded_in_editor():
		# An already-running embedded session must be restarted after installing
		# this fix. Never claim that an embedded preview became fullscreen.
		fullscreen_changed.emit(false)
		return
	if not _changing_mode and enabled == get_fullscreen() and enabled == _fullscreen:
		return
	if enabled and not _fullscreen and is_instance_valid(_window) and not _native_fullscreen() and not _changing_mode:
		_windowed_size = _window.size
		_windowed_position = _window.position
		_windowed_mode = Window.MODE_MAXIMIZED if _window.mode == Window.MODE_MAXIMIZED else Window.MODE_WINDOWED
	_fullscreen = enabled
	_transition_id += 1
	var request := _transition_id
	_changing_mode = true
	_apply_fullscreen()
	# Let Windows apply its native mode before updating the checkbox or saving.
	for frame in 12:
		await get_tree().process_frame
		if request != _transition_id:
			return
		if frame >= 1 and (DisplayServer.get_name() == "headless" or _native_fullscreen() == enabled):
			break
	if request != _transition_id:
		return
	if DisplayServer.get_name() != "headless":
		_fullscreen = _native_fullscreen()
	_changing_mode = false
	# Reuse the loaded config so other settings sections survive saving.
	_config.set_value("display", "fullscreen", _fullscreen)
	var error := _config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Display settings could not be saved: %s" % error_string(error))
	fullscreen_changed.emit(_fullscreen)
	_reported_fullscreen = _fullscreen


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	# Handle before GUI controls, which can consume Enter/F11 in paused menus.
	var code := key.keycode if key.keycode != 0 else key.physical_keycode
	if code == KEY_F11 or (key.alt_pressed and code in [KEY_ENTER, KEY_KP_ENTER]):
		set_fullscreen(not get_fullscreen())
		get_viewport().set_input_as_handled()


func _apply_fullscreen() -> void:
	if not is_instance_valid(_window) or DisplayServer.get_name() == "headless":
		return
	if _fullscreen:
		# Do not resize a fullscreen Window: native fullscreen already matches
		# the desktop, and post-mode size writes can undo a native transition.
		# Borderless native fullscreen stays at desktop resolution and does not
		# lose its fullscreen mode when Windows switches focus or shows overlays.
		_window.mode = Window.MODE_FULLSCREEN
	else:
		_window.mode = Window.MODE_WINDOWED
		_window.size = _windowed_size
		_window.position = _windowed_position
		if _windowed_mode == Window.MODE_MAXIMIZED:
			_window.mode = Window.MODE_MAXIMIZED


func _refresh_native_fullscreen() -> void:
	if _fullscreen and _native_fullscreen():
		# Native modes size themselves. Reassert only after a monitor change.
		_window.mode = Window.MODE_FULLSCREEN


func _restore_fullscreen_on_focus() -> void:
	if _fullscreen and not _changing_mode and not _native_fullscreen() and not Engine.is_embedded_in_editor():
		set_fullscreen(true)


func _poll_display() -> void:
	if not is_instance_valid(_window) or DisplayServer.get_name() == "headless":
		return
	var count := DisplayServer.get_screen_count()
	if count <= 0:
		return
	var screen := clampi(_window.current_screen, 0, count - 1)
	var native_size := DisplayServer.screen_get_size(screen)
	if not _changing_mode and _reported_fullscreen != _native_fullscreen():
		# A temporary native transition must not erase the user's preference.
		_reported_fullscreen = _native_fullscreen()
		fullscreen_changed.emit(_reported_fullscreen)
	if screen == _screen and native_size == _native_size and count == _screen_count:
		return
	_screen = screen
	_native_size = native_size
	_screen_count = count
	_refresh_native_fullscreen()
	resolution_changed.emit(_resolution_description())


func _resolution_description() -> String:
	if _native_size.x <= 0 or _native_size.y <= 0:
		return "Resolution: Native (Automatic)"
	return "Resolution: %d × %d — Native (Automatic)" % [_native_size.x, _native_size.y]


func create_controls(parent: VBoxContainer) -> VBoxContainer:
	var controls := VBoxContainer.new()
	controls.name = "DisplaySettingsControls"
	# Controls and keyboard shortcuts remain available in a paused menu.
	controls.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(controls)
	var fullscreen_button := CheckButton.new()
	fullscreen_button.name = "Fullscreen"
	fullscreen_button.text = "Fullscreen"
	fullscreen_button.tooltip_text = "Toggle with F11 or Alt+Enter"
	fullscreen_button.disabled = Engine.is_embedded_in_editor()
	if fullscreen_button.disabled:
		fullscreen_button.text = "Fullscreen — restart game in native window"
	fullscreen_button.set_pressed_no_signal(get_fullscreen())
	fullscreen_button.toggled.connect(set_fullscreen)
	fullscreen_changed.connect(fullscreen_button.set_pressed_no_signal)
	controls.add_child(fullscreen_button)
	var resolution_label := Label.new()
	resolution_label.name = "NativeResolution"
	resolution_label.text = _resolution_description()
	resolution_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resolution_changed.connect(resolution_label.set_text)
	controls.add_child(resolution_label)
	return controls
