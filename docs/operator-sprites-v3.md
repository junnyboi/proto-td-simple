# Operator sprites V3

## Approved scope

This update replaces the male and female Gunner, Swordmaster, and Mage Apprentice battle-sprite families with six newly conceptualized identities. The two recruit families, their portraits, their animation resources, and recruitment behavior are excluded. The user explicitly approved the operator-art exception and delivery to the repository's existing `master` mainline. Gameplay rules, combat values, stage content, controls, audio, and the title/loading identity are unchanged.

The new reference sheets use the recruits only as a rendering-style and body-proportion benchmark. Existing advanced-operator artwork was not used as an identity reference. One accepted continuous silent carrier supplies every facing for each new character. The female Mage's first carrier was replaced after a concrete weapon-framing failure. All four facings are genuinely generated; no west-facing animation is mirrored. The catalog humanoid reference could not be retrieved in this session, as recorded in the implementation plan; no successful mannequin inspection or motion transfer is claimed.

## Runtime contract

| Property | Contract |
|---|---|
| Identities | `gunner_female`, `gunner_male`, `swordmaster_female`, `swordmaster_male`, `mage_apprentice_female`, `mage_apprentice_male` |
| Directions | NE, SE, SW, NW |
| Actions | Idle and attack, matching the existing stationary-operator action scope |
| Frames | 24 idle and 13 attack frames per facing; 888 frames across 48 sheets |
| Runtime cadence | Existing 12 FPS idle/attack contract retained; carrier time intervals recorded separately |
| Format | Lossless WebP with real alpha |
| Cell | 256 × 256 pixels, with additional transparent action clearance |
| Ground anchor | `(128, 196)` source-cell boundary; resource pivot `(0.5, 0.765625)` |
| Body calibration | 106 source pixels to 58 display pixels, matching recruit scale |
| Grounding | New operators use the isometric tile-top front/bottom corner; lift is applied once by the existing projection |
| Recruit behavior | Existing 192-pixel cells, pivots, scale, and two-direction compatibility remain unchanged |
| Storage | New media in `assets/operators/v3/`, restored from runtime-owned `assets.lock.json`; binary media is not committed |

Each character has one common scale and one measured neutral ground anchor per direction shared across its idle and attack frames. Changing silhouettes do not trigger per-frame centering or rescaling. Source intervals, hashes, anchors, and atlas metadata are recorded in `data/presentation/operator_sprites_v3.json`. The retained legacy aliases route old non-recruit operator entry points to the new identity families rather than leaving original artwork reachable through those deployment paths.

The presentation adapter supports explicit four-direction resources while retaining the recruit fallback. Health bars, skill bars, shadows, and facing indicators use a visible-body anchor instead of the enlarged transparent canvas. The simulation remains authoritative and unchanged.

## Asset production and recovery

`tools/operator_sprites/build_operator_sprites_v3.py` performs bounded extraction, chroma removal, shared-scale packing, and stable-anchor mapping. The male Gunner carrier used coral rather than the requested magenta, so it uses measured hue-aware keying and a bounded dark-rifle/body span to exclude a detached generated shot plume. Skin colors are retained. The registration tool updates the active visual resources and manifest without removing retained assets. The validation tool checks all frame cells, atlas hashes, alpha, common scale, fixed offsets, contact ranges, and the immutable recruit ledger.

Raw carriers, references, and individual frames are delivered separately rather than shipped in the playable pack. Install processing dependencies from `tools/operator_sprites/requirements-v3.txt`. In a configured Manus GameDev environment, use the existing asset hydration workflow to restore missing media from `assets.lock.json`; no local cache or authoring-machine path is required by the game.

## Verification

The focused checks cover the advanced schema, animation routing, every four-direction frame, recruit alignment, auto-facing, specialization/gender deployment, actual deploy-card image content, health/depth behavior, skill-bar layout, title-to-battle flow, pause menus, and Web audio unlock. The deploy-card test compares selected frame pixels rather than `AtlasTexture` instance identity because generated frames deliberately bypass the process-lifetime frame cache.

```bash
tools/run_godot_test.sh tests/advanced_operator_schema_test.gd
tools/run_godot_test.sh tests/advanced_operator_animation_test.gd
tools/run_godot_test.sh tests/operator_four_direction_test.gd
tools/run_godot_test.sh tests/recruit_animation_alignment_test.gd
tools/run_godot_test.sh tests/operator_auto_facing_test.gd
tools/run_godot_test.sh tests/operator_specialization_gender_deployment_test.gd
tools/run_godot_test.sh tests/deploy_bar_operator_icon_test.gd
tools/run_godot_test.sh tests/battle_health_and_depth_test.gd
tools/run_godot_test.sh tests/operator_sp_bar_layout_test.gd
```

The native harness uses the actual battle renderer, stable game state, and the same operator animation clock as production. It captures four facings per identity at idle, attack anticipation, strike, recovery, and returned idle. Landscape includes both recruit benchmarks; each portrait sweep includes its matching recruit. It asserts frame selection, template identity, common display calibration, and mapped ground contact. Fixture-only tracers are suppressed after assigning direction-consistent synthetic targets; no gameplay tracer code is altered.

```bash
xvfb-run -a tools/run_godot_isolated.sh --audio-driver Dummy \
  --rendering-method gl_compatibility \
  --script res://test/operator_v3_visual_harness.gd -- \
  --class gunner --output-prefix /absolute/output/gunner
```

Existing shutdown resource-in-use warnings in some test fixtures are distinguished from passing assertions. Browser sustained-play and input acceptance remain the user's final acceptance step; no routine browser-automation test is claimed. The managed project must be re-imported, exported, validated, and checkpointed separately from the original GitHub push.
