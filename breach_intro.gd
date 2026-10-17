extends Node3D
## Short, skippable in-engine prologue. All gameplay and HUD state is restored.
signal finished
const FX := preload("res://combat_fx.gd")
const AUDIO := preload("res://breach_audio.gd")
const DECOY := preload("res://shadow_decoy.gd")
var player: CharacterBody3D
var world: Node3D
var elapsed := 0.0
var duration := 12.6
var impact_time := 3.2
var completed := false
var power_received := false
var dash_shown := false
var portal_started := false
var meteor_started := false
var arrivals_started := false
var arrivals: Array = []
var frozen: Array = []
var hidden_hud: Array = []
var hidden_world: Array = []
var origin := Vector3.ZERO
var original_rotation := Vector3.ZERO
var old_invulnerable := false
var old_animation_mode: int
var old_animation_speed := 1.0
var camera: Camera3D
var old_camera: WeakRef
var overlay: CanvasLayer
var fade: ColorRect
var flash: ColorRect
var title: Label
var skip_hint: Label
var environment_node: WorldEnvironment
var original_environment: Environment
var cinematic_environment: Environment
var sunlight: Array = []
var power_orb: MeshInstance3D
var power_particles: GPUParticles3D
var power_light: OmniLight3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	world.prepare_intro()
	origin = player.global_position
	original_rotation = player.character.rotation
	old_invulnerable = player.is_invulnerable
	player.is_invulnerable = true
	player.velocity = Vector3.ZERO
	old_animation_mode = player.animation_player.callback_mode_process
	old_animation_speed = player.animation_player.speed_scale
	player.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.animation_player.speed_scale = 1.0
	player.last_animation = ""
	player._play("Idle")
	player.animation_player.advance(0.0)
	for actor in [player, player.ultimate_controller, get_parent().get_node("EncounterDirector")]:
		frozen.append([weakref(actor), actor.process_mode])
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	var director := get_parent().get_node("EncounterDirector") as Node3D
	hidden_world.append([weakref(director), director.visible])
	director.hide()
	for label: Label3D in get_parent().get_node("CampusMap").find_children("*", "Label3D", true, false):
		hidden_world.append([weakref(label), label.visible])
		label.hide()
	for enemy in get_tree().get_nodes_in_group("enemy"):
		frozen.append([weakref(enemy), enemy.process_mode])
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	for hud in get_parent().find_children("*", "CanvasLayer", true, false):
		hidden_hud.append([weakref(hud), hud.visible])
		hud.hide()
	var active_camera := get_viewport().get_camera_3d()
	if active_camera != null:
		old_camera = weakref(active_camera)
	camera = Camera3D.new()
	camera.near = 0.08
	camera.far = 300.0
	camera.fov = 58.0
	add_child(camera)
	camera.make_current()
	_setup_lighting()
	_build_overlay()
	_build_power_effect()
	_update_timeline(0.0)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _setup_lighting() -> void:
	var campus := get_parent().get_node("CampusMap")
	for node: WorldEnvironment in campus.find_children("*", "WorldEnvironment", true, false):
		environment_node = node
		break
	if environment_node != null:
		original_environment = environment_node.environment
		cinematic_environment = original_environment.duplicate(true)
		environment_node.environment = cinematic_environment
		camera.environment = cinematic_environment
	for light: DirectionalLight3D in campus.find_children("*", "DirectionalLight3D", true, false):
		sunlight.append([weakref(light), light.light_color, light.light_energy])

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "IntroPresentation"
	overlay.layer = 35
	add_child(overlay)
	for bottom in [false, true]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
		if bottom:
			bar.offset_top = -58
		else:
			bar.offset_bottom = 58
		overlay.add_child(bar)
	flash = ColorRect.new()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 0.5, 0.12, 0)
	overlay.add_child(flash)
	fade = ColorRect.new()
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	overlay.add_child(fade)
	title = Label.new()
	title.text = "FAST:\nTHE SHADOW BREACH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.75, 0.48, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.3, 0.05, 0.65))
	title.add_theme_constant_override("shadow_outline_size", 6)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.modulate.a = 0
	overlay.add_child(title)
	skip_hint = Label.new()
	skip_hint.text = "SPACE / ESC — SKIP"
	skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_hint.position = Vector2(-230, -40)
	skip_hint.add_theme_font_size_override("font_size", 14)
	skip_hint.modulate = Color(0.8, 0.8, 0.85, 0.7)
	overlay.add_child(skip_hint)

