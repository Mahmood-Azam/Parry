extends SceneTree

const OWL := preload("res://assets/npc/owl/owl_companion.gd")
var owl: Node3D
var player: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func advance(seconds: float) -> void:
	# Drive the Owl's state machine without waiting through the dialogue in real time.
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
	check(owl.get("state") == "hidden", "Owl should start hidden")
	check(not owl.call("call_owl", player), "Owl must not be callable before the introduction")
	owl.call("start_intro", player)
	check(owl.get("state") == "orbit", "Introduction must start with a flight")
	advance(2.8)
	check(owl.get("speech").text == "salam ustaad", "First line should appear after one orbit")
	advance(3.0)
	check(owl.get("speech").text == "you have just found a relic, collect 4 more of these, and then with the relics and my powers, we can make a time machine", "Second line should follow after three seconds")
	advance(5.0)
	check(owl.get("speech").text == "with that, we can reverse the meteor attack and bring back peace at FAST", "Third line should follow after five seconds")
	advance(5.0)
	check(owl.get("state") == "poof" and owl.get("poof_node") != null, "Owl should poof after the dialogue")
	advance(0.65)
	check(owl.get("state") == "hidden" and owl.get("intro_seen"), "Owl should become callable after its introduction")
	check(owl.call("call_owl", player), "K should summon the Owl")
	advance(2.3)
	check(owl.get("state") == "waiting" and owl.get("speech").text == "Did you get all 5 relics?", "Summoned Owl should ask about relics")
	check(owl.call("interact", 1), "O should answer the Owl")
	check(owl.get("state") == "poof", "Owl should leave when fewer than five relics are held")
	advance(0.65)
	check(owl.call("call_owl", player), "Owl should be summonable again")
	advance(2.3)
	check(owl.call("interact", 5), "O should answer the Owl with five relics")
	check(owl.get("speech").text == "Great, go to the Nascon Ground and use the time machine!", "Owl should give the Nascon Ground direction")
	advance(4.0)
	check(owl.get("state") == "poof", "Owl should poof after the success line")
	print("PASS Owl orbit, timed dialogue, poof, summon and both relic outcomes")
	quit()
