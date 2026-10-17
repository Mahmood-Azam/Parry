extends "res://assets/enemies/skeleton/skeleton_enemy.gd"

const CLIP_FOLDER := "res://assets/enemies/Mutant/Creature Pack/"
const CLIPS := {
	"Idle": "mutant breathing idle.fbx",
	"Walk": "mutant walking.fbx",
	"Flex": "mutant flexing muscles.fbx",
	"Punch": "mutant punch.fbx",
	"Jump": "mutant jump attack.fbx",
	"Death": "mutant dying.fbx",
}

signal engaged_player()
signal jump_landed()

var engaged: bool = false
var flexed: bool = false
var flexing: bool = false
var punches_done: int = 0
var punches_before_jump: int = 2
var attack_kind: StringName = &""
@onready var walk_sound: AudioStreamPlayer3D = $WalkSound
@onready var hit_sound: AudioStreamPlayer3D = $HitSound
@onready var jump_sound: AudioStreamPlayer3D = $JumpSound
@onready var punch_sound: AudioStreamPlayer3D = $PunchSound

func _ready() -> void:
	current_health = max_health
	is_boss = true
	add_to_group("enemy")
	target = player_target
	_setup_health_bar()
	health_bar.hide()
	_import_clips()
	animation_player.animation_finished.connect(_on_animation_finished)
	punches_before_jump = randi_range(2, 3)
	_play(&"Idle")

func _import_clips() -> void:
	var library := AnimationLibrary.new()
	for clip_name: String in CLIPS:
		var source := load(CLIP_FOLDER + CLIPS[clip_name]) as PackedScene
		var source_root := source.instantiate()
		var source_player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if source_player == null or not source_player.has_animation("mixamo_com"):
			push_error("Missing Mutant animation: " + clip_name)
			source_root.free()
			continue
		var animation := source_player.get_animation("mixamo_com").duplicate(true) as Animation
		for track in animation.get_track_count():
			var track_path := String(animation.track_get_path(track))
			if clip_name == "Walk" and animation.track_get_type(track) == Animation.TYPE_POSITION_3D and track_path.ends_with(":mixamorig_Hips"):
				# The supplied walk travels 1.7 m forward in its hip track. Replaying
				# that travel snaps the visible model backward at every loop boundary.
				# CharacterBody3D already moves through the world, so keep only the
				# vertical bounce from the clip.
				var first_position: Vector3 = animation.track_get_key_value(track, 0)
				for key_index in animation.track_get_key_count(track):
					var hip_position: Vector3 = animation.track_get_key_value(track, key_index)
					hip_position.x = first_position.x
					hip_position.z = first_position.z
					animation.track_set_key_value(track, key_index, hip_position)
			animation.track_set_path(track, NodePath("MutantModel/" + track_path))
		animation.loop_mode = Animation.LOOP_LINEAR if clip_name in ["Idle", "Walk"] else Animation.LOOP_NONE
		library.add_animation(clip_name, animation)
		source_root.free()
	animation_player.add_animation_library("", library)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not engaged and _can_see_player():
		engaged = true
		engaged_player.emit()
	if flexing or stun_remaining > 0.0 or not engaged:
		walk_sound.stop()
		if stun_remaining > 0.0:
			stun_remaining = maxf(stun_remaining - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, stopping_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, stopping_friction * delta)
		if not flexing and not is_attacking:
			_play(&"Idle")
		_apply_gravity(delta)
		move_and_slide()
		return
	target = _get_preferred_target()
	if target == null or not is_instance_valid(target):
		walk_sound.stop()
		_apply_gravity(delta)
		move_and_slide()
		return
	attack_timer = maxf(attack_timer - delta, 0.0)
	var to_target := _get_target_center() - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var facing := false
	if distance > 0.05:
		rotation.y = rotate_toward(rotation.y, atan2(to_target.x, to_target.z), turn_speed * delta)
		facing = global_transform.basis.z.dot(to_target.normalized()) > 0.88
	if is_attacking:
		velocity.x = move_toward(velocity.x, 0.0, stopping_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, stopping_friction * delta)
		_process_attack_contact()
	elif distance > attack_range:
		velocity.x = move_toward(velocity.x, to_target.normalized().x * move_speed, movement_acceleration * delta)
		velocity.z = move_toward(velocity.z, to_target.normalized().z * move_speed, movement_acceleration * delta)
		_play(&"Walk")
	else:
		velocity.x = move_toward(velocity.x, 0.0, stopping_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, stopping_friction * delta)
		if attack_timer <= 0.0 and facing:
			_start_attack()
		else:
			_play(&"Idle")
	_apply_gravity(delta)
	move_and_slide()
	if current_animation == &"Walk" and not is_attacking and Vector2(velocity.x, velocity.z).length() > 0.4:
		if not walk_sound.playing:
			walk_sound.play()
	else:
		walk_sound.stop()

func _apply_gravity(delta: float) -> void:
	velocity.y = velocity.y - gravity * delta if not is_on_floor() else 0.0

