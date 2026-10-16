extends SceneTree

func _init() -> void:
	print("========================================")
	print("--- RUNNING DEV 1 UNIT & COMBAT TESTS ---")
	print("========================================")
	
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	assert(player_scene != null, "Player scene failed to load!")
	
	var player: Player = player_scene.instantiate() as Player
	assert(player != null, "Player instantiation failed!")
	root.add_child(player)
	
	# Wait one frame for _ready
	await process_frame
	
	var results := {
		"damaged": false,
		"health_changed": false,
		"perfect_parry": false,
		"normal_parry": false,
		"parry_failed": false,
		"dash_started": false,
		"evaded": false,
		"died": false
	}
	
	player.damaged.connect(func(_amt, _atk): results["damaged"] = true)
	player.health_changed.connect(func(_c, _m): results["health_changed"] = true)
	player.damage_evaded.connect(func(_amt, _atk): results["evaded"] = true)
	player.parry_failed.connect(func(): results["parry_failed"] = true)
	player.dash_started.connect(func(_dir): results["dash_started"] = true)
	player.died.connect(func(): results["died"] = true)
	player.parry_success.connect(func(_atk, is_perfect, _data):
		if is_perfect:
			results["perfect_parry"] = true
		else:
			results["normal_parry"] = true
	)
	
	# Test 1: Initial Health
	print("[TEST 1] Checking initial health...")
	assert(player.current_health == 100.0, "Expected health 100, got %f" % player.current_health)
	assert(player.is_alive == true, "Player should be alive")
	print("  -> PASSED: Health is 100 and player is alive.")

	# Test 2: Normal Damage Reception
	print("[TEST 2] Testing normal damage reception...")
	var took_damage := player.take_damage(25.0)
	assert(took_damage == true, "take_damage should return true when hit normally")
	assert(player.current_health == 75.0, "Expected health 75, got %f" % player.current_health)
	assert(results["damaged"] == true, "damaged signal should have fired")
	assert(results["health_changed"] == true, "health_changed signal should have fired")
	print("  -> PASSED: Took 25 damage, current health 75.")

	# Test 3: Perfect Parry Detection
	print("[TEST 3] Testing Perfect Parry detection...")
	var started := player.try_start_parry()
	assert(started == true, "Parry should start")
	assert(player.is_parrying == true, "Player should be in parrying state")
	
	# Strike immediately while within perfect parry window (0.12s)
	var parry_result := player.take_damage(30.0)
	assert(parry_result == false, "take_damage should return false when parried")
	assert(player.current_health == 75.0, "Health should not decrease on parry")
	assert(results["perfect_parry"] == true, "Perfect parry signal must be emitted")
	assert(player.is_parrying == false, "Parry state should reset after successful parry")
	print("  -> PASSED: Perfect parry absorbed attack without damage and emitted signal.")

	# Test 3b: Normal Parry Detection (after 0.12s)
	print("[TEST 3b] Testing Normal Parry detection...")
	player.parry_cooldown_timer = 0.0
	player.try_start_parry()
	player.parry_timer = 0.20 # Past perfect parry window (0.12), within normal window (0.35)
	results["normal_parry"] = false
	var norm_parry_result := player.take_damage(20.0)
	assert(norm_parry_result == false, "take_damage should return false on normal parry")
	assert(player.current_health == 75.0, "Health should not decrease on normal parry")
	assert(results["normal_parry"] == true, "normal parry signal must be emitted")
	print("  -> PASSED: Normal parry absorbed attack without damage and emitted signal.")

	# Test 4: Shadow Dash & Invulnerability
	print("[TEST 4] Testing Shadow Dash and Invulnerability...")
	var dash_success := player.try_start_dash()
	assert(dash_success == true, "Dash should start successfully")
	assert(player.is_dashing == true, "is_dashing should be true")
	assert(player.is_invulnerable == true, "is_invulnerable should be true during dash")
	assert(results["dash_started"] == true, "dash_started signal should have fired")
	
	# Attack player while dashing
	var dash_hit_result := player.take_damage(40.0)
	assert(dash_hit_result == false, "take_damage should return false while invulnerable")
	assert(player.current_health == 75.0, "No damage should be taken during dash")
	assert(results["evaded"] == true, "damage_evaded signal must be emitted")
	print("  -> PASSED: Shadow dash evaded incoming strike cleanly.")

	# Test 5: Whiffed Parry & Cooldown Penalty
	print("[TEST 5] Testing Whiffed Parry and recovery cooldown...")
	# Simulate dash ending
	player._end_dash()
	assert(player.is_dashing == false, "Dash should be ended")
	
	# Force cooldown to 0 to test clean parry whiff
	player.parry_cooldown_timer = 0.0
	player.try_start_parry()
	assert(player.is_parrying == true, "Parry started")
	
	# Simulate passing the parry window without any attack
	player._update_timers(player.parry_window + 0.01)
	assert(player.is_parrying == false, "Parry should end after window expires")
	assert(results["parry_failed"] == true, "parry_failed signal should be emitted on whiff")
	assert(player.parry_cooldown_timer > 0.0, "Parry cooldown must be active after whiff")
	
	# Attempting to parry immediately during cooldown should fail
	var spam_parry := player.try_start_parry()
	assert(spam_parry == false, "Parry should be rejected during recovery cooldown")
	print("  -> PASSED: Missed parry triggered whiff penalty and cooldown protection.")

	# Test 6: Lethal Damage & Death
	print("[TEST 6] Testing lethal damage...")
	player.current_health = 10.0
	player.take_damage(20.0)
	assert(player.current_health == 0.0, "Health should drop to 0")
	assert(player.is_alive == false, "Player should be dead")
	assert(results["died"] == true, "died signal should have fired")
	print("  -> PASSED: Player died properly when health reached 0.")

	# Test 7: Placeholder Attack Combo & Signal
	print("[TEST 7] Testing Attack Combo and signal emission...")
	# Revive player for attack test
	player.is_alive = true
	results["attack_pressed"] = false
	player.attack_pressed.connect(func(): results["attack_pressed"] = true)
	var attacked := player.try_start_attack()
	assert(attacked == true, "try_start_attack should succeed")
	assert(player.is_attacking == true, "player.is_attacking should be true")
	assert(results["attack_pressed"] == true, "attack_pressed signal should be emitted for Dev 2")
	print("  -> PASSED: Attack combo started, animation triggered, and signal emitted.")

	print("========================================")
	print("ALL DEV 1 TESTS PASSED SUCCESSFULLY! ")
	print("========================================")
	
	player.queue_free()
	quit(0)
