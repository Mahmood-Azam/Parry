extends SceneTree
var failures := 0

func _initialize() -> void:
	create_timer(40.0, true).timeout.connect(func(): push_error("New Game timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var identity := scene.get_instance_id()
	var player: CharacterBody3D = scene.get_node("Player")
	check(player.position.z > -66, "Player starts farther from the first wave")
	var click := Time.get_ticks_msec()
	scene._new_game()
	check(scene.opening_loading and paused, "New Game immediately shows loading and keeps gameplay paused")
	while scene.opening_loading:
		await process_frame
	print("New Game warm/cached start milliseconds: ", Time.get_ticks_msec() - click)
	check(is_instance_valid(scene) and current_scene.get_instance_id() == identity, "First New Game reuses campus instead of reloading it")
	check(is_instance_valid(scene.opening_intro), "New Game starts the cinematic")
	scene.opening_intro.finish()
	await process_frame
	check(not paused and scene.session_started, "Skipping intro hands off to playable game")
	var director: Node = scene.get_node("EncounterDirector")
	if not director.active:
		director._start_encounter()
	for enemy: CharacterBody3D in get_nodes_in_group("enemy"):
		check(player.global_position.distance_to(enemy.global_position) > 12, "Initial enemies have breathing room from player")
		check(enemy.awareness.home.distance_to(enemy.global_position) < 0.1, "Enemy territory is anchored to courtyard, not rooftop arrival")
	for i in 30:
		await physics_frame
	check(player.is_on_floor() and player.global_position.y > -0.1, "Farther player spawn is grounded on the actual campus")
	scene._show_home()
	scene.queue_free()
	await process_frame
	await process_frame
	print("New Game checks complete, failures=", failures)
	quit(1 if failures else 0)
