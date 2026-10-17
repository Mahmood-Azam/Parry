extends Node3D
## Owns Soul Steal's temporary time dilation and camera, including cleanup.

const SLOW_SCALE := 0.42
const RAMP_IN_SECONDS := 0.18
const RAMP_OUT_SECONDS := 0.38

var player: Node3D
var shadow: Node3D
var target: Node3D
var gameplay_camera: Camera3D
var cinematic_camera: Camera3D
var original_time_scale := 1.0
var applied_time_scale := 1.0
var elapsed_real := 0.0
var ending_real := -1.0
var strike_impulse := 0.0
var view_direction := Vector3(0.0, 0.35, 1.0)
var camera_probe := SphereShape3D.new()


func begin(caster: Node3D, decoy: Node3D) -> void:
	player = caster
	shadow = decoy
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera_probe.radius = 0.28
	original_time_scale = Engine.time_scale
	applied_time_scale = original_time_scale
	shadow.soul_target_started.connect(_on_target_started)
	shadow.soul_struck.connect(_on_soul_struck)
	shadow.soul_finished.connect(_on_soul_finished)
	gameplay_camera = caster.get("camera") as Camera3D
	if is_instance_valid(gameplay_camera) and get_viewport().get_camera_3d() == gameplay_camera:
		view_direction = (gameplay_camera.global_position - player.global_position).normalized()
		cinematic_camera = Camera3D.new()
		cinematic_camera.name = "SoulStealCamera"
		cinematic_camera.fov = gameplay_camera.fov
		cinematic_camera.near = gameplay_camera.near
		cinematic_camera.far = gameplay_camera.far
		add_child(cinematic_camera)
		cinematic_camera.global_transform = gameplay_camera.global_transform
		cinematic_camera.make_current()


func _process(delta: float) -> void:
	if get_tree().paused or not is_instance_valid(player) or player.get("is_alive") == false:
		finish_now()
		return
	var real_delta := minf(delta / maxf(Engine.time_scale, 0.01), 0.1)
	strike_impulse = move_toward(strike_impulse, 0.0, real_delta * 3.8)
	if ending_real < 0.0 and not is_instance_valid(shadow):
		ending_real = 0.0
	if ending_real >= 0.0:
		ending_real += real_delta
		var return_weight := clampf(ending_real / RAMP_OUT_SECONDS, 0.0, 1.0)
		_apply_time_scale(lerpf(SLOW_SCALE, original_time_scale, return_weight * return_weight * (3.0 - 2.0 * return_weight)))
		if ending_real >= RAMP_OUT_SECONDS:
			finish_now()
		return
	elapsed_real += real_delta
	var entry_weight := clampf(elapsed_real / RAMP_IN_SECONDS, 0.0, 1.0)
	_apply_time_scale(lerpf(original_time_scale, SLOW_SCALE, entry_weight * entry_weight * (3.0 - 2.0 * entry_weight)))


func _physics_process(delta: float) -> void:
	if get_tree().paused or not is_instance_valid(cinematic_camera) or not is_instance_valid(player):
		return
	var real_delta := minf(delta / maxf(Engine.time_scale, 0.01), 0.1)
	if ending_real >= 0.0:
		_update_return_camera(real_delta)
	else:
		_update_strike_camera(real_delta)


func _update_strike_camera(real_delta: float) -> void:
	if not is_instance_valid(cinematic_camera) or not is_instance_valid(shadow):
		return
	var focus := shadow.global_position + Vector3.UP * 1.15
	var separation := 0.0
	var side := Vector3.ZERO
	if is_instance_valid(target):
		var travel := target.global_position - shadow.global_position
		separation = travel.length()
		focus = focus.lerp(target.global_position + Vector3.UP * 1.15, 0.36)
		if travel.length_squared() > 0.01:
			side = travel.normalized().cross(Vector3.UP) * 0.7
	var desired_position := focus + view_direction * clampf(5.3 + separation * 0.22, 5.3, 7.7) + side
	desired_position.y = maxf(desired_position.y, focus.y + 1.25)
	var follow_weight := 1.0 - exp(-7.5 * real_delta)
	var next_position := cinematic_camera.global_position.lerp(desired_position, follow_weight)
	cinematic_camera.global_position = _resolve_camera_collision(focus, next_position)
	var look_direction := focus - cinematic_camera.global_position
	if look_direction.length_squared() > 0.01:
		var desired_basis := Basis.looking_at(look_direction.normalized(), Vector3.UP)
		cinematic_camera.global_basis = cinematic_camera.global_basis.slerp(desired_basis, 1.0 - exp(-9.0 * real_delta))
	var safe_distance := cinematic_camera.global_position.distance_to(focus)
	var close_fov := clampf((4.2 - safe_distance) * 2.5, 0.0, 10.0)
	cinematic_camera.fov = lerpf(cinematic_camera.fov, 53.0 + close_fov + strike_impulse * 2.4, 1.0 - exp(-8.0 * real_delta))
	cinematic_camera.h_offset = sin(elapsed_real * 27.0) * strike_impulse * 0.045
	cinematic_camera.v_offset = cos(elapsed_real * 31.0) * strike_impulse * 0.03


