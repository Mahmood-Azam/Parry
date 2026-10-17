extends SceneTree

func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var scene := load("res://assets/enemies/skeleton/shadow_enemy.tscn") as PackedScene
	assert(scene != null)
	var boss := scene.instantiate() as CharacterBody3D
	boss.is_boss = true
	stage.add_child(boss)
	assert(boss.boss_attack_sound.stream != null)
	assert(boss.attack_sound == null)
	assert(boss.get_node_or_null("BossImpactSound") == null)
	assert(boss.get_node_or_null("BossHurtSound") == null)
	boss._start_strike()
	assert(boss.boss_attack_sound.playing)
	var normal := scene.instantiate() as CharacterBody3D
	stage.add_child(normal)
	assert(normal.attack_sound != null)
	assert(normal.boss_attack_sound == null)
	print("ASH_WARDEN_AUDIO_OK")
	current_scene = null
	stage.queue_free()
	await process_frame
	quit()
