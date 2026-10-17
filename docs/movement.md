# Fast traversal controller

The active controller is `player_controller.gd` on `main.tscn`'s Player.

- WASD: camera-relative movement, 5.8 m/s. Shift: 8.6 m/s sprint.
- Vector acceleration, faster reversals, controlled braking, and partial air control.
- Q: directional Shadow dash. No direction held uses character facing. Starts
  at 19 m/s, eases toward traversal speed, and preserves exit momentum.
  Duration 0.28 s, protection 0.16 s, start-to-start cooldown 1.25 s.
  The dash decoy lasts 1.0 s so it cannot permanently distract enemies.
  A 0.12 s input buffer accepts slightly early presses. The decoy still spawns
  at departure. Dash can cancel melee or guard, not hit stun/channel/ultimate.
- RMB: existing parry-then-block; movement while guarding is 70% normal speed.
- Space: buffered/coyote-time jump, with a quicker gravity-driven arc. Air dash
  does not freeze vertical motion. Expired jump requests no longer fire later.
- Automatic stepping up to 0.42 m and descending floor snap up to 0.45 m.
  Full-body up/forward/down sweeps require clearance and a walkable landing.
  A short flat cylinder sole complements the capsule so rounded capsule edges
  do not snag curbs. High walls and low overhangs still block movement.
- Run/walk playback follows actual speed; dash lean eases in/out without the old
  vertical bob or restoring stale camera yaw. Camera step-height compensation
  smooths curb changes, with a subtle movement/dash field-of-view increase.

Movement and dash values are exported for tuning. Combat targeting, parry
windows, damage, fire and ultimate economy are unchanged.

## Validation

Run Godot with `--headless --path . --script tests/player_movement.gd` for the
real controller physics tests. Omit `--headless` to capture running/curb/dash
frames in `.godot/movement_*.png`. Tests cover speeds, reversing, braking,
curbs/stairs/slopes, ceilings/walls, dash collisions and momentum, blocking,
damage locks, jumping and air dash landing.

`tests/campus_route_walk.gd` walks the actual campus route without jumping.
`tests/mutant_integration.gd` and `tests/ultimate_combat.gd` cover combat compatibility.
