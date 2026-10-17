extends SceneTree
var scene: Node3D
var player: CharacterBody3D
var failures := 0
var parries := 0

func _initialize() -> void:
	create_timer(35.0, true).timeout.connect(func(): push_error("Combo test timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS ", message)
	else:
		failures += 1
		push_error(message)

func spawn_enemy() -> CharacterBody3D:
	var enemy := load("res://assets/enemies/skeleton/shadow_enemy.tscn").instantiate() as CharacterBody3D
	enemy.triple_attack_chance = 1.0
	enemy.position = Vector3(0, 0.02, -1.35)
	scene.add_child(enemy)
	enemy.attack_timer = 0.0
	return enemy

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var main := load("res://main.tscn").instantiate() as Node3D
	player = main.get_node("Player")
	main.remove_child(player)
	main.free()
	player.position = Vector3(0, 0.02, 0)
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.character.rotation.y = PI
	player.parry_success.connect(func(_a, _p, _d): parries += 1)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(100, 0.2, 100)
	floor_body.position.y = -0.1
	floor_body.add_child(shape)
	scene.add_child(floor_body)
	var sun := DirectionalLight3D.new()
	scene.add_child(sun)
	sun.rotation_degrees = Vector3(-50, -30, 0)
	var enemy := spawn_enemy()
	var hp: float = player.current_health
	var times: Array[float] = []
	var started := Time.get_ticks_msec()
	for i in 240:
		await physics_frame
		player._update_timers(1.0 / 60.0)
		if enemy.is_dead:
			break
		if enemy.is_attack_in_parry_window() and enemy.last_parried_step != enemy.combo_step:
			check(player.try_start_parry(), "Fresh parry is available for combo strike %d" % (enemy.combo_step + 1))
			player._check_active_parry_contacts()
			times.append((Time.get_ticks_msec() - started) / 1000.0)
	check(parries == 3 and enemy.combo_parries == 3, "Three actual animation-window parries registered")
	check(enemy.is_dead and enemy.current_health == 0.0, "Complete combo parry instantly kills the skeleton")
	check(player.current_health == hp, "Fully parried combo causes no player damage")
	check(is_instance_valid(enemy.burn_effect) and enemy.burn_effect.flames.emitting, "Execution visibly ignites the skeleton")
	check(times.size() == 3 and times[2] - times[0] < 1.5, "Three strikes have a fast, repeatable cadence")
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		scene.add_child(camera)
		camera.position = Vector3(3.5, 2.5, 4)
		camera.look_at(Vector3(0, 1, -0.5))
		camera.make_current()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/combo_execution.png")
	enemy.queue_free()
	await process_frame
	player.parry_cooldown_timer = 0.0
	parries = 0
	enemy = spawn_enemy()
	for i in 200:
		await physics_frame
		player._update_timers(1.0 / 60.0)
		# Hold ordinary block on the opening hit, then parry strikes two and three.
		player.blocking = enemy.combo_step == 0
		if enemy.combo_step > 0 and enemy.is_attack_in_parry_window() and enemy.last_parried_step != enemy.combo_step:
			player.try_start_parry()
			player._check_active_parry_contacts()
		if times.size() > 0 and enemy.combo_step == 2 and not enemy.is_attacking:
			break
	check(not enemy.is_dead and enemy.combo_parries == 2, "Blocking one strike forfeits the execution")
	check(player.current_health < hp, "Ordinary blocking still takes reduced damage")
	enemy.set_physics_process(false)
	player.position = Vector3(0, 0.02, 25)
	check(not enemy.awareness.can_engage(enemy, player) and enemy.awareness.returning, "Leaving territory breaks pursuit")
	enemy.position = enemy.awareness.home
	check(not enemy.awareness.can_engage(enemy, player), "Distant player cannot immediately re-aggro")
	player.position = enemy.position + Vector3(0, 0, 3)
	check(enemy.awareness.can_engage(enemy, player), "Enemy re-engages after returning and player approaching")
	player.position = Vector3(0, 0.02, 25)
	enemy.position = enemy.awareness.home + Vector3(0, 0, -3)
	enemy.is_attacking = false
	enemy.awareness.returning = true
	enemy.set_physics_process(true)
	for i in 150:
		await physics_frame
	check(enemy.global_position.distance_to(enemy.awareness.home) < 0.9 and not enemy.is_attacking, "Live skeleton returns to spawn instead of chasing the distant player")
	enemy.set_physics_process(false)
	var mage := load("res://assets/enemies/mage/shadowkin_mage.tscn").instantiate() as CharacterBody3D
	mage.position = Vector3(5, 0.02, -1)
	scene.add_child(mage)
	mage.position += Vector3(0, 0, -3)
	mage.awareness.returning = true
	for i in 150:
		await physics_frame
	check(mage.global_position.distance_to(mage.awareness.home) < 0.9 and not mage.is_attacking, "Live mage returns to its territory without casting at distant targets")
	mage.set_physics_process(false)
	check(enemy.health_bar.size.x == 48 and enemy.health_bar.size.y == 4, "Enemy health bar is compact")
	check(player.player_health_bar.size.x == 244 and player.player_health_bar.size.y == 8, "Player has a compact labeled health bar")
	# Let transient VFX timers expire, then release the scene before exiting.
	await create_timer(2.5).timeout
	scene.queue_free()
	await process_frame
	await process_frame
	print("Combo and awareness checks complete, failures=", failures, " strike times=", times)
	quit(1 if failures else 0)
