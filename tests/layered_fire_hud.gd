extends SceneTree
var failures := 0
var scene: Node3D
var player: CharacterBody3D

func _initialize() -> void:
	create_timer(40.0, true).timeout.connect(func(): push_error("Layered HUD test timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/layered_" + label + ".png")

func run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene._continue_game()
	player = scene.get_node("Player")
	for i in 20:
		await physics_frame
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process(false)
	var ult: Node = player.ultimate_controller
	player.fire_meter = 0.0
	player._add_fire_meter(75)
	check(player.fire_meter == 75 and ult.charge == 75, "Parry fire is credited once to one shared reserve")
	check(player.fire_meter_bar.value == 75 and not player.fire_meter_bar.overflow.visible, "First layer fills orange only")
	player._add_fire_meter(75)
	check(player.fire_meter == 150 and player.fire_meter_bar.value == 100 and player.fire_meter_bar.overflow.value == 50, "Violet overfill covers half the same orange track")
	check(not ult.is_ready() and ult.bars.is_empty(), "No independent ultimate bank or separate HUD bars")
	await capture("half_overfill")
	player._add_fire_meter(50)
	check(ult.is_ready() and player.fire_meter_bar.overflow.value == 100, "Both layers full unlock ultimate")
	player._begin_fire_channel()
	player._update_fire_channel(0.25)
	check(player.fire_meter < 200 and not ult.is_ready() and player.fire_channel_charge > 0, "Charging a slash spends the same ultimate reserve")
	player.is_fire_channeling = false
	player.fire_channel_charge = 0
	player.fire_meter = 150
	player.fire_full_hold_remaining = 0
	player.fire_was_full = false
	player._update_passive_fire(1.0)
	check(ult.charge == player.fire_meter and player.fire_meter < 150, "Decay reduces both combat fire and ultimate readiness")
	var director: Node = scene.get_node("EncounterDirector")
	director._start_encounter()
	var skeleton: CharacterBody3D
	for enemy: CharacterBody3D in get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
		if enemy.has_method("_begin_combo"):
			skeleton = enemy
		else:
			enemy.position = Vector3(38, 0.02, -67)
	skeleton.position = Vector3(35, 0.02, -66)
	skeleton.target = player
	skeleton.triple_attack_chance = 1.0
	skeleton._begin_combo()
	skeleton.animation_player.pause()
	player.character.rotation.y = PI
	player.fire_meter = 200
	check(player._process_player_attack_hit(), "Melee attack hits the nearby skeleton")
	check(player.fire_meter < 200 and ult.charge == player.fire_meter and not ult.is_ready(), "Confirmed melee damage also spends ultimate progress")
	var patterns := {}
	skeleton.triple_attack_chance = 0.45
	for i in 64:
		skeleton._begin_combo()
		patterns[skeleton.combo_length] = true
	check(patterns.has(1) and patterns.has(3) and patterns.size() == 2, "Random attack selection produces single and triple patterns")
	skeleton.triple_attack_chance = 0
	skeleton._begin_combo()
	skeleton._process(0)
	check(skeleton.combo_length == 1 and not skeleton.combo_hint.visible, "Single attacks have no triple hint")
	check(not skeleton.on_parried(player, true), "Single-strike parries retain the ordinary stun response")
	skeleton.triple_attack_chance = 1
	skeleton._begin_combo()
	skeleton._process(0)
	check(skeleton.combo_hint.visible and skeleton.combo_hint.get_child_count() == 3, "Triple windup has three subtle non-text amber ticks")
	skeleton.animation_player.pause()
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(38, 3.2, -60)
	camera.look_at(Vector3(35, 1.1, -65))
	camera.make_current()
	player.fire_meter = 150
	player._update_combat_stats()
	for i in 3:
		await process_frame
	for label in scene.find_children("*", "Label", true, false):
		if scene.menu_layer.is_ancestor_of(label) or player.status_hud.is_ancestor_of(label) or label.name in [&"BossTitle", &"RelicPickupPrompt", &"EncounterMessage"]:
			continue
		check(label.self_modulate.a == 0 or not label.is_visible_in_tree(), "Gameplay text remains suppressed: " + str(label.name))
	for label: Label3D in scene.find_children("*", "Label3D", true, false):
		if scene.get_node("CampusMap").is_ancestor_of(label):
			continue
		check(label.transparency == 1.0, "World text suppressed: " + str(label.name))
	check(skeleton.health_bar.size == Vector2(48, 4), "Skeleton overhead bar is 48 by 4")
	await capture("clean_gameplay")
	scene._show_options()
	var controls := scene.options_panel.find_child("ControlsReference", true, false) as Label
	check(controls.self_modulate.a == 1 and scene.options_panel.visible, "Menu and Options text remains readable")
	print("Layered reserve/HUD checks complete, failures=", failures)
	quit(1 if failures else 0)
