extends SceneTree

const OWL := preload("res://assets/npc/owl/owl_companion.gd")
var owl: Node3D
var player: Node3D
var stories := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func advance(seconds: float) -> void:
	owl.call("_process", seconds)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	player = Node3D.new()
	scene.add_child(player)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 3, 5)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	camera.make_current()
	owl = OWL.new() as Node3D
	scene.add_child(owl)
	owl.set_process(false)
	owl.connect("story_finished", func(): stories += 1)
	check(not owl.call("call_owl", player, "find the relic in C 101"), "Owl must not be callable before Warden defeat")
	var first_lines: Array[String] = [
		"Salam Ustaad", "Ki Haal hai", "you have found the first relic",
		"Collect all 3 relics to break the portal and bring back peace at FAST",
		"find the next relic in C 101",
	]
	var first_durations: Array[float] = [3.0, 3.0, 3.0, 5.0, 4.0]
	owl.call("start_story", player, first_lines, first_durations)
	check(owl.get("state") == "orbit", "First story must begin with one circle")
	advance(2.8)
	for index in first_lines.size():
		check(owl.get("speech").text == first_lines[index], "Wrong first-story line %d" % index)
		advance(first_durations[index])
	check(owl.get("state") == "poof" and owl.get("poof_node") != null, "Story must end with visible poof")
	advance(0.65)
	check(stories == 1 and owl.get("intro_seen"), "Owl should become callable after first story")
	check(owl.call("call_owl", player, "find the relic in C 101"), "K should call the Owl")
	advance(2.3)
	check(owl.get("speech").text == "find the relic in C 101", "Owl should give the current clue")
	advance(4.0)
	advance(0.65)
	check(owl.call("call_owl", player, "find the relic around A block"), "Owl should be callable again")
	advance(2.3)
	check(owl.get("speech").text == "find the relic around A block", "Owl should update the clue")
	advance(4.0)
	advance(0.65)
	var final_lines: Array[String] = ["Great, you have found all relics, rush to the roof of D block and break the portal"]
	var final_durations: Array[float] = [5.0]
	owl.call("start_story", player, final_lines, final_durations)
	advance(2.8)
	check(owl.get("speech").text == final_lines[0], "Final story must point to D block roof")
	advance(5.0)
	advance(0.65)
	check(stories == 2 and owl.get("state") == "hidden", "Final Owl story must finish cleanly")
	print("PASS Owl timed first story, stage clues, circling and poof")
	quit()
