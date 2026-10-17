extends Node3D
## Only the current encounter exists, so distant enemies do not simulate or
## chase through walls. Block D's open lobby and central corridor form the route.
const ENEMY := preload("res://assets/enemies/skeleton/shadow_enemy.tscn")
const MAGE := preload("res://assets/enemies/mage/shadowkin_mage.tscn")
const MUTANT := preload("res://assets/enemies/Mutant/mutant_boss.tscn")
const GREMLIN := preload("res://assets/enemies/gremlin/gremlin_enemy.tscn")
const OWL := preload("res://assets/npc/owl/owl_companion.gd")
const BARA_ARRIVAL := preload("res://final_boss_arrival.gd")
const WAYPOINT := preload("res://objective_waypoint.gd")
const RELIC_ROOM_PATH := "CampusMap/White Campus Extensions C and D/Block C/Floor 1 central corridor and classrooms/Lecture room C-101"
const RELIC_LOCAL := Vector3(-3.2, 4.35, -10.0)
const A_BLOCK_RELIC := Vector3(-0.1, 0.8, -6.2)
const MUTANT_LOCAL := Vector3(0.5, 3.45, -14.0)
const GREMLIN_SPAWNS := [
	[Vector3(33, 0.15, -76)],
	[Vector3(48.3, 0.4, -75.4)],
	[Vector3(48.45, 0.4, -84.5), Vector3(49.55, 0.4, -90.5)],
	[Vector3(48.45, 0.4, -97.5), Vector3(49.55, 0.4, -101)],
	[], # Boss fights are summon-free.
]
const PHASE_WARDEN_RELIC := 1
const PHASE_C101_RELIC := 2
const PHASE_MUTANT := 3
const PHASE_A_RELIC := 4
const PHASE_PORTAL := 5
const PHASE_FINAL_BOSS := 6
const PHASE_COMPLETE := 7
const FIRST_OWL_LINES: Array[String] = [
	"Salam Ustaad",
	"Ki Haal hai",
	"you have found the first relic",
	"Collect all 3 relics to break the portal and bring back peace at FAST",
	"find the next relic in C 101",
]
const FIRST_OWL_DURATIONS: Array[float] = [3.0, 3.0, 3.0, 5.0, 4.0]
const SECOND_OWL_LINES: Array[String] = ["the last relic is somewhere around A block"]
const SECOND_OWL_DURATIONS: Array[float] = [4.5]
const THIRD_OWL_LINES: Array[String] = ["Great, you have found all relics, rush to the roof of D block and break the portal"]
const THIRD_OWL_DURATIONS: Array[float] = [5.0]
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
var encounter_enemies: Array[CharacterBody3D] = []
var objective: Label
var boss_bar: ProgressBar
var boss_title: Label
var boss: CharacterBody3D
var mutant: CharacterBody3D
var bara: CharacterBody3D
var arrival: Node3D
var player: CharacterBody3D
var ui_clock: float = 0.0
var relic_phase: int = 0
var relic_count: int = 0
var relic: Node3D
var relic_base_y := 0.0
var owl: Node3D
var pending_mutant_spawn := false
var pickup_prompt: Label
var message_label: Label

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
	# Keep the first-floor hallway readable during the Mutant encounter.
	for p in [Vector3(49.4, 5.5, -61.0), Vector3(49.4, 5.5, -68.0)]:
		var hallway_light := OmniLight3D.new()
		hallway_light.position = p
		hallway_light.light_color = Color(0.67, 0.75, 1.0)
		hallway_light.light_energy = 1.45
		hallway_light.omni_range = 5.8
		hallway_light.shadow_enabled = false
		add_child(hallway_light)
	_set_marker()
	_update_hud()