func _build_power_effect() -> void:
	power_orb = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	power_orb.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(0.65, 0.12, 1.0)
	material.emission_energy_multiplier = 4.0
	material.albedo_color = Color(0.4, 0.05, 0.7)
	power_orb.material_override = material
	add_child(power_orb)
	power_orb.hide()
	power_particles = world._particles(self, Color(0.4, 0.1, 0.8), 48, 0.8, 1.3)
	power_particles.emitting = false
	power_light = world._light(self, Color(0.55, 0.1, 1), 0.0, 5.0)

func _process(delta: float) -> void:
	if completed:
		return
	elapsed += delta
	_update_timeline(delta)
	if elapsed >= duration:
		finish()

func _update_timeline(delta: float) -> void:
	var impact := world.impact_point as Vector3
	var gate_position := world.gate_point as Vector3
	if elapsed >= 1.2 and not meteor_started:
		meteor_started = true
		_play_sound("meteor", -8.0)
		world.meteor_trail.emitting = true
	var fall := pow(clampf((elapsed - 1.2) / (impact_time - 1.2), 0.0, 1.0), 1.45)
	world.meteor.position = (impact + Vector3(-18, 30, -20)).lerp(impact + Vector3.UP, fall)
	world.meteor.scale = Vector3.ONE
	world.meteor.rotation += Vector3(0.4, 0.8, 0.25) * delta
	if elapsed >= impact_time and not world.impact_started:
		world.strike()
		_play_sound("impact", -3.0)
	if elapsed >= 4.1 and not portal_started:
		portal_started = true
		world.gate.show()
		world.gate_motes.emitting = true
		_play_sound("portal", -8.0)
	world.gate.position = gate_position
	world.gate.scale = Vector3.ONE
	if elapsed >= 5.0 and not arrivals_started:
		_begin_portal_arrivals()
	_update_portal_arrivals(delta)
	if elapsed > 6.7:
		world.explosion.hide()
	var night := smoothstep(3.6, 6.8, elapsed)
	_update_lighting(night)
	if elapsed < 1.2:
		camera.position = impact + Vector3(-8, 17, 24).lerp(Vector3(-6, 14, 20), elapsed / 1.2)
		camera.look_at(impact + Vector3(3, 2, -2))
	elif elapsed < 4.1:
		camera.position = impact + Vector3(-12, 8, 17)
		camera.look_at((impact + Vector3.UP * 4).lerp(world.meteor.position, 0.6 * (1.0 - smoothstep(2.3, 3.2, elapsed))))
		if elapsed >= impact_time:
			var shake := exp(-(elapsed - impact_time) * 5) * 0.25
			camera.position += Vector3(sin(elapsed * 95), cos(elapsed * 110), 0) * shake
	elif elapsed < 7.2:
		var phase := smoothstep(4.1, 7.2, elapsed)
		camera.position = gate_position + Vector3(-10, 6.5, 16).lerp(Vector3(-6, 4.8, 12), phase)
		camera.look_at(gate_position + Vector3.UP * 3.3)
	else:
		camera.position = origin + Vector3(3, 2.0, -3.6).lerp(Vector3(2.6, 1.8, -3.0), smoothstep(7.2, 10.8, elapsed))
		camera.look_at(player.global_position + Vector3.UP * 1.15)
		var facing := gate_position - origin
		player.character.rotation.y = atan2(facing.x, facing.z)
	# The visible pulse travels FROM the portal TO the protagonist before any dash.
	power_orb.visible = elapsed >= 7.2 and elapsed < 7.85
	power_orb.position = (gate_position + Vector3.UP * 3.6).lerp(origin + Vector3.UP * 1.1, smoothstep(7.2, 7.85, elapsed))
	if elapsed >= 7.85 and not power_received:
		power_received = true
		_play_sound("shadow", -9.0)
		FX.burst(self, origin + Vector3.UP, Color(0.5, 0.15, 0.9), 45, 0.9)
		FX.ring(self, origin + Vector3.UP * 0.12, Color(0.5, 0.1, 0.9), 1.5)
		power_particles.emitting = true
	power_particles.position = player.global_position + Vector3.UP * 0.9
	power_light.position = player.global_position + Vector3.UP
	power_light.light_energy = 2.0 if elapsed >= 7.85 and elapsed < 10.5 else 0.0
	if elapsed >= 9.25 and not dash_shown:
		dash_shown = true
		var decoy := DECOY.new()
		decoy.source_character = player.character
		decoy.lifetime = 1.2
		add_child(decoy)
		decoy.global_position = origin
		decoy.global_rotation = player.character.global_rotation
		player.last_animation = ""
		player._play("Run")
		player.animation_player.speed_scale = 1.5
		_play_sound("shadow", -8.0)
	if dash_shown:
		player.global_position = origin + Vector3(-2.2, 0, -0.3) * smoothstep(9.25, 9.55, elapsed)
		if elapsed > 9.65:
			player.animation_player.speed_scale = 1.0
			player._play("Idle")
	player.animation_player.advance(delta)
	flash.color = Color(1.0, 0.53, 0.16, maxf(0.0, 1.0 - absf(elapsed - impact_time) / 0.16) * 0.72)
	if elapsed > 7.7:
		flash.color = Color(0.4, 0.1, 0.8, maxf(0.0, 1.0 - absf(elapsed - 7.85) / 0.16) * 0.25)
	fade.color.a = maxf(1.0 - smoothstep(0.0, 0.35, elapsed), smoothstep(10.7, 11.05, elapsed))
	title.modulate.a = smoothstep(11.0, 11.3, elapsed) * (1.0 - smoothstep(12.15, duration, elapsed))
	if elapsed >= 10.7:
		power_particles.emitting = false

