# Campus map

Imported environment from the user-provided GameDevy campus project.

`campus.tscn` retains the supplied baked buildings, interiors, vegetation,
materials, lighting, and collision geometry. Shader and texture dependencies
are self-contained in `art/`. The source project's player, overview cameras,
editor generation script, and day/night HUD are intentionally not included.

The environment is instantiated as `CampusMap` in `res://main.tscn`. Its
`campus_runtime.gd` applies the night lighting, rendering presets, evenly
sampled spatial vegetation chunks, and static architecture instancing. Original
terrain and building collisions are retained. Performance is the default preset.

The player starts at `(35, 0.15, -73)`. `res://encounter_director.gd` owns five
sequential encounters: courtyard (2 enemies), entrance (2), corridor (3), elite
rearguard (2), then the Ash Warden (1). Amber beacons and an objective HUD guide
the player through Block D. Clearing encounters opens shadow seals and restores
25 health. The Warden enrages at half health; victory unlocks exploration or a
new game. New game and respawn reset the full route.

Keep the map's process mode Pausable so future ambient effects respect menus.
The enemy retains its existing direct-chase AI, not campus-wide navigation.

Display: F11 / Alt+Enter toggles desktop-native fullscreen. Escape pauses and
opens the menu. Options includes fullscreen and Performance/Balanced/High.
Settings are stored in Godot's per-user data folder, not in the map files.

Regression checks (run from the project with the Godot executable):

```
godot --headless --path . --script res://tests/campus_smoke.gd
godot --headless --path . --script res://tests/campus_route_walk.gd
```

The smoke test checks wave progression, boss enrage, victory, restart, and
vegetation reduction. The route test physically walks the player from courtyard
to boss entrance without teleporting or jumping, clearing test enemies on the way.
