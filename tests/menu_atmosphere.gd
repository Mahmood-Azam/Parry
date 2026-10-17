extends SceneTree
var failures := 0

func _initialize() -> void:
	create_timer(40, true).timeout.connect(func(): push_error("Menu atmosphere test timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func capture(label: String) -> int:
	if DisplayServer.get_name() == "headless":
		return 0
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	frame.save_png("res://.godot/menu_" + label + ".png")
	return hash(frame.get_data())

func settle() -> void:
	for i in 4:
		await process_frame

func run() -> void:
	var scene: Node3D = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await settle()
	var fx: Control = scene.menu_atmosphere
	var player: CharacterBody3D = scene.get_node("Player")
	var original_position := player.global_position
	var time: float = fx.elapsed
	await create_timer(0.7, true).timeout
	check(paused and scene.home_panel.visible and fx.elapsed > time + 0.5, "Flames animate while the title menu keeps gameplay paused")
	check(player.global_position.is_equal_approx(original_position) and player.process_mode == Node.PROCESS_MODE_DISABLED, "Menu motion never advances the player simulation")
	check(fx.embers.size() == 2 and fx.embers[0].emitting and fx.embers[1].emitting, "Separate near/far ember layers are active")
	var decorations_safe := fx.mouse_filter == Control.MOUSE_FILTER_IGNORE
	for child in fx.find_children("*", "Control", true, false):
		decorations_safe = decorations_safe and child.mouse_filter == Control.MOUSE_FILTER_IGNORE
	check(decorations_safe, "Atmosphere layers cannot intercept menu clicks")
	check(scene.home_panel.get_global_rect().end.y < root.get_visible_rect().size.y - 52, "Title, lore and every button fit above the footer")
	var first := await capture("home")
	await create_timer(0.65, true).timeout
	var second := await capture("home_later")
	if DisplayServer.get_name() != "headless":
		check(first != second, "Rendered title image changes as flames, haze and embers move")
	var options := scene.home_panel.find_child("OPTIONSButton", true, false) as Button
	options.grab_focus()
	await create_timer(0.25, true).timeout
	check(options.get_node("HoverArrow").modulate.a > 0.9 and fx.current_heat > 0.5, "Keyboard focus animates the highlight and warms the fire")
	await capture("hover")
	options.pressed.emit()
	await settle()
	check(scene.options_panel.visible and not scene.home_panel.visible and fx.is_processing(), "Options button works through the effects and retains animation")
	await capture("options")
	var back := scene.options_panel.find_child("BACKButton", true, false) as Button
	back.pressed.emit()
	await settle()
	check(scene.home_panel.visible and not scene.options_panel.visible, "Back returns to the upgraded home menu")
	var continue_button := scene.home_panel.find_child("CONTINUEButton", true, false) as Button
	continue_button.pressed.emit()
	await settle()
	time = fx.elapsed
	await create_timer(0.15, true).timeout
	check(not paused and not fx.is_visible_in_tree() and not fx.is_processing() and fx.elapsed == time, "Continue hides and stops atmosphere work during gameplay")
	check(not fx.embers[0].emitting and fx.embers[0].process_mode == Node.PROCESS_MODE_DISABLED, "Hidden menu does not keep simulating particles")
	scene._show_home()
	await settle()
	check(paused and fx.is_processing() and fx.embers[0].emitting, "Pausing again restores the animated menu")
	print("Menu atmosphere checks complete, failures=", failures)
	quit(1 if failures else 0)
