extends SceneTree
const MUTANT := preload("res://assets/enemies/Mutant/mutant_boss.tscn")
const ENEMY := preload("res://assets/enemies/skeleton/shadow_enemy.tscn")
var scene: Node3D
var player: CharacterBody3D
var mutant: CharacterBody3D
var deaths := 0

func _initialize() -> void:
	create_timer(45.0, true).timeout.connect(func(): push_error("Mutant integration timed out"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/" + label + ".png")

func ready_player(parry: bool = false) -> void:
	player.is_parrying = false
	player.blocking = false
	player.is_invulnerable = false
	player.is_dashing = false
	player.attacking = false
	player.hit_stun_remaining = 0.0
	player.parry_cooldown_timer = 0.0
	player.character.rotation.y = PI
	if parry:
		check(player.try_start_parry(), "Player must enter parry stance")

func seek_attack(jump: bool, fraction: float) -> void:
	mutant.stun_remaining = 0.0
	mutant.punches_done = mutant.punches_before_jump if jump else 0
	mutant.target = player
	mutant._start_attack()
	mutant.animation_player.seek(mutant.animation_player.get_animation(mutant.attack_kind).length * fraction, true)
	mutant.animation_player.pause()

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var main := load("res://main.tscn").instantiate() as Node3D
	player = main.get_node("Player")
	main.remove_child(player)
	main.free()
	player.position = Vector3(0, 0.05, 0)
	scene.add_child(player)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.camera_unlocked = true
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	shape.shape = box
	floor_body.add_child(shape)
	scene.add_child(floor_body)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(30, 30)
	scene.add_child(ground)
	var camera := Camera3D.new()
	camera.position = Vector3(5, 3.5, 5)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 1.1, -1.2))
	camera.make_current()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	scene.add_child(sun)
	await create_timer(0.35).timeout
	player.set_physics_process(false)
	mutant = MUTANT.instantiate() as CharacterBody3D
	mutant.position = Vector3(0, 0, -1.7)
	mutant.max_health = 675.0
	mutant.attack_damage = 25.0
	scene.add_child(mutant)
	mutant.engaged = true
	mutant.set_physics_process(false)
	for clip in ["Idle", "Walk", "Flex", "Punch", "Jump", "Death"]:
		check(mutant.animation_player.has_animation(clip), "Imported Mutant clip missing: " + clip)
	ready_player(true)
	seek_attack(false, 0.48)
	check(mutant.is_attack_in_parry_window(), "Punch contact must be parryable")
	player._check_active_parry_contacts()
	check(player.current_health == 100.0 and mutant.stun_remaining > 0.0, "A timed punch parry must stun the Mutant without player damage")
	check(player.ultimate_controller.charge > 0.0, "Mutant parries must charge the ultimate reserve")
	await capture("merged_mutant_parry")
	ready_player(true)
	seek_attack(true, 0.7)
	check(not mutant.is_attack_in_parry_window(), "Jump must not offer a melee parry contact")
	mutant._process_attack_contact()
	check(is_equal_approx(player.current_health, 63.75), "Mutant jump must bypass parry and indefinite block")
	ready_player()
	player.is_invulnerable = true
	seek_attack(true, 0.7)
	mutant._process_attack_contact()
	check(is_equal_approx(player.current_health, 63.75), "Shadow protection must evade the unparryable jump")
	print("PASS imported animations, punch parry, ultimate charge and jump/Shadow rules")
	ready_player()
	player.blocking = true
	seek_attack(false, 0.1)
	mutant._process_attack_contact()
	check(is_equal_approx(player.current_health, 63.75), "Punch must not hit before its animation contact")
	mutant.animation_player.seek(mutant.animation_player.get_animation("Punch").length * 0.48, true)
	mutant._process_attack_contact()
	check(is_equal_approx(player.current_health, 55.0), "Held block must reduce normal Mutant punch damage")
	mutant._process_attack_contact()
	check(is_equal_approx(player.current_health, 55.0), "Punch contact must damage only once")
	print("PASS synchronized punch contact, block reduction and no double hits")
	ready_player()
	player.current_health = 100.0
	mutant.stun_remaining = 0.0
	mutant.is_attacking = false
	mutant._play(&"Idle", true)
	var neighbor := ENEMY.instantiate() as CharacterBody3D
	neighbor.position = Vector3(1.5, 0, -2.5)
	scene.add_child(neighbor)
	neighbor.set_physics_process(false)
	player.ultimate_controller.add_fire(200.0)
	check(player.ultimate_controller.select_focused_target() == mutant, "Boss-target ultimate must prioritize the Mutant")
	check(player.ultimate_controller.try_activate("focused"), "Focused ultimate must activate on the imported boss")
	await create_timer(1.55).timeout
	check(is_equal_approx(mutant.current_health, 335.0), "Focused ultimate must deal 340 direct damage to the Mutant")
	check(neighbor.current_health == 100.0, "Focused ultimate must not damage the neighboring skeleton")
	await capture("merged_mutant_ultimate")
	await create_timer(1.5).timeout
	check(not player.is_using_ultimate, "Ultimate must release controls after striking the Mutant")
	mutant.take_damage(310.0, player)
	check(mutant.flexed and mutant.flexing, "Low-health Mutant must enter its supplied recovery phase")
	var flex_hp: float = mutant.current_health
	check(not mutant.take_damage(50.0, player) and mutant.current_health == flex_hp, "Recovery phase must preserve incoming damage immunity")
	mutant.apply_stun(1.0)
	check(mutant.flexing, "Stun must not interrupt recovery animation")
	await capture("merged_mutant_flex")
	await create_timer(mutant.animation_player.get_animation("Flex").length + 0.1).timeout
	check(not mutant.flexing, "Recovery animation must return the boss to combat")
	mutant.died.connect(func(): deaths += 1)
	mutant.take_damage(999.0, player)
	check(mutant.is_dead and deaths == 1 and not mutant.is_in_group("enemy"), "Mutant must die once after its recovery phase")
	check(mutant.animation_player.current_animation == "Death", "Boss death must play its supplied clip")
	var cleanup_delay: float = mutant.animation_player.get_animation("Death").length + 0.65
	await create_timer(cleanup_delay).timeout
	check(not is_instance_valid(mutant), "Dead Mutant must leave the scene")
	print("PASS focused ultimate compatibility, recovery phase, death animation and cleanup")
	quit()
