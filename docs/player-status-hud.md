# Player status HUD and Shadow balance

The compact upper-left panel shows labeled current/max health, total fire (0–200 by default), ultimate percentage or ready bindings, Shadow recharge (Q), and guard/parry state (RMB/F). Holding a charged slash temporarily replaces the ultimate line with charge percentage and the release hint. The single orange/violet layered fire meter is unchanged: attacks, charging, decay and ultimate activation still share one resource. Low health gets a subdued red label; enemy bars remain small.

Only `PlayerStatusHUD` is exempted from gameplay text suppression. Old debug stats, damage/parry text pop-ups and the fill-fire button stay absent. Menus, narrative/ending UI and world presentation retain their existing behavior. The panel inherits the player's gameplay pause and cinematic visibility.

Shadow now has a **1.25 s start-to-start cooldown**, **0.16 s protection**, and a **1.0 s decoy**. The 19 m/s initial burst, 0.28 s traversal, momentum exit and short input buffer are unchanged. The decoy expires before another dash can recharge, preventing permanent aggro diversion. Recharge stops while paused. Other attack/parry timing and enemy recovery are unchanged.

Verification: `tests/player_status_hud.gd`, `tests/player_movement.gd`, and the shared-meter/combat regression tests. Rendered HUD captures: `.godot/status_hud_*.png`.
