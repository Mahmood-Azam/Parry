extends SceneTree
var failures := 0
var scene: Node3D
var player: CharacterBody3D

func _initialize() -> void:
	create_timer(35.0, true).timeout.connect(func(): push_error("Parry/pressure test timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/parry_motion_" + label + ".png")

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
	player.set_process_unhandled_input(false)
	player.character.rotation.y = PI
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(30, 0.2, 30)
	floor_body.position.y = -0.1
	floor_body.add_child(shape)
	scene.add_child(floor_body)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(2.2, 2.2, -3.6)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.make_current()
	var sun := DirectionalLight3D.new()
	scene.add_child(sun)
	sun.rotation_degrees = Vector3(-45, -30, 0)
	var enemy := load("res://assets/enemies/skeleton/shadow_enemy.tscn").instantiate() as CharacterBody3D
	enemy.position = Vector3(0, 0.02, -1.35)
	enemy.triple_attack_chance = 1.0
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	var modifier: SkeletonModifier3D = player.sword_guard_pose
	var rig := modifier.get_skeleton()
	var socket := rig.get_node("RightHandSocket") as BoneAttachment3D
	var sword := socket.get_node("Sword") as Node3D
	var grip_mount := sword.transform
	player._start_block()
	await create_timer(0.3).timeout
	# SkeletonModifier poses are transient; sample the rendered attachment,
	# not the animation-only bone pose restored outside the modifier callback.
	var rest := sword.global_transform
	await capture("guard")
	enemy.target = player
	enemy._begin_combo()
	check(player.try_start_parry(), "Player can enter a fresh parry")
	player._resolve_parry(enemy)
	await create_timer(0.08).timeout
	var first := sword.global_transform
	var side: float = modifier.parry_side
	check(modifier.parry_motion() > 0.3 and modifier.influence > 0.5, "Successful parry immediately drives a visible deflection")
	check(rest.origin.distance_to(first.origin) > 0.015 or rest.basis.get_rotation_quaternion().angle_to(first.basis.get_rotation_quaternion()) > 0.08, "Parry moves the actual sword hand, not just a visual effect")
	check(sword.transform.is_equal_approx(grip_mount), "Deflection preserves the sword's fitted hilt grip")
	await capture("deflect_a")
	await create_timer(0.55).timeout
	check(modifier.parry_motion() == 0.0 and modifier.influence < 0.01, "Parry smoothly releases into locomotion/idle without sticking")
	player._start_block()
	await create_timer(0.22).timeout
	enemy.combo_step = 1
	enemy._start_strike()
	player.parry_cooldown_timer = 0
	player.try_start_parry()
	player._resolve_parry(enemy)
	await create_timer(0.08).timeout
	check(modifier.parry_side == -side, "Consecutive parries alternate deflection direction")
	check(sword.transform.is_equal_approx(grip_mount), "Repeated parries cannot accumulate sword mount drift")
	await capture("deflect_b")
	player.is_dashing = true
	await create_timer(0.22).timeout
	check(modifier.parry_elapsed == modifier.PARRY_DURATION and modifier.influence < 0.01, "Dash interrupts the upper-body deflection cleanly")
	player.is_dashing = false
	player.is_invulnerable = true
	player._end_block()
	enemy.stun_remaining = 0
	enemy.triple_attack_chance = 0
	enemy.target = player
	enemy._begin_combo()
	enemy.combo_step = 0
	enemy.animation_player.seek(enemy.animation_player.current_animation_length * 0.79, true)
	enemy._finish_combo_strike()
	check(is_equal_approx(enemy.attack_timer, 0.9), "Skeleton gets 0.9 seconds of recovery between attack patterns")
	enemy.set_physics_process(true)
	var resumed := false
	var recovery_frames := 0
	for i in 75:
		await physics_frame
		recovery_frames += 1
		if enemy.is_attacking:
			resumed = true
			break
	check(resumed and recovery_frames >= 45, "Skeleton pauses meaningfully before starting the next attack")
	enemy.set_physics_process(false)
	enemy.apply_stun(0.3)
	check(enemy.attack_timer <= 0.91, "A parry stun does not leave a second long cooldown afterward")
	await create_timer(2.0).timeout
	scene.queue_free()
	await process_frame
	await process_frame
	print("Parry motion and skeleton pressure checks complete, failures=", failures)
	quit(1 if failures else 0)