func _update_return_camera(real_delta: float) -> void:
	if not is_instance_valid(cinematic_camera) or not is_instance_valid(gameplay_camera):
		return
	var weight := 1.0 - exp(-10.0 * real_delta)
	var focus := player.global_position + Vector3.UP * 1.15
	var next_position := cinematic_camera.global_position.lerp(gameplay_camera.global_position, weight)
	cinematic_camera.global_position = _resolve_camera_collision(focus, next_position)
	cinematic_camera.global_basis = cinematic_camera.global_basis.slerp(gameplay_camera.global_basis, weight)
	cinematic_camera.fov = lerpf(cinematic_camera.fov, gameplay_camera.fov, weight)
	cinematic_camera.h_offset = move_toward(cinematic_camera.h_offset, 0.0, real_delta * 0.3)
	cinematic_camera.v_offset = move_toward(cinematic_camera.v_offset, 0.0, real_delta * 0.3)


func _resolve_camera_collision(focus: Vector3, candidate: Vector3) -> Vector3:
	var motion := candidate - focus
	if motion.length_squared() < 0.001:
		return candidate
	var exclusions: Array[RID] = []
	if player is CollisionObject3D:
		exclusions.append((player as CollisionObject3D).get_rid())
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = camera_probe
	query.transform = Transform3D(Basis.IDENTITY, focus)
	query.motion = motion
	query.collision_mask = 1
	query.exclude = exclusions
	var space := get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)
	var safe_fraction := 1.0
	if fractions.size() > 0:
		safe_fraction = minf(safe_fraction, fractions[0])
	var ray := PhysicsRayQueryParameters3D.create(focus, candidate, 1, exclusions)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		safe_fraction = minf(safe_fraction, focus.distance_to(hit.position) / motion.length())
	return focus + motion * maxf(0.0, safe_fraction - 0.035)


func _on_target_started(next_target: Node3D) -> void:
	target = next_target


func _on_soul_struck(_victim: Node3D, accepted: bool) -> void:
	if accepted:
		strike_impulse = 1.0


func _on_soul_finished() -> void:
	if ending_real < 0.0:
		ending_real = 0.0
		target = null


func _apply_time_scale(value: float) -> void:
	var pause := get_tree().current_scene.get_node_or_null("CombatHitPause") if is_instance_valid(get_tree().current_scene) else null
	if pause != null and pause.remaining_until > 0:
		pause.previous_scale = value
	elif is_equal_approx(Engine.time_scale, applied_time_scale):
		Engine.time_scale = value
	applied_time_scale = value


func finish_now() -> void:
	var pause := get_tree().current_scene.get_node_or_null("CombatHitPause") if is_instance_valid(get_tree().current_scene) else null
	if pause != null and pause.remaining_until > 0:
		pause.previous_scale = original_time_scale
	if is_equal_approx(Engine.time_scale, applied_time_scale):
		Engine.time_scale = original_time_scale
	if is_instance_valid(cinematic_camera) and is_instance_valid(gameplay_camera) and get_viewport().get_camera_3d() == cinematic_camera:
		gameplay_camera.make_current()
	queue_free()


func _exit_tree() -> void:
	if is_equal_approx(Engine.time_scale, applied_time_scale):
		Engine.time_scale = original_time_scale
	if is_instance_valid(cinematic_camera) and is_instance_valid(gameplay_camera) and get_viewport().get_camera_3d() == cinematic_camera:
		gameplay_camera.make_current()
