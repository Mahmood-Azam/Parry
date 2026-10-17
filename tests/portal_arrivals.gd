extends SceneTree
var scene: Node3D
var failures := 0

func _initialize() -> void:
	create_timer(35, true).timeout.connect(func(): push_error("Portal arrival test timed out"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene._begin_opening()
	var movie: Node3D = scene.opening_intro
	movie.set_process(false)
	movie.elapsed = 6.3
	movie._update_timeline(1.0 / 60.0)
	check(movie.arrivals.size() == 3, "Rooftop portal emits the first skeleton/mage/gremlin group")
	check(scene.breach_world.gate.global_position.y > 6.0, "Portal remains on the surviving roof slab")
	var identities: Array[int] = []
	for state in movie.arrivals:
		var actor: CharacterBody3D = state.actor.get_ref()
		identities.append(actor.get_instance_id())
		check(actor.global_position.y > 6.0 and actor.collision_layer == 0, "Mid-emergence actor is safe and on the roof")
	for i in 3:
		await process_frame
	var input := InputEventKey.new()
	input.keycode = KEY_ESCAPE
	input.pressed = true
	Input.parse_input_event(input)
	await process_frame
	await process_frame
	input = input.duplicate()
	input.pressed = false
	Input.parse_input_event(input)
	await process_frame
	check(not is_instance_valid(scene.opening_intro) and not paused, "Escape skips safely in the middle of enemy emergence")
	check(scene.get_node("EncounterDirector").active and scene.get_node("EncounterDirector").alive == 3, "Encounter accounting survives mid-arrival skip")
	check(get_nodes_in_group("enemy").size() == 3 and get_nodes_in_group("gremlin").size() == 1, "Skipping cannot duplicate the first wave")
	for actor: CharacterBody3D in get_nodes_in_group("enemy"):
		check(actor.get_instance_id() in identities and actor.global_position.y < 1.0, "Same emitted enemy is placed safely in the courtyard")
		check(actor.process_mode == Node.PROCESS_MODE_PAUSABLE and actor.collision_layer == 4 and actor.collision_mask == 7, "Skipped arrival restores AI and collision masks")
		var visible := true
		for mesh: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
			visible = visible and mesh.transparency < 0.01
		check(visible, "Skip cannot leave an enemy faded or invisible")
		for animator: AnimationPlayer in actor.find_children("*", "AnimationPlayer", true, false):
			check(animator.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "Enemy animation returns to automatic playback")
	check(not scene.breach_world.gate.take_damage(999999.0), "Portal remains invulnerable after skip")
	await scene.breach_world.restore_campus(0.05)
	check(not scene.breach_world.gate.visible and not scene.breach_world.destruction.destroyed, "Invulnerability does not prevent the explicit future time-reversal hook")
	print("Portal arrival checks complete, failures=", failures)
	quit(1 if failures else 0)
