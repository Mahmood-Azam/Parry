extends Node3D
## Only the current encounter exists, so distant enemies do not simulate or
## chase through walls. Block D's open lobby and central corridor form the route.
const ENEMY := preload("res://assets/enemies/skeleton/shadow_enemy.tscn")
const STAGES := [
	{"name": "THE COURTYARD", "hint": "Clear the courtyard. Enter the amber-lit Block D doorway.", "trigger": Vector3(35, 0.1, -74), "spawns": [Vector3(35, 0.15, -79), Vector3(31.5, 0.15, -77)], "gate": Vector3(40.15, 1.6, -74.55), "gate_size": Vector3(0.12, 2.9, 2.4)},
	{"name": "BLOCK D — ENTRANCE", "hint": "Clear the lobby, then turn right into the long corridor.", "trigger": Vector3(44.5, 0.3, -74.55), "spawns": [Vector3(47, 0.4, -74.55), Vector3(49, 0.4, -77)], "gate": Vector3(49, 1.7, -80), "gate_size": Vector3(2.75, 2.9, 0.12)},
	{"name": "THE LONG CORRIDOR", "hint": "Push through the corridor. The shadows grow stronger.", "trigger": Vector3(49, 0.3, -82), "spawns": [Vector3(48.5, 0.4, -86), Vector3(49.5, 0.4, -89), Vector3(49, 0.4, -92)], "gate": Vector3(49, 1.7, -94.5), "gate_size": Vector3(2.75, 2.9, 0.12)},
	{"name": "THE REARGUARD", "hint": "Defeat the elite guard. Follow the corridor through the rear exit.", "trigger": Vector3(49, 0.3, -96), "spawns": [Vector3(48.45, 0.4, -99), Vector3(49.55, 0.4, -102)], "gate": Vector3(49, 1.7, -104.05), "gate_size": Vector3(2.8, 2.9, 0.12)},
	{"name": "THE ASH WARDEN", "hint": "The Warden guards the rear court. Parry to ignite your blade.", "trigger": Vector3(49, -0.1, -108), "spawns": [Vector3(49, 0.1, -114)], "gate": Vector3(49, 1.7, -104.05), "gate_size": Vector3(2.8, 2.9, 0.12)},
]

var stage: int = 0
var active: bool = false
var completed: bool = false
var alive: int = 0
var defeated: Dictionary = {}
var gates: Array[StaticBody3D] = []
var marker: Node3D
var objective: Label
var boss_bar: ProgressBar
var boss_title: Label
var boss: CharacterBody3D
var player: CharacterBody3D
var ui_clock: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	player = get_parent().get_node("Player")
	var player_fill := OmniLight3D.new()
	player_fill.name = "MoonlightFill"
	player_fill.position = Vector3(0, 1.6, 0)
	player_fill.light_color = Color(0.40, 0.50, 0.70)
	player_fill.light_energy = 0.65
	player_fill.omni_range = 4.8
	player_fill.shadow_enabled = false
	player.add_child(player_fill)
	_build_hud()
	for index in STAGES.size() - 1:
		_build_gate(index)
	# Warm pools of light guide the route without costly shadowed local lights.
	for p in [Vector3(38, 2.5, -74.55), Vector3(46, 2.5, -74.55), Vector3(49, 2.65, -83), Vector3(49, 2.65, -92), Vector3(49, 2.65, -101), Vector3(45, 2.5, -110), Vector3(53, 2.5, -115)]:
		var lamp := OmniLight3D.new()
		lamp.position = p
		lamp.light_color = Color(1.0, 0.43, 0.14)
		lamp.light_energy = 1.8
		lamp.omni_range = 6.5
		lamp.shadow_enabled = false
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 20.0
		lamp.distance_fade_length = 5.0
		add_child(lamp)
		var ember := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.07
		sphere.height = 0.14
		ember.mesh = sphere
		ember.material_override = _emissive(Color(1.0, 0.32, 0.045), 4.0)
		lamp.add_child(ember)
	_set_marker()
	_update_hud()

func _process(delta: float) -> void:
	if completed or not is_instance_valid(player) or not player.is_alive:
		return
	if not active:
		var destination: Vector3 = STAGES[stage].trigger
		var offset := player.global_position - destination
		if Vector2(offset.x, offset.z).length() < (4.5 if stage == 0 else 2.5) and absf(offset.y) < 1.6:
			_start_encounter()
	ui_clock += delta
	if marker:
		marker.rotation.y += delta * 0.8
	if ui_clock > 0.1:
		ui_clock = 0.0
		_update_hud()

