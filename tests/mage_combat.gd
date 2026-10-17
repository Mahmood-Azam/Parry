extends SceneTree
const MAGE := preload("res://assets/enemies/mage/shadowkin_mage.tscn")
const ENEMY := preload("res://assets/enemies/skeleton/shadow_enemy.tscn")
const PROJECTILE := preload("res://mage_projectile.gd")
var scene: Node3D
var player: CharacterBody3D
var camera: Camera3D
var fired: Array[Node3D] = []

func _initialize() -> void:
	create_timer(35.0, true).timeout.connect(func(): push_error("Mage combat test timed out"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func spawn_enemy(point: Vector3, mage: bool = false) -> CharacterBody3D:
	var enemy := (MAGE if mage else ENEMY).instantiate() as CharacterBody3D
	enemy.position = point
	enemy.max_health = 150.0
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func launch(point: Vector3, heading: Vector3, speed: float = 7.0) -> Node3D:
	var projectile := PROJECTILE.new()
	projectile.position = point
	projectile.direction = heading
	projectile.speed = speed
	scene.add_child(projectile)
	return projectile

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/" + label + ".png")

func wall(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	body.add_child(mesh)
	scene.add_child(body)
	return body

func ready_parry(facing: Vector3 = Vector3.FORWARD) -> void:
	player.attacking = false
	player.is_parrying = false
	player.is_invulnerable = false
	player.is_dashing = false
	player.blocking = false
	player.hit_stun_remaining = 0.0
	player.parry_cooldown_timer = 0.0
	player.character.rotation.y = atan2(facing.x, facing.z)
	check(player.try_start_parry(), "Player failed to enter parry")

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	# Use the shipped player scene nodes and real player damage/parry callbacks.
	var main := load("res://main.tscn").instantiate() as Node3D
	player = main.get_node("Player")
	main.remove_child(player)
	main.free()
	player.position = Vector3.ZERO
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.camera_unlocked = true
	player.character.rotation.y = PI
	camera = Camera3D.new()
	camera.position = Vector3(7, 5, 7)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 1, -3))
	camera.make_current()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.018, 0.025, 0.045)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.65, 0.85)
	environment.environment.ambient_light_energy = 0.6
	environment.environment.glow_enabled = true
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 0.7
	scene.add_child(sun)
	wall(Vector3(0, -0.1, -4), Vector3(40, 0.2, 40))
	await physics_frame
	await physics_frame
	var mage := spawn_enemy(Vector3(0, 0, -7), true)
	var neighbor := spawn_enemy(Vector3(1.5, 0, -7))
	var outside := spawn_enemy(Vector3(6, 0, -7))
	mage.rotation.y = 0.0
	mage._begin_cast(player)
	mage.windup_elapsed = 0.6
	mage.orb.scale = Vector3.ONE
	await capture("mage_cast")
	mage._cancel_cast()
	var hp: float = player.current_health
	ready_parry()
	var orb := launch(Vector3(0, 1.1, -1.6), Vector3.BACK)
	await create_timer(0.08).timeout
	check(is_instance_valid(orb) and orb.reflected, "Incoming orb must convert via the actual player parry")
	check(player.current_health == hp and player.fire_meter > 0.0, "Parry must protect health and build fire")
	check(orb.direction.is_equal_approx(Vector3.FORWARD), "Reflection must follow character facing")
	await capture("mage_fireball")
	await create_timer(0.29).timeout
	await capture("mage_explosion")
	await create_timer(0.2).timeout
	check(mage.current_health < 150.0 and neighbor.current_health < 150.0, "Fireball blast must damage multiple enemies")
	check(outside.current_health == 150.0, "Enemies outside blast radius must not take damage")
	check(is_instance_valid(mage.burn_effect) and is_instance_valid(neighbor.burn_effect), "Explosion must ignite targets")
	print("PASS timed parry conversion, facing, multi-target blast, falloff and burn")
	# Facing differs from the caster: a return must not auto-aim at the mage.
	ready_parry(Vector3.RIGHT)
	var angled := launch(Vector3(1.2, 1.1, -0.8), Vector3(-1.2, 0, 0.8).normalized())
	await create_timer(0.05).timeout
	check(angled.reflected and angled.direction.is_equal_approx(Vector3.RIGHT), "Fireball must use facing, not caster position")
	var fixed: Vector3 = angled.direction
	player.character.rotation.y = PI
	await create_timer(0.08).timeout
	check(angled.direction.is_equal_approx(fixed), "Returned fireball must never home after reflection")
	angled.queue_free()
	print("PASS manual reflection direction is locked after launch")
	ready_parry()
	Input.action_press("block")
	player._update_timers(player.parry_window + 0.01)
	check(not player.is_parrying and player.blocking, "Expired held parry must become block")
	Input.action_release("block")
	player.is_invulnerable = false
	hp = player.current_health
	var blocked := launch(Vector3(0, 1, -0.8), Vector3.BACK)
	await create_timer(0.2).timeout
	check(player.current_health < hp and player.current_health > hp - 18.0, "Holding block must reduce damage without reflecting")
	check(not is_instance_valid(blocked), "Blocked dark orb must dissipate")
	player.blocking = false
	player.is_invulnerable = false
	hp = player.current_health
	launch(Vector3(0, 1, -0.8), Vector3.BACK)
	await create_timer(0.2).timeout
	check(is_equal_approx(player.current_health, hp - 18.0), "Unblocked dark orb must damage player exactly once")
	ready_parry(Vector3.BACK)
	hp = player.current_health
	launch(Vector3(0, 1, -0.8), Vector3.BACK)
	await create_timer(0.2).timeout
	check(player.current_health < hp, "A rear projectile must bypass a front-facing parry")
	player.is_parrying = false
	print("PASS block reduction, unblocked hit, rear attack rejection")
	player.is_invulnerable = true
	hp = player.current_health
	launch(Vector3(0, 1, -0.8), Vector3.BACK)
	await create_timer(0.1).timeout
	check(player.current_health == hp, "Shadow protection must evade dark orb damage")
	player.is_invulnerable = false
	var separator := wall(Vector3(8, 1.5, 0), Vector3(0.12, 3, 6))
	var protected := spawn_enemy(Vector3(9, 0, 0), true)
	await physics_frame
	var blast := launch(Vector3(7.5, 1, 0), Vector3.RIGHT)
	blast.reflected = true
	blast.source_player = weakref(player)
	blast._detonate()
	check(protected.current_health == 150.0, "Blast must not damage through a wall")
	var stopped := launch(Vector3(6, 1, 0), Vector3.RIGHT, 200.0)
	await create_timer(0.05).timeout
	check(not is_instance_valid(stopped), "Swept collision must stop fast orbs at thin walls")
	separator.queue_free()
	print("PASS wall obstruction and high-speed swept collision")
	var paused_orb := launch(Vector3(15, 2, -4), Vector3.FORWARD)
	var position_before: Vector3 = paused_orb.position
	paused = true
	await create_timer(0.15, true).timeout
	check(paused_orb.position.is_equal_approx(position_before) and paused_orb.age == 0.0, "Projectiles must pause in menus")
	paused = false
	paused_orb.queue_free()
	# Exercise the live AI release timing and cancellation by a melee/fire hit.
	player.current_health = 100.0
	player.hit_stun_remaining = 0.0
	player.is_parrying = false
	mage.position = Vector3(0, 0, -5)
	mage.stun_remaining = 0.0
	mage.attack_timer = 0.0
	mage.projectile_fired.connect(func(projectile): fired.append(projectile))
	mage.set_physics_process(true)
	await create_timer(0.12).timeout
	check(mage.is_attacking and fired.is_empty(), "Mage must telegraph before releasing")
	mage.apply_stun(0.25)
	await create_timer(0.4).timeout
	check(fired.is_empty(), "Stun must interrupt an unfinished cast")
	await create_timer(1.6).timeout
	check(not fired.is_empty(), "Mage must recover and release its orb after the windup")
	mage.set_physics_process(false)
	for shot in fired:
		if is_instance_valid(shot):
			shot.queue_free()
	var before := fired.size()
	player._spawn_shadow_decoy()
	var decoy: Node3D = get_nodes_in_group("shadow_decoy").back()
	decoy.global_position = Vector3(3, 0, -2)
	mage._begin_cast(player)
	mage.set_physics_process(true)
	await create_timer(mage.windup_duration + 0.06).timeout
	check(fired.size() == before + 1, "Distracted mage must complete its cast")
	var distracted: Node3D = fired.back()
	var to_decoy: Vector3 = (decoy.global_position + Vector3.UP - distracted.global_position).normalized()
	check(distracted.direction.dot(to_decoy) > 0.99, "Shadow decoy must redirect an unfinished mage cast")
	mage.set_physics_process(false)
	decoy.queue_free()
	distracted.queue_free()
	print("PASS Shadow invulnerability and decoy distraction during cast windup")
	var death_count := [0]
	protected.died.connect(func(): death_count[0] += 1)
	protected.take_damage(9999.0, player)
	protected.take_damage(9999.0, player)
	check(protected.is_dead and death_count[0] == 1 and not protected.is_in_group("enemy"), "Mage death must count once and leave enemy targeting")
	await create_timer(1.6).timeout
	check(not is_instance_valid(protected), "Dead mage must dissolve and clean up")
	print("PASS pause, cast telegraph, stun interrupt, recovery and mage death cleanup")
	quit()
