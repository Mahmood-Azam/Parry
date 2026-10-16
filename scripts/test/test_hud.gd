extends CanvasLayer

@export var player_path: NodePath
var _player: Player

@onready var health_label: Label = $Panel/VBoxContainer/HealthLabel
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var controls_label: Label = $Panel/VBoxContainer/ControlsLabel


func _ready() -> void:
	if player_path:
		_player = get_node_or_null(player_path) as Player
	if not _player:
		_player = get_tree().get_first_node_in_group("player") as Player

	if _player:
		_player.health_changed.connect(_on_health_changed)
		_player.died.connect(_on_player_died)
		_on_health_changed(_player.current_health, _player.max_health)


func _process(_delta: float) -> void:
	if not _player:
		return

	var status_text := ""
	if _player.is_parrying:
		var window_type := "PERFECT" if _player.parry_timer <= _player.perfect_parry_window else "NORMAL"
		status_text = "[PARRYING (%s)]" % window_type
	elif _player.is_dashing:
		status_text = "[SHADOW DASHING (INVULNERABLE)]"
	elif _player.parry_cooldown_timer > 0.0:
		status_text = "[Parry Recovery: %.2fs]" % _player.parry_cooldown_timer
	elif _player.dash_cooldown_timer > 0.0:
		status_text = "[Dash CD: %.2fs]" % _player.dash_cooldown_timer
	else:
		status_text = "[Ready]"

	status_label.text = "Status: " + status_text


func _on_health_changed(current: float, max_h: float) -> void:
	if health_label:
		health_label.text = "Health: %d / %d" % [int(current), int(max_h)]


func _on_player_died() -> void:
	if health_label:
		health_label.text = "Health: 0 (DEAD)"
	if status_label:
		status_label.text = "Status: DEFEATED"
