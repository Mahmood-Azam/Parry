extends SceneTree

class DummyEnemy extends Node3D:
	var is_dead := false
	var accepts := true
	var tag := 0
	var attempts: Array[int]
	var hits := 0

	func _ready() -> void:
		add_to_group("enemy")

	func take_damage(_amount: float, _attacker: Node = null) -> bool:
		attempts.append(tag)
		if not accepts:
			return false
		hits += 1
		return true


func _initialize() -> void:
	create_timer(35.0, true).timeout.connect(func(): push_error("Soul Steal test timed out"); quit(1))
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	scene._continue_game()
	var player: CharacterBody3D = scene.get_node("Player")
	var gameplay_camera := player.camera as Camera3D
	for frame in 12:
		await physics_frame
	player.set_physics_process(false)
	player.global_position = Vector3(10000.0, 0.0, 10000.0)
	player.current_health = 40.0
	var hud: Panel = player.status_hud
	hud.refresh()
	assert("READY" in hud.soul_label.text)
	assert((load("res://assets/audio/soul_steal/soul_cast.wav") as AudioStream).get_length() > 0.4)
	assert((load("res://assets/audio/soul_steal/soul_travel.wav") as AudioStream).get_length() > 0.3)
	assert((load("res://assets/audio/soul_steal/soul_hit.wav") as AudioStream).get_length() > 0.6)
	var attempts: Array[int] = []
	var enemies: Array[DummyEnemy] = []
	for index in 4:
		var enemy := DummyEnemy.new()
		enemy.tag = index
		enemy.attempts = attempts
		enemy.accepts = index != 1
		scene.add_child(enemy)
		enemy.global_position = player.global_position + Vector3(float(index + 2) * 2.0, 0.0, 0.0)
		enemies.append(enemy)
	var distant := DummyEnemy.new()
	distant.tag = 99
	distant.attempts = attempts
	scene.add_child(distant)
	distant.global_position = player.global_position + Vector3(20.0, 0.0, 0.0)
	assert(player.try_start_dash())
	var dash_shadow: Node3D = player.active_shadow_decoy
	player._end_dash()
	assert(player.try_start_soul_steal())
	assert(player.active_shadow_decoy == dash_shadow and dash_shadow.soul_active)
	assert(dash_shadow.soul_animation != null and dash_shadow.soul_animation.is_playing())
	assert(is_equal_approx(dash_shadow.material.albedo_color.a, 1.0))
	assert(dash_shadow.silhouette_meshes[0].material_overlay != null)
	assert(is_instance_valid(player.soul_cinematic))
	assert(root.get_camera_3d() == player.soul_cinematic.cinematic_camera)
	assert(is_equal_approx(player.soul_steal_cooldown_timer, 10.0))
	hud.refresh()
	assert("10.0s" in hud.soul_label.text)
	assert(not player.try_start_soul_steal())
	var slow_seen := false
	for frame in 120:
		await process_frame
		if Engine.time_scale <= 0.45:
			slow_seen = true
			break
	assert(slow_seen)
	await dash_shadow.soul_finished
	await create_timer(0.5, true, false, true).timeout
	assert(is_equal_approx(Engine.time_scale, 1.0))
	assert(root.get_camera_3d() == gameplay_camera)
	assert(attempts == [0, 1, 2, 3])
	assert(enemies[0].hits == 1 and enemies[1].hits == 0 and enemies[2].hits == 1 and enemies[3].hits == 1)
	assert(distant.hits == 0)
	assert(is_equal_approx(player.current_health, 70.0))
	player._update_timers(10.0)
	assert(is_zero_approx(player.soul_steal_cooldown_timer))
	hud.refresh()
	assert("READY" in hud.soul_label.text)
	assert(player.try_start_soul_steal())
	assert(player.active_shadow_decoy != dash_shadow)
	var second_shadow: Node3D = player.active_shadow_decoy
	await second_shadow.soul_finished
	await create_timer(0.5, true, false, true).timeout
	assert(is_equal_approx(player.current_health, 100.0))
	assert(is_equal_approx(Engine.time_scale, 1.0))
	player._update_timers(10.0)
	assert(player.try_start_soul_steal())
	await create_timer(0.25, true, false, true).timeout
	player.active_shadow_decoy.queue_free()
	await create_timer(0.55, true, false, true).timeout
	assert(is_equal_approx(Engine.time_scale, 1.0))
	assert(root.get_camera_3d() == gameplay_camera)
	print("SOUL_STEAL_OK")
	quit()
