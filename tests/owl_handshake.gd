extends SceneTree
var scene: Node3D
var player: CharacterBody3D
var owl: Node3D
var failures := 0

func _initialize() -> void:
	create_timer(35, true).timeout.connect(func(): push_error("Handshake test timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func settle() -> void:
	for i in 4:
		await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/owl_handshake_" + label + ".png")

func marker(rig: Skeleton3D, bone: String, offset: Vector3) -> Marker3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	rig.add_child(attachment)
	var point := Marker3D.new()
	point.position = offset
	attachment.add_child(point)
	return point

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
	player.character.rotation = Vector3.ZERO
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(20, 0.2, 20)
	floor_body.position.y = -0.1
	floor_body.add_child(shape)
	scene.add_child(floor_body)
	var sun := DirectionalLight3D.new()
	scene.add_child(sun)
	sun.rotation_degrees = Vector3(-45, -25, 0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.04, 0.06, 0.09)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.85, 1)
	environment.environment.ambient_light_energy = 0.7
	scene.add_child(environment)
	await create_timer(0.15).timeout
	owl = preload("res://assets/npc/owl/owl_companion.gd").new()
	scene.add_child(owl)
	owl.set_process(false)
	var original_position := player.position
	var human := player.character.get_node("Skeleton3D") as Skeleton3D
	var sword := human.get_node("RightHandSocket/Sword") as Node3D
	var grip_mount := sword.transform
	var sword_visible := sword.visible
	var guard_active: bool = player.sword_guard_pose.active
	var first_lines: Array[String] = ["Salam Ustaad", "Ki Haal hai"]
	var first_durations: Array[float] = [3.0, 1.5]
	owl.start_story(player, first_lines, first_durations)
	owl._process(2.8)
	check(owl.greeting != null and owl.speech.text == "Salam Ustaad", "Salam Ustaad starts the physical greeting")
	check(not player.is_physics_processing(), "Player remains locked for the greeting")
	if owl.greeting == null:
		quit(1)
		return
	var greeting: RefCounted = owl.greeting
	var palm := marker(human, "mixamorig_LeftHand", Vector3(0, 0.10, 0.025))
	var wing_tip := marker(greeting.bird, greeting.bird.get_bone_name(greeting.wing_tip), Vector3.ZERO)
	owl._process(0.4)
	await settle()
	await capture("reach")
	owl._process(0.6)
	await settle()
	var gap := palm.global_position.distance_to(wing_tip.global_position)
	print("Contact gap metres=", gap, " palm=",palm.global_position, " wing=",wing_tip.global_position, " goal=",greeting.contact)
	check(gap < 0.08, "Player palm and actual owl feather tip meet")
	check(greeting.blend > 0.99 and owl.global_position.y < 1.6, "Owl lowers and both limbs fully extend into the greeting")
	check(player.position.distance_to(original_position) < 0.02, "Greeting never moves the player capsule or feet")
	check(sword.transform.is_equal_approx(grip_mount) and sword.visible == sword_visible, "Sword remains fitted in the other hand")
	var y_high: float = greeting.contact.y
	owl._process(0.2)
	await settle()
	var y_low: float = greeting.contact.y
	check(absf(y_high - y_low) > 0.015, "Joined wing and hand perform a small synchronized shake")
	await capture("contact")
	owl._process(0.3)
	await settle()
	await capture("second_shake")
	owl._process(1.3)
	await settle()
	check(greeting.blend < 0.01, "Both limbs blend out before the next dialogue line")
	owl._process(0.2)
	await settle()
	check(owl.greeting == null and owl.speech.text == "Ki Haal hai", "The next line restores normal flight and idle")
	check(player.sword_guard_pose.active == guard_active, "Greeting restores the combat arm modifier exactly")
	check(human.find_child("OwlHandshakeHand", false, false) == null, "Temporary hand IK is removed")
	owl._process(1.5)
	owl._process(0.65)
	check(player.is_physics_processing() and owl.state == "hidden", "Dialogue completes and restores player controls")
	var greeting_lines: Array[String] = ["Salam Ustaad"]
	var greeting_durations: Array[float] = [3.0]
	owl.start_story(player, greeting_lines, greeting_durations)
	owl._process(2.8)
	owl._process(0.9)
	owl._interrupt_current()
	await settle()
	check(owl.greeting == null and player.is_physics_processing() and player.sword_guard_pose.active == guard_active, "Interrupting mid-handshake cleans up both rigs and control locks")
	var other_lines: Array[String] = ["A different clue"]
	var other_durations: Array[float] = [1.0]
	owl.start_story(player, other_lines, other_durations)
	owl._process(2.8)
	check(owl.greeting == null, "Non-greeting dialogue does not replay the handshake")
	owl._interrupt_current()
	print("Owl handshake checks complete, failures=",failures)
	quit(1 if failures else 0)
