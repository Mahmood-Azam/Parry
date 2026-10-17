extends Node
## Per-actor feedback. Overlay ownership is restored without modifying shared assets.
const RECOIL := preload("res://combat_recoil.gd")
static var sounds: Dictionary = {}
var meshes: Array[MeshInstance3D] = []
var originals: Array[Material] = []
var flash: ShaderMaterial
var recoil: SkeletonModifier3D
var sound: AudioStreamPlayer3D
var elapsed := 1.0
var last_hit := -1000

static func hit(actor: Node3D, attacker: Node, damage: float, blocked: bool = false) -> void:
	if not is_instance_valid(actor) or damage <= 0.0 or damage >= 99999.0:
		return
	var feedback := actor.get_node_or_null("CombatImpact")
	if feedback == null:
		feedback = new()
		feedback.name = "CombatImpact"
		actor.add_child(feedback)
	feedback.trigger(attacker, damage, blocked)

func _ready() -> void:
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, blend_add, depth_draw_never; uniform vec4 tint : source_color = vec4(1.0); uniform float strength = 0.0; void fragment() { ALBEDO = tint.rgb; EMISSION = tint.rgb * 1.5; ALPHA = strength; }"
	flash = ShaderMaterial.new()
	flash.shader = shader
	for child in get_parent().find_children("*", "MeshInstance3D", true, false):
		# Do not flash weapon FX, debug meshes, or attached status effects.
		if child is MeshInstance3D and child.mesh != null and child.get_parent() is Skeleton3D:
			meshes.append(child)
	# Imported models may wrap their skinned meshes in an extra node.
	if meshes.is_empty():
		for child in get_parent().find_children("*", "MeshInstance3D", true, false):
			if child.skeleton != NodePath("") and child.get_node_or_null(child.skeleton) is Skeleton3D:
				meshes.append(child)
	var rig := get_parent().find_child("Skeleton3D", true, false) as Skeleton3D
	if rig != null:
		recoil = RECOIL.new()
		recoil.name = "ImpactRecoil"
		rig.add_child(recoil)
	sound = AudioStreamPlayer3D.new()
	sound.name = "ContactSound"
	sound.max_distance = 24.0
	sound.unit_size = 5.0
	sound.volume_db = -10.0
	add_child(sound)
	sound.position.y = 1.0

func trigger(attacker: Node, damage: float, blocked: bool) -> void:
	# Small burn ticks do not retrigger full hit feedback or drown out combat.
	if (damage < 3.0 and not blocked) or Time.get_ticks_msec() - last_hit < 90:
		return
	last_hit = Time.get_ticks_msec()
	_restore_overlays()
	for mesh in meshes:
		originals.append(mesh.material_overlay)
		mesh.material_overlay = flash
	elapsed = 0.0
	flash.set_shader_parameter("tint", Color(0.3, 0.65, 1.0) if blocked else Color(1.0, 0.48, 0.16))
	flash.set_shader_parameter("strength", 0.65)
	var direction := Vector3.BACK
	if attacker is Node3D:
		direction = (get_parent().global_position - attacker.global_position).normalized()
	if direction.length_squared() < 0.001:
		direction = Vector3.BACK
	if recoil != null:
		recoil.kick(direction, 0.12 if blocked else clampf(damage / 100.0, 0.16, 0.30))
	sound.stream = _contact_sound(blocked)
	sound.pitch_scale = randf_range(0.93, 1.07)
	sound.play()
	var root := get_tree().current_scene
	if root != null:
		var tint := Color(0.3, 0.7, 1.0) if blocked else Color(1.0, 0.55, 0.12)
		var contact: Vector3 = get_parent().global_position + Vector3.UP * 1.0 - direction * 0.22
		preload("res://combat_fx.gd").burst(root, contact, tint, 16 if blocked else 28, 0.85)
		preload("res://combat_fx.gd").ring(root, contact, tint, 0.38 if blocked else 0.58, direction)

func _process(delta: float) -> void:
	if elapsed >= 0.14:
		return
	elapsed += delta
	flash.set_shader_parameter("strength", maxf(0.0, 1.0 - elapsed / 0.14) * 0.65)
	if elapsed >= 0.14:
		_restore_overlays()

func _restore_overlays() -> void:
	for i in originals.size():
		if is_instance_valid(meshes[i]) and meshes[i].material_overlay == flash:
			meshes[i].material_overlay = originals[i]
	originals.clear()

func _exit_tree() -> void:
	_restore_overlays()

static func _contact_sound(blocked: bool) -> AudioStreamWAV:
	var key := "guard" if blocked else "hit"
	if sounds.has(key):
		return sounds[key]
	var rate := 22050
	var data := PackedByteArray()
	var samples := int(rate * 0.15)
	data.resize(samples * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 91237
	for i in samples:
		var t := float(i) / rate
		var thud := sin(TAU * (115.0 * t - 190.0 * t * t)) * exp(-t * 38.0)
		var crunch := noise.randf_range(-1.0, 1.0) * exp(-t * 65.0)
		var clang := (sin(TAU * 1650.0 * t) + sin(TAU * 2570.0 * t) * 0.35) * exp(-t * 32.0)
		var value := (clang * 0.30 + crunch * 0.15) if blocked else (thud * 0.62 + crunch * 0.35)
		value *= minf(t / 0.0015, 1.0)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	sounds[key] = stream
	return stream
