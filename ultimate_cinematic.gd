extends Node3D
## A bounded real-time cinematic: gameplay actors freeze, while menu pause
## still pauses this timeline. No global time-scale changes or deferred damage.
const FX := preload("res://combat_fx.gd")
const EXPLOSION := preload("res://fireball_explosion.gd")
const WAVE := preload("res://ultimate_flame_wave.gd")
signal finished(kind: String)
var controller: Node
var player: CharacterBody3D
var kind := "area"
var target: WeakRef
var elapsed := 0.0
var impact_time := 1.3
var duration := 2.8
var impact_applied := false
var release_started := false
var completed := false
var hit_targets: Dictionary = {}
var frozen: Array = []
var hidden_hud: Array = []
var original_camera: WeakRef
var original_invulnerable := false
var cinematic_camera: Camera3D
var overlay: CanvasLayer
var top_bar: ColorRect
var bottom_bar: ColorRect
var title: Label
var subtitle: Label
var flash: ColorRect
var forward := Vector3.FORWARD
var side := Vector3.RIGHT
var origin := Vector3.ZERO
var victim_point := Vector3.ZERO
var pulse_clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	name = "UltimateCinematic"
	origin = player.global_position
	forward = player.character.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	side = forward.cross(Vector3.UP).normalized()
	victim_point = origin + forward * 8.0 + Vector3.UP
	if target != null and is_instance_valid(target.get_ref()):
		victim_point = target.get_ref().global_position + Vector3.UP
	original_invulnerable = player.is_invulnerable
	player.is_invulnerable = true
	player.ultimate_charging = true
	player.animation_player.speed_scale = 1.0
	player.last_animation = ""
	player._play("Block")
	player._set_sword_guard_pose(true)
	_freeze_gameplay()
	var active_camera := get_viewport().get_camera_3d()
	if active_camera != null:
		original_camera = weakref(active_camera)
	cinematic_camera = Camera3D.new()
	cinematic_camera.near = 0.05
	cinematic_camera.far = 500.0
	cinematic_camera.fov = 50.0
	add_child(cinematic_camera)
	cinematic_camera.global_position = _safe_camera(origin + Vector3.UP * 1.4, origin + forward * 3.8 + side * 1.2 + Vector3.UP * 1.8)
	cinematic_camera.look_at(origin + Vector3.UP * 1.4)
	cinematic_camera.make_current()
	_build_overlay()
	player._update_fire_blade_effect()

func _freeze_gameplay() -> void:
	for group in ["enemy", "mage_projectile", "combat_projectile", "shadow_decoy"]:
		for actor in get_tree().get_nodes_in_group(group):
			frozen.append([weakref(actor), actor.process_mode])
			actor.process_mode = Node.PROCESS_MODE_DISABLED
	var director := get_tree().current_scene.get_node_or_null("EncounterDirector")
	if director != null:
		frozen.append([weakref(director), director.process_mode])
		director.process_mode = Node.PROCESS_MODE_DISABLED
		for child in director.get_children():
			if child is CanvasLayer:
				hidden_hud.append([weakref(child), child.visible])
				child.hide()
	var combat_hud := player.get_node_or_null("CombatFeedbackLayer") as CanvasLayer
	if combat_hud != null:
		hidden_hud.append([weakref(combat_hud), combat_hud.visible])
		combat_hud.hide()

func _process(delta: float) -> void:
	if completed:
		return
	if not is_instance_valid(player) or not player.is_alive:
		_finish()
		return
	elapsed += delta
	player.camera_trauma = maxf(player.camera_trauma - delta * 1.3, 0.0)
	player.ultimate_power = smoothstep(0.0, impact_time, elapsed) if elapsed < impact_time else maxf(1.0 - (elapsed - impact_time) / 0.7, 0.0)
	player.velocity = Vector3.ZERO
	_update_camera(delta)
	var fade := minf(clampf(elapsed / 0.18, 0.0, 1.0), clampf((duration - elapsed) / 0.35, 0.0, 1.0))
	top_bar.modulate.a = fade
	bottom_bar.modulate.a = fade
	if elapsed < impact_time:
		pulse_clock += delta
		if pulse_clock > 0.3:
			pulse_clock = 0.0
			FX.ring(get_tree().current_scene, origin + Vector3.UP * 0.08, Color(1, 0.48, 0.05, 0.7), 0.8 + player.ultimate_power * 1.3)
	if not release_started and elapsed >= impact_time - 0.26:
		release_started = true
		player.ultimate_charging = false
		player.sword_guard_pose.play_release()
	if not impact_applied and elapsed >= impact_time:
		_apply_impact()
	if elapsed >= duration:
		_finish()

