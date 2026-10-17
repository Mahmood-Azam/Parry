extends SceneTree
const ENEMY := preload("res://assets/enemies/skeleton/shadow_enemy.tscn")
const PROJECTILE := preload("res://mage_projectile.gd")
var scene: Node3D
var player: CharacterBody3D
var ult: Node
var camera: Camera3D

func _initialize() -> void:
	create_timer(40.0, true).timeout.connect(func(): push_error("Ultimate test timed out"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func spawn_enemy(point: Vector3, boss: bool = false) -> CharacterBody3D:
	var enemy := ENEMY.instantiate() as CharacterBody3D
	enemy.position = point
	enemy.max_health = 600.0
	enemy.is_boss = boss
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func wall(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.07, 0.08, 0.1)
	visual.material_override = material
	body.add_child(visual)
	scene.add_child(body)
	return body

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/" + label + ".png")

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var main := load("res://main.tscn").instantiate() as Node3D
	player = main.get_node("Player")
	main.remove_child(player)
	main.free()
	player.position = Vector3(0, 0.05, 0)
	scene.add_child(player)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.character.rotation.y = PI
	player.camera_unlocked = true
	ult = player.ultimate_controller
	wall(Vector3(0, -0.1, 0), Vector3(50, 0.2, 50))
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(8, 5, 8)
	camera.look_at(Vector3(0, 1, -3))
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	scene.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.015, 0.02, 0.035)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.45, 0.5, 0.65)
	environment.environment.ambient_light_energy = 0.6
	environment.environment.glow_enabled = true
	scene.add_child(environment)
	await create_timer(0.35).timeout
	check(player.is_on_floor(), "Fixture player must be grounded")
	player.set_physics_process(false)
	check(not ult.try_activate("area"), "Uncharged ultimate must be unavailable")
	player._add_fire_meter(100.0)
	check(ult.charge == 100.0 and not ult.is_ready(), "One full bar must bank only half an ultimate")
	player.fire_full_hold_remaining = 0.0
	player.fire_was_full = true
	player._update_passive_fire(20.0)
	check(player.fire_meter == 0.0 and ult.charge == 0.0, "Fire decay also spends ultimate progress from the same reserve")
	player._add_fire_meter(200.0)
	check(ult.is_ready(), "Two bars earned through fire gain must unlock ultimate")
	player._add_fire_meter(200.0)
	check(ult.charge == 200.0, "Reserve must cap at one ultimate")
	check(not ult.try_activate("focused") and ult.is_ready(), "No focused target must not consume ultimate")
	print("PASS shared layered reserve, decay, cap and no-target protection")
	var near := spawn_enemy(Vector3(0, 0, -4))
	var beside := spawn_enemy(Vector3(3, 0, -5))
	var distant := spawn_enemy(Vector3(0, 0, -14))
	var cover := wall(Vector3(-3, 1.5, 0), Vector3(0.2, 3, 6))
	var protected := spawn_enemy(Vector3(-5, 0, 0))
	var locked := spawn_enemy(Vector3(4, 0, 0))
	locked.process_mode = Node.PROCESS_MODE_DISABLED
	var projectile := PROJECTILE.new()
	projectile.position = Vector3(14, 1, 8)
	projectile.direction = Vector3.BACK
	scene.add_child(projectile)
	var orb_start := projectile.position
	await physics_frame
	check(ult.try_activate("area"), "Area ultimate must activate when ready")
	var movie: Node3D = ult.cinematic
	check(player.is_using_ultimate and ult.charge == 0.0, "Activation must consume reserve exactly once")
	check(not ult.try_activate("focused"), "Cannot activate twice during cinematic")
	check(not player.try_start_dash() and not player.try_start_parry(), "Cinematic must lock other combat actions")
	check(not player.take_damage(50.0, near), "Cinematic must protect the player")
	await create_timer(0.65).timeout
	check(near.current_health == 600.0, "Ultimate must not apply damage before the visible release")
	check(projectile.position.distance_to(orb_start) < 0.15, "Existing projectiles must freeze during cinematic")
	await capture("ultimate_inferno_charge")
	var movie_time: float = movie.elapsed
	paused = true
	await create_timer(0.2, true).timeout
	check(is_equal_approx(movie.elapsed, movie_time), "Menu pause must stop cinematic timeline")
	paused = false
	await create_timer(0.8).timeout
	check(movie.impact_applied and movie.hit_targets.size() == 3, "Inferno must strike three exposed nearby enemies")
	check(near.current_health < 600.0 and beside.current_health < 600.0, "Inferno must damage a group")
	check(distant.current_health == 600.0 and protected.current_health == 600.0, "Inferno must respect range and walls")
	check(is_instance_valid(near.burn_effect) and near.stun_remaining > 0.0, "Inferno must burn and stun survivors")
	var hit_hp: float = near.current_health
	movie._apply_impact()
	check(near.current_health == hit_hp, "Cinematic impact must not apply twice")
	await create_timer(0.12).timeout
	await capture("ultimate_inferno_impact")
	await create_timer(1.5).timeout
	check(not player.is_using_ultimate and not player.is_invulnerable, "Cinematic must restore player control and vulnerability")
	check(near.process_mode == Node.PROCESS_MODE_INHERIT and locked.process_mode == Node.PROCESS_MODE_DISABLED, "Actor process modes must restore exactly")
	check(projectile.process_mode == Node.PROCESS_MODE_PAUSABLE, "Projectile processing must restore")
	check(root.get_camera_3d() == camera, "Original camera must restore")
	projectile.queue_free()
	print("PASS group damage, range, cover, impact timing, invulnerability, pause and restoration")
	for enemy in get_nodes_in_group("enemy"):
		enemy.free()
	cover.queue_free()
	await physics_frame
	var boss := spawn_enemy(Vector3(0, 0, -8), true)
	var bystander := spawn_enemy(Vector3(1.5, 0, -8))
	var behind := spawn_enemy(Vector3(0, 0, 5))
	player.character.rotation.y = PI
	player._fill_fire_meter()
	player._fill_fire_meter()
	check(ult.is_ready(), "R twice must allow ultimate practice")
	check(ult.select_focused_target() == boss, "Focused ultimate must select the visible boss ahead")
	check(ult.try_activate("focused"), "Focused ultimate must activate on the boss")
	await create_timer(0.75).timeout
	await capture("ultimate_execution_charge")
	await create_timer(0.7).timeout
	check(is_equal_approx(boss.current_health, 260.0), "Focused ultimate must deliver its high direct damage once")
	check(bystander.current_health == 600.0 and behind.current_health == 600.0, "Focused ultimate must not damage neighboring enemies")
	await create_timer(0.12).timeout
	await capture("ultimate_execution_impact")
	await create_timer(1.5).timeout
	check(not player.is_using_ultimate, "Focused cinematic must complete")
	check(root.get_camera_3d() == camera, "Focused cinematic must restore camera")
	print("PASS focused boss damage, target selection, no collateral damage and camera recovery")
	player._fill_fire_meter()
	player._fill_fire_meter()
	check(ult.try_activate("area"), "Another charged ultimate must activate")
	ult.cinematic.queue_free()
	await process_frame
	await process_frame
	check(not player.is_using_ultimate and not player.is_invulnerable, "Interrupted cinematic must release controls and immunity")
	check(boss.process_mode == Node.PROCESS_MODE_INHERIT, "Interrupted cinematic must unfreeze enemies")
	check(root.get_camera_3d() == camera, "Interrupted cinematic must recover camera")
	print("PASS interrupted cinematic cleanup")
	quit()
