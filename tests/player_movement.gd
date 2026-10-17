extends SceneTree
## Exercise the real controller and capsule against actual physics, not mocks.
var scene: Node3D
var player: CharacterBody3D
var failures := 0

func _initialize() -> void:
	create_timer(50.0, true).timeout.connect(func(): push_error("Movement test timed out"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		push_error(message + " position=" + str(player.position) + " velocity=" + str(player.velocity))

func box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	body.add_child(mesh)
	scene.add_child(body)
	return body

func ticks(count: int) -> void:
	for i in count:
		await physics_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/movement_" + label + ".png")

func release() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back", "sprint", "jump", "dash", "block"]:
		Input.action_release(action)

func reset_at(point: Vector3 = Vector3(0, 0.02, 0)) -> void:
	release()
	player.is_dashing = false
	player.is_invulnerable = false
	player.dash_cooldown_timer = 0.0
	player.dash_buffer_remaining = 0.0
	player.attacking = false
	player.is_attacking = false
	player.hit_stun_remaining = 0.0
	player.is_fire_channeling = false
	player.blocking = false
	player.is_parrying = false
	player.jump_requested = false
	player.position = point
	player.velocity = Vector3.ZERO
	await ticks(12)

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var main := load("res://main.tscn").instantiate() as Node3D
	player = main.get_node("Player")
	main.remove_child(player)
	main.free()
	scene.add_child(player)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.camera_target_yaw = 0.0
	player.camera_pivot.rotation.y = 0.0
	box(Vector3(0, -0.1, 0), Vector3(80, 0.2, 80))
	# Four isolated lanes: curb, high wall, low overhang and stairs.
	box(Vector3(0, 0.18, -3), Vector3(3, 0.36, 3))
	box(Vector3(8, 0.6, -3), Vector3(3, 1.2, 1))
	box(Vector3(16, 0.18, -3), Vector3(3, 0.36, 3))
	box(Vector3(16, 2.05, -2.5), Vector3(3, 0.3, 4))
	for i in 4:
		var height := 0.20 * (i + 1)
		box(Vector3(24, height / 2.0, -2.0 - i * 0.8), Vector3(3, height, 0.8))
	var ramp := box(Vector3(-8, 0.75, -4), Vector3(3, 0.2, 6))
	ramp.rotation.x = deg_to_rad(20.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	scene.add_child(sun)
	await reset_at()
	check(player.is_on_floor(), "Player starts grounded")
	Input.action_press("move_forward")
	await ticks(12)
	check(absf(player.velocity.z + player.walk_speed) < 0.15, "Normal movement reaches speed responsively")
	Input.action_release("move_forward")
	await ticks(12)
	check(player.velocity.length() < 0.1, "Release brakes cleanly without skating")
	await reset_at(Vector3(4, 0.02, 4))
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await ticks(20)
	check(absf(Vector2(player.velocity.x, player.velocity.z).length() - player.walk_speed) < 0.1, "Diagonal speed equals straight speed")
	Input.action_press("sprint")
	await ticks(15)
	check(absf(Vector2(player.velocity.x, player.velocity.z).length() - player.run_speed) < 0.1, "Shift sprints using the action binding")
	check(player.animation_player.current_animation == "Run", "Fast traversal uses running animation")
	await capture("running")
	await reset_at(Vector3(4, 0.02, 4))
	Input.action_press("move_forward")
	await ticks(12)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await ticks(12)
	check(player.velocity.z > player.walk_speed * 0.9, "Direction reversals are responsive")
	await reset_at()
	Input.action_press("move_forward")
	var previous_camera_y: float = player.camera_pivot.global_position.y
	var largest_camera_step := 0.0
	for i in 33:
		await ticks(1)
		largest_camera_step = maxf(largest_camera_step, absf(player.camera_pivot.global_position.y - previous_camera_y))
		previous_camera_y = player.camera_pivot.global_position.y
	check(player.position.y > 0.33 and player.position.z < -2.2 and player.is_on_floor(), "Walk onto a 36cm curb without jumping")
	check(largest_camera_step < 0.12, "Camera eases over curbs without a one-frame height jolt")
	await capture("curb")
	await ticks(42)
	check(player.position.z < -5.0 and absf(player.position.y) < 0.025 and player.is_on_floor(), "Walk down curb and remain grounded")
	await reset_at(Vector3(8, 0.02, 0))
	Input.action_press("move_forward")
	await ticks(55)
	check(player.position.z > -2.4 and player.position.y < 0.05, "Tall walls cannot be auto-climbed")
	await reset_at(Vector3(16, 0.02, 0))
	Input.action_press("move_forward")
	await ticks(40)
	check(player.position.z > -1.6 and player.position.y < 0.05, "Headroom prevents stepping into low ceilings")
	await reset_at(Vector3(24, 0.02, 0))
	Input.action_press("move_forward")
	await ticks(48)
	check(player.position.z < -3.8 and player.position.y > 0.59, "Consecutive stair steps work without jump input")
	await reset_at(Vector3(-8, 0.02, 0))
	Input.action_press("move_forward")
	await ticks(50)
	check(player.position.z < -3.5 and player.position.y > 0.5 and player.is_on_floor(), "Flat sole also traverses slopes without snagging")
	await reset_at()
	Input.action_press("move_forward")
	check(player.try_start_dash(), "Dash starts immediately")
	check(get_nodes_in_group("shadow_decoy").size() > 0, "Dash decoy appears at departure")
	await ticks(6)
	await capture("dash")
	await ticks(11)
	check(player.position.z < -2.7 and player.position.y > 0.33, "Dash traverses curbs without collision snagging")
	await ticks(2)
	check(not player.is_dashing and player.velocity.z < -4.5, "Dash exits into movement without killing momentum")
	await ticks(25)
	Input.action_press("dash")
	await ticks(2)
	Input.action_release("dash")
	check(not player.is_dashing, "Q cannot spam another dash before the balanced cooldown expires")
	await ticks(36)
	Input.action_press("dash")
	await ticks(2)
	Input.action_release("dash")
	check(player.is_dashing, "Q retriggers once the 1.25 second cooldown has elapsed")
	await reset_at(Vector3(4, 0.02, 4))
	player.dash_cooldown_timer = 0.08
	Input.action_press("dash")
	await ticks(2)
	Input.action_release("dash")
	await ticks(5)
	check(player.is_dashing, "Slightly early dash input buffers until cooldown ends")
	await reset_at(Vector3(4, 0.02, 4))
	player.attacking = true
	player.is_attacking = true
	player.attack_combo_phase = 2
	Input.action_press("dash")
	await ticks(2)
	Input.action_release("dash")
	check(player.is_dashing and not player.attacking and player.attack_combo_phase == 0, "Q cancels a melee swing with no leftover combo state")
	await reset_at(Vector3(8, 0.02, 0))
	Input.action_press("move_forward")
	player.try_start_dash()
	await ticks(24)
	check(player.position.z > -2.4, "Dash respects walls and does not tunnel")
	await reset_at(Vector3(4, 0.02, 4))
	Input.action_press("block")
	Input.action_press("move_forward")
	await ticks(20)
	check(player.blocking and -player.velocity.z > 3.5, "Blocking still permits useful movement")
	check(player.try_start_dash() and not player.blocking, "Dash cancels block without keeping the guard pose")
	await reset_at(Vector3(4, 0.02, 4))
	player.hit_stun_remaining = 0.2
	check(not player.try_start_dash(), "Damage stun cannot be bypassed by dashing")
	player.jump_requested = true
	player.jump_buffer_remaining = 0.03
	await ticks(8)
	check(not player.jump_requested, "Blocked jump requests expire instead of unexpectedly firing later")
	await reset_at(Vector3(4, 0.02, 4))
	Input.action_press("jump")
	await ticks(2)
	Input.action_release("jump")
	await ticks(10)
	check(player.position.y > 0.6 and not player.is_on_floor(), "Jump leaves the floor without snap cancelling it")
	var start_y := player.position.y
	player.try_start_dash()
	await ticks(14)
	check(player.velocity.y < -1.0 and player.position.y < start_y + 0.15, "Air dash continues vertical gravity instead of hovering")
	await ticks(35)
	check(player.is_on_floor() and absf(player.position.y) < 0.025, "Jump and air dash return to ground reliably")
	release()
	print("Movement checks complete, failures=", failures)
	quit(1 if failures > 0 else 0)
