# Integration: Parry-ShadowBorn (2).zip

Merged against the earlier `Parry-ShadowBorn.zip` snapshot, preserving the
current project's mage, reflected fireballs, ultimates, and fullscreen fixes.

Incoming additions:

- Classroom doors and their blocking collisions removed from the campus.
- Additional quality-dependent detail culling and shadow reductions.
- After the Ash Warden, an objective leads to the relic in room C-101.
- **O** collects the relic and starts the Mutant encounter (675 HP).
- Mutant model, idle/walk/punch/jump/flex/death clips and spatial sound effects.
- Mutant punches are parryable. Its jump bypasses parry/block and can be
  evaded with Shadow protection. Its low-health flex restores health once.

Shared code was combined so that Mutant parries still bank ultimate fire,
focused ultimates recognize the Mutant as a boss, and cinematic/menu pause
behavior remains intact. The boss bar sits above the ultimate reserve HUD.

The incoming chapter currently ends after the Mutant with **1/5 relics**.
The archive does not implement the other four relic objectives.

Validation:

```
godot --headless --path . --script res://tests/campus_smoke.gd
godot --headless --path . --script res://tests/mutant_integration.gd
godot --headless --path . --script res://tests/mage_combat.gd
godot --headless --path . --script res://tests/ultimate_combat.gd
godot --path . --script res://tests/fullscreen_input.gd
```

The ZIP's Git repository, editor caches, and macOS sidecar files were not
imported into the project. Current shared scripts were backed up in the
ignored `.godot/integration_backup/` directory before the three-way merge.
