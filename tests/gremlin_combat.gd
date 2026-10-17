extends SceneTree
const GREMLIN := preload("res://assets/enemies/gremlin/gremlin_enemy.tscn")

func _initialize() -> void:
	create_timer(30.0, true).timeout.connect(func(): push_error("Gremlin combat timed out"); quit(1))
	call_deferred("run")

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var main := load("res://main.tscn").instantiate() as Node3D
	var player := main.get_node("Player") as CharacterBody3D
	main.remove_child(player)
	main.free()
	player.position = Vector3(0, 0.05, 0)
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.camera_unlocked = true
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, 0.2, 20)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	var gremlin := GREMLIN.instantiate() as CharacterBody3D
	gremlin.position = Vector3(0, 0, -4)
	scene.add_child(gremlin)
	assert(gremlin.player_target == player)
	assert(gremlin.is_in_group("enemy"))
	for clip in [&"Lesha_idle", &"Lesha_walk", &"Lesha_attack_1"]:
		assert(gremlin.animation_player.has_animation(clip), "Gremlin animation missing: " + clip)
	var body := gremlin.get_node("SkeletonModel/GremlinModel/Dokkeabi/Skeleton3D/SM_Dokkeabi") as MeshInstance3D
	assert((body.get_surface_override_material(0) as StandardMaterial3D).albedo_texture != null)
	var player_collider := player.get_node("CollisionShape3D") as CollisionShape3D
	assert((body.global_transform * body.get_aabb()).size.y < (player_collider.shape as CapsuleShape3D).height * 0.6, "Gremlin must be visibly smaller than the player")
	await create_timer(0.4).timeout
	assert(gremlin.global_position.z > -4.0, "Gremlin must pursue the player")
	assert(gremlin.current_animation == &"Lesha_walk", "Pursuit must play the walk cycle")

	gremlin.set_physics_process(false)
	gremlin.global_position = Vector3(0, 0, -1.4)
	gremlin.target = player
	player.character.rotation.y = PI
	assert(player.try_start_parry())
	gremlin.is_attacking = true
	gremlin.attack_has_hit = false
	gremlin._play(&"Lesha_attack_1", true)
	gremlin.animation_player.seek(gremlin.animation_player.get_animation(&"Lesha_attack_1").length * 0.53, true)
	gremlin.animation_player.pause()
	assert(gremlin.is_attack_in_parry_window(), "Club contact must be parryable")
	player._check_active_parry_contacts()
	assert(gremlin.stun_remaining > 0.0, "Parrying the club must stun the Gremlin")
	assert(is_equal_approx(player.current_health, player.max_health))

	player.is_parrying = false
	player.blocking = false
	player.is_invulnerable = false
	player.hit_stun_remaining = 0.0
	gremlin.global_position = Vector3(0, 0, -0.65)
	gremlin.stun_remaining = 0.0
	gremlin.is_attacking = true
	gremlin.attack_has_hit = false
	gremlin._play(&"Lesha_attack_1", true)
	gremlin.animation_player.seek(gremlin.animation_player.get_animation(&"Lesha_attack_1").length * 0.53, true)
	gremlin._process_attack_hit()
	assert(is_equal_approx(player.current_health, player.max_health - gremlin.attack_damage), "Club strike must damage the player")
	gremlin._process_attack_hit()
	assert(is_equal_approx(player.current_health, player.max_health - gremlin.attack_damage), "A swing must only hit once")
	gremlin.take_damage(100.0, player)
	assert(gremlin.is_dead, "Gremlins must be killable")
	print("PASS gremlin textures, walk, club parry, attack damage and death")
	for sound in scene.find_children("*", "AudioStreamPlayer", true, false):
		sound.stop()
	for sound in scene.find_children("*", "AudioStreamPlayer3D", true, false):
		sound.stop()
	await create_timer(0.15).timeout
	current_scene = null
	scene.queue_free()
	await process_frame
	quit()
