extends SceneTree
var scene: Node3D
func _initialize() -> void:
	create_timer(45.0, true).timeout.connect(func(): push_error("Campus smoke test timed out"); quit(1))
	call_deferred("run")
func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/" + label + ".png")
func run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var map := scene.get_node("CampusMap")
	var director := scene.get_node("EncounterDirector")
	var player := scene.get_node("Player") as CharacterBody3D
	print("QUALITY ",map.quality," vegetation ",map.source_instances," -> ",map.rendered_instances," materials=",map.surface_materials.size())
	print("BATCHES ", map.batched_mesh_count, " -> ",map.batch_count, " chunks=",map.foliage_chunks.size())
	assert(map.rendered_instances < map.source_instances * 0.4)
	assert(paused)
	scene._show_options()
	await create_timer(0.2, true).timeout
	await capture("night_options")
	scene._continue_game()
	await create_timer(0.5).timeout
	assert(director.active and director.alive == 2)
	await capture("night_courtyard")
	for stage in range(5):
		if stage > 0:
			player.global_position = director.STAGES[stage].trigger + Vector3.UP * 0.1
			await create_timer(0.25).timeout
		print("STAGE ",stage," active=",director.active," alive=",director.alive)
		assert(director.stage == stage and director.active)
		for enemy in get_nodes_in_group("enemy"):
			enemy.set_physics_process(false)
		if stage == 1:
			await capture("night_lobby")
		if stage == 4:
			assert(director.boss.is_boss)
			director.boss.take_damage(230.0, player)
			assert(director.boss.enraged)
			await create_timer(0.1).timeout
			await capture("night_boss")
		for enemy in get_nodes_in_group("enemy"):
			enemy.take_damage(99999.0, player)
		await create_timer(0.8).timeout
		print("CLEARED ",stage," next=",director.stage," completed=",director.completed)
	assert(director.completed)
	await create_timer(1.5, true).timeout
	assert(scene.victory_panel.visible and paused)
	print("PASS progression, gates, boss enrage, victory and menu pause")
	scene._new_game()
	await create_timer(0.3, true).timeout
	assert(current_scene.get_node("EncounterDirector").stage == 0)
	print("PASS new game resets encounters")
	quit()
