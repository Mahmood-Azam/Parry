# Ultimates

Earn two fire bars' worth of parry fire (200 at the default meter size) to
bank one ultimate. Progress is separate from spendable blade fire and does
not decay. Parry fire still counts when the blade meter is already full.
The two segments at the bottom of the screen show the banked charge.

- **E — Inferno:** a 10 m area blast, 110 direct damage with distance falloff,
  followed by burning and stun. Level geometry blocks damage.
- **G — Ash Execution:** a focused 340-damage strike with burning and stun.
  Face a visible enemy within 16 m. Bosses ahead are prioritized. No target
  means no charge is spent. Nearby enemies take no collateral damage.

Both consume the same banked ultimate and play a short cinematic with a
blade windup, fire aura, release effects and camera recovery. The player is
protected and other combat actors freeze during the cinematic. Escape/menu
pause still works. Normal blade fire is retained.

For practice, **R twice** also charges one ultimate. New Game/respawn resets
the reserve. Cannot activate in midair, during hit stun, a dash, a melee
attack or fire channeling.

Validation with the project's Godot executable:

```
godot --headless --path . --script res://tests/ultimate_combat.gd
godot --headless --path . --script res://tests/ultimate_menu.gd
```

Run `ultimate_combat.gd` without `--headless` to capture the two cinematic
windups and impacts into `.godot/ultimate_*.png`.
