extends CharacterBody3D

@export var move_speed: float = 2.6
@export var attack_range: float = 1.45
@export var attack_cooldown: float = 1.8
@export var turn_speed: float = 8.0

@onready var target: CharacterBody3D = get_node_or_null("../Player") as CharacterBody3D
@onready var animation_player: AnimationPlayer = $SkeletonModel/AnimationPlayer

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var attack_timer: float = 0.0
var is_attacking: bool = false
var current_animation: StringName = &""

func _ready() -> void:
	for animation_name in [&"Lesha_idle", &"Lesha_walk"]:
		if animation_player.has_animation(animation_name):
			animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	animation_player.animation_finished.connect(_on_animation_finished)
	_play(&"Lesha_idle")

func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	attack_timer = maxf(attack_timer - delta, 0.0)
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > 0.05:
		var desired_yaw := atan2(to_target.x, to_target.z)
		rotation.y = rotate_toward(rotation.y, desired_yaw, turn_speed * delta)

	if distance > attack_range:
		is_attacking = false
		var direction := to_target.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		_play(&"Lesha_walk")
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * 4.0 * delta)
		if not is_attacking and attack_timer <= 0.0:
			is_attacking = true
			attack_timer = attack_cooldown
			_play(&"Lesha_attack_1", true)
		elif not is_attacking:
			_play(&"Lesha_idle")

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()

func _play(animation_name: StringName, restart: bool = false) -> void:
	if not animation_player.has_animation(animation_name):
		return
	if restart or current_animation != animation_name:
		current_animation = animation_name
		animation_player.play(animation_name, 0.1)

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"Lesha_attack_1":
		is_attacking = false
		current_animation = &""
