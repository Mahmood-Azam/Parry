extends Node
## Minimal gameplay presentation. Menus retain their labels and controls.
## Alpha suppression survives existing show()/hide() calls in encounter logic.
func _ready() -> void:
	_strip(get_parent())
	get_tree().node_added.connect(_on_node_added)

func _strip(node: Node) -> void:
	_suppress(node)
	for child in node.get_children():
		_strip(child)

func _on_node_added(node: Node) -> void:
	if node is Label or node is RichTextLabel or node is Label3D or node.name == &"SpeechBubble":
		_suppress_id.call_deferred(node.get_instance_id())

func _suppress_id(node_id: int) -> void:
	var node := instance_from_id(node_id) as Node
	if is_instance_valid(node):
		_suppress(node)

func _suppress(node: Node) -> void:
	if not is_instance_valid(node) or not get_parent().is_ancestor_of(node):
		return
	var ancestor := node
	while ancestor != get_parent():
		# Opening story presentation and front-end menus are not the gameplay HUD.
		if ancestor.name in [&"FrontEndLayer", &"OpeningCinematic", &"OwlDialogueLayer"] or node.name == &"RelicPickupPrompt":
			return
		ancestor = ancestor.get_parent()
	if node is Label or node is RichTextLabel:
		node.self_modulate.a = 0.0
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif node is Label3D:
		node.transparency = 1.0
	elif node is Control and node.name == &"SpeechBubble":
		node.modulate.a = 0.0