func _update_camera(delta: float) -> void:
	var windup := smoothstep(0.0, impact_time, elapsed)
	var focus := origin + Vector3.UP * 1.4
	var desired := origin + forward * lerpf(3.8, 3.4, windup) + side * lerpf(1.2, -0.4, windup) + Vector3.UP * 1.8
	var fov := lerpf(50.0, 44.0, windup)
	if elapsed >= impact_time - 0.25:
		# Orbit around the actor before release; a straight front-to-back
		# interpolation passes through the character and the outgoing beam.
		var reveal := smoothstep(impact_time - 0.25, impact_time + 0.25, elapsed)
		var orbit_angle := lerpf(-0.12, 2.4, reveal)
		var orbit_radius := lerpf(3.4, 8.0, reveal)
		var height := lerpf(0.4, 5.0, reveal)
		if kind == "focused":
			focus = focus.lerp((origin + Vector3.UP + victim_point) * 0.5, reveal)
			orbit_angle = lerpf(-0.12, 1.4, reveal)
			orbit_radius = lerpf(3.4, maxf(6.0, origin.distance_to(victim_point) * 0.75), reveal)
			height = lerpf(0.4, 2.6, reveal)
		desired = focus + (forward * cos(orbit_angle) + side * sin(orbit_angle)) * orbit_radius + Vector3.UP * height
		fov = lerpf(44.0, 76.0 if kind == "area" else 68.0, reveal)
	var original: Camera3D = original_camera.get_ref() if original_camera != null else null
	if is_instance_valid(original) and elapsed > duration - 0.55:
		var recover := smoothstep(duration - 0.55, duration, elapsed)
		desired = desired.lerp(original.global_position, recover)
		var return_focus := original.global_position - original.global_basis.z * 6.0
		focus = focus.lerp(return_focus, recover)
		fov = lerpf(fov, original.fov, recover)
	desired = _safe_camera(focus, desired)
	cinematic_camera.global_position = cinematic_camera.global_position.lerp(desired, 1.0 - exp(-delta * 15.0))
	if cinematic_camera.global_position.distance_squared_to(focus) > 0.001:
		cinematic_camera.look_at(focus)
	cinematic_camera.fov = fov
	if elapsed >= impact_time and elapsed < impact_time + 0.45:
		var shake := (1.0 - (elapsed - impact_time) / 0.45) * 0.055
		cinematic_camera.global_position += side * sin(elapsed * 82.0) * shake + Vector3.UP * cos(elapsed * 93.0) * shake

