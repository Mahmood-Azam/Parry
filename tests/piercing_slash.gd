extends SceneTree
const ENEMY := preload("res://assets/enemies/skeleton/shadow_enemy.tscn")
const SLASH := preload("res://fire_air_slash.gd")
var scene: Node3D
var source: Node3D
var death_count: int = 0

func _initialize() -> void:
	create_timer(20.0, true).timeout.connect(func(): push_error("Piercing slash test timed out"); quit(1))
	call_deferred("run")

func spawn_enemy(point: Vector3, hp: float = 100.0) -> CharacterBody3D:
	var enemy := ENEMY.instantiate() as CharacterBody3D
	enemy.position = point
	enemy.max_health = hp
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	source = Node3D.new()
	source.name = "Player"
	scene.add_child(source)
	var camera := Camera3D.new()
	camera.position = Vector3(9, 5, 5)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 0.9, -5))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 0.7
	scene.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.018, 0.025, 0.04)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.4, 0.45, 0.55)
	environment.environment.ambient_light_energy = 0.6
	environment.environment.glow_enabled = true
	scene.add_child(environment)
	var enemies: Array[CharacterBody3D] = []
	for point in [Vector3(-0.7,0,-3),Vector3(0.7,0,-3),Vector3(0,0,-7),Vector3(0,0,-12)]:
		enemies.append(spawn_enemy(point))
	var missed := spawn_enemy(Vector3(4,0,-7))
	var slash := SLASH.new()
	slash.direction = Vector3.FORWARD
	slash.position = Vector3(0,1.3,0)
	slash.damage = 20.0
	slash.charge_ratio = 1.0
	slash.source_player = source
	scene.add_child(slash)
	await create_timer(0.65).timeout
	assert(is_instance_valid(slash) and not slash.is_queued_for_deletion())
	assert(slash.hit_targets.size() == 4)
	assert(slash.velocity.is_equal_approx(Vector3.FORWARD * slash.speed))
	assert(absf(slash.position.x) < 0.001)
	for enemy in enemies:
		assert(enemy.current_health <= 80.0 and enemy.current_health > 76.0)
		assert(is_instance_valid(enemy.burn_effect) and enemy.burn_effect.remaining > 0.0)
	assert(is_equal_approx(missed.current_health, 100.0))
	assert(not is_instance_valid(missed.burn_effect))
	print("PASS four targets pierced, one direct hit each, off-axis target missed, fixed aim")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/piercing_slash.png")
	var hp: float = enemies[0].current_health
	var remaining: float = enemies[0].burn_effect.remaining
	paused = true
	await create_timer(0.3, true).timeout
	assert(is_equal_approx(hp, enemies[0].current_health))
	assert(is_equal_approx(remaining, enemies[0].burn_effect.remaining))
	paused = false
	print("PASS burn damage and VFX respect pause")
	var burning := spawn_enemy(Vector3(8,0,-3))
	burning.apply_burn(0.6, 8.0, 0.7, source)
	await create_timer(0.2).timeout
	var effect_id: int = burning.burn_effect.get_instance_id()
	burning.apply_burn(0.3, 4.0, 0.3, source)
	assert(burning.burn_effect.get_instance_id() == effect_id)
	await create_timer(0.5).timeout
	assert(absf(burning.current_health - 95.2) < 0.15)
	assert(burning.burn_effect.extinguished)
	print("PASS refresh does not stack emitters or damage; burn expires")
	burning.apply_burn(0.3, 4.0, 0.5, source)
	assert(not burning.burn_effect.extinguished)
	assert(burning.burn_effect.get_instance_id() == effect_id)
	var dying := spawn_enemy(Vector3(10,0,-5), 2.0)
	dying.died.connect(func(): death_count += 1)
	dying.apply_burn(1.0, 8.0, 0.8, source)
	await create_timer(0.4).timeout
	assert(dying.is_dead and death_count == 1)
	assert(dying.burn_effect.extinguished)
	await create_timer(0.1).timeout
	assert(not is_instance_valid(slash))
	print("PASS re-ignition, burn kill emits death once, slash lifetime cleanup")
	quit()