func _update_lighting(night: float) -> void:
	for state in sunlight:
		var light: DirectionalLight3D = state[0].get_ref()
		if is_instance_valid(light):
			light.light_energy = lerpf(1.4, state[2], night)
			light.light_color = Color(1, 0.91, 0.76).lerp(state[1], night)
	if cinematic_environment == null:
		return
	cinematic_environment.ambient_light_color = Color(0.65, 0.75, 0.92).lerp(original_environment.ambient_light_color, night)
	cinematic_environment.ambient_light_energy = lerpf(0.75, original_environment.ambient_light_energy, night)
	cinematic_environment.fog_density = lerpf(0.0015, original_environment.fog_density, night)
	cinematic_environment.fog_light_color = Color(0.60, 0.72, 0.88).lerp(original_environment.fog_light_color, night)
	cinematic_environment.fog_sky_affect = lerpf(0.0, original_environment.fog_sky_affect, night)
	cinematic_environment.adjustment_saturation = lerpf(1.0, original_environment.adjustment_saturation, night)
	if cinematic_environment.sky != null and cinematic_environment.sky.sky_material is ProceduralSkyMaterial:
		var sky := cinematic_environment.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = Color(0.16, 0.42, 0.8).lerp(Color(0.004, 0.008, 0.022), night)
		sky.sky_horizon_color = Color(0.66, 0.78, 0.9).lerp(Color(0.032, 0.045, 0.067), night)
		sky.ground_horizon_color = Color(0.66, 0.78, 0.9).lerp(Color(0.025, 0.032, 0.045), night)
		sky.ground_bottom_color = Color(0.28, 0.31, 0.32).lerp(Color(0.003, 0.005, 0.009), night)