func _start_encounter() -> void:
	active = true
	if stage == STAGES.size() - 1:
		_build_gate(stage) # Seal the rear doorway only after entering the boss court.
	defeated.clear()
	alive = STAGES[stage].spawns.size()
	if marker:
		marker.queue_free()
		marker = null
	for index in alive:
		var enemy := ENEMY.instantiate() as CharacterBody3D
		enemy.name = "Encounter%d_Shadow%d" % [stage + 1, index + 1]
		enemy.position = STAGES[stage].spawns[index]
		enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
		enemy.max_health = [80.0, 100.0, 110.0, 150.0, 450.0][stage]
		enemy.attack_damage = [12.0, 14.0, 15.0, 18.0, 23.0][stage]
		enemy.attack_timer = 0.5 + float(index) * 0.45
		if stage == STAGES.size() - 1:
			enemy.is_boss = true
			enemy.attack_cooldown = 1.9
			enemy.attack_animation_speed_scale = 0.91
			enemy.attack_range = 1.7
			enemy.default_parry_stun_duration = 0.8
			var model := enemy.get_node("SkeletonModel") as Node3D
			model.scale *= 1.22
			boss = enemy
			var halo := OmniLight3D.new()
			halo.light_color = Color(0.52, 0.12, 0.8)
			halo.light_energy = 2.0
			halo.omni_range = 3.5
			halo.position.y = 1.4
			enemy.add_child(halo)
		# Enemies remain siblings of Player, preserving the existing target path.
		enemy.died.connect(_enemy_defeated.bind(enemy.get_instance_id()))
		get_parent().add_child(enemy)
		if enemy.is_boss:
			enemy.health_bar.hide()
	_update_hud()

func _enemy_defeated(identity: int) -> void:
	if not active or defeated.has(identity):
		return
	defeated[identity] = true
	alive -= 1
	if alive > 0:
		_update_hud()
		return
	active = false
	if stage < gates.size() and is_instance_valid(gates[stage]):
		var gate := gates[stage]
		# Death signals can originate inside physics callbacks.
		gate.get_node("CollisionShape3D").set_deferred("disabled", true)
		var tween := create_tween()
		tween.tween_property(gate.get_node("Veil"), "transparency", 1.0, 0.65)
		tween.tween_callback(gate.queue_free)
	if stage == STAGES.size() - 1:
		completed = true
		boss_bar.hide()
		boss_title.hide()
		objective.text = "BLOCK D CLEARED\nThe Ash Warden has fallen."
		get_parent().show_victory()
		return
	stage += 1
	# Small between-encounter recovery, rather than resetting combat mid-fight.
	if player.is_alive:
		player.current_health = minf(player.max_health, player.current_health + 25.0)
		player.health_changed.emit(player.current_health, player.max_health)
		player._update_combat_stats()
	_set_marker()
	_update_hud()

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 4
	add_child(canvas)
	objective = Label.new()
	objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	objective.position = Vector2(-375, 70)
	objective.custom_minimum_size = Vector2(350, 115)
	objective.size.x = 350
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.add_theme_font_size_override("font_size", 18)
	objective.add_theme_color_override("font_color", Color(1.0, 0.79, 0.48))
	objective.add_theme_color_override("font_shadow_color", Color.BLACK)
	objective.add_theme_constant_override("shadow_offset_x", 2)
	objective.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(objective)
	boss_bar = ProgressBar.new()
	boss_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	boss_bar.position = Vector2(-260, -52)
	boss_bar.size = Vector2(520, 16)
	boss_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.19, 0.055)
	boss_bar.add_theme_stylebox_override("fill", fill)
	canvas.add_child(boss_bar)
	boss_title = Label.new()
	boss_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	boss_title.position = Vector2(-260, -84)
	boss_title.size.x = 520
	boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_title.add_theme_font_size_override("font_size", 23)
	canvas.add_child(boss_title)
	boss_bar.hide()
	boss_title.hide()

func _update_hud() -> void:
	if completed:
		return
	var data: Dictionary = STAGES[stage]
	var distance := player.global_position.distance_to(data.trigger)
	objective.text = "%d / %d  %s\n%s\n%s" % [stage + 1, STAGES.size(), data.name, data.hint, ("Shadows remaining: %d" % alive) if active else ("Follow the amber beacon — %dm" % int(distance))]
	if is_instance_valid(boss) and not boss.is_dead:
		boss_bar.show()
		boss_title.show()
		boss_bar.max_value = boss.max_health
		boss_bar.value = boss.current_health
		boss_title.text = "THE ASH WARDEN" + ("  —  UNBOUND" if boss.enraged else "")
		boss.health_bar.hide()

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _build_gate(index: int) -> void:
	var data: Dictionary = STAGES[index]
	var gate := StaticBody3D.new()
	gate.name = "ShadowSeal%d" % index
	gate.position = data.gate
	gate.collision_layer = 1
	gate.collision_mask = 0
	add_child(gate)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = data.gate_size
	shape.shape = box
	gate.add_child(shape)
	var veil := MeshInstance3D.new()
	veil.name = "Veil"
	var mesh := BoxMesh.new()
	mesh.size = data.gate_size
	veil.mesh = mesh
	var material := _emissive(Color(0.14, 0.045, 0.23, 0.65), 1.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil.material_override = material
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(veil)
	gates.append(gate)

func _set_marker() -> void:
	marker = Node3D.new()
	marker.position = STAGES[stage].trigger + Vector3.UP * 0.12
	add_child(marker)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.65
	ring.mesh = torus
	ring.material_override = _emissive(Color(1.0, 0.40, 0.07), 3.0)
	marker.add_child(ring)
	var label := Label3D.new()
	label.text = STAGES[stage].name
	label.position.y = 1.7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.modulate = Color(1.0, 0.63, 0.26)
	label.visibility_range_end = 30.0
	marker.add_child(label)
