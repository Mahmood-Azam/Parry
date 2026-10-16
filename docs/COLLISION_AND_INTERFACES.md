# Parry or Perish — Shared Interfaces & Collision Contracts

This document defines the shared interfaces and contracts established by Developer 1 (Player, Parrying & Shadow) for seamless integration with Developer 2 (Heat/Time), Developer 3 (Enemies/Projectiles), and Developer 4 (Arena/UI).

---

## 1. Physics Collision Layers & Masks (3D)

| Layer # | Layer Name      | Value | Description |
|---------|-----------------|-------|-------------|
| 1       | `World`         | 1     | Static geometry, floor, arena boundaries, walls |
| 2       | `Player`        | 2     | Player CharacterBody3D physical collision |
| 3       | `Enemies`       | 4     | Enemy CharacterBody3D physical collision |
| 4       | `PlayerHitbox`  | 8     | Player attack/parry detection Area3D |
| 5       | `EnemyHitbox`   | 16    | Enemy melee attack Area3D |
| 6       | `Projectiles`   | 32    | Arrows, fireballs, projectiles |

---

## 2. Player Damage & Parry Interface (`Player`)

When an enemy attack or projectile reaches the player, it calls:
```gdscript
player.take_damage(amount: float, attacker: Node = null, attack_type: String = "melee", attack_data: Dictionary = {}) -> bool
```

### Return Value
- `false`: Attack was **parried** or **evaded** (no health lost).
- `true`: Damage was **applied** to player's health.

### Directional Parry Rule
- Parrying is directional: the player must face towards the incoming attack source within `parry_max_angle` (default: **75°**, creating a 150° forward protection arc).
- Attacks from behind or the rear flanks bypass parry and deal full damage to the player.
- For projectiles (arrows), pass `attack_data = {"direction": projectile_velocity.normalized()}` or `attacker` node.

---

## 3. Player Signals (For Dev 2 Heat & Dev 4 UI)

| Signal | Arguments | Description |
|--------|-----------|-------------|
| `health_changed` | `(current_health: float, max_health: float)` | Emitted when health changes. Useful for Dev 4 HUD. |
| `damaged` | `(amount: float, attacker: Node)` | Emitted when player receives actual damage. |
| `died` | `()` | Emitted on player death. Dev 4 listens to show defeat screen. |
| `parry_started` | `()` | Emitted the instant parry stance begins. |
| `parry_success` | `(attacker: Node, is_perfect: bool, attack_data: Dictionary)` | **CRITICAL FOR DEV 2**: Dev 2 listens to grant heat and trigger time-slow if `is_perfect == true`. |
| `parry_failed` | `()` | Emitted when a parry expires without deflecting an attack (whiff). |
| `dash_started` | `(direction: Vector3)` | Emitted when Shadow Dash begins. |
| `dash_finished` | `()` | Emitted when Shadow Dash ends. |
| `attack_pressed`| `()` | Emitted when attack button is clicked (hook for Dev 2 heat attacks). |

---

## 4. Input Map Actions

- `move_forward`: W / Up Arrow
- `move_backward`: S / Down Arrow
- `move_left`: A / Left Arrow
- `move_right`: D / Right Arrow
- `parry`: Right Mouse Button / F / Q
- `dash`: Space / Shift
- `attack`: Left Mouse Button
