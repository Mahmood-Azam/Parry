# Objective markers

One active destination is shown as a small amber diamond with a title and distance, plus a pulsing ground ring. Offscreen destinations become an edge arrow; objectives on another floor show ABOVE/BELOW. Relic markers are cyan. This is destination guidance, not wall-aware pathfinding.

The encounter route marks the next courtyard/doorway/corridor. During combat it follows the nearest surviving member of the current wave, then advances only when the wave is cleared. The Warden's dropped relic, Mutant, A-block relic, D-block rooftop portal, and final boss all receive markers at their respective progression stages.

**C-101 is intentionally unmarked**, including its room, building, and collectible. The first relic clears the previous waypoint immediately; the phase also refuses accidental marker creation. Existing Owl dialogue, classroom signage, visible relic and close-range O pickup prompt are preserved so players can search normally. Guidance resumes after collecting it.

Markers hide during menus, death and cinematic cameras and never intercept mouse input. They adapt to viewport size with screen-edge padding and use no additional shadow-casting lights or particles. The text policy exempts only the waypoint subtree, leaving debug text hidden.

Checks: `tests/objective_waypoints.gd` exercises projection, behind-camera arrows, pause/resume, text visibility, C-101 exclusion, portal elevation and enemy tracking. `tests/campus_smoke.gd` verifies markers across the full relic/boss progression.
