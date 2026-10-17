extends SceneTree

const BARA := preload("res://assets/enemies/Bara Ustaad/bara_ustaad.tscn")
var boss: CharacterBody3D
var player: CharacterBody3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var main := load("res://main.tscn").instantiate() as Node3D
	player = main.get_node("Player")
	main.remove_child(player)
	main.free()
	player.position = Vector3(0, 0.05, 0)
	scene.add_child(player)
	player.set_physics_process(false)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var ground := BoxShape3D.new()
	ground.size = Vector3(30, 0.2, 30)
	shape.shape = ground
	floor_body.add_child(shape)
	floor_body.position.y = -0.1
	scene.add_child(floor_body)
	var camera := Camera3D.new()
	camera.position = Vector3(5, 3, 5)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 1.2, -2))
	camera.make_current()
	boss = BARA.instantiate() as CharacterBody3D
	boss.name = "BaraUstaad"
	boss.max_health = 1350.0
	boss.position = Vector3(0, 0, -2)
	scene.add_child(boss)
	boss.set_physics_process(false)
	check(is_equal_approx(boss.current_health, 1350.0), "Final boss must have twice Mutant HP")
	check(boss.get_node("SkeletonModel/BaraModel").find_child("MAW", true, false) != null, "Bara Ustaad model must render")
	for clip_name in ["Idle", "Walk", "AttackHorizontal", "AttackDownward", "AttackKick", "HitLeft", "HitRight", "HitGut", "EntranceJump", "Death"]:
		check(boss.animation_player.has_animation(clip_name), "Missing final boss clip: " + clip_name)
		boss._play(StringName(clip_name), true)
		await process_frame
	var attacks := {}
	for index in 36:
		boss._start_attack()
		attacks[boss.attack_kind] = true
		boss.animation_player.seek(boss.animation_player.get_animation(boss.attack_kind).length * boss._hit_fraction(), true)
		boss.animation_player.pause()
		check(boss.is_attack_in_parry_window(), "Each final boss strike must be parryable")
		boss.attack_has_hit = true
		boss.is_attacking = false
		boss.animation_player.stop()
	check(attacks.size() == 3, "Final boss must choose all three attack patterns")
	player.character.rotation.y = PI
	player.parry_cooldown_timer = 0.0
	player.hit_stun_remaining = 0.0
	player.attacking = false
	player.is_invulnerable = false
	check(player.try_start_parry(), "Player must be able to parry Bara Ustaad")
	boss.target = player
	boss.stun_remaining = 0.0
	boss._start_attack()
	boss.animation_player.seek(boss.animation_player.get_animation(boss.attack_kind).length * boss._hit_fraction(), true)
	boss.animation_player.pause()
	player._check_active_parry_contacts()
	check(boss.stun_remaining > 0.0 and player.current_health == player.max_health, "A timed parry must stun Bara Ustaad without damage")
	player.is_parrying = false
	player.is_invulnerable = false
	player.hit_stun_remaining = 0.0
	boss.stun_remaining = 0.0
	boss._start_attack()
	boss.animation_player.seek(boss.animation_player.get_animation(boss.attack_kind).length * boss._hit_fraction(), true)
	boss._process_attack_contact()
	check(player.current_health < player.max_health, "An unblocked Bara Ustaad strike must damage the player")
	var health_after_contact: float = player.current_health
	boss._process_attack_contact()
	check(is_equal_approx(player.current_health, health_after_contact), "One attack must contact the player only once")
	var reactions := {}
	for index in 24:
		boss.take_damage(4.0, player)
		reactions[boss.animation_player.current_animation] = true
	check(reactions.has("HitLeft") and reactions.has("HitRight") and reactions.has("HitGut"), "Final boss must vary all three damage reactions")
	boss.hit_sound.stop()
	boss.take_burn_damage(1.0, player)
	check(not boss.hit_sound.playing, "Burn ticks must not replay Mutant hit audio")
	boss.take_damage(999999.0, player)
	check(boss.is_dead and boss.animation_player.current_animation == "Death", "Final boss must die with an animation")
	var cleanup_time: float = boss.animation_player.get_animation("Death").length + 0.6
	await create_timer(cleanup_time).timeout
	check(not is_instance_valid(boss), "Final boss must clean up after its death animation")
	print("PASS Bara Ustaad model, 1350 HP, movement, three attacks, three reactions and audio")
	scene.queue_free()
	await process_frame
	quit()
