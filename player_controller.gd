extends CharacterBody3D

const MOVEMENT_SCENE: PackedScene = preload("res://assets/KayKit_Adventurers_2.0_FREE/KayKit_Adventurers_2.0_FREE/Animations/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb")
const GENERAL_SCENE: PackedScene = preload("res://assets/KayKit_Adventurers_2.0_FREE/KayKit_Adventurers_2.0_FREE/Animations/gltf/Rig_Medium/Rig_Medium_General.glb")

@export var walk_speed: float = 3.8
@export var run_speed: float = 6.0
@export var jump_velocity: float = 4.6
@export var turn_speed: float = 12.0

@onready var character: Node3D = $KayKitKnight
@onready var animation_player: AnimationPlayer = $KayKitKnight/AnimationPlayer

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var attacking := false
var last_animation := ""
func _ready() -> void:
	_import_animation_library(MOVEMENT_SCENE)
	_import_animation_library(GENERAL_SCENE)
	
	# Ensure the target library exists before accessing it
	var library: AnimationLibrary = _get_or_create_default_library()
	
	for clip in ["Idle_A", "Idle_B", "Walking_A", "Walking_B", "Walking_C", "Running_A", "Running_B"]:
		if animation_player.has_animation(clip):
			var animation := animation_player.get_animation(clip)
			animation.loop_mode = Animation.LOOP_LINEAR
			
	if animation_player.has_animation("Throw"):
		var attack_clip: Animation = animation_player.get_animation("Throw").duplicate(true)
		library.add_animation("Attack", attack_clip)
		
	animation_player.play("Idle_A")
	last_animation = "Idle_A"

func _import_animation_library(source_scene: PackedScene) -> void:
	var source_root := source_scene.instantiate()
	var source_player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	
	if source_player == null:
		source_root.queue_free()
		return

	var target_library := _get_or_create_default_library()

	# Retrieve clips safely from the source AnimationPlayer
	for library_name in source_player.get_animation_library_list():
		var source_lib := source_player.get_animation_library(library_name)
		for clip_name in source_lib.get_animation_list():
			if not animation_player.has_animation(clip_name):
				var anim := source_lib.get_animation(clip_name).duplicate(true)
				target_library.add_animation(clip_name, anim)
				
	source_root.queue_free()

# Helper function to guarantee an AnimationLibrary is returned
func _get_or_create_default_library() -> AnimationLibrary:
	if animation_player.has_animation_library(""):
		return animation_player.get_animation_library("")
	
	var new_lib := AnimationLibrary.new()
	animation_player.add_animation_library("", new_lib)
	return new_lib

func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_vector.x, 0.0, input_vector.y).normalized()
	var moving := direction.length_squared() > 0.001
	var sprinting := Input.is_key_pressed(KEY_SHIFT)

	if moving:
		var target_yaw := atan2(direction.x, -direction.z)
		character.rotation.y = rotate_toward(character.rotation.y, target_yaw, turn_speed * delta)

	var speed := run_speed if sprinting else walk_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		_play("Jump_Full_Short")

	if Input.is_action_just_pressed("attack") and not attacking:
		attacking = true
		_play("Attack")

	move_and_slide()

	if not attacking:
		if not is_on_floor():
			return
		if moving:
			_play("Running_A" if sprinting else "Walking_A")
		else:
			_play("Idle_A")

func _play(animation_name: String) -> void:
	if animation_player.has_animation(animation_name) and last_animation != animation_name:
		last_animation = animation_name
		animation_player.play(animation_name, 0.12)

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == "Attack":
		attacking = false
		last_animation = ""
