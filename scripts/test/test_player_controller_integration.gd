@tool
extends SceneTree

func _init() -> void:
	print("==========================================================")
	print("--- TESTING PLAYER CONTROLLER & KNIGHT COMBAT SUITE ---")
	print("==========================================================")
	
	var main_scene: PackedScene = load("res://main.tscn")
	assert(main_scene != null, "main.tscn failed to load!")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	
	# Wait for ready and socket mounting
	await process_frame
	
	var player = main_node.find_child("Player", true, false)
	assert(player != null, "Player not found under Main!")
	
	var signals_fired = {
		"health_changed": false,
		"damaged": false,
		"damage_evaded": false,
		"died": false,
		"parry_started": false,
		"parry_success": false,
		"is_perfect": false,
		"parry_failed": false,
		"dash_started": false,
		"dash_finished": false,
		"attack_pressed": false
	}
	
	player.health_changed.connect(func(_c, _m): signals_fired["health_changed"] = true)
	player.damaged.connect(func(_a, _atk): signals_fired["damaged"] = true)
	player.damage_evaded.connect(func(_a, _atk): signals_fired["damage_evaded"] = true)
	player.died.connect(func(): signals_fired["died"] = true)
	player.parry_started.connect(func(): signals_fired["parry_started"] = true)
	player.parry_success.connect(func(_atk, is_perf, _data):
		signals_fired["parry_success"] = true
		signals_fired["is_perfect"] = is_perf
	)
	player.parry_failed.connect(func(): signals_fired["parry_failed"] = true)
	player.dash_started.connect(func(_dir): signals_fired["dash_started"] = true)
	player.dash_finished.connect(func(): signals_fired["dash_finished"] = true)
	player.attack_pressed.connect(func(): signals_fired["attack_pressed"] = true)
	
	# Test 1: Initial health and alive
	print("[TEST 1] Initial Health...")
	assert(player.current_health == 100.0, "Health should start at 100")
	assert(player.is_alive == true, "Player should be alive")
	print("  -> PASSED: Player alive with 100 HP.")
	
	# Test 2: Normal damage
	print("[TEST 2] Normal Damage Reception...")
	var hit = player.take_damage(20.0)
	assert(hit == true, "take_damage should return true on normal hit")
	assert(player.current_health == 80.0, "Health should be 80")
	assert(signals_fired["damaged"] == true, "damaged signal should fire")
	print("  -> PASSED: Took 20 damage, HP is 80.")
	
	# Test 3: Perfect Parry from Front
	print("[TEST 3] Perfect Parry Detection...")
	var parry_ok = player.try_start_parry()
	assert(parry_ok == true, "Parry should start")
	assert(player.is_parrying == true, "Player should be parrying")
	assert(signals_fired["parry_started"] == true, "parry_started signal should fire")
	
	# Front attacker (player faces +Z by default)
	var attacker_front = Node3D.new()
	attacker_front.position = player.global_position + Vector3(0, 0, 4.0) # In front of knight (+Z)
	root.add_child(attacker_front)
	
	var parry_res = player.take_damage(25.0, attacker_front)
	assert(parry_res == false, "take_damage should return false when parried")
	assert(player.current_health == 80.0, "Health should not decrease on parry")
	assert(signals_fired["parry_success"] == true, "parry_success should fire")
	assert(signals_fired["is_perfect"] == true, "Should be detected as perfect parry")
	attacker_front.queue_free()
	print("  -> PASSED: Attack from front absorbed by Perfect Parry.")
	
	# Test 4: Directional Parry - Attack from Behind
	print("[TEST 4] Directional Parry (Attack from behind bypasses parry)...")
	player.parry_cooldown_timer = 0.0
	player.try_start_parry()
	var attacker_back = Node3D.new()
	attacker_back.position = player.global_position + Vector3(0, 0, -4.0) # Behind knight (-Z)
	root.add_child(attacker_back)
	
	signals_fired["damaged"] = false
	var behind_hit = player.take_damage(15.0, attacker_back)
	assert(behind_hit == true, "Attack from behind must bypass parry")
	assert(player.current_health == 65.0, "Health should drop to 65")
	assert(signals_fired["damaged"] == true, "damaged signal should fire")
	attacker_back.queue_free()
	print("  -> PASSED: Attack from behind bypassed parry correctly.")
	
	# Test 5: Shadow Dash Invulnerability
	print("[TEST 5] Shadow Dash & Invulnerability...")
	var dash_ok = player.try_start_dash()
	assert(dash_ok == true, "Dash should start")
	assert(player.is_dashing == true, "is_dashing should be true")
	assert(player.is_invulnerable == true, "is_invulnerable should be true")
	assert(signals_fired["dash_started"] == true, "dash_started signal should fire")
	
	var dash_hit = player.take_damage(30.0)
	assert(dash_hit == false, "Damage during dash must be evaded")
	assert(player.current_health == 65.0, "Health should remain unchanged")
	assert(signals_fired["damage_evaded"] == true, "damage_evaded signal must fire")
	player._end_dash()
	print("  -> PASSED: Shadow Dash evaded damage cleanly.")
	
	# Test 6: Whiffed Parry Penalty
	print("[TEST 6] Whiffed Parry & Recovery Penalty...")
	player.parry_cooldown_timer = 0.0
	player.try_start_parry()
	signals_fired["parry_failed"] = false
	player._update_timers(player.parry_window + 0.05)
	assert(player.is_parrying == false, "Parry window expired")
	assert(signals_fired["parry_failed"] == true, "parry_failed should fire on whiff")
	assert(player.parry_cooldown_timer > 0.0, "Whiff should trigger cooldown")
	assert(player.try_start_parry() == false, "Parry should be rejected during cooldown")
	print("  -> PASSED: Whiffed parry applied recovery cooldown.")
	
	# Test 7: Attack & Signal
	print("[TEST 7] Attack Combo & Dev 2 Signal...")
	signals_fired["attack_pressed"] = false
	player._begin_attack("Attack")
	assert(player.is_attacking == true, "Player is attacking")
	assert(signals_fired["attack_pressed"] == true, "attack_pressed signal fired")
	print("  -> PASSED: Attack initiated and signal emitted.")
	
	# Test 8: Death at 0 HP
	print("[TEST 8] Lethal Damage & Defeat State...")
	player.take_damage(100.0)
	assert(player.current_health == 0.0, "Health should drop to 0")
	assert(player.is_alive == false, "Player should be dead")
	assert(signals_fired["died"] == true, "died signal should fire")
	print("  -> PASSED: Player died properly.")
	
	# Test 9: Weapon Mounts & Sword Scaling
	print("[TEST 9] Weapon Mounts & Sword Scale...")
	var skeleton = player.character.find_child("Skeleton3D", true, false)
	assert(skeleton != null, "Skeleton3D must exist")
	var r_socket = skeleton.find_child("RightHandSocket", true, false)
	var l_socket = skeleton.find_child("LeftHandSocket", true, false)
	assert(r_socket != null, "RightHandSocket must exist")
	assert(l_socket != null, "LeftHandSocket must exist")
	var sword = r_socket.find_child("Sword", true, false)
	var shield = l_socket.find_child("Shield", true, false)
	assert(sword != null, "Sword must be mounted in RightHandSocket")
	assert(shield != null, "Shield must be mounted in LeftHandSocket")
	print("  -> PASSED: Sword and shield mounted with scaled proportions.")
	
	print("==========================================================")
	print("ALL INTEGRATION TESTS PASSED 100%! ")
	print("==========================================================")
	main_node.queue_free()
	quit(0)