func _process(delta: float) -> void:
	if completed or not is_instance_valid(player) or not player.is_alive:
		return
	if relic_phase == 0 and not active:
		var destination: Vector3 = STAGES[stage].trigger
		var offset := player.global_position - destination
		if Vector2(offset.x, offset.z).length() < (4.5 if stage == 0 else 2.5) and absf(offset.y) < 1.6:
			_start_encounter()
	if is_instance_valid(relic):
		relic.rotate_y(delta * 0.8)
		relic.global_position.y = relic_base_y + sin(Time.get_ticks_msec() * 0.002) * 0.12
		pickup_prompt.text = "Press O to collect relic"
		pickup_prompt.visible = player.global_position.distance_to(relic.global_position) < 2.2
	elif relic_phase == PHASE_PORTAL and _near_portal():
		pickup_prompt.text = "Press O to insert the 3 relics"
		pickup_prompt.show()
	else:
		pickup_prompt.hide()
	ui_clock += delta
	if ui_clock > 0.1:
		ui_clock = 0.0
		_update_marker_target()
		_update_hud()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(player) or not player.is_alive or not event is InputEventKey or not event.pressed or event.echo:
		return
	if player.is_using_ultimate:
		return
	if is_instance_valid(owl) and owl.get("is_intro") and owl.get("state") != "hidden":
		return
	if event.keycode == KEY_O and is_instance_valid(relic):
		if player.global_position.distance_to(relic.global_position) < 2.2:
			_collect_relic()
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_O and relic_phase == PHASE_PORTAL and _near_portal():
		_insert_relics()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_K and is_instance_valid(owl) and relic_phase < PHASE_FINAL_BOSS:
		if owl.call("call_owl", player, _owl_hint()):
			_update_hud()
			get_viewport().set_input_as_handled()

func _owl_hint() -> String:
	if relic_count == 0:
		return "Collect the relic dropped by the Ash Warden."
	if relic_count == 1:
		return "find the relic in C 101"
	if relic_count == 2:
		return "find the relic around A block"
	return "rush to the roof of D block and break the portal"

func _near_portal() -> bool:
	var world := get_parent().get_node_or_null("ShadowBreach")
	if world == null or not is_instance_valid(player):
		return false
	var point: Vector3 = world.gate_point
	var offset := player.global_position - point
	return Vector2(offset.x, offset.z).length() < 3.6 and absf(offset.y) < 2.4

func _start_encounter() -> void:
	active = true
	if stage == STAGES.size() - 1:
		_build_gate(stage) # Seal the rear doorway only after entering the boss court.
	defeated.clear()
	var base_count: int = STAGES[stage].spawns.size()
	alive = base_count + GREMLIN_SPAWNS[stage].size()
	_clear_marker()
	encounter_enemies.clear()
	for index in base_count:
		# One ranged caster supports each group; the final encounter retains its boss.
		var is_mage := stage < STAGES.size() - 1 and index == base_count - 1
		var enemy := (MAGE if is_mage else ENEMY).instantiate() as CharacterBody3D
		enemy.name = "Encounter%d_Shadow%d" % [stage + 1, index + 1]
		enemy.position = STAGES[stage].spawns[index]
		enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
		enemy.max_health = [80.0, 100.0, 110.0, 150.0, 450.0][stage]
		enemy.attack_damage = [12.0, 14.0, 15.0, 18.0, 23.0][stage]
		enemy.attack_timer = 0.5 + float(index) * 0.45
		if is_mage:
			enemy.max_health *= 0.85
			enemy.attack_cooldown = 2.8
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
		encounter_enemies.append(enemy)
		if enemy.is_boss:
			enemy.health_bar.hide()
	for index in GREMLIN_SPAWNS[stage].size():
		var gremlin := GREMLIN.instantiate() as CharacterBody3D
		gremlin.name = "Encounter%d_Gremlin%d" % [stage + 1, index + 1]
		gremlin.position = GREMLIN_SPAWNS[stage][index]
		gremlin.attack_timer = 0.8 + float(index) * 0.35
		gremlin.process_mode = Node.PROCESS_MODE_PAUSABLE
		gremlin.died.connect(_enemy_defeated.bind(gremlin.get_instance_id()))
		get_parent().add_child(gremlin)
		encounter_enemies.append(gremlin)
	_set_marker(STAGES[stage].trigger, "CLEAR " + STAGES[stage].name.trim_prefix("THE "))
	_update_marker_target()
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
		boss_bar.hide()
		boss_title.hide()
		relic_phase = PHASE_WARDEN_RELIC
		_place_relic_at(boss.global_position + Vector3(0.8, 0.8, 0.1), "WardenRelic", "ASH WARDEN RELIC")
		message_label.text = "THE ASH WARDEN HAS FALLEN"
		message_label.show()
		_ensure_owl()
		_start_warden_owl()
		_update_hud()
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
	pickup_prompt = Label.new()
	pickup_prompt.name = "RelicPickupPrompt"
	pickup_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pickup_prompt.position = Vector2(-170, -140)
	pickup_prompt.size = Vector2(340, 34)
	pickup_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_prompt.text = "Press O to collect relic"
	pickup_prompt.add_theme_font_size_override("font_size", 23)
	pickup_prompt.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	canvas.add_child(pickup_prompt)
	pickup_prompt.hide()
	message_label = Label.new()
	message_label.name = "EncounterMessage"
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message_label.position = Vector2(-320, 100)
	message_label.size = Vector2(640, 80)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 26)
	message_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.36))
	message_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	message_label.add_theme_constant_override("shadow_offset_x", 2)
	message_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(message_label)
	message_label.hide()
	boss_bar = preload("res://combat_health_bar.gd").new()
	boss_bar.bar_height = 6.0
	boss_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	boss_bar.position = Vector2(-140, -65)
	boss_bar.size = Vector2(280, 6)
	boss_bar.show_percentage = false
	boss_bar.fill_tint = Color(0.85, 0.19, 0.055)
	canvas.add_child(boss_bar)
	boss_title = Label.new()
	boss_title.name = "BossTitle"
	boss_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	boss_title.position = Vector2(-190, -128)
	boss_title.size.x = 380
	boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_title.add_theme_font_size_override("font_size", 18)
	canvas.add_child(boss_title)
	boss_bar.hide()
	boss_title.hide()

