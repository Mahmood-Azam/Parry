# Solid portal

The portal uses one world-layer StaticBody3D with a fitted, double-sided concave collision surface. Mesh transforms are baked after the imported model is normalized, so the stairs, base and portal opening follow the visible model instead of a rooftop-sized bounding box. Walking and swept dash movement collide normally.

Collision geometry uses imported low-detail index buffers (53,642 triangles versus 1,489,672 visual triangles) and is cached across instances/new games. It adds no per-frame geometry generation. Existing player stepping can climb the machine's stairs, and a player-sized standing position remains inside the relic interaction radius.

The opening temporarily disables portal collision for cinematic arrivals. Gameplay restores it; the ending disables it before shrinking the machine. Hiding the portal always removes its world collision, avoiding invisible walls after campus restoration. Combat damage still cannot destroy it.

`tests/portal_collision.gd` checks player/dash sweeps from four ground directions and both sides of the upper opening, visibility/cinematic lifecycle, interaction clearance and time-restoration cleanup.
