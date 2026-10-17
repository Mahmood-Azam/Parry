# Sword sounds and mixed gremlin encounters

The supplied `sword.zip` contains one 0.30-second stereo WAV. Its original audio is copied to `assets/audio/sword_attack.wav`; archive import-cache metadata is deliberately not reused. The player's SwordSwingSound routes through Master, so the Options volume controls it. Each of the three melee phases emits one slightly pitch-varied swish at 28% of its authored phase, before contact at 55%. Queuing clicks cannot play future sounds early. Empty-fire swings and misses still sound; JumpAttack also has a swish. Existing parry and enemy audio are unchanged.

Gremlins no longer spawn periodically during the Mutant fight: the summon method, timer, spawn coordinates and special cleanup are removed. Instead the regular courtyard/lobby/corridor/rearguard waves include 1/1/2/2 gremlins alongside their skeletons and mage. Boss waves remain summon-free. Their deaths are included in the encounter count, gate unlocking, objective tracking and portal-opening arrival sequence.

Gremlins have 24 HP (two full-fire basic hits), 6 damage, 4.8 m/s movement, faster acceleration/turning, a small 0.78 m collider and faster scurrying animation. Their club attack remains readable and parryable with 1.45 s cooldown and no skeleton triple-combo execution. Existing separation, line of sight, territory leash, burn and death handling remain intact.

Validation: `tests/player_sword_audio.gd`, `tests/gremlin_combat.gd`, `tests/portal_arrivals.gd`, `tests/breach_intro.gd` and `tests/campus_smoke.gd`.