func _update_hud() -> void:
	if relic_phase == PHASE_WARDEN_RELIC:
		objective.text = "ASH WARDEN DEFEATED\nCollect the relic he dropped. Then find the next in C-101."
	elif relic_phase == PHASE_C101_RELIC:
		objective.text = "1/3 RELICS\nFind room C-101, Block C first floor. Press K to call the Owl."
	elif relic_phase == PHASE_MUTANT:
		objective.text = "2/3 RELICS\nDefeat the Mutant in the hallway. The final relic is around A block."
	elif relic_phase == PHASE_A_RELIC:
		objective.text = "2/3 RELICS\nFind the final relic by A block's domed entrance and fountain."
	elif relic_phase == PHASE_PORTAL:
		objective.text = "3/3 RELICS\nReach the exposed roof of D block. Press O near the portal."
	elif relic_phase == PHASE_FINAL_BOSS:
		objective.text = "BARA USTAAD\nDefeat him on D block's roof. Parry his strikes."
	elif relic_phase == PHASE_COMPLETE:
		objective.text = "PORTAL DEFENDER DEFEATED\nAll three relics have been brought to the portal."
	else:
		var data: Dictionary = STAGES[stage]
		var distance := player.global_position.distance_to(data.trigger)
		var hint: String = data.hint
		if active and not get_tree().get_nodes_in_group("mage").is_empty():
			hint = "Parry violet orbs into fireballs. Face the group to return an explosive blast."
		objective.text = "%d / %d  %s\n%s\n%s" % [stage + 1, STAGES.size(), data.name, hint, ("Shadows remaining: %d" % alive) if active else ("Follow the amber beacon — %dm" % int(distance))]
	var shown_boss: CharacterBody3D = null
	if relic_phase == 0:
		shown_boss = boss
	elif relic_phase == PHASE_MUTANT:
		shown_boss = mutant
	elif relic_phase == PHASE_FINAL_BOSS:
		shown_boss = bara
	if is_instance_valid(shown_boss) and not shown_boss.is_dead and (relic_phase == 0 or bool(shown_boss.get("engaged"))):
		boss_bar.show()
		boss_title.show()
		boss_bar.max_value = shown_boss.max_health
		boss_bar.value = shown_boss.current_health
		if shown_boss == bara:
			boss_title.text = "BARA USTAAD"
		elif shown_boss == mutant:
			boss_title.text = "THE MUTANT" + ("  -  RENEWED" if bool(mutant.get("flexed")) else "")
		else:
			boss_title.text = "THE ASH WARDEN" + ("  -  UNBOUND" if boss.enraged else "")
		shown_boss.health_bar.hide()
	else:
		boss_bar.hide()
		boss_title.hide()

