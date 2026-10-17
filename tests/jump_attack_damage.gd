extends SceneTree

class DummyEnemy extends Node3D:
	var hits := 0
	var damage_taken := 0.0
	var stun_count := 0

	func _ready() -> void:
		add_to_group("enemy")

	func take_damage(amount: float, _attacker: Node = null) -> bool:
		hits += 1
		damage_taken += amount
		return true

	func apply_stun(_duration: float) -> void:
		stun_count += 1


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var main := load("res://main.tscn").instantiate() as Node3D
	var player := main.get_node("Player")
	main.remove_child(player)
	main.free()
	stage.add_child(player)
	player.set_physics_process(false)
	player.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var enemy := DummyEnemy.new()
	stage.add_child(enemy)
	enemy.global_position = player.global_position + Vector3(0.0, 0.0, 2.0)
	player.fire_meter = 0.0
	player._begin_attack("JumpAttack")
	var clip := player.animation_player.get_animation("JumpAttack") as Animation
	assert(clip != null)
	player.animation_player.seek(clip.length * (player.jump_attack_hit_fraction - 0.08), true)
	player._update_player_attack_hit()
	assert(enemy.hits == 0)
	player.animation_player.seek(clip.length * (player.jump_attack_hit_fraction + 0.02), true)
	player._update_player_attack_hit()
	assert(enemy.hits == 1)
	assert(is_equal_approx(enemy.damage_taken, player.jump_attack_damage))
	assert(enemy.stun_count == 1)
	assert(is_zero_approx(player.fire_meter))
	player._update_player_attack_hit()
	assert(enemy.hits == 1)
	print("JUMP_ATTACK_DAMAGE_OK")
	await create_timer(0.08, true, false, true).timeout
	current_scene = null
	stage.queue_free()
	await process_frame
	await process_frame
	quit()