func _begin_portal_arrivals() -> void:
	arrivals_started = true
	var director := get_parent().get_node("EncounterDirector")
	# Use the actual first encounter, not disposable lookalikes followed by a
	# second wave popping into existence when gameplay resumes.
	if director.active or director.stage != 0:
		return
	var previous: Dictionary = {}
	for actor in get_tree().get_nodes_in_group("enemy"):
		previous[actor.get_instance_id()] = true
	director._start_encounter()
	for actor: CharacterBody3D in get_tree().get_nodes_in_group("enemy"):
		if previous.has(actor.get_instance_id()):
			continue
		var state := {
			"actor": weakref(actor), "destination": actor.global_position,
			"local_destination": actor.position,
			"mode": actor.process_mode, "layer": actor.collision_layer,
			"mask": actor.collision_mask, "start": 5.0 + arrivals.size() * 0.6,
			"meshes": [], "animators": [], "modifiers": [], "landed": false, "emerged": false,
		}
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.collision_layer = 0
		actor.collision_mask = 0
		actor.velocity = Vector3.ZERO
		actor.hide()
		for mesh: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
			state.meshes.append([weakref(mesh), mesh.transparency])
			mesh.transparency = 1.0
		for animator: AnimationPlayer in actor.find_children("*", "AnimationPlayer", true, false):
			state.animators.append([weakref(animator), animator.callback_mode_process, animator.speed_scale])
			animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			if animator.has_animation("Lesha_walk"):
				animator.play("Lesha_walk", 0.1)
				animator.speed_scale = 1.5
		for hud: CanvasLayer in actor.find_children("*", "CanvasLayer", true, false):
			hidden_hud.append([weakref(hud), hud.visible])
			hud.hide()
		for label: Label3D in actor.find_children("*", "Label3D", true, false):
			hidden_world.append([weakref(label), label.visible])
			label.hide()
		for modifier: SkeletonModifier3D in actor.find_children("*", "SkeletonModifier3D", true, false):
			if modifier.get_script() == preload("res://assets/enemies/mage/mage_pose.gd"):
				state.modifiers.append(weakref(modifier))
		arrivals.append(state)


func _update_portal_arrivals(delta: float) -> void:
	for i in arrivals.size():
		var state: Dictionary = arrivals[i]
		var actor: CharacterBody3D = state.actor.get_ref()
		if not is_instance_valid(actor):
			continue
		var age: float = elapsed - state.start
		if age < 0.0:
			continue
		actor.show()
		var side := -0.45 if i == 0 else 0.45
		var aperture: Vector3 = world.gate_point + Vector3(side, 2.0, -0.3)
		if not state.emerged:
			state.emerged = true
			FX.burst(self, aperture + Vector3.UP, Color(0.45, 0.1, 0.85), 24, 0.6)
			_play_sound("portal", -17.0)
		var apron: Vector3 = world.gate_point + Vector3(side, 0.15, 4.7)
		var edge := Vector3(40.0, world.gate_point.y + 0.1, -77.5 + i * 0.8)
		var destination: Vector3 = state.destination
		var heading := Vector3.BACK
		if age < 0.8:
			actor.global_position = aperture.lerp(apron, smoothstep(0.0, 0.8, age))
			heading = apron - aperture
		elif age < 1.6:
			actor.global_position = apron.lerp(edge, smoothstep(0.8, 1.6, age))
			heading = edge - apron
		elif age < 2.4:
			var drop := smoothstep(1.6, 2.4, age)
			actor.global_position = edge.lerp(destination, drop) + Vector3.UP * sin(drop * PI) * 0.8
			heading = destination - edge
		else:
			actor.global_position = destination
			heading = origin - destination
			if not state.landed:
				state.landed = true
				FX.burst(self, destination + Vector3.UP * 0.1, Color(0.32, 0.14, 0.48), 18, 0.7, true)
				for saved in state.animators:
					var animator: AnimationPlayer = saved[0].get_ref()
					if is_instance_valid(animator) and animator.has_animation("Lesha_idle"):
						animator.play("Lesha_idle", 0.18)
						animator.speed_scale = 1.0
		actor.rotation.y = lerp_angle(actor.rotation.y, atan2(heading.x, heading.z), minf(delta * 12.0, 1.0))
		for saved in state.meshes:
			var mesh: MeshInstance3D = saved[0].get_ref()
			if is_instance_valid(mesh):
				mesh.transparency = lerpf(1.0, saved[1], smoothstep(0.0, 0.25, age))
		for saved in state.animators:
			var animator: AnimationPlayer = saved[0].get_ref()
			if is_instance_valid(animator) and animator.is_playing():
				animator.advance(delta)
		# The mage uses its own procedural rig rather than a walking clip.
		for saved in state.modifiers:
			var modifier: SkeletonModifier3D = saved.get_ref()
			if is_instance_valid(modifier):
				modifier._process(delta)
				modifier._process_modification()