func _safe_camera(focus: Vector3, desired: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(focus, desired, 1)
	var collision := player.get_world_3d().direct_space_state.intersect_ray(query)
	return collision.position + collision.normal * 0.18 if not collision.is_empty() else desired

func _apply_impact() -> void:
	if impact_applied:
		return
	impact_applied = true
	player.ultimate_charging = false
	player._add_camera_trauma(0.8)
	flash.color = Color(1, 0.7, 0.3, 0.28)
	var fade := create_tween()
	fade.tween_property(flash, "color:a", 0.0, 0.18)
	if kind == "area":
		_area_impact()
	else:
		_focused_impact()
	subtitle.text = "%d SHADOWS STRUCK" % hit_targets.size() if kind == "area" else "ONE BLADE. ONE VERDICT."

func _area_impact() -> void:
	var blast := EXPLOSION.new()
	blast.radius = controller.area_radius
	blast.position = origin + Vector3.UP * 0.55
	get_tree().current_scene.add_child(blast)
	var wave := WAVE.new()
	wave.position = origin + Vector3.UP * 0.06
	wave.radius = controller.area_radius
	get_tree().current_scene.add_child(wave)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or not enemy is Node3D or enemy.get("is_dead") == true:
			continue
		var distance: float = enemy.global_position.distance_to(origin)
		if distance > controller.area_radius or not controller.has_clear_path(enemy):
			continue
		hit_targets[enemy.get_instance_id()] = true
		var falloff := lerpf(1.0, 0.7, clampf(distance / controller.area_radius, 0.0, 1.0))
		enemy.take_damage(controller.area_damage * falloff, player)
		if enemy.get("is_dead") != true:
			if enemy.has_method("apply_burn"):
				enemy.apply_burn(4.0, 12.0, 1.0, player)
			if enemy.has_method("apply_stun"):
				enemy.apply_stun(1.2)

func _focused_impact() -> void:
	var victim: Node3D = target.get_ref() if target != null else null
	_beam(origin + Vector3.UP * 1.3, victim_point)
	var blast := EXPLOSION.new()
	blast.radius = 2.0
	blast.position = victim_point
	get_tree().current_scene.add_child(blast)
	if is_instance_valid(victim) and victim.get("is_dead") != true and controller.has_clear_path(victim):
		hit_targets[victim.get_instance_id()] = true
		victim.take_damage(controller.focused_damage, player)
		if victim.get("is_dead") != true:
			if victim.has_method("apply_stun"):
				victim.apply_stun(1.8)
			if victim.has_method("apply_burn"):
				victim.apply_burn(3.0, 10.0, 1.0, player)

func _beam(start: Vector3, end: Vector3) -> void:
	var beam := MeshInstance3D.new()
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.22
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 24
	beam.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.9, 0.6)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.58, 0.15)
	material.emission_energy_multiplier = 6.0
	beam.material_override = material
	get_tree().current_scene.add_child(beam)
	beam.global_position = (start + end) * 0.5
	beam.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	var tween := beam.create_tween().set_parallel(true)
	tween.tween_property(beam, "scale", Vector3(0.02, 1, 0.02), 0.55).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.55)
	tween.chain().tween_callback(beam.queue_free)
	FX.burst(get_tree().current_scene, end, Color(1.0, 0.85, 0.35), 100, 1.8)

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 12 # Pause/menu artwork stays above the cinematic.
	add_child(overlay)
	flash = ColorRect.new()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 0.6, 0.2, 0)
	overlay.add_child(flash)
	top_bar = ColorRect.new()
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 52.0
	top_bar.color = Color(0.005, 0.003, 0.01, 0.96)
	overlay.add_child(top_bar)
	bottom_bar = ColorRect.new()
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -100.0
	bottom_bar.color = Color(0.005, 0.003, 0.01, 0.96)
	overlay.add_child(bottom_bar)
	title = Label.new()
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 10
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "INFERNO" if kind == "area" else "ASH EXECUTION"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.77, 0.35))
	bottom_bar.add_child(title)
	subtitle = Label.new()
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	subtitle.position.y = 52
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.text = "LET THE SHADOWS BURN" if kind == "area" else "THE FLAME PASSES JUDGMENT"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.74, 0.65))
	bottom_bar.add_child(subtitle)

func _finish() -> void:
	if completed:
		return
	completed = true
	_restore()
	finished.emit(kind)
	queue_free()

func _restore() -> void:
	for entry in frozen:
		var actor: Node = entry[0].get_ref()
		if is_instance_valid(actor) and not actor.is_queued_for_deletion():
			actor.process_mode = entry[1]
	frozen.clear()
	for entry in hidden_hud:
		var canvas: CanvasLayer = entry[0].get_ref()
		if is_instance_valid(canvas):
			canvas.visible = entry[1]
	hidden_hud.clear()
	if is_instance_valid(player):
		player.is_using_ultimate = false
		player.ultimate_power = 0.0
		player.ultimate_charging = false
		player.ultimate_kind = ""
		player.is_invulnerable = original_invulnerable
		player._set_sword_guard_pose(false)
		if player.is_alive:
			player.last_animation = ""
			player._play("Idle")
		player._update_fire_blade_effect()
	var camera: Camera3D = original_camera.get_ref() if original_camera != null else null
	if is_instance_valid(camera) and camera.is_inside_tree():
		camera.make_current()

func _exit_tree() -> void:
	# Reloading or removing the cinematic cannot leave enemies or controls locked.
	if not completed:
		_restore()
