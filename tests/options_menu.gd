extends SceneTree
var scene: Node3D
var settings: Node
var original_volume := 1.0
var failures := 0

func _initialize() -> void:
	create_timer(35.0, true).timeout.connect(func(): push_error("Options test timed out"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in 6:
		await process_frame

func run() -> void:
	settings = root.get_node("DisplaySettings")
	original_volume = settings.get_master_volume()
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene._show_options()
	await settle()
	check(paused and scene.options_panel.visible, "Options pauses gameplay")
	var controls := scene.options_panel.find_child("ControlsReference", true, false) as Label
	check(controls != null and "Ctrl Crouch" in controls.text and "Q Shadow Dash" in controls.text and "F11" in controls.text, "Controls reference is complete inside Options")
	var player: Node = scene.get_node("Player")
	player._update_combat_stats()
	check(not "WASD" in player.combat_stats_label.text and "HP:" in player.combat_stats_label.text, "Gameplay HUD keeps stats but no controls list")
	var slider := scene.options_panel.find_child("MasterVolume", true, false) as HSlider
	check(slider != null and slider.min_value == 0 and slider.max_value == 100, "Options has a 0–100 master volume slider")
	slider.value = 37
	check(is_equal_approx(settings.get_master_volume(), 0.37), "Slider updates volume immediately while paused")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.37), "Master audio bus receives the volume setting")
	await create_timer(0.4, true).timeout
	var config := ConfigFile.new()
	config.load(settings.SETTINGS_PATH)
	check(is_equal_approx(float(config.get_value("audio", "master_volume", -1.0)), 0.37), "Volume preference is saved to disk")
	check(config.has_section_key("display", "fullscreen"), "Saving volume preserves display settings")
	slider.value = 0
	check(AudioServer.is_bus_mute(0), "0% genuinely mutes all game audio")
	slider.value = 58
	check(not AudioServer.is_bus_mute(0), "Increasing volume unmutes audio")
	var panel: Control = scene.options_panel
	var scroll := panel.find_child("SettingsScroll", true, false) as ScrollContainer
	check(panel.position.x < root.get_visible_rect().size.x * 0.5 and panel.position.y >= 0, "Options remains left-aligned and inside the viewport")
	check(panel.get_global_rect().end.y <= root.get_visible_rect().size.y + 1, "Options fits the screen vertically")
	check(scroll != null and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Long controls stay in a vertical scroll area")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/options_volume.png")
	scene._continue_game()
	check(not paused and not panel.visible, "Continue resumes gameplay and hides Options")
	scene.free()
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene._show_options()
	await settle()
	slider = scene.options_panel.find_child("MasterVolume", true, false) as HSlider
	check(slider.value == 58, "Rebuilt Options retains the selected volume")
	settings.set_master_volume(original_volume)
	settings._save_volume()
	print("Options checks complete, failures=", failures)
	quit(1 if failures > 0 else 0)
