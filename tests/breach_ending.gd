extends SceneTree
var failures := 0
var scene: Node3D

func _initialize() -> void:
	create_timer(45.0, true).timeout.connect(func(): push_error("Ending test timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/ending_" + label + ".png")

func run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene._continue_game()
	var player: CharacterBody3D = scene.get_node("Player")
	var director: Node3D = scene.get_node("EncounterDirector")
	var world: Node3D = scene.breach_world
	for i in 5:
		await physics_frame
	# Go through the real arrival and death signal, not a disconnected movie.
	director.relic_phase = director.PHASE_PORTAL
	director.relic_count = 3
	player.global_position = world.gate_point + Vector3(0, 0.1, 1)
	player.velocity = Vector3.ZERO
	director._insert_relics()
	var boss: CharacterBody3D = director.bara
	check(is_instance_valid(boss), "Three relics summon Bara Ustaad")
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in boss.skeleton_model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (boss.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	check(bounds.size.y >= 8.4 and bounds.size.y <= 8.8, "Boss visual is 8.6 m tall, slightly larger than the portal")
	var collider := boss.get_node("CollisionShape3D") as CollisionShape3D
	check(is_equal_approx(collider.shape.height, 8.6) and is_equal_approx(collider.position.y, 4.3), "Giant boss collision fits its height and stays rooted at its feet")
	await create_timer(1.9).timeout
	await capture("arrival_wide")
	await create_timer(1.25).timeout
	check(not is_instance_valid(director.arrival) and boss.is_physics_processing(), "Large boss arrival hands off to combat")
	boss.set_physics_process(false)
	await capture("giant_boss")
	boss.take_damage(999999, player)
	await process_frame
	await process_frame
	var movie: Node3D = scene.ending_intro
	check(is_instance_valid(movie) and director.completed, "Killing Bara Ustaad automatically starts the ending once")
	if not is_instance_valid(movie):
		quit(1)
		return
	check(player.global_position.distance_to(movie.FIELD) < 6 and player.global_position.y < 1, "Player leaves the roof for a checked field position before restoration")
	check(player.process_mode == Node.PROCESS_MODE_DISABLED and player.is_invulnerable, "Ending protects and locks the player during reversal")
	var elapsed: float = movie.elapsed
	paused = true
	await create_timer(0.12, true).timeout
	check(movie.elapsed == elapsed, "Reversal cutscene respects a paused tree")
	paused = false
	await create_timer(2.2).timeout
	check(movie.reversal_started and world.meteor.global_position.y > world.impact_point.y, "Meteor visibly retraces the opening into the sky")
	await capture("reversal")
	await create_timer(3.0).timeout
	check(not world.destruction.destroyed, "Reversed collapse restores the original buildings")
	await capture("redirected")
	await create_timer(4.2).timeout
	check(movie.title.modulate.a > 0.9 and movie.subtitle.self_modulate.a == 1, "Ending text remains visible despite the minimal gameplay HUD")
	check("FAST" in movie.title.text and "NUST" in movie.subtitle.text, "Ending carries the requested FAST/NUST message")
	await capture("message")
	await create_timer(1.9, true).timeout
	check(movie.video_started and movie.impact_video.is_playing() and not paused, "Supplied NUST impact clip plays after the in-engine ending")
	check(player.process_mode == Node.PROCESS_MODE_DISABLED, "Gameplay remains frozen throughout the NUST clip")
	check(movie.impact_video.bus == &"Master", "Clip audio follows the in-game volume setting")
	await create_timer(1.0, true).timeout
	await capture("nust_impact_video")
	# Check real playback near its end, not a manually sampled fade function.
	while is_instance_valid(movie) and movie.impact_video.stream_position < 3.48:
		await process_frame
	check(is_instance_valid(movie) and movie.video_fade > 0.35 and movie.impact_video.modulate.a < 0.65, "Final meteor frames fade smoothly to black before playback ends")
	check(is_instance_valid(movie) and movie.impact_video.volume_db < -3.0, "Clip audio fades with the final frames")
	await capture("nust_fading_out")
	await create_timer(0.85, true).timeout
	check(scene.ending_completed and scene.victory_panel.visible and paused, "Ending completes into a paused victory menu")
	check(not world.gate.visible and not world.meteor.visible and not world.scorch.visible, "Restored campus has no portal, meteor or scorch mark")
	check(root.get_camera_3d() == player.camera, "Player camera is restored after the ending")
	check(not player.is_invulnerable and player.velocity == Vector3.ZERO, "Ending clears motion and temporary protection")
	scene._continue_game()
	for i in 45:
		await physics_frame
	check(player.is_on_floor() and player.global_position.y > -0.1 and player.global_position.distance_to(Vector3(18, 0, -55)) < 6, "Explore resumes grounded in the field without clipping")
	await capture("explore")
	scene.play_ending()
	check(not is_instance_valid(scene.ending_intro), "Victory cannot restart the ending accidentally")
	# Exercise an early skip separately; restored collision must not strand us.
	scene.ending_completed = false
	world.show_aftermath()
	player.global_position = world.gate_point
	scene.play_ending()
	movie = scene.ending_intro
	movie.finish()
	await process_frame
	check(scene.ending_completed and not world.destruction.destroyed and not world.gate.visible, "Skipping finalizes restoration rather than leaving a half-reversed world")
	scene._continue_game()
	for i in 20:
		await physics_frame
	check(player.is_on_floor() and player.global_position.y < 1, "Skipping also returns the player safely to the field")
	scene.ending_completed = false
	scene.play_ending()
	movie = scene.ending_intro
	movie._begin_impact_video()
	await create_timer(0.3).timeout
	var video: VideoStreamPlayer = movie.impact_video
	check(video.is_playing(), "NUST clip can also be started for a skip check")
	var skip := InputEventKey.new()
	skip.keycode = KEY_SPACE
	skip.pressed = true
	Input.parse_input_event(skip)
	await process_frame
	await process_frame
	check(scene.ending_completed and scene.victory_panel.visible and paused, "Space skips the NUST video into the victory screen")
	check(not is_instance_valid(video) or not video.is_playing(), "Skipping stops the video and its audio")
	print("Ending checks complete, failures=", failures)
	quit(1 if failures else 0)
