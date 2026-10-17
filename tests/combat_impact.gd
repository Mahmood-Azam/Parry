extends SceneTree
const IMPACT := preload("res://combat_impact.gd")
const PAUSE := preload("res://combat_hit_pause.gd")
var scene: Node3D
var player: CharacterBody3D
var failures := 0

func _initialize() -> void:
	create_timer(40.0, true).timeout.connect(func(): push_error("Impact test timed out"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		push_error(message)

func wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/impact_" + label + ".png")

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var main := load("res://main.tscn").instantiate() as Node3D
	player = main.get_node("Player")
	main.remove_child(player)
	main.free()
	scene.add_child(player)
	player.position = Vector3.ZERO
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.camera_unlocked = true
	player.character.rotation.y = PI
	var camera := Camera3D.new()
	camera.position = Vector3(4, 3, 5)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 1, -1))
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	scene.add_child(light)
	var enemies: Array[CharacterBody3D] = []
	for path in ["res://assets/enemies/skeleton/shadow_enemy.tscn", "res://assets/enemies/mage/shadowkin_mage.tscn", "res://assets/enemies/Mutant/mutant_boss.tscn"]:
		var enemy := load(path).instantiate() as CharacterBody3D
		enemy.position = Vector3(enemies.size() * 3, 0, -2)
		scene.add_child(enemy)
		enemy.set_physics_process(false)
		enemies.append(enemy)
	await wait(0.15)
	for enemy in enemies:
		var hp: float = enemy.current_health
		check(enemy.take_damage(12.0, player), "Enemy accepts damage")
		var feedback := enemy.get_node("CombatImpact")
		check(not feedback.meshes.is_empty(), "Imported enemy meshes get hit overlay")
		check(feedback.recoil != null and feedback.recoil.bone >= 0, "Enemy has additive torso recoil")
		check(feedback.sound.stream != null and feedback.sound.playing, "Enemy contact audio plays")
		check(is_equal_approx(enemy.current_health, hp - 12.0), "Feedback does not change damage balance")
	await capture("enemy_hit")
	await create_timer(0.3).timeout
	for enemy in enemies:
		var feedback := enemy.get_node("CombatImpact")
		check(feedback.originals.is_empty(), "Hit overlay cleans up without changing original materials")
		IMPACT.hit(enemy, player, 1.0)
		check(feedback.elapsed >= 0.14, "Small burn ticks do not cause repeated hit flashes")
	player.fire_meter = 100.0
	check(player._process_player_attack_hit(), "Actual melee hit connects")
	check(Engine.time_scale < 0.2, "Confirmed melee hit produces brief hit pause")
	await wait(0.10)
	check(is_equal_approx(Engine.time_scale, 1.0), "Melee hit pause restores normal speed")
	for enemy in enemies:
		enemy.position.x += 30.0
	player.fire_meter = 100.0
	check(not player._process_player_attack_hit() and is_equal_approx(Engine.time_scale, 1.0) and player.fire_meter == 100.0, "Misses do not spend fire or trigger false hit confirmation")
	var boss: CharacterBody3D = enemies[2]
	boss.position = Vector3(0, 0, -2)
	boss.flexing = true
	check(not player._process_player_attack_hit() and player.fire_meter == 100.0 and is_equal_approx(Engine.time_scale, 1.0), "Immune targets do not trigger false hit confirmation")
	boss.flexing = false
	enemies[0].position = Vector3(0, 0, -2)
	player.hit_stun_remaining = 0.0
	player.take_damage(15.0, enemies[0])
	await wait(0.025)
	check(player.hit_stun_remaining > 0.0, "Player damage still locks controls for the existing stun")
	check(player.camera_trauma > 0.0 and (absf(player.camera.h_offset) + absf(player.camera.v_offset)) > 0.00001, "Camera responds while player is damage-stunned")
	check(player.hit_flash.color.a > 0.0, "Player damage has immediate screen feedback")
	await capture("player_hit")
	await wait(0.35)
	check(is_equal_approx(Engine.time_scale, 1.0), "Damage hit pause restores speed")
	player.hit_stun_remaining = 0.0
	player.blocking = true
	var hp: float = player.current_health
	player.take_damage(10.0, enemies[0])
	check(is_equal_approx(player.current_health, hp - 3.5), "Block damage reduction is unchanged")
	check(player.get_node("CombatImpact").sound.stream == IMPACT._contact_sound(true), "Blocked hit uses distinct metallic contact audio")
	await wait(0.15)
	PAUSE.request(scene, 0.04)
	PAUSE.request(scene, 0.06)
	check(Engine.time_scale < 0.2, "Overlapping hit pauses share one owner")
	await wait(0.12)
	check(is_equal_approx(Engine.time_scale, 1.0), "Overlapping pauses cannot leave the game slowed")
	PAUSE.request(scene, 0.04)
	paused = true
	await wait(0.1)
	check(paused and is_equal_approx(Engine.time_scale, 1.0), "Menu pause is preserved while impact slowdown expires")
	paused = false
	PAUSE.request(scene, 0.5)
	scene.get_node("CombatHitPause").free()
	check(is_equal_approx(Engine.time_scale, 1.0), "Scene cleanup restores speed even mid-impact")
	print("Impact checks complete, failures=", failures)
	quit(1 if failures > 0 else 0)
