extends Node3D
## Bara Ustaad enters the surviving D-block roof in a brief locked-camera landing.

signal landed(actor: CharacterBody3D)

const BOSS := preload("res://assets/enemies/Bara Ustaad/bara_ustaad.tscn")
const FX := preload("res://combat_fx.gd")
const LANDING := Vector3(48.2, 6.55, -85.3)

var player: CharacterBody3D
var boss: CharacterBody3D
var previous_camera: Camera3D
var shot_camera: Camera3D
var saved_physics := true
var saved_input := true
var saved_unhandled := true
var shot_time := 0.0
var shake_time := 0.0
var restored := false

func begin(target: CharacterBody3D) -> void:
	player = target
	process_mode = Node.PROCESS_MODE_PAUSABLE
	saved_physics = player.is_physics_processing()
	saved_input = player.is_processing_input()
	saved_unhandled = player.is_processing_unhandled_input()
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	previous_camera = get_viewport().get_camera_3d()
	shot_camera = Camera3D.new()
	shot_camera.name = "BaraArrivalCamera"
	shot_camera.fov = 64.0
	shot_camera.near = 0.05
	get_parent().add_child(shot_camera)
	shot_camera.global_transform = previous_camera.global_transform if previous_camera else Transform3D.IDENTITY
	shot_camera.make_current()
	boss = BOSS.instantiate() as CharacterBody3D
	boss.name = "BaraUstaad"
	boss.position = LANDING + Vector3.UP * 9.0
	boss.max_health = 1350.0 # Twice the Mutant's 675 HP.
	boss.attack_damage = 32.0
	boss.move_speed = 2.7
	boss.attack_range = 2.2
	boss.collision_layer = 0
	boss.collision_mask = 0
	boss.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_parent().add_child(boss)
	boss.set_physics_process(false)
	boss.health_bar.hide()
	boss._play(&"Idle", true)
	boss.animation_player.advance(0.0)
	boss.jump_sound.play()
	_play_arrival()

func _process(delta: float) -> void:
	if not is_instance_valid(shot_camera) or restored:
		return
	shot_time += delta
	shake_time = maxf(shake_time - delta, 0.0)
	var destination := LANDING + Vector3(5.0, 3.3, 6.8)
	shot_camera.global_position = shot_camera.global_position.lerp(destination, minf(delta * 2.6, 1.0))
	if shake_time > 0.0:
		shot_camera.global_position += Vector3(randf_range(-0.10, 0.10), randf_range(-0.08, 0.08), 0) * (shake_time / 0.55)
	shot_camera.look_at(LANDING + Vector3.UP * 1.8)

func _play_arrival() -> void:
	await get_tree().create_timer(0.35, false).timeout
	if not is_inside_tree():
		return
	boss.animation_player.speed_scale = 1.8
	boss._play(&"EntranceJump", true)
	var leap := create_tween()
	leap.tween_property(boss, "global_position", LANDING, 1.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await leap.finished
	if not is_inside_tree():
		return
	_impact()
	await get_tree().create_timer(1.35, false).timeout
	if not is_inside_tree():
		return
	_restore_control()
	boss.collision_layer = 4
	boss.collision_mask = 7
	boss.animation_player.speed_scale = 1.0
	boss._play(&"Idle", true)
	boss.awareness.home = LANDING
	boss.engaged = true
	boss.set_physics_process(true)
	landed.emit(boss)
	queue_free()

func _impact() -> void:
	shake_time = 0.55
	boss.jump_sound.play()
	if is_instance_valid(player):
		player.call("_add_camera_trauma", 0.35)
	FX.burst(get_parent(), LANDING + Vector3.UP * 0.2, Color(1.0, 0.53, 0.2), 45, 1.3)
	FX.ring(get_parent(), LANDING + Vector3.UP * 0.12, Color(0.75, 0.3, 0.9), 2.3)
	for index in 10:
		var brick := MeshInstance3D.new()
		brick.name = "LandingBrick"
		var box := BoxMesh.new()
		box.size = Vector3(0.22, 0.14, 0.32) * randf_range(0.7, 1.25)
		brick.mesh = box
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color(0.48, 0.43, 0.42).lerp(Color(0.7, 0.62, 0.56), randf())
		brick.material_override = stone
		get_parent().add_child(brick)
		brick.global_position = LANDING + Vector3.UP * 0.3
		var angle := TAU * float(index) / 10.0 + randf_range(-0.12, 0.12)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var peak := brick.global_position + outward * randf_range(0.8, 1.7) + Vector3.UP * randf_range(0.8, 1.6)
		var ground := LANDING + outward * randf_range(1.4, 2.7) + Vector3.UP * 0.15
		var flight := create_tween()
		flight.tween_property(brick, "global_position", peak, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		flight.tween_property(brick, "global_position", ground, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		flight.tween_callback(brick.queue_free)
		var spin := create_tween()
		spin.tween_property(brick, "rotation", Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)), 1.05)

func _restore_control() -> void:
	if restored:
		return
	restored = true
	if is_instance_valid(previous_camera):
		previous_camera.make_current()
	if is_instance_valid(shot_camera):
		shot_camera.queue_free()
	if is_instance_valid(player):
		player.set_physics_process(saved_physics)
		player.set_process_input(saved_input)
		player.set_process_unhandled_input(saved_unhandled)

func _exit_tree() -> void:
	_restore_control()
