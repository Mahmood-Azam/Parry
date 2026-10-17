extends SceneTree
## Run without --headless to verify native Windows mode and actual input routing.
var original_preference: bool
var display: Node

func _initialize() -> void:
	create_timer(45.0, true).timeout.connect(func(): push_error("Fullscreen test timed out"); quit(1))
	call_deferred("run")

func settle() -> void:
	for frame in 5:
		await process_frame

func key(code: Key, alt: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.alt_pressed = alt
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	await settle()
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	Input.parse_input_event(event)
	await settle()

func check_fullscreen(expected: bool) -> void:
	assert(display.get_fullscreen() == expected)
	if DisplayServer.get_name() != "headless":
		assert((root.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]) == expected)
		if expected:
			var desktop := DisplayServer.screen_get_size(root.current_screen)
			print("NATIVE mode=",root.mode," output=",root.size," desktop=",desktop)
			assert(root.size == desktop)

func run() -> void:
	display = root.get_node("DisplaySettings")
	original_preference = display.get_fullscreen()
	display.set_fullscreen(false)
	await settle()
	var window_size := root.size
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	scene._show_options()
	var checkbox := scene.options_panel.get_node("Margin/VBox/DisplaySettingsControls/Fullscreen") as CheckButton
	checkbox.grab_focus()
	assert(paused)
	await key(KEY_F11)
	check_fullscreen(true)
	assert(checkbox.button_pressed)
	await key(KEY_F11, false, true)
	check_fullscreen(true)
	await key(KEY_ENTER, true)
	check_fullscreen(false)
	assert(root.size == window_size and not checkbox.button_pressed)
	print("PASS focused Options: F11, Alt+Enter, ignore repeat, native desktop resolution, window restore")
	checkbox.button_pressed = true
	await settle()
	check_fullscreen(true)
	checkbox.button_pressed = false
	await settle()
	check_fullscreen(false)
	print("PASS Options fullscreen checkbox")
	# Reproduce stale UI state: enabling must retry, not trust a cached bool.
	display._fullscreen = true
	display.set_fullscreen(true)
	await settle()
	check_fullscreen(true)
	scene._continue_game()
	await key(KEY_F11)
	check_fullscreen(false)
	print("PASS stale-state recovery and gameplay shortcut")
	display.set_fullscreen(original_preference)
	await settle()
	print("PASS fullscreen regression suite")
	quit()
