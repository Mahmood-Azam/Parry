extends SceneTree
var scene: Node3D
var player: CharacterBody3D
var director: Node3D
func _initialize() -> void:
	create_timer(90.0, true).timeout.connect(func(): push_error("Campus route walk timed out"); quit(1))
	call_deferred("run")
func walk_to(point: Vector3) -> void:
	var start := Time.get_ticks_msec()
	while Vector2(player.position.x - point.x, player.position.z - point.z).length() > 0.25:
		for enemy in get_nodes_in_group("enemy"):
			if director.stage == 4 and enemy == director.boss:
				# Reaching the Warden is the route goal. Killing him starts the
				# Owl cutscene, which deliberately locks player movement.
				enemy.set_physics_process(false)
			else:
				enemy.take_damage(99999.0, player)
		var offset := point - player.position
		# Camera yaw zero: use analogue action strengths for a diagonal path.
		Input.action_release("move_right")
		Input.action_release("move_left")
		Input.action_release("move_forward")
		Input.action_release("move_back")
		var direction := Vector2(offset.x, offset.z).normalized()
		Input.action_press("move_right" if direction.x > 0.0 else "move_left", absf(direction.x))
		Input.action_press("move_back" if direction.y > 0.0 else "move_forward", absf(direction.y))
		await physics_frame
		if Time.get_ticks_msec() - start > 18000:
			push_error("WALK BLOCKED at %s toward %s" % [player.position, point])
			quit(1)
			return
	for action in ["move_right", "move_left", "move_forward", "move_back"]:
		Input.action_release(action)
	print("WALK PASS ",point," grounded=",player.is_on_floor()," stage=",director.stage)
func run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene._continue_game()
	player = scene.get_node("Player")
	director = scene.get_node("EncounterDirector")
	await create_timer(0.4).timeout
	for p in [Vector3(35,0,-74.55), Vector3(39,0,-74.55), Vector3(44.5,0,-74.55), Vector3(49,0,-74.55), Vector3(49,0,-83), Vector3(49,0,-96), Vector3(49,0,-108)]:
		await walk_to(p)
	assert(director.stage == 4 and director.active and director.relic_phase == 0)
	print("PASS continuous courtyard-to-boss route without teleporting or jumping")
	quit()
