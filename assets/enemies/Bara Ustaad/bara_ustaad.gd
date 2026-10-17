extends "res://assets/enemies/Mutant/mutant_boss.gd"

const BARA_FOLDER := "res://assets/enemies/Bara Ustaad/"
const BARA_CLIPS := {
	"Idle": "res://assets/enemies/Mutant/Creature Pack/mutant breathing idle.fbx",
	"Walk": "res://assets/enemies/Mutant/Creature Pack/mutant walking.fbx",
	"AttackHorizontal": BARA_FOLDER + "Standing Melee Attack Horizontal.fbx",
	"AttackDownward": BARA_FOLDER + "Standing Melee Attack Downward.fbx",
	"AttackKick": BARA_FOLDER + "Standing Melee Attack Kick Ver. 2.fbx",
	"HitLeft": BARA_FOLDER + "Standing React Large From Left.fbx",
	"HitRight": BARA_FOLDER + "Standing React Large From Right.fbx",
	"HitGut": BARA_FOLDER + "Standing React Large Gut.fbx",
	"EntranceJump": BARA_FOLDER + "Standing Melee Run Jump Attack.fbx",
	"Death": "res://assets/enemies/Mutant/Creature Pack/mutant dying.fbx",
}
const ATTACKS: Array[StringName] = [&"AttackHorizontal", &"AttackDownward", &"AttackKick"]
const REACTIONS: Array[StringName] = [&"HitLeft", &"HitRight", &"HitGut"]
const TARGET_HEIGHT := 8.6 # The portal spans 8 m; its defender is slightly taller.

var hit_reacting := false
var last_attack: StringName = &""

func _ready() -> void:
	super._ready()
	_fit_giant()
	# The arrival starts high above the roof; combat territory begins at landing.
	awareness.home = Vector3(global_position.x, 6.55, global_position.z)
	awareness.aggro_range = 18.0
	awareness.leash_range = 30.0

