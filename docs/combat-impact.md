# Combat impact feedback

Successful damage on skeletons, mages and the Mutant now triggers a brief warm
mesh overlay, additive chest recoil, sparks/contact ring and a short synthesized
crunch/thud. Guard impacts use blue feedback and a distinct metallic contact.
Feedback does not add damage, move colliders, change attack timings, increase
stun durations or change the fire requirement for melee damage.

`combat_impact.gd` caches feedback per actor and restores original mesh overlays.
Small damage-over-time ticks and the debug kill-all command do not spam effects.
`combat_recoil.gd` adds recoil to the existing animated chest joint, including
the original skeleton's anonymous chest bone, without moving feet or weapon mounts.

Confirmed player melee hits receive 35 ms of impact slowdown and a small camera
impulse. Misses and rejected damage do not trigger this hit confirmation. Taking
damage receives the existing 60 ms impact pause, a red screen pulse, body recoil
and stronger camera feedback; blocking gets a lighter 25 ms pause and blue pulse.
Camera feedback now updates during damage stun (previously an early return
silently disabled it). The old whole-character bouncing hit pose is replaced by
a small settling lean plus localized torso recoil.

`combat_hit_pause.gd` owns the shared real-time slowdown. Overlapping hits extend
one deadline rather than stacking timers or capturing an already-slow time scale.
Menu pause is respected and scene cleanup restores speed safely.

Validation: run `--path . --script tests/combat_impact.gd` in Godot for rendered
feedback captures under `.godot/impact_*.png`, or add `--headless` for automated
checks. Covers all enemy rigs, material restoration, audio, burn suppression,
actual melee confirmation, player damage/block, camera response during stun,
overlapping pauses, menu pause and scene teardown. Piercing slash, Mutant combat
and ultimate regressions are also covered by their existing tests.
