extends SceneTree
var scene: Node3D
func _initialize() -> void:
	create_timer(80.0, true).timeout.connect(func(): push_error("Campus smoke test timed out"); quit(1))
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
	# The updated starting position is farther from the first wave.
	if not director.active:
		director._start_encounter()
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
			var resting_rotation: Vector3 = director.boss.stun_pose_base_rotation
			director.boss.apply_stun()
			director.boss.stun_pose_elapsed = 0.08
			director.boss._update_stun_pose()
			director.boss.apply_stun()
			assert(director.boss.stun_pose_base_rotation.is_equal_approx(resting_rotation), "Repeated stuns must not tilt the Ash Warden")
			director.boss.stun_remaining = 0.01
			director.boss.set_physics_process(true)
			await create_timer(0.1).timeout
			director.boss.set_physics_process(false)
			assert(director.boss.skeleton_model.rotation.is_equal_approx(resting_rotation), "Ash Warden must return to its upright pose")
			await capture("night_boss")
			player.is_using_ultimate = true
		for enemy in get_nodes_in_group("enemy"):
			enemy.take_damage(99999.0, player)
		await create_timer(0.8).timeout
		print("CLEARED ",stage," next=",director.stage," completed=",director.completed)
	assert(not director.completed)
	assert(director.relic_phase == 1)
	assert(director.relic_count == 0 and director.relic.name == "WardenRelic")
	assert(director.owl.get("state") == "hidden", "Owl must wait for an active ultimate to finish")
	player.is_using_ultimate = false
	player.ultimate_controller.ultimate_finished.emit("focused")
	await process_frame
	assert(is_instance_valid(director.owl) and director.owl.get("state") == "orbit")
	assert(director.pickup_prompt.self_modulate.a > 0.99, "Relic pickup prompt must remain visible to the HUD")
	assert(player.animation_player.current_animation == "Idle", "Owl story must settle the player into idle")
	assert(root.get_camera_3d() == director.owl.story_camera, "Owl story must use a front-facing camera")
	assert(not scene.victory_panel.visible and not paused)
	director.owl.set_process(false)
	director.owl.call("_process", 2.8)
	assert(director.owl.bubble.visible and director.owl.bubble.modulate.a > 0.99 and director.owl.speech.self_modulate.a > 0.99, "Owl dialogue must be readable")
	assert((director.owl.story_camera.global_position - player.global_position).normalized().dot(player.character.global_basis.z) > 0.5, "Owl camera must pan in front of the player")
	for seconds in director.FIRST_OWL_DURATIONS:
		director.owl.call("_process", seconds)
	director.owl.call("_process", 0.65)
	assert(director.owl.get("intro_seen"))
	player.global_position = director.relic.global_position + Vector3.DOWN * 0.8
	var collect_key := InputEventKey.new()
	collect_key.keycode = KEY_O
	collect_key.pressed = true
	director._input(collect_key)
	assert(director.relic_phase == director.PHASE_C101_RELIC and director.relic_count == 1)
	assert(director.relic.name == "C101Relic")
	player.global_position = director.relic.global_position + Vector3.DOWN * 0.8
	director._input(collect_key)
	assert(director.relic_phase == director.PHASE_MUTANT and director.relic_count == 2)
	assert(not is_instance_valid(director.mutant), "Mutant must wait until the Owl finishes its warning")
	director.owl.call("_process", 2.8)
	director.owl.call("_process", 4.5)
	director.owl.call("_process", 0.65)
	assert(is_instance_valid(director.mutant))
	assert(director.mutant.max_health == director.boss.max_health * 1.5)
	assert(not director.mutant.engaged and not director.boss_bar.visible)
	assert(director.mutant.animation_player.has_animation("Death"))
	assert(director.mutant.animation_player.has_animation("Flex"))
	assert(director.mutant.animation_player.has_animation("Idle"))
	assert(director.mutant.animation_player.has_animation("Jump"))
	assert(director.mutant.animation_player.has_animation("Punch"))
	assert(director.mutant.animation_player.has_animation("Walk"))
	assert(director.mutant.global_position.is_equal_approx(director.get_parent().get_node(director.RELIC_ROOM_PATH).to_global(director.MUTANT_LOCAL)))
	assert(is_equal_approx(director.gremlin_wave_timer.wait_time, 10.0) and not director.gremlin_wave_timer.is_stopped())
	assert(director.gremlins.is_empty(), "Gremlins should first arrive ten seconds after the Mutant")
	director._spawn_gremlin_wave()
	assert(director.gremlins.size() == 2)
	for gremlin in director.gremlins:
		assert(gremlin.is_in_group("enemy") and gremlin.animation_player.has_animation("Lesha_attack_1"))
		gremlin.set_physics_process(false)
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
	assert(not director.boss_bar.get_global_rect().intersects(player.fire_meter_bar.get_global_rect()), "Boss bar must not overlap the shared fire meter")
	await create_timer(0.15).timeout
	await capture("merged_mutant_hall")
	director.mutant.take_damage(642.0, player)
	assert(director.mutant.flexed and director.mutant.flexing)
	assert(director.mutant.current_health > director.mutant.max_health * 0.1)
	await create_timer(0.15).timeout
	await capture("merged_mutant_hall_flex")
	director.mutant.take_damage(999999.0, player)
	assert(not director.completed and director.relic_phase == director.PHASE_A_RELIC)
	assert(director.relic.name == "ABlockRelic" and director.relic.global_position.distance_to(director.A_BLOCK_RELIC) < 0.3)
	var a_point: Vector3 = director.A_BLOCK_RELIC
	var a_ray := PhysicsRayQueryParameters3D.create(a_point + Vector3.UP * 3.0, a_point + Vector3.DOWN * 2.0, 1)
	var a_ground := scene.get_world_3d().direct_space_state.intersect_ray(a_ray)
	assert(not a_ground.is_empty() and absf(a_ground.position.y - a_point.y) < 1.2, "A-block relic must be over walkable ground")
	assert(director.gremlin_wave_timer.is_stopped() and director.gremlins.is_empty())
	assert(director.mutant.animation_player.current_animation == "Death")
	player.global_position = director.relic.global_position + Vector3.DOWN * 0.8
	director._input(collect_key)
	assert(director.relic_count == 3 and director.relic_phase == director.PHASE_PORTAL)
	director.owl.call("_process", 2.8)
	director.owl.call("_process", 5.0)
	director.owl.call("_process", 0.65)
	var roof_point: Vector3 = scene.breach_world.gate_point
	var roof_ray := PhysicsRayQueryParameters3D.create(roof_point + Vector3.UP * 5.0, roof_point + Vector3.DOWN * 2.0, 1)
	var roof_ground := scene.get_world_3d().direct_space_state.intersect_ray(roof_ray)
	assert(not roof_ground.is_empty() and absf(roof_ground.position.y - roof_point.y) < 0.3, "Portal must stand on the reachable roof slab")
	player.global_position = scene.breach_world.gate_point + Vector3(0.8, 0, 0.5)
	assert(director._near_portal())
	director._input(collect_key)
	assert(director.relic_phase == director.PHASE_FINAL_BOSS and is_instance_valid(director.bara))
	assert(is_equal_approx(director.bara.max_health, director.mutant.max_health * 2.0))
	assert(director.bara.animation_player.current_animation == "Idle", "Bara Ustaad must spawn in an idle pose")
	await create_timer(3.2, false).timeout
	assert(director.bara.engaged and director.bara.process_mode == Node.PROCESS_MODE_PAUSABLE)
	assert(director.bara.awareness.home.distance_to(Vector3(48.2, 6.55, -85.3)) < 0.1, "Bara Ustaad territory must start on the roof")
	var boss_attacks := [0]
	director.bara.animation_player.animation_started.connect(func(clip: StringName) -> void:
		if clip in [&"AttackHorizontal", &"AttackDownward", &"AttackKick"]:
			boss_attacks[0] += 1
	)
	player.is_invulnerable = true
	await create_timer(8.0, false).timeout
	assert(boss_attacks[0] >= 2, "Bara Ustaad must continue attacking after the arrival")
	director.bara.take_damage(999999.0, player)
	assert(director.completed and director.relic_phase == director.PHASE_COMPLETE)
	await create_timer(5.1, true).timeout
	assert(not scene.breach_world.gate.visible, "The portal must close after Bara Ustaad falls")
	assert(scene.victory_panel.visible and paused, "The final fight must lead to the victory screen")
	var daylight: WorldEnvironment = scene.get_node("CampusMap").find_children("*", "WorldEnvironment", true, false)[0]
	assert(daylight.environment.sky.sky_material.sky_top_color.b > 0.5, "Victory must restore a blue daytime sky")
	print("PASS three relics, Owl visits, Mutant, rooftop arrival and final boss")
	scene._new_game()
	await create_timer(0.3, true).timeout
	assert(current_scene.get_node("EncounterDirector").stage == 0)
	print("PASS new game resets encounters")
	quit()