func _can_see_player() -> bool:
	if player_target == null or not is_instance_valid(player_target) or not bool(player_target.get("is_alive")):
		return false
	var start := global_position + Vector3.UP * 1.4
	var end := _get_target_center()
	if start.distance_to(end) > 9.0 or absf(start.y - end.y) > 2.5:
		return false
	var query := PhysicsRayQueryParameters3D.create(start, end, 3, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == player_target

func _start_attack() -> void:
	is_attacking = true
	attack_has_hit = false
	walk_sound.stop()
	if punches_done >= punches_before_jump:
		attack_kind = &"Jump"
		punches_done = 0
		punches_before_jump = randi_range(2, 3)
		animation_player.speed_scale = 1.45
		jump_sound.play()
	else:
		attack_kind = &"Punch"
		punches_done += 1
		animation_player.speed_scale = 1.0
		punch_sound.play()
	_play(attack_kind, true)

func _process_attack_contact() -> void:
	if attack_has_hit or not animation_player.has_animation(attack_kind):
		return
	var clip := animation_player.get_animation(attack_kind)
	var hit_fraction := 0.69 if attack_kind == &"Jump" else 0.48
	if animation_player.current_animation_position < clip.length * hit_fraction:
		return
	attack_has_hit = true
	if attack_kind == &"Jump":
		jump_landed.emit()
		if is_instance_valid(player_target) and player_target.has_method("_add_camera_trauma"):
			player_target.call("_add_camera_trauma", 0.13)
	if target == null or not is_instance_valid(target):
		return
	var target_center := _get_target_center()
	var flat_distance := Vector2(target_center.x - global_position.x, target_center.z - global_position.z).length()
	var hit_range := 2.8 if attack_kind == &"Jump" else 2.1
	if flat_distance > hit_range or absf(target_center.y - (global_position.y + 1.0)) > 2.0:
		return
	# A player who retreats through the classroom doorway is protected by the wall.
	var sight := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.4, target_center, 3, [get_rid()])
	var obstruction := get_world_3d().direct_space_state.intersect_ray(sight)
	if not obstruction.is_empty() and obstruction.collider != target:
		return
	if target.has_method("take_damage"):
		var jump := attack_kind == &"Jump"
		target.call("take_damage", attack_damage * (1.45 if jump else 1.0), self, "melee", {
			"attack_name": "Mutant Jump Attack" if jump else "Mutant Punch",
			"unparryable": jump,
			"direction": global_position.direction_to(target_center),
		})

func is_attack_in_parry_window() -> bool:
	if not is_attacking or attack_has_hit or attack_kind != &"Punch":
		return false
	var clip := animation_player.get_animation(&"Punch")
	if clip == null or clip.length <= 0.0:
		return false
	var fraction := animation_player.current_animation_position / clip.length
	return fraction >= 0.35 and fraction <= 0.57

func apply_stun(duration: float = -1.0) -> void:
	if is_dead or flexing:
		return
	stun_remaining = maxf(stun_remaining, default_parry_stun_duration if duration < 0.0 else duration)
	is_attacking = false
	attack_has_hit = true
	attack_timer = 0.5
	animation_player.speed_scale = 1.0
	current_animation = &""
	_play(&"Idle", true)
	_spawn_stun_effect()

func take_damage(amount: float, _attacker: Node = null, play_hit_audio: bool = true) -> bool:
	if is_dead or amount <= 0.0:
		return false
	# Keep the existing P quick-playtest shortcut lethal for this boss too.
	if amount >= 999999.0:
		current_health = 0.0
		health_changed.emit(current_health, max_health)
		_die()
		return true
	if flexing:
		return false
	current_health = maxf(current_health - amount, 0.0)
	if play_hit_audio and not hit_sound.playing:
		hit_sound.play()
	if not flexed and current_health <= max_health * 0.05:
		flexed = true
		flexing = true
		is_attacking = false
		attack_has_hit = true
		current_health = maxf(current_health, max_health * 0.05) + max_health * 0.10
		animation_player.speed_scale = 1.0
		_play(&"Flex", true)
	if health_bar != null:
		health_bar.value = current_health
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		_die()
	return true

func take_burn_damage(amount: float, attacker: Node = null) -> bool:
	# Ultimate burn ticks apply damage without restarting the impact sound.
	return take_damage(amount, attacker, false)

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"Flex":
		flexing = false
		attack_timer = 0.5
		_play(&"Idle")
	elif animation_name == &"Punch" or animation_name == &"Jump":
		is_attacking = false
		attack_has_hit = false
		attack_timer = 0.45
		animation_player.speed_scale = 1.0
		current_animation = &""
		_play(&"Idle")

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	remove_from_group("enemy")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	is_attacking = false
	walk_sound.stop()
	if health_bar != null:
		health_bar.hide()
	animation_player.speed_scale = 1.0
	_play(&"Death", true)
	died.emit()
	var death_clip := animation_player.get_animation(&"Death")
	get_tree().create_timer(death_clip.length + 0.5).timeout.connect(queue_free)
