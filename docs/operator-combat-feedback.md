# Operator combat feedback and range inspection

This update implements the explicitly approved presentation exception for the six regenerated operators. Combat damage, range definitions, targeting, cooldowns, progression, recruit media, and the existing game identity remain unchanged. All deployed operators, including recruits, support range inspection; only the six regenerated identities receive the new attack audio and particles.

| Identity | Attack audio | Particle presentation |
|---|---|---|
| Female Gunner | Bright, compact firearm report | Short amber muzzle flare, fine brass sparks and casing |
| Male Gunner | Lower, weightier rifle report | Blue-white shock ring, heavier streak and cooling motes |
| Female Swordmaster | Fast bright steel flick | Paired crimson/silver crescent trails |
| Male Swordmaster | Broad weighted slash | Teal/silver heavy arc and larger edge shards |
| Female Mage | Soft warm magical release | Amber ember motes and launch/impact rings |
| Male Mage | Crystalline frost snap | Cyan diamond shards and a luminous spell thread |

The four blade/magic cues were generated as sound effects. The initial firearm candidates were too mechanical; the accepted gunfire was extracted from an original built-in audio carrier, then separately equalized and pitch-shaped into bright and heavy reports. All final cues are mono OGG, peak-normalized to −14 dBFS with an additional −4 dB cue gain. Existing music and other SFX are unchanged. Final audio inspection found the firearm reports distinct and free of speech, music, and clipping. Actual browser listening remains the final subjective mix check.

`OperatorAttackFeedback` observes `last_attack_tick`, resolves the same identity as the sprite catalog, and emits once per new visible attack. It uses the validated sprite ground contact and visible height, never padded atlas dimensions. Its 32-burst cap, brief lifetimes, reduced-motion mode, camera culling, pause cleanup, and teardown keep work bounded. The central `Sfx` autoload retains its eight-voice pool, per-frame cue deduplication, existing bus/mute controls, and stream playback. New world cues are culled before voice allocation and stopped if their origin leaves view. No simulation randomness or state is changed.

Range painting uses `Targeting.omni_range_cells()` with the deployed unit's actual offsets, filtered to non-VOID map cells. It lives below actors under `GridRoot`, so camera pan/zoom/resize and elevated tile tops use the existing projection once. Hover temporarily overrides selection; leaving restores the selected operator. Empty clicks, Escape, interaction locks, and removed/dead units cannot retain stale selected coverage. Transient placement, heal targeting, pause, tutorial holds, and UI-owned pointer input suppress range inspection. Alpha-aware sprite picking ignores transparent padding and uses a bounded cache keyed by the underlying atlas region.

## Focused verification

Run `tools/run_godot_test.sh tests/operator_attack_feedback_test.gd` and `tools/run_godot_test.sh tests/operator_range_overlay_test.gd` for the new contracts. Related regressions cover operator auto-facing, four-direction sprites and unchanged recruits, UI audio, button feedback, Web audio unlock, pause menus, health/depth, and deployment icons. Native verification uses `test/operator_attack_visual_harness.gd` for every identity/facing and `test/operator_feedback_hud_capture.gd` for actual hover/click range states in landscape and portrait. Harness-only synthetic deployments do not change the playable simulation.

Final media lives in `assets/audio/operator_attacks/`, outside reserved template assets. Binary files are restored from runtime-owned `assets.lock.json`; text import sidecars remain tracked. The managed preview applies its existing `assets/template/` to `assets/upstream/` compatibility mapping without changing media bytes.
