# Final ending — FAST restored

Killing Bara Ustaad in the final relic phase triggers an approximately eleven-second in-engine ending. If the killing blow is an ultimate, the ending waits for that cinematic to restore its actors/camera before taking ownership. Duplicate death notifications cannot start another ending.

The player is protected, transient combat actions are cleared, and gameplay actors/projectiles are frozen. Before any building collision is restored, the player is moved to an open field near (18, 0, -55). A ground ray and full player-capsule clearance check choose the spawn; alternate nearby candidates are tried if needed.

The meteor rises from the impact site and retraces its original approach, the explosion clip plays backward, rubble gathers into the damaged buildings, and the portal contracts. The camera follows the meteor onto a new trajectory away from FAST. Darkness smoothly changes to the restored daylight sky. The final shot displays:

> YOU SAVED FAST SUCCESSFULLY
>
> The meteor has been redirected to NUST.

After this message, the supplied 3.8-second NUST meteor-impact video plays fullscreen with its original audio. The project includes a Theora/Vorbis copy at `assets/cinematics/ending/nust_impact.ogv` for native Godot playback; the original MP4 is not changed. The video preserves 16:9 with black letterboxing on other aspect ratios, routes audio through Master volume, and keeps gameplay frozen. Its last 0.7 seconds smoothly fade both picture and audio to black/silence using decoded playback time. A brief black hold precedes the result menu; skipping still finishes immediately.

The paused victory menu then offers Explore, New Game and Home over the restored campus. Explore returns to the normal player camera, grounded on the field with motion/stun/dash/charge states reset. Space, Enter or Escape skip the cinematic or the video but still finish restoration and the safe relocation. Video completion/skip stops its audio; a timeout fallback prevents a decoder failure from trapping the result. Gameplay's text policy explicitly permits ending titles; transient boss-defeat text is cleared.

Bara Ustaad's visual bounds are normalized to 8.6 m, slightly larger than the portal's 8 m span. His collision capsule is resized and positioned from the feet upward. The arrival shot pulls back and aims higher to frame the giant without scaling the CharacterBody or animation rig bone translations independently.

Validation: `tests/breach_ending.gd` follows the actual three-relic arrival, boss death, complete ending, paused result menu, Explore and an early skip. Rendered captures are saved under `.godot/ending_*.png`.