func _place_relic() -> void:
	var room := get_parent().get_node(RELIC_ROOM_PATH) as Node3D
	_place_relic_at(room.to_global(RELIC_LOCAL), "C101Relic", "ROOM C-101")

func _place_relic_at(world_position: Vector3, relic_name: String, marker_text: String) -> void:
	relic = Node3D.new()
	relic.name = relic_name
	add_child(relic)
	relic.global_position = world_position
	relic_base_y = world_position.y
	var sphere := MeshInstance3D.new()
	sphere.name = "GlowingRelic"
	var mesh := SphereMesh.new()
	mesh.radius = 0.32
	mesh.height = 0.64
	sphere.mesh = mesh
	sphere.material_override = _emissive(Color(0.35, 0.8, 1.0), 4.0)
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	relic.add_child(sphere)
	var halo := OmniLight3D.new()
	halo.light_color = Color(0.3, 0.7, 1.0)
	halo.light_energy = 2.0
	halo.omni_range = 3.0
	halo.shadow_enabled = false
	relic.add_child(halo)
	_clear_marker()
	# The C-101 search is intentionally unguided: no floor or screen marker.
	if relic_name != "C101Relic":
		_set_marker(relic.global_position - Vector3.UP * 0.8, marker_text)

func _collect_relic() -> void:
	if not is_instance_valid(relic):
		return
	var collected_phase := relic_phase
	relic.queue_free()
	relic = null
	pickup_prompt.hide()
	_clear_marker()
	relic_count += 1
	message_label.text = "%d/3 relics collected" % relic_count
	message_label.show()
	if is_instance_valid(player):
		player.call("_add_camera_trauma", 0.28)
	if collected_phase == PHASE_WARDEN_RELIC:
		relic_phase = PHASE_C101_RELIC
		_place_relic()
	elif collected_phase == PHASE_C101_RELIC:
		relic_phase = PHASE_MUTANT
		pending_mutant_spawn = true
		_ensure_owl()
		owl.call("start_story", player, SECOND_OWL_LINES, SECOND_OWL_DURATIONS)
	elif collected_phase == PHASE_A_RELIC:
		relic_phase = PHASE_PORTAL
		_set_marker(get_parent().get_node("ShadowBreach").gate_point, "D BLOCK ROOF - PORTAL")
		_ensure_owl()
		owl.call("start_story", player, THIRD_OWL_LINES, THIRD_OWL_DURATIONS)
	_update_hud()
	if collected_phase == PHASE_WARDEN_RELIC:
		_hide_message_after(2.0, message_label.text)

func _hide_message_after(seconds: float, expected_text: String) -> void:
	await get_tree().create_timer(seconds, false).timeout
	if is_inside_tree() and message_label.text == expected_text:
		message_label.hide()

func _ensure_owl() -> void:
	if is_instance_valid(owl):
		return
	owl = OWL.new() as Node3D
	owl.name = "OwlCompanion"
	add_child(owl)
	owl.connect("orbit_finished", _owl_orbit_finished)
	owl.connect("story_finished", _owl_story_finished)

func _start_warden_owl() -> void:
	if player.is_using_ultimate:
		await player.ultimate_controller.ultimate_finished
	if is_inside_tree() and relic_phase == PHASE_WARDEN_RELIC and is_instance_valid(player) and player.is_alive:
		owl.call("start_story", player, FIRST_OWL_LINES, FIRST_OWL_DURATIONS)

func _owl_story_finished() -> void:
	if pending_mutant_spawn and relic_phase == PHASE_MUTANT:
		pending_mutant_spawn = false
		_place_mutant()
		message_label.text = "The second relic has alerted the Mutant"
		message_label.show()
		_hide_message_after(3.0, message_label.text)
	_update_hud()

func _place_mutant() -> void:
	var room := get_parent().get_node(RELIC_ROOM_PATH) as Node3D
	mutant = MUTANT.instantiate() as CharacterBody3D
	mutant.name = "MutantBoss"
	mutant.position = room.to_global(MUTANT_LOCAL)
	mutant.max_health = 675.0 # 1.5 times the Ash Warden's 450 HP.
	mutant.attack_damage = 25.0
	mutant.move_speed = 2.5
	mutant.attack_range = 1.9
	mutant.process_mode = Node.PROCESS_MODE_PAUSABLE
	mutant.died.connect(_mutant_defeated)
	mutant.engaged_player.connect(_update_hud)
	get_parent().add_child(mutant)
	mutant.health_bar.hide()
	_set_marker(mutant.global_position, "DEFEAT THE MUTANT")

