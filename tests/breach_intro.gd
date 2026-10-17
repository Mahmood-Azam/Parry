extends SceneTree
var scene: Node3D
var player: CharacterBody3D
var movie: Node3D
var failures := 0

func _initialize() -> void:
	create_timer(65.0, true).timeout.connect(func(): push_error("Breach intro timed out"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		push_error(message)

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/breach_" + label + ".png")

func until(time: float) -> void:
	while is_instance_valid(movie) and movie.elapsed < time:
		await process_frame

func run() -> void:
	root.set_meta("shadowborn_start_game", "intro")
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 4:
		await process_frame
	movie = scene.opening_intro
	check(is_instance_valid(movie), "New Game starts the opening cinematic")
	if not is_instance_valid(movie):
		quit(1)
		return
	player = scene.get_node("Player")
	check(player.process_mode == Node.PROCESS_MODE_DISABLED and scene.get_node("EncounterDirector").process_mode == Node.PROCESS_MODE_DISABLED, "Gameplay and encounters are frozen during opening")
	check(not player.get_node("CombatFeedbackLayer").visible, "Opening has no gameplay HUD")
	check(not player.ultimate_controller.hud.visible, "Ultimate HUD is also hidden during opening")
	check(not scene.breach_world.destruction.destroyed, "Opening begins with intact right-side buildings")
	check(scene.breach_world.gate_point.y > 6.0 and scene.breach_world.gate.position.is_equal_approx(scene.breach_world.gate_point), "Portal already exists inside the roof structure")
	check(scene.breach_world.gate.scale.is_equal_approx(Vector3.ONE), "Portal is revealed, not grown out of thin air")
	check(not scene.breach_world.gate.take_damage(999999.0, player), "Portal rejects meteor and combat damage")
	await until(0.9)
	await capture("01_campus")
	await until(2.6)
	check(scene.breach_world.meteor.visible and scene.breach_world.meteor_trail.emitting, "Imported meteor descends with a fiery trail")
	await capture("02_meteor")
	await until(3.5)
	check(scene.breach_world.impact_started and scene.breach_world.explosion.visible, "Impact plays the imported explosion")
	check(scene.breach_world.explosion_player.is_playing(), "Authored explosion animation is actually playing")
	check(scene.breach_world.destruction.destroyed and scene.breach_world.destruction.rubble.visible, "Meteor breaks the right-side upper buildings and emits rubble")
	check(scene.breach_world.gate.visible and scene.breach_world.gate.is_invulnerable, "Portal survives destruction on the exposed roof")
	await capture("03_impact")
	await until(5.7)
	check(scene.breach_world.gate.visible and scene.breach_world.gate.scale.x > 0.9, "Imported gate opens on campus")
	check(movie.arrivals.size() == 2 and scene.get_node("EncounterDirector").alive == 2, "Actual first encounter emerges from the portal")
	for state in movie.arrivals:
		var actor: CharacterBody3D = state.actor.get_ref()
		check(actor.global_position.y > 6.0 and actor.process_mode == Node.PROCESS_MODE_DISABLED, "Emerging enemy is visibly on the rooftop with AI suspended")
		check(actor.collision_layer == 0 and actor.collision_mask == 0, "Arrival animation cannot damage or collide with player")
	await capture("04_portal")
	await until(6.2)
	await capture("04b_enemies_emerging")
	await until(8.3)
	check(movie.power_received and not movie.dash_shown, "Portal energy reaches player before first shadow dash")
	await capture("05_shadow")
	await until(9.4)
	check(movie.dash_shown and player.position.distance_to(movie.origin) > 0.2, "First shadow dash is demonstrated after exposure")
	await capture("06_dash")
	await until(11.6)
	await capture("07_title")
	while is_instance_valid(scene.opening_intro):
		await process_frame
	await process_frame
	check(not paused and player.process_mode == Node.PROCESS_MODE_PAUSABLE, "Opening hands control to gameplay")
	check(player.current_health == player.max_health and not player.is_invulnerable, "Opening does not damage player or leak invulnerability")
	check(player.camera.current and player.get_node("CombatFeedbackLayer").visible, "Gameplay camera and HUD are restored")
	check(scene.breach_world.gate.visible and scene.breach_world.meteor.visible, "Gate and meteor remain in the playable map")
	check(scene.breach_world.destruction.destroyed, "Building destruction persists into gameplay")
	check(scene.get_node("EncounterDirector").alive == 2 and get_nodes_in_group("enemy").size() == 2, "Cinematic wave becomes gameplay wave without duplicate spawns")
	for actor: CharacterBody3D in get_nodes_in_group("enemy"):
		check(actor.process_mode == Node.PROCESS_MODE_PAUSABLE and actor.collision_layer == 4 and actor.collision_mask == 7, "Arrived enemy regains normal combat and collisions")
		check(actor.global_position.y < 1.0, "Enemy arrives in courtyard instead of remaining stranded on roof")
	scene._begin_opening()
	movie = scene.opening_intro
	await until(0.3)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	check(not is_instance_valid(scene.opening_intro) and not paused, "Space skips the cinematic and resumes gameplay")
	check(player.jump_buffer_remaining <= 0.0 and not player.jump_requested, "Skip does not accidentally trigger a jump")
	scene._show_options()
	check(paused and scene.options_panel.visible, "Options still pauses the game after the opening")
	print("Breach checks complete, failures=", failures)
	quit(1 if failures > 0 else 0)
