extends SceneTree
var failures := 0

func _initialize() -> void:
	create_timer(25, true).timeout.connect(func(): push_error("Sword audio test timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var main := load("res://main.tscn").instantiate() as Node3D
	var player := main.get_node("Player") as CharacterBody3D
	main.remove_child(player)
	main.free()
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var sound: AudioStreamPlayer = player.sword_swing_sound
	check(sound.stream.resource_path == "res://assets/audio/sword_attack.wav" and sound.stream.get_length() > 0.25, "Supplied WAV is imported and assigned to the player")
	check(sound.bus == &"Master" and sound.max_polyphony == 3, "Sword audio uses the options volume and allows short overlapping tails")
	player.fire_meter = 0.0
	player._begin_attack("Attack")
	player._update_sword_audio()
	check(player.attack_phase_sound == 0 and not sound.playing, "Attack windup does not play the swish prematurely")
	var phase_duration: float = player._attack_combo_phase_duration()
	for phase in range(1, 4):
		player.animation_player.seek(phase_duration * (float(phase - 1) + 0.3), true)
		player._update_sword_audio()
		check(sound.playing and player.attack_phase_sound == phase, "Actual swing %d plays its sound even with no fire or enemy" % phase)
		await create_timer(0.05).timeout
		var old_position := sound.get_playback_position()
		player._update_sword_audio()
		check(player.attack_phase_sound == phase and sound.get_playback_position() >= old_position, "Swing %d cannot restart the sound every physics tick" % phase)
		if phase < 3:
			player._advance_attack_combo()
			check(player.attack_phase_sound == phase, "Buffering the next click does not fire another sound")
			player.animation_player.seek(phase_duration * phase - player.attack_combo_transition_lead + 0.01, true)
			player._update_attack_combo(0)
			player._update_sword_audio()
			check(player.attack_combo_phase == phase + 1 and player.attack_phase_sound == phase, "Next phase waits for its own authored swing cue")
	player._finish_attack("Attack")
	sound.stop()
	player._update_sword_audio()
	check(not sound.playing and player.attack_phase_sound == 0, "Idle/cancelled attacks cannot emit stale combo sounds")
	player._begin_attack("JumpAttack")
	check(sound.playing, "Airborne sword attack also plays the supplied sound")
	for audio in scene.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	await create_timer(0.15).timeout
	current_scene = null
	scene.queue_free()
	await process_frame
	await process_frame
	print("Sword audio checks complete, failures=", failures)
	quit(1 if failures else 0)
