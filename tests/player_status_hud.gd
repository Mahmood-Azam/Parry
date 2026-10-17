extends SceneTree
var failures := 0

func _initialize() -> void:
	create_timer(35, true).timeout.connect(func(): push_error("Status HUD test timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/status_hud_" + label + ".png")

func run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	scene._continue_game()
	var player: CharacterBody3D = scene.get_node("Player")
	for i in 20:
		await physics_frame
	player.set_physics_process(false)
	player.set_process_input(false)
	var hud: Panel = player.status_hud
	player.current_health = 73
	player.fire_meter = 150
	player._update_combat_stats()
	await process_frame
	check(hud.health_label.text == "HEALTH:  73 / 100", "Health label displays current and maximum HP")
	check(hud.fire_label.text == "FIRE METER:  150 / 200", "Fire label displays the complete shared reserve")
	check(hud.ultimate_label.text == "ULTIMATE: 75%", "Ultimate progress reflects that same reserve")
	check(hud.fire_bar.value == 100 and hud.fire_bar.overflow.value == 50, "Layered orange/violet track is unchanged")
	check(hud.health_label.self_modulate.a == 1 and hud.dash_label.self_modulate.a == 1, "Gameplay text policy permits only the intended status panel")
	check(player.try_start_dash(), "Ready dash starts normally")
	player._update_combat_stats()
	check(is_equal_approx(player.dash_cooldown_timer, 1.25) and not player.try_start_dash(), "Dash has a real 1.25-second repeat lock")
	check(not "READY" in hud.dash_label.text and hud.dash_bar.value == 0, "HUD immediately shows dash cooldown and an empty recharge gauge")
	var decoy: Node = get_nodes_in_group("shadow_decoy").back()
	check(is_equal_approx(decoy.lifetime, 1.0), "Decoy duration is shorter than the recharge, preventing continuous distraction")
	player._update_timers(0.17)
	check(not player.is_invulnerable and player.is_dashing, "Invulnerability ends at 0.16 seconds while dash traversal continues")
	player._end_dash()
	player._update_timers(0.9)
	check(not player.try_start_dash(), "The player cannot immediately repeat dash after movement ends")
	player._update_combat_stats()
	await capture("recovering")
	player._update_timers(0.2)
	player._update_combat_stats()
	check("READY" in hud.dash_label.text and is_equal_approx(hud.dash_bar.value, 1), "HUD changes back to ready when recharge completes")
	player.fire_meter = 200
	player._update_combat_stats()
	check("ULTIMATE READY" in hud.ultimate_label.text, "Full shared meter shows ultimate readiness and bindings")
	player.is_fire_channeling = true
	player.fire_channel_charge = 50
	player._update_combat_stats()
	check("SLASH CHARGE: 50%" in hud.ultimate_label.text, "Charging shows concise release feedback instead of extra HUD clutter")
	player.is_fire_channeling = false
	player.blocking = true
	player._update_combat_stats()
	check("BLOCKING" in hud.parry_label.text, "Guard status distinguishes blocking from parrying")
	player.blocking = false
	player.fire_meter = 150
	player._update_combat_stats()
	await capture("ready")
	player.dash_cooldown_timer = 0.7
	player.set_physics_process(true)
	scene._show_options()
	var controls := scene.options_panel.find_child("ControlsReference", true, false) as Label
	check(paused and controls.self_modulate.a == 1, "Options stays readable and pauses cooldowns")
	var saved: float = player.dash_cooldown_timer
	await create_timer(0.15, true).timeout
	check(player.dash_cooldown_timer == saved, "Cooldown cannot recharge while paused")
	scene._continue_game()
	await create_timer(0.2).timeout
	check(player.dash_cooldown_timer < saved, "Cooldown resumes counting down with gameplay")
	print("Status HUD/balance checks complete, failures=", failures)
	quit(1 if failures else 0)
