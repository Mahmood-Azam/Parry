extends SceneTree
var scene: Node3D
var player: CharacterBody3D
func _initialize() -> void:
	create_timer(25.0, true).timeout.connect(func(): push_error("Ultimate menu test timed out"); quit(1))
	call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
func run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene._continue_game()
	player = scene.get_node("Player")
	await create_timer(0.4).timeout
	check(player.is_on_floor(), "Map player must be grounded")
	await key(KEY_R)
	await key(KEY_R)
	check(player.ultimate_controller.is_ready(), "R practice binding must fill two reserve segments")
	await key(KEY_E)
	check(player.is_using_ultimate, "E binding must start Inferno")
	var movie: Node3D = player.ultimate_controller.cinematic
	await create_timer(0.55).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/ultimate_campus.png")
	scene._show_options()
	var elapsed: float = movie.elapsed
	await create_timer(0.25, true).timeout
	check(paused and is_equal_approx(movie.elapsed, elapsed), "Actual Options menu must pause ultimate")
	scene._continue_game()
	await create_timer(0.15).timeout
	check(movie.elapsed > elapsed and player.is_using_ultimate, "Continue must resume cinematic")
	for enemy in get_nodes_in_group("enemy"):
		check(enemy.process_mode == Node.PROCESS_MODE_DISABLED, "Continue must keep cinematic enemies frozen")
	print("PASS R/E bindings, real Options menu pause and safe cinematic resume")
	scene._new_game()
	await create_timer(0.5, true).timeout
	scene = current_scene
	player = scene.get_node("Player")
	check(not player.is_using_ultimate and player.ultimate_controller.charge == 0.0, "New Game must reset reserve and cinematic state")
	check(root.get_camera_3d() == player.camera, "New Game must restore the normal player camera")
	await key(KEY_R)
	await key(KEY_R)
	await key(KEY_G)
	check(player.is_using_ultimate and player.ultimate_controller.cinematic.kind == "focused", "G binding must start focused ultimate")
	await create_timer(1.58).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/ultimate_campus_execution.png")
	await create_timer(1.5).timeout
	check(not player.is_using_ultimate, "Actual map focused cinematic must finish")
	check(root.get_camera_3d() == player.camera, "Actual map cinematic must restore player camera")
	print("PASS New Game mid-cinematic, reserve reset, G binding and normal camera recovery")
	quit()
