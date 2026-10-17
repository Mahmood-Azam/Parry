extends SceneTree
var failures := 0

func _initialize() -> void:
	create_timer(35, true).timeout.connect(func(): push_error("Portal collision test timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func run() -> void:
	var scene: Node3D = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene._continue_game()
	var world: Node3D = scene.breach_world
	var gate: Node3D = world.gate
	var player: CharacterBody3D = scene.get_node("Player")
	var director: Node3D = scene.get_node("EncounterDirector")
	director.set_process(false)
	player.set_physics_process(false)
	player.set_process_input(false)
	var body: StaticBody3D = gate.collision_body
	check(body.collision_layer == 1 and body.collision_mask == 0, "Portal is solid on the player's world collision layer")
	var shape := body.get_node("FittedPortalShape").shape as ConcavePolygonShape3D
	check(shape != null and shape.get_faces().size() > 0 and shape.backface_collision, "Fitted surface blocks the portal from both sides")
	print("Portal collision triangles=", shape.get_faces().size() / 3)
	check(shape.get_faces().size() < 450000, "Collision uses lightweight imported LODs, not the full high-poly render model")
	# Test the real player's capsule in isolation from unrelated campus walls.
	gate.global_position = Vector3(200, 1, 200)
	await physics_frame
	await physics_frame
	for offset in [Vector3(0, 0.1, 6), Vector3(0, 0.1, -6), Vector3(6, 0.1, 0), Vector3(-6, 0.1, 0), Vector3(0, 3.5, 6), Vector3(0, 3.5, -6)]:
		var motion: Vector3 = Vector3(-offset.x, 0, -offset.z) * 2
		var collision := KinematicCollision3D.new()
		var hit := player.test_move(Transform3D(Basis.IDENTITY, gate.global_position + offset), motion, collision)
		check(hit and collision.get_collider() == body, "Swept player/dash movement hits the actual portal at " + str(offset))
	gate.hide()
	await physics_frame
	await physics_frame
	check(body.collision_layer == 0, "Hidden portal leaves no invisible wall")
	var hidden_hit := player.test_move(Transform3D(Basis.IDENTITY, gate.global_position + Vector3(0, 0.1, 6)), Vector3(0, 0, -12))
	check(not hidden_hit, "Player can cross the former portal space once it disappears")
	gate.show()
	await physics_frame
	await physics_frame
	check(body.collision_layer == 1, "Showing the portal restores its collision")
	world.prepare_intro()
	check(body.collision_layer == 0, "Opening cinematic emergence does not collide with the portal")
	world.show_aftermath()
	await physics_frame
	await physics_frame
	check(body.collision_layer == 1, "Returning to gameplay restores the solid portal")
	# A player-sized standing position must still exist inside relic-use range.
	var reachable := false
	var space := scene.get_world_3d().direct_space_state
	for offset in [Vector3(0, 0, 3), Vector3(1.5, 0, 2.5), Vector3(-1.5, 0, 2.5), Vector3(3, 0, 0), Vector3(-3, 0, 0)]:
		var point: Vector3 = world.gate_point + offset
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.3, point - Vector3.UP, 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.75:
			continue
		var stand: Vector3 = hit.position + Vector3.UP * 0.04
		var collider := player.get_node("CollisionShape3D") as CollisionShape3D
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collider.shape
		query.transform = Transform3D(Basis.IDENTITY, stand + collider.position)
		query.collision_mask = 1
		if not space.intersect_shape(query, 1).is_empty():
			continue
		player.global_position = stand
		if director._near_portal():
			reachable = true
			break
	check(reachable, "Player can stand beside/on the portal stairs within relic-interaction range")
	check(not gate.take_damage(99999, player), "Solid portal remains invulnerable")
	await world.restore_campus(0.01)
	check(body.collision_layer == 0 and not gate.visible, "Time restoration removes collision along with the portal")
	print("Portal collision checks complete, failures=", failures)
	quit(1 if failures else 0)
