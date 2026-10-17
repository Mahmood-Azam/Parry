extends SceneTree
var failures := 0

func _initialize() -> void:
	create_timer(30, true).timeout.connect(func(): push_error("Waypoint test timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/waypoint_" + label + ".png")

func run() -> void:
	var scene: Node3D = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene._continue_game()
	var director: Node3D = scene.get_node("EncounterDirector")
	var player: CharacterBody3D = scene.get_node("Player")
	player.is_invulnerable = true
	player.set_physics_process(false)
	player.set_process(false)
	director.set_process(false)
	var camera: Camera3D = player.camera
	var marker: Node3D = director.marker
	camera.global_position = player.global_position + Vector3(4, 5, 8)
	camera.look_at(marker.global_position + Vector3.UP * 1.5)
	await process_frame
	await process_frame
	check(marker.canvas.visible and not marker.offscreen, "Visible objective has a screen-space diamond")
	check(marker.label.self_modulate.a > 0.99 and "COURTYARD" in marker.label.text and "m" in marker.label.text, "Waypoint caption and distance survive the HUD text filter")
	check(marker.label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Markers never capture combat mouse input")
	await capture("courtyard")
	camera.look_at(camera.global_position * 2 - (marker.global_position + Vector3.UP * 1.5))
	await process_frame
	await process_frame
	check(marker.offscreen and root.get_visible_rect().has_point(marker.badge.position), "Destination behind the camera produces a bounded edge arrow")
	await capture("behind_camera")
	scene._show_options()
	await process_frame
	await process_frame
	check(not marker.canvas.visible and not marker.ring.visible, "Options menu hides screen and world markers")
	scene._continue_game()
	await process_frame
	await process_frame
	check(marker.canvas.visible, "Continuing restores navigation")
	# C-101 keeps its actual pickup and map signage, but no guiding waypoint.
	director.relic_phase = director.PHASE_C101_RELIC
	director._place_relic()
	await process_frame
	check(not is_instance_valid(director.marker) and director.relic.name == "C101Relic", "C-101 search has a collectible but no destination marker")
	director._collect_relic()
	check(director.relic_phase == director.PHASE_MUTANT, "Collecting the unmarked C-101 relic still progresses")
	director.owl._unlock_player()
	director.owl.set_process(false)
	director.relic_phase = director.PHASE_PORTAL
	director._set_marker(scene.breach_world.gate_point, "D BLOCK ROOF - PORTAL")
	marker = director.marker
	player.global_position = Vector3(35, 0, -65)
	player.set_physics_process(false)
	camera.make_current()
	camera.global_position = player.global_position + Vector3(4, 4, 8)
	camera.look_at(marker.global_position)
	await process_frame
	await process_frame
	check(marker.canvas.visible and "ABOVE" in marker.label.text, "Rooftop portal points out its height difference")
	await capture("portal")
	director.relic_phase = 0
	director.stage = 0
	director._start_encounter()
	for enemy in director.encounter_enemies:
		enemy.set_physics_process(false)
	var enemy: CharacterBody3D = director.encounter_enemies[0]
	enemy.global_position = player.global_position + Vector3(0, 0, -3)
	director._update_marker_target()
	check(director.marker.global_position.distance_to(enemy.global_position) < 0.2, "Active combat marker follows the nearest remaining encounter enemy")
	director.completed = true
	director._clear_marker()
	check(not is_instance_valid(director.marker), "Clearing an objective synchronously removes its pointer")
	print("Waypoint checks complete, failures=", failures)
	quit(1 if failures else 0)
