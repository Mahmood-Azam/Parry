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
	assert(get_nodes_in_group("mage").size() == 1)
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
	assert(not director.completed)
	assert(director.relic_phase == 1)
	assert(not scene.victory_panel.visible and not paused)
	assert(director.objective.text.contains("C-101"))
	player.global_position = director.relic.global_position + Vector3.DOWN * 0.8
	var collect_key := InputEventKey.new()
	collect_key.keycode = KEY_O
	collect_key.pressed = true
	director._input(collect_key)
	assert(director.relic_phase == 2 and director.relic_count == 1)
	assert(director.mutant.max_health == director.boss.max_health * 1.5)
	assert(not director.mutant.engaged and not director.boss_bar.visible)
	assert(director.mutant.animation_player.has_animation("Death"))
	assert(director.mutant.animation_player.has_animation("Flex"))
	assert(director.mutant.animation_player.has_animation("Idle"))
	assert(director.mutant.animation_player.has_animation("Jump"))
	assert(director.mutant.animation_player.has_animation("Punch"))
	assert(director.mutant.animation_player.has_animation("Walk"))
	# Check the actual new hallway scene, with room-space placement intact.
	director.mutant.engaged = true
	director.mutant.set_physics_process(false)
	player.set_physics_process(false)
	var mutant_camera := Camera3D.new()
	scene.add_child(mutant_camera)
	mutant_camera.near = 0.05
	mutant_camera.global_position = director.mutant.global_position + Vector3(0.7, 2.4, 3.0)
	mutant_camera.look_at(director.mutant.global_position + Vector3.UP * 1.3)
	mutant_camera.make_current()
	director._update_hud()
	assert(director.boss_bar.visible and director.boss_title.text.contains("MUTANT"))
	var ultimate_panel := player.ultimate_controller.hud.get_child(0) as Control
	assert(director.boss_bar.get_global_rect().end.y < ultimate_panel.get_global_rect().position.y, "Boss bar must be above the ultimate HUD")
	await create_timer(0.15).timeout
	await capture("merged_mutant_hall")
	director.mutant.take_damage(642.0, player)
	assert(director.mutant.flexed and director.mutant.flexing)
	assert(director.mutant.current_health > director.mutant.max_health * 0.1)
	await create_timer(0.15).timeout
	await capture("merged_mutant_hall_flex")
	director.mutant.take_damage(999999.0, player)
	assert(director.completed and director.relic_phase == 3)
	assert(director.mutant.animation_player.current_animation == "Death")
	print("PASS progression, relic pickup, Mutant clips, flex, death, and P shortcut")
	scene._new_game()
	await create_timer(0.3, true).timeout
	assert(current_scene.get_node("EncounterDirector").stage == 0)
	print("PASS new game resets encounters")
	quit()
