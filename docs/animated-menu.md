# Animated front end

The existing ShadowBorn key art is retained and enhanced with a front-end-only atmosphere layer:

- Slowly moving/parallax artwork, flickering blade warmth, violet backlight and a soft vignette.
- Procedural turbulent fire along the lower screen and right edge, with drifting haze.
- Two depth layers of warm, additive embers (94 particles total).
- Dark left-side shading, serif title treatment, chapter/lore details, corner rules and footer accents.
- Warm charcoal/copper panels, a distinct New Game action, hover/focus glows and sliding chevrons. Button focus/hover subtly increases the fire's intensity.

Options, death and victory panels share the updated theme; existing menu actions, settings and controls remain unchanged. The Options scroll area stays on the left. Layout uses the logical viewport so fullscreen/native resolution does not change UI proportions.

`menu_atmosphere.gd` updates its own shader clock in PROCESS_MODE_ALWAYS so gameplay stays paused while menu effects move. All decorative controls ignore mouse input. Hiding the title background immediately stops the atmosphere's updates and disables both particle emitters; gameplay and HUD-only victory views do not pay the animation cost. Opening/ending cinematic transitions keep their existing ownership of the camera and pause state.

No downloaded assets or movie loops are required: `assets/ui/menu_art.gdshader` and `assets/ui/menu_fire.gdshader` implement the new visual motion. The original background image is unchanged.

Validation: `tests/menu_atmosphere.gd` checks animation while paused, unchanged player position, decorative input transparency, layout, hover/focus, Options/Back/Continue, and effect suspension/restoration. Rendered checks save `.godot/menu_home.png`, `menu_home_later.png`, `menu_hover.png` and `menu_options.png`. Existing options and cinematic tests cover the retained settings and game transitions.
