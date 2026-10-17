# Short Shadow Breach opening and reversible campus damage

## Playing it

Select **New Game** from the home menu. A 12.6-second in-engine opening plays:

1. Daylit campus establishing shot and incoming meteor.
2. Meteor strikes the upper right-side buildings; the imported explosion's
   `Take 001` animation plays with impact light, debris, dust and sound.
3. The blast uncovers the existing gate on the surviving roof slab. The
   machine stays full-size and flashes a protective field while the surrounding
   floors collapse; its damage interface always rejects damage.
4. The actual first-wave skeleton and mage emerge through the rooftop gate,
   cross its steps, and descend into the courtyard. They remain inert during
   the movie and become the first playable encounter, without duplicate spawns.
5. A visible purple pulse travels from the portal to the actual playable
   character. Only after exposure does he demonstrate Shadow Dash and leave
   behind his own silhouette.
6. Brief **FAST: THE SHADOW BREACH** title, then gameplay control returns.

**Space, Escape or Enter skips.** Continue and Respawn bypass the opening.
Gameplay actors, encounters, markers and HUDs are frozen/hidden while it plays.
Player camera, position, input, invulnerability, lighting and HUDs are restored
on completion, skip, or scene teardown. Skip does not also trigger a jump.

This is the requested short functional version using existing game art, not
the full classroom/student/voice-acted 30-second production. Cinematic sound
cues are synthesized locally and obey the Options master volume.

## Imported user assets

- `assets/cinematics/breach/meteor.glb`
- `assets/cinematics/breach/meteor_explosion.glb`
- `assets/cinematics/breach/star_x_gate-zeta.glb`

`breach_world.gd` normalizes their differing scales. The gate and a meteor
remnant remain on the map after the intro. They add no route-blocking physics.
The portal is anchored at `(47, 6.56, -81)` on the exposed Block D roof, not
on courtyard ground. `breach_gate.gd` makes it immune to damage; the future
ending still removes it explicitly through the restoration hook.
`breach_intro.gd` controls the opening timeline; `breach_audio.gd` supplies cues.

## Buildings and the future ending

Story intent explicitly reserved for later development:

**Recover every relic → insert them into the portal → form a time machine →
reverse the breach and restore the university as though it never happened.**

The present game only has its existing partial relic progression. That is not
treated as collecting all relics, and the ending is not automatically triggered.

`campus_destruction.gd` creates a separate reversible damage layer for the
right-side C/D building footprint. Upper storeys/roofs are removed, tall visual
trim is shortened, associated collision is disabled, and falling concrete
fragments settle outside the entrance. Ground-floor routes and the first-floor
relic room remain intact. Rubble uses one 48-instance MultiMesh, not a large
number of simulated rigid bodies.

### The intact campus is preserved

The source **`assets/maps/campus/campus.tscn` is not edited or destructively
replaced**. Original mesh transforms, visibility, collision flags, decorative
labels and affected runtime batch instance transforms are snapshotted before
damage. All original nodes remain available; this is not irreversible deletion.
New scene loads reconstruct the same intact baseline before applying damage.

### Future integration hook

Once the full quest and time-machine sequence are implemented, call:

```gdscript
await get_node("ShadowBreach").restore_campus(2.5)
```

This reverses the fragment motion, restores the saved structural/collision
state, and removes the meteor, scorch and portal visuals. It is a tested
structural restoration hook, **not the completed ending**. Future ending work
still needs the full relic check, insertion animation, time-machine sequence,
return to peaceful daytime, enemy removal and final narrative/game-state reset.
Restoration currently returns the pre-impact game-map art; it does not repaint
the map's pre-existing weathering/graffiti or invent a populated campus.

For immediate structural reset, use `CampusDestruction.restore_intact()`.
For gameplay aftermath/replay, use `ShadowBreach.show_aftermath()`.

## Verification

- `tests/breach_intro.gd`: rendered timeline captures, all three assets,
  explosion animation, destruction timing, power-before-dash, HUD hiding,
  camera/control restoration, Space skip and menu pause afterward.
- `tests/portal_arrivals.gd`: actual wave identity/count, mid-emergence Escape
  skip, restored AI/collision/visibility/animation and portal invulnerability.
- `tests/campus_destruction.gd`: damaged upper collisions, safe relic room,
  reversal and exact restoration of saved transforms/visibility/collisions.
- `tests/campus_route_walk.gd`: continuous courtyard-to-boss walk through the
  damaged map, without jumping or teleporting.

Use Godot `--path . --script tests/breach_intro.gd` to render; add `--headless`
for automated checks. Captures are under `.godot/breach_*.png`.
