extends Node3D
## Project Eclipse survives the meteor and cannot be destroyed by combat.
## The future time-reversal ending removes it explicitly, not through damage.
var is_invulnerable := true

func take_damage(_amount: float, _attacker: Node = null, _attack_type: String = "environment", _attack_data: Dictionary = {}) -> bool:
	return false