func _finish_portal_arrivals() -> void:
	for state in arrivals:
		var actor: CharacterBody3D = state.actor.get_ref()
		if not is_instance_valid(actor):
			continue
		# Local coordinates also work during scene teardown, when newly spawned
		# siblings can already have left the tree before this cinematic exits.
		actor.position = state.local_destination
		actor.velocity = Vector3.ZERO
		actor.collision_layer = state.layer
		actor.collision_mask = state.mask
		actor.attack_timer = maxf(actor.attack_timer, 0.9)
		actor.process_mode = state.mode
		actor.show()
		for saved in state.meshes:
			var mesh: MeshInstance3D = saved[0].get_ref()
			if is_instance_valid(mesh):
				mesh.transparency = saved[1]
		for saved in state.animators:
			var animator: AnimationPlayer = saved[0].get_ref()
			if is_instance_valid(animator):
				animator.callback_mode_process = saved[1]
				animator.speed_scale = saved[2]
				if animator.has_animation("Lesha_idle"):
					animator.play("Lesha_idle", 0.1)

func _play_sound(kind: String, volume: float) -> void:
	var sound := AudioStreamPlayer.new()
	sound.stream = AUDIO.cue(kind)
	sound.volume_db = volume
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func finish() -> void:
	if completed:
		return
	completed = true
	_restore()
	finished.emit()
	queue_free()

func _restore() -> void:
	_finish_portal_arrivals()
	if is_instance_valid(environment_node) and original_environment != null:
		environment_node.environment = original_environment
	for state in sunlight:
		var light: DirectionalLight3D = state[0].get_ref()
		if is_instance_valid(light):
			light.light_color = state[1]
			light.light_energy = state[2]
	for state in frozen:
		var actor: Node = state[0].get_ref()
		if is_instance_valid(actor):
			actor.process_mode = state[1]
	for state in hidden_hud:
		var hud: CanvasLayer = state[0].get_ref()
		if is_instance_valid(hud):
			hud.visible = state[1]
	for state in hidden_world:
		var item: Node3D = state[0].get_ref()
		if is_instance_valid(item):
			item.visible = state[1]
	if is_instance_valid(player):
		player.global_position = origin
		player.velocity = Vector3.ZERO
		player.character.rotation = original_rotation
		player.is_invulnerable = old_invulnerable
		player.animation_player.callback_mode_process = old_animation_mode
		player.animation_player.speed_scale = old_animation_speed
		player.last_animation = ""
		player._play("Idle")
		player.motion_fx_last_position = origin
		player.jump_requested = false
		player.jump_buffer_remaining = 0.0
		player.dash_buffer_remaining = 0.0
		player.jump_key_was_down = Input.is_key_pressed(KEY_SPACE)
		player.suppress_jump_until_release = Input.is_key_pressed(KEY_SPACE) or Input.is_action_pressed("jump")
		player.attack_mouse_was_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		player.attack_requested = false
		player.camera.make_current()
	elif old_camera != null and is_instance_valid(old_camera.get_ref()):
		old_camera.get_ref().make_current()
	if is_instance_valid(world):
		world.show_aftermath()

func _exit_tree() -> void:
	if not completed:
		_restore()
