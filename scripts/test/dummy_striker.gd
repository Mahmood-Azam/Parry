class_name DummyStriker
extends Node3D

## Simple automated training dummy to test parrying, dodging, and damage reception.
@export var attack_interval: float = 3.0
@export var telegraph_duration: float = 0.7
@export var damage: float = 20.0
@export var player_path: NodePath

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D

var _timer: float = 0.0
var _is_telegraphing: bool = false
var _player: Player
var _default_mat: StandardMaterial3D
var _telegraph_mat: StandardMaterial3D


func _ready() -> void:
	if player_path:
		_player = get_node_or_null(player_path) as Player
	if not _player:
		_player = get_tree().get_first_node_in_group("player") as Player

	_default_mat = StandardMaterial3D.new()
	_default_mat.albedo_color = Color(0.8, 0.3, 0.2) # Reddish enemy

	_telegraph_mat = StandardMaterial3D.new()
	_telegraph_mat.albedo_color = Color(1.0, 0.8, 0.1) # Bright yellow telegraph
	_telegraph_mat.emission_enabled = true
	_telegraph_mat.emission = Color(1.0, 0.7, 0.0)
	_telegraph_mat.emission_energy_multiplier = 3.0

	if mesh:
		mesh.set_surface_override_material(0, _default_mat)

	if _player:
		_player.parry_success.connect(_on_parry_success)
		_player.damage_evaded.connect(_on_damage_evaded)
		_player.damaged.connect(_on_player_damaged)
		_player.parry_failed.connect(_on_parry_failed)


func _process(delta: float) -> void:
	if not _player or not _player.is_alive:
		return

	_timer += delta

	if not _is_telegraphing and _timer >= (attack_interval - telegraph_duration):
		_start_telegraph()

	if _timer >= attack_interval:
		_strike()


func _start_telegraph() -> void:
	_is_telegraphing = true
	if mesh:
		mesh.set_surface_override_material(0, _telegraph_mat)
	if label:
		label.text = "! ATTACK INCOMING !"
		label.modulate = Color(1.0, 0.9, 0.2)


func _strike() -> void:
	_timer = 0.0
	_is_telegraphing = false
	if mesh:
		mesh.set_surface_override_material(0, _default_mat)

	if not _player:
		return

	# Check distance to player
	var dist := global_position.distance_to(_player.global_position)
	if dist <= 3.5:
		_player.take_damage(damage, self, "melee", {"attack_name": "Dummy Strike"})
	else:
		if label:
			label.text = "(Player out of range)"
			label.modulate = Color(0.7, 0.7, 0.7)


func _on_parry_success(attacker: Node, is_perfect: bool, _data: Dictionary) -> void:
	if attacker != self and attacker != null:
		return
	if label:
		if is_perfect:
			label.text = "★★★ PERFECT PARRY! ★★★"
			label.modulate = Color(0.2, 1.0, 0.4)
		else:
			label.text = "★ PARRY SUCCESS ★"
			label.modulate = Color(0.3, 0.7, 1.0)


func _on_damage_evaded(_amount: float, attacker: Node) -> void:
	if attacker != self and attacker != null:
		return
	if label:
		label.text = "≈ SHADOW DASH EVADED ≈"
		label.modulate = Color(0.8, 0.4, 1.0)


func _on_player_damaged(amount: float, attacker: Node) -> void:
	if attacker != self and attacker != null:
		return
	if label:
		label.text = "✗ HIT! Damage: -%d" % int(amount)
		label.modulate = Color(1.0, 0.2, 0.2)


func _on_parry_failed() -> void:
	if label:
		label.text = "⚠ PARRY WHIP / FAILED!"
		label.modulate = Color(1.0, 0.5, 0.2)
