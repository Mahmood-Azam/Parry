extends Node
## One owner for short, real-time impact pauses. Never stack slow-motion timers.
var remaining_until := 0
var previous_scale := 1.0
const IMPACT_SCALE := 0.08

static func request(parent: Node, duration: float) -> void:
	if not is_instance_valid(parent) or parent.get_tree().paused:
		return
	var pause := parent.get_node_or_null("CombatHitPause")
	if pause == null:
		pause = new()
		pause.name = "CombatHitPause"
		pause.process_mode = Node.PROCESS_MODE_ALWAYS
		parent.add_child(pause)
	if pause.remaining_until == 0:
		pause.previous_scale = Engine.time_scale
		Engine.time_scale = IMPACT_SCALE
	pause.remaining_until = maxi(pause.remaining_until, Time.get_ticks_msec() + int(duration * 1000.0))

func _process(_delta: float) -> void:
	if remaining_until > 0 and Time.get_ticks_msec() >= remaining_until:
		_restore()

func _restore() -> void:
	if remaining_until > 0 and is_equal_approx(Engine.time_scale, IMPACT_SCALE):
		Engine.time_scale = previous_scale
	remaining_until = 0

func _exit_tree() -> void:
	_restore()
