# Ultimates

Fire and ultimate now share one spendable reserve (0–200 by default).
One compact track fills orange from 0–100, then violet fills over it from
100–200. Full violet pulses gently and unlocks the ultimate. There is no
separate bank: melee hits, charged slashes and passive decay all reduce
ultimate progress too. Fully filling either layer briefly protects it from
passive decay; spending fire ends that protection.

- **E — Inferno:** a 10 m area blast, 110 direct damage with distance falloff,
  followed by burning and stun. Level geometry blocks damage.
- **G — Ash Execution:** a focused 340-damage strike with burning and stun.
  Face a visible enemy within 16 m. Bosses ahead are prioritized. No target
  means no charge is spent. Nearby enemies take no collateral damage.

Both consume the entire shared fire reserve and play a short cinematic with a
blade windup, fire aura, release effects and camera recovery. The player is
protected and other combat actors freeze during the cinematic. Escape/menu
pause still works. No blade fire is retained after activation.

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
