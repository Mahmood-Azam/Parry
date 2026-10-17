# Salam Ustaad greeting

Only the first-story line matching `Salam Ustaad` triggers the greeting. During its existing three-second duration, the owl lowers beside the player and turns toward them, the player's empty left hand reaches out, and the near wing extends its feather tip into that palm. Both use the same animated world-space contact point for two small synchronized shakes. The sword stays attached to the right-hand hilt socket throughout.

Temporary `SkeletonModifier3D` two-joint reaches layer over the existing human idle and owl flight animations. The actual owl upper-wing, forewing, hand and feather-tip bones are used; no proxy wing or whole-body rotation substitutes for the reach. Reach influence and body approach blend in/out before the next line. A slightly closer, collision-checked three-quarter camera shows the contact.

Dialogue advancement, interruption and scene teardown remove both modifiers and restore the existing combat-arm modifier's enabled state. Later clue visits do not replay the greeting. Player physics/input stay locked for the story and restore through the existing Owl lifecycle; player position and sword mounting are unchanged.

`tests/owl_handshake.gd` verifies real BoneAttachment palm/feather-tip contact, shake movement, preserved feet/sword mount, timing, cleanup and interruptions. Rendered snapshots: `.godot/owl_handshake_*.png`. `tests/owl_encounter.gd` covers the timed dialogue and clue lifecycle.
