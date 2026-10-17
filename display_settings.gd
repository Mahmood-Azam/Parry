extends Node
## Add as an autoload named DisplaySettings, or as a persistent Node.
## Call create_controls(options_vbox) after this service has entered the tree.

signal fullscreen_changed(enabled: bool)
signal resolution_changed(description: String)
signal master_volume_changed(percent: float)
signal music_volume_changed(percent: float)

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
var _master_volume := 1.0
var _music_volume := 0.4
var _volume_save_timer: Timer
var _volume_dirty := false


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
	var saved_volume: Variant = _config.get_value("audio", "master_volume", 1.0)
	if (saved_volume is float or saved_volume is int) and is_finite(float(saved_volume)):
		_master_volume = clampf(float(saved_volume), 0.0, 1.0)
	var saved_music: Variant = _config.get_value("audio", "music_volume", 0.4)
	if (saved_music is float or saved_music is int) and is_finite(float(saved_music)):
		_music_volume = clampf(float(saved_music), 0.0, 1.0)
	_apply_master_volume()
	_volume_save_timer = Timer.new()
	_volume_save_timer.name = "VolumeSaveTimer"
	_volume_save_timer.one_shot = true
	_volume_save_timer.wait_time = 0.25
	_volume_save_timer.timeout.connect(_save_volume)
	add_child(_volume_save_timer)
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


func get_master_volume() -> float:
	return _master_volume


func get_music_volume() -> float:
	return _music_volume


func set_music_volume(value: float) -> void:
	if not is_finite(value):
		return
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(value, _music_volume):
		return
	_music_volume = value
	_config.set_value("audio", "music_volume", _music_volume)
	_volume_dirty = true
	_volume_save_timer.start()
	music_volume_changed.emit(_music_volume * 100.0)


func set_master_volume(value: float) -> void:
	if not is_finite(value):
		return
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(value, _master_volume):
		return
	_master_volume = value
	_apply_master_volume()
	_config.set_value("audio", "master_volume", _master_volume)
	_volume_dirty = true
	_volume_save_timer.start()
	master_volume_changed.emit(_master_volume * 100.0)


func _apply_master_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(_master_volume, 0.0001)))
	AudioServer.set_bus_mute(bus, _master_volume <= 0.0)


func _save_volume() -> void:
	if not _volume_dirty:
		return
	var error := _config.save(SETTINGS_PATH)
	if error == OK:
		_volume_dirty = false
	else:
		push_warning("Volume setting could not be saved: %s" % error_string(error))


func _exit_tree() -> void:
	_save_volume()


func create_volume_controls(parent: VBoxContainer) -> void:
	var row := VBoxContainer.new()
	row.name = "AudioSettingsControls"
	parent.add_child(row)
	var label := Label.new()
	label.name = "VolumeLabel"
	label.text = "MASTER VOLUME  %d%%" % roundi(_master_volume * 100.0)
	label.add_theme_color_override("font_color", Color(1.0, 0.66, 0.3))
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "MasterVolume"
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = _master_volume * 100.0
	slider.custom_minimum_size.y = 28.0
	slider.tooltip_text = "Adjust all game audio. 0% mutes sound."
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.13, 0.12, 0.12)
	track.content_margin_top = 4.0
	track.content_margin_bottom = 4.0
	track.set_corner_radius_all(4)
	slider.add_theme_stylebox_override("slider", track)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = Color(0.95, 0.35, 0.08)
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	row.add_child(slider)
	slider.value_changed.connect(func(percent: float):
		label.text = "MASTER VOLUME  %d%%" % roundi(percent) if percent > 0 else "MASTER VOLUME  MUTED"
		set_master_volume(percent / 100.0)
	)
	slider.drag_ended.connect(func(_changed: bool): _save_volume())
	master_volume_changed.connect(slider.set_value)
	if _master_volume <= 0.0:
		label.text = "MASTER VOLUME  MUTED"


func create_music_controls(parent: VBoxContainer) -> void:
	var row := VBoxContainer.new()
	row.name = "MusicSettingsControls"
	parent.add_child(row)
	var label := Label.new()
	label.name = "MusicVolumeLabel"
	label.text = "GAME MUSIC  %d%%" % roundi(_music_volume * 100.0)
	label.add_theme_color_override("font_color", Color(1.0, 0.66, 0.3))
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "MusicVolume"
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = _music_volume * 100.0
	slider.custom_minimum_size.y = 28.0
	slider.tooltip_text = "Adjust only the cinematic game music."
	row.add_child(slider)
	slider.value_changed.connect(func(percent: float):
		label.text = "GAME MUSIC  %d%%" % roundi(percent) if percent > 0 else "GAME MUSIC  MUTED"
		set_music_volume(percent / 100.0)
	)
	slider.drag_ended.connect(func(_changed: bool): _save_volume())
	music_volume_changed.connect(slider.set_value)
	if _music_volume <= 0.0:
		label.text = "GAME MUSIC  MUTED"


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