func _fit_giant() -> void:
	animation_player.advance(0.0)
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in skeleton_model.find_children("*", "MeshInstance3D", true, false):
		var local: AABB = (skeleton_model.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	if not first and bounds.size.y > 0.01:
		skeleton_model.scale = Vector3.ONE * (TARGET_HEIGHT / bounds.size.y)
		skeleton_model.position.y = -bounds.position.y * skeleton_model.scale.y
	var collider := get_node("CollisionShape3D") as CollisionShape3D
	var body := CapsuleShape3D.new()
	body.radius = 1.25
	body.height = TARGET_HEIGHT
	collider.shape = body
	collider.position.y = TARGET_HEIGHT * 0.5

func _import_clips() -> void:
	var library := AnimationLibrary.new()
	for clip_name: String in BARA_CLIPS:
		var source := load(BARA_CLIPS[clip_name]) as PackedScene
		if source == null:
			push_error("Missing Bara Ustaad clip: " + clip_name)
			continue
		var source_root := source.instantiate()
		var source_player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if source_player == null or not source_player.has_animation("mixamo_com"):
			push_error("Invalid Bara Ustaad clip: " + clip_name)
			source_root.free()
			continue
		var animation := source_player.get_animation("mixamo_com").duplicate(true) as Animation
		for track in animation.get_track_count():
			var track_path := String(animation.track_get_path(track))
			# World movement is owned by CharacterBody3D. Imported hip travel
			# would snap the model back when a loop or hit reaction ends.
			if animation.track_get_type(track) == Animation.TYPE_POSITION_3D and track_path.ends_with(":mixamorig_Hips"):
				var origin: Vector3 = animation.track_get_key_value(track, 0)
				for key_index in animation.track_get_key_count(track):
					var pose: Vector3 = animation.track_get_key_value(track, key_index)
					pose.x = origin.x
					pose.z = origin.z
					if clip_name == "EntranceJump":
						pose.y = origin.y
					animation.track_set_key_value(track, key_index, pose)
			animation.track_set_path(track, NodePath("BaraModel/" + track_path))
		animation.loop_mode = Animation.LOOP_LINEAR if clip_name in ["Idle", "Walk"] else Animation.LOOP_NONE
		library.add_animation(clip_name, animation)
		source_root.free()
	animation_player.add_animation_library("", library)

func _physics_process(delta: float) -> void:
	if hit_reacting and not is_dead:
		walk_sound.stop()
		velocity.x = move_toward(velocity.x, 0.0, stopping_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, stopping_friction * delta)
		_apply_gravity(delta)
		move_and_slide()
		return
	super._physics_process(delta)

func _start_attack() -> void:
	var choices := ATTACKS.filter(func(item: StringName) -> bool: return item != last_attack)
	attack_kind = choices.pick_random()
	last_attack = attack_kind
	is_attacking = true
	attack_has_hit = false
	walk_sound.stop()
	animation_player.speed_scale = 1.35 if attack_kind != &"AttackKick" else 1.1
	if attack_kind == &"AttackKick":
		jump_sound.play()
	else:
		punch_sound.play()
	_play(attack_kind, true)

func _hit_fraction() -> float:
	match attack_kind:
		&"AttackHorizontal": return 0.48
		&"AttackDownward": return 0.55
		&"AttackKick": return 0.52
	return 0.5

func is_attack_in_parry_window() -> bool:
	if not is_attacking or attack_has_hit or not animation_player.has_animation(attack_kind):
		return false
	var clip := animation_player.get_animation(attack_kind)
	var fraction := animation_player.current_animation_position / maxf(clip.length, 0.01)
	return fraction >= _hit_fraction() - 0.13 and fraction <= _hit_fraction() + 0.07

func _process_attack_contact() -> void:
	if attack_has_hit or not animation_player.has_animation(attack_kind):
		return
	var clip := animation_player.get_animation(attack_kind)
	if animation_player.current_animation_position < clip.length * _hit_fraction():
		return
	attack_has_hit = true
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	var center := _get_target_center()
	var horizontal := Vector2(center.x - global_position.x, center.z - global_position.z).length()
	if horizontal > 2.7 or absf(center.y - (global_position.y + 1.4)) > 2.3:
		return
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.4, center, 3, [get_rid()])
	var obstruction := get_world_3d().direct_space_state.intersect_ray(ray)
	if not obstruction.is_empty() and obstruction.collider != target:
		return
	target.call("take_damage", attack_damage * (1.2 if attack_kind == &"AttackKick" else 1.0), self, "melee", {
		"attack_name": "Bara Ustaad " + String(attack_kind),
		"unparryable": false,
		"direction": global_position.direction_to(center),
	})

func take_damage(amount: float, attacker: Node = null, play_hit_audio: bool = true) -> bool:
	if is_dead or amount <= 0.0:
		return false
	if amount >= 999999.0:
		current_health = 0.0
		health_changed.emit(current_health, max_health)
		_die()
		return true
	current_health = maxf(current_health - amount, 0.0)
	preload("res://combat_impact.gd").hit(self, attacker, amount)
	if play_hit_audio and not hit_sound.playing:
		hit_sound.play()
	if health_bar != null:
		health_bar.value = current_health
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		_die()
	elif play_hit_audio and amount >= 3.0:
		hit_reacting = true
		is_attacking = false
		attack_has_hit = true
		animation_player.speed_scale = 1.6
		_play(REACTIONS.pick_random(), true)
	return true

func apply_stun(duration: float = -1.0) -> void:
	hit_reacting = false
	super.apply_stun(duration)

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name in REACTIONS:
		hit_reacting = false
		animation_player.speed_scale = 1.0
		current_animation = &""
		_play(&"Idle")
	elif animation_name in ATTACKS:
		is_attacking = false
		attack_has_hit = false
		attack_timer = 0.75
		animation_player.speed_scale = 1.0
		current_animation = &""
		_play(&"Idle")