func _mutant_defeated() -> void:
	if relic_phase != PHASE_MUTANT:
		return
	relic_phase = PHASE_A_RELIC
	boss_bar.hide()
	boss_title.hide()
	message_label.text = "THE MUTANT HAS FALLEN — SEARCH A BLOCK"
	message_label.show()
	_place_relic_at(A_BLOCK_RELIC, "ABlockRelic", "A BLOCK ENTRANCE")
	_hide_message_after(3.0, message_label.text)
	_update_hud()

func _owl_orbit_finished() -> void:
	message_label.hide()

func _insert_relics() -> void:
	if relic_phase != PHASE_PORTAL or relic_count != 3:
		return
	relic_phase = PHASE_FINAL_BOSS
	_clear_marker()
	pickup_prompt.hide()
	message_label.text = "THE THREE RELICS OPEN THE PORTAL"
	message_label.show()
	get_parent().get_node("ShadowBreach").energize_with_relics(player.global_position)
	arrival = BARA_ARRIVAL.new() as Node3D
	arrival.name = "BaraUstaadArrival"
	get_parent().add_child(arrival)
	arrival.connect("landed", _bara_landed)
	arrival.call("begin", player)
	bara = arrival.get("boss") as CharacterBody3D
	bara.died.connect(_bara_defeated)
	_update_hud()

func _bara_landed(_actor: CharacterBody3D) -> void:
	_set_marker(_actor.global_position, "BARA USTAAD")
	message_label.text = "BARA USTAAD"
	message_label.show()
	_hide_message_after(2.5, message_label.text)
	_update_hud()

func _bara_defeated() -> void:
	if relic_phase != PHASE_FINAL_BOSS:
		return
	relic_phase = PHASE_COMPLETE
	completed = true
	_clear_marker()
	boss_bar.hide()
	boss_title.hide()
	message_label.text = "BARA USTAAD HAS FALLEN"
	message_label.show()
	_update_hud()
	_finish_portal()

func _finish_portal() -> void:
	# A killing ultimate still owns its camera/actor snapshots until it ends.
	if player.is_using_ultimate:
		await player.ultimate_controller.ultimate_finished
	if is_inside_tree() and is_instance_valid(player) and player.is_alive:
		get_parent().play_ending.call_deferred()

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

func _set_marker(marker_position: Vector3 = Vector3.ZERO, marker_text: String = "") -> void:
	_clear_marker()
	if relic_phase == PHASE_C101_RELIC or completed:
		return
	marker = WAYPOINT.new()
	marker.name = "ObjectiveWaypoint"
	marker.player = player
	marker.caption = STAGES[stage].name if marker_text.is_empty() else marker_text
	marker.tint = Color(0.43, 0.88, 1.0) if is_instance_valid(relic) else Color(1.0, 0.65, 0.23)
	marker.position = (STAGES[stage].trigger + Vector3.UP * 0.12) if marker_text.is_empty() else marker_position
	add_child(marker)

func _clear_marker() -> void:
	if is_instance_valid(marker):
		# Hide synchronously so a collected relic never leaves a stale HUD pointer.
		marker.canvas.hide()
		marker.hide()
		marker.set_process(false)
		marker.queue_free()
	marker = null

func _update_marker_target() -> void:
	if not is_instance_valid(marker):
		return
	var target: CharacterBody3D = null
	if active and relic_phase == 0:
		var closest := INF
		for enemy in encounter_enemies:
			if not is_instance_valid(enemy) or enemy.is_dead:
				continue
			var distance := player.global_position.distance_squared_to(enemy.global_position)
			if distance < closest:
				closest = distance
				target = enemy
	elif relic_phase == PHASE_MUTANT:
		target = mutant
	elif relic_phase == PHASE_FINAL_BOSS:
		target = bara
	if is_instance_valid(target) and not target.is_dead:
		marker.global_position = target.global_position + Vector3.UP * 0.12
