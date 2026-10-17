extends SceneTree
var scene: Node3D
var failures := 0

func _initialize() -> void:
	create_timer(40, true).timeout.connect(func(): push_error("Destruction test timed out"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		push_error(message)

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/campus_" + label + ".png")

func run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene._continue_game()
	var damage: Node3D = scene.breach_world.destruction
	await physics_frame
	await physics_frame
	check(damage.destroyed and damage.mesh_states.size() > 100, "Right-side buildings have a persistent destruction layer")
	check(damage.collision_states.size() > 0, "Destroyed upper floors also disable their original collision")
	var hidden := 0
	for state in damage.mesh_states:
		var mesh: MeshInstance3D = state[0].get_ref()
		if not state[3] and not mesh.visible:
			hidden += 1
	check(hidden > 100, "Upper storeys and roof geometry are removed, not just covered by particles")
	var collisions_disabled := true
	for state in damage.collision_states:
		collisions_disabled = collisions_disabled and state[0].get_ref().disabled
	check(collisions_disabled, "Damaged geometry has no invisible colliders")
	var room := scene.get_node("EncounterDirector").RELIC_ROOM_PATH as String
	var relic_room := scene.get_node(room) as Node3D
	check(relic_room.is_visible_in_tree(), "First-floor relic room remains intact and accessible")
	var original_environment: Environment = scene.get_node("CampusMap").environment
	var camera := Camera3D.new()
	camera.position = Vector3(18, 15, -61)
	scene.add_child(camera)
	camera.look_at(Vector3(45, 7, -74))
	camera.make_current()
	await capture("destroyed")
	await scene.breach_world.restore_campus(0.3)
	await physics_frame
	await physics_frame
	check(not damage.destroyed and not damage.rubble.visible, "Reversal gathers rubble and restores the intact campus")
	var exact := true
	for state in damage.mesh_states:
		var mesh: MeshInstance3D = state[0].get_ref()
		exact = exact and mesh.visible == state[1] and mesh.transform.is_equal_approx(state[2])
	for state in damage.collision_states:
		exact = exact and state[0].get_ref().disabled == state[1]
	for state in damage.batch_states:
		var batch: MultiMeshInstance3D = state[0].get_ref()
		exact = exact and batch.multimesh.get_instance_transform(state[1]).is_equal_approx(state[2])
	check(exact, "All saved transforms, visibility, batched geometry and collision states restore exactly")
	check(not scene.breach_world.gate.visible and not scene.breach_world.meteor.visible, "Future ending hook removes the portal, meteor and scorch")
	check(scene.get_node("CampusMap").environment == original_environment, "Structural reversal does not overwrite graphics settings")
	await capture("restored")
	scene.breach_world.show_aftermath()
	await physics_frame
	check(damage.destroyed, "Destruction can be reapplied for a new run")
	check(scene.get_node("EncounterDirector").relic_count == 0, "Reversal hook does not fake relic quest completion")
	print("Destruction checks complete, failures=", failures, " saved meshes=", damage.mesh_states.size(), " colliders=",damage.collision_states.size())
	quit(1 if failures else 0)
