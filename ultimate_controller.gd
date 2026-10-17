extends Node
## Ultimate access is a view of the same reserve used by attacks and decay.
const CINEMATIC := preload("res://ultimate_cinematic.gd")
const FX := preload("res://combat_fx.gd")
signal charge_changed(charge: float, maximum: float)
signal ultimate_started(kind: String)
signal ultimate_finished(kind: String)
@export var area_radius := 10.0
@export var area_damage := 110.0
@export var focused_damage := 340.0
@export var focused_range := 16.0
var charge: float:
	get:
		return player.fire_meter if is_instance_valid(player) else 0.0
	set(amount):
		if is_instance_valid(player):
			player.fire_meter = clampf(amount, 0.0, maximum_charge())
var last_charge := -1.0
var player: CharacterBody3D
var cinematic: Node3D
var hud: CanvasLayer
var title: Label
var hint: Label
var bars: Array[ProgressBar] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	player = get_parent() as CharacterBody3D
	_build_hud()
	_refresh_hud()

func maximum_charge() -> float:
	return maxf(player.fire_meter_max, 1.0) * 2.0

func is_ready() -> bool:
	return charge >= maximum_charge() - 0.001

func add_fire(amount: float) -> void:
	if amount <= 0.0 or not player.is_alive or player.is_using_ultimate:
		return
	var was_ready := is_ready()
	player._add_fire_meter(amount)
	charge_changed.emit(charge, maximum_charge())
	_refresh_hud()
	if is_ready() and not was_ready:
		player._show_combat_feedback("ULTIMATE READY  [E / G]", Color(1, 0.82, 0.25))
		FX.ring(get_tree().current_scene, player.global_position + Vector3.UP * 0.1, Color(1, 0.7, 0.18), 2.0)

func try_activate(kind: String) -> bool:
	if kind not in ["area", "focused"] or not player.is_alive or player.is_using_ultimate or get_tree().paused:
		return false
	if not is_ready():
		player._show_combat_feedback("ULTIMATE: BANK TWO FIRE BARS", Color(1, 0.6, 0.2))
		return false
	if player.attacking or player.is_dashing or player.is_fire_channeling or player.hit_stun_remaining > 0.0:
		return false
	if not player.is_on_floor():
		player._show_combat_feedback("LAND TO USE ULTIMATE", Color(1, 0.6, 0.2))
		return false
	var target: Node3D = null
	if kind == "focused":
		target = select_focused_target()
		if target == null:
			player._show_combat_feedback("FACE A VISIBLE TARGET  [G]", Color(1, 0.65, 0.25))
			return false # Invalid aim never consumes the banked charge.
	charge = 0.0
	charge_changed.emit(charge, maximum_charge())
	player.is_using_ultimate = true
	player.ultimate_kind = kind
	player.ultimate_power = 0.0
	player.is_parrying = false
	player.blocking = false
	player._set_parry_hitbox_active(false)
	player.attack_requested = false
	player.attack_combo_queued = false
	player.jump_requested = false
	player.jump_buffer_remaining = 0.0
	player.velocity = Vector3.ZERO
	cinematic = CINEMATIC.new()
	cinematic.controller = self
	cinematic.player = player
	cinematic.kind = kind
	cinematic.target = weakref(target) if target != null else null
	cinematic.finished.connect(_on_cinematic_finished)
	get_tree().current_scene.add_child(cinematic)
	ultimate_started.emit(kind)
	_refresh_hud()
	return true

func select_focused_target() -> Node3D:
	var forward: Vector3 = player.character.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best: Node3D = null
	var best_score := -INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or not enemy is Node3D or enemy.get("is_dead") == true:
			continue
		var offset: Vector3 = enemy.global_position - player.global_position
		if offset.length() > focused_range or absf(offset.y) > 3.0:
			continue
		offset.y = 0.0
		var alignment := forward.dot(offset.normalized()) if offset.length_squared() > 0.001 else 1.0
		if alignment < cos(deg_to_rad(35.0)) or not has_clear_path(enemy):
			continue
		var score := alignment * 10.0 - offset.length() * 0.15 + (3.0 if enemy.get("is_boss") == true else 0.0)
		if score > best_score:
			best_score = score
			best = enemy
	return best

func has_clear_path(enemy: Node3D) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, enemy.global_position + Vector3.UP, 1)
	return player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _on_cinematic_finished(kind: String) -> void:
	cinematic = null
	_refresh_hud()
	ultimate_finished.emit(kind)

func _process(_delta: float) -> void:
	var current := charge
	if not is_equal_approx(current, last_charge):
		last_charge = current
		charge_changed.emit(current, maximum_charge())
	hud.visible = false # The player owns the single shared layered meter.


func _build_hud() -> void:
	# Retained as a lifecycle hook for cinematics; no second on-screen meter.
	hud = CanvasLayer.new()
	hud.name = "UltimateHUD"
	add_child(hud)
	hud.hide()


func _refresh_hud() -> void:
	player._update_combat_stats()
