# Operator Sprite and Animation Regeneration: Implementation Plan

**Project:** Proto TD Simple / Game template - TD
**Author:** Manus AI
**Date:** 13 September 2026, Singapore time
**Source baseline:** `junnyboi/proto-td-simple`, `master`, commit `1e4f5d99fe67024f960fd193dbd1e3b4a29cb594`
**Status:** Technical inventory and production plan complete. Generation and implementation are not yet started. Upstream write authentication is blocked because the enabled GitHub CLI connector has not supplied `GH_TOKEN` to the execution environment.

## 1. Objective and authorized boundaries

Replace the six non-recruit operator identities with original directional character reference sheets and newly generated idle and attack animations. Their rendering style, visible body size, and planted-foot presentation must fit the existing recruits. Every supported tactical facing must display and attack in its correct isometric screen direction. The user has explicitly approved this scoped exception to the project’s visual-preservation rule and approved `master` as this task’s upstream mainline.

Male and female recruit artwork, animation sheets, portrait art, animation resources, and legacy facing behavior remain unchanged. Tactical rules, damage, attack ranges, cooldowns, target selection, campaign state, persistence, controls, audio, and unrelated visual assets remain unchanged. Existing operator artwork will not be supplied to image or video generation as character-identity references. Recruit artwork is permitted only as a style, proportion, scale, and ground-contact benchmark.

The latest upstream font and HUD changes are part of the starting baseline. They must not be replaced by the older managed-preview copy. The production work will not include gameplay mockups, a new title screen, or a game-wide redesign.

## 2. Findings that determine the implementation

The current presentation catalog contains male and female variants of Gunner, Swordmaster, and Mage Apprentice. It also contains legacy `sniper_1`, `guard_1`, and `caster_1` visual routes. Those routes must resolve to the corresponding new gendered specialization art so that old non-recruit sprites cannot remain reachable through a compatibility path. The tactical operator IDs and their statistics will remain unchanged. [1]

The animation schema currently admits only `ne` and `nw`. Its renderer maps both RIGHT and UP to `ne`, and both DOWN and LEFT to `nw`. Consequently, replacing images alone cannot satisfy the requested directional correctness. A backward-compatible presentation-schema extension is required. [2] [3]

| Contract | Observed baseline | Planned treatment |
|---|---|---|
| Recruit cells | 192 × 192 pixels | Preserve exactly; use this as the new runtime-cell target. |
| Recruit visible-body calibration | 106 source pixels mapped to 58 display pixels | Match the new characters’ head-to-ground body scale to this benchmark, excluding weapon reach. |
| Recruit contact pivot | `(0.5, 0.770833)`, approximately source point `(96, 148)` | Preserve recruits. Author and validate a stable new-character foot anchor rather than treating transparent padding as the foot position. |
| Idle animation | 24 frames at 12 FPS | Preserve the two-second playback cycle. |
| Attack animation | 13 frames at 12 FPS | Preserve existing visual playback and simulation timing; author readable anticipation, strike, and recovery. |
| Advanced existing art | 640-pixel cells and nominal 64-pixel display height | Do not inherit its larger scale or regenerate at the expense of recruit consistency. |
| Isometric tile | 64 × 32 pixels; elevation lift 16 pixels | Use actual projected tile geometry and apply elevation once. |
| Existing actor foot offset | Six pixels below face center | Do not globally change this and move recruits. Use an explicit new-schema ground-contact calculation for the replacement operators. |
| Existing processing | Rescales each frame to its longest visible edge | Do not reuse that normalization rule: a weapon swing would change apparent body size. |
| Optional advanced-art packs | Existing Web export excludes selected advanced operator atlases | Put the new, compact core operator atlases in an included project-owned directory so the replacements do not depend on an optional download. |

The proposed counts are **six new character sheets**, **six continuous animation carriers**, **48 directional animation atlases**, and **888 animation frames**: six characters × four directions × two actions, with 24 idle and 13 attack frames per direction. These are production targets, not completed outputs.

## 3. Original character design briefs

These working identity names identify production assets only. They do not rename classes or alter player-facing game terminology. Each design should be rendered as compact tactical RPG pixel art with the recruits’ restrained palette, readable small-scale shading, practical layered clothing, modest head proportions, and visible boots. Avoid photorealistic faces, glossy illustration rendering, oversized mascot heads, excessive filigree, floating garments, and weapons that hide the whole body.

| Runtime identity | New design direction | Readability and attack identity |
|---|---|---|
| `gunner_female` | **Ember Scout:** short dark braid, warm medium skin, cropped charcoal jacket, muted rust neck wrap, worn bronze fasteners, practical dark trousers. | Compact two-handed rifle; clear stock, barrel, recoil, and reset. No enormous scope or weapon silhouette that dominates the figure. |
| `gunner_male` | **Ashline Marksman:** close-cropped silver-brown hair, weathered face, desaturated navy field coat, pale ash scarf, brown leather shoulder reinforcement. | Distinct compact long gun with visible muzzle orientation and grounded firing stance. Preserve consistent handedness in every view. |
| `swordmaster_female` | **Cinder Duelist:** short ash-blond bob, brick-red fitted tunic, dark segmented hip protection, steel-grey gloves and boots. | One readable slender sabre. The strike arc extends along the target-facing axis and returns to a compact guard. |
| `swordmaster_male` | **Mossguard Blade:** chestnut hair tied back, muted olive surcoat, charcoal underlayers, narrow copper waist sash, restrained shoulder armour. | Long straight blade with a recognisable crossguard. Weight shifts stay inside the planted footprint; no root translation or unrequested lunging across tiles. |
| `mage_apprentice_female` | **Amber Scribe:** dark coiled hair, muted indigo wrap coat, ochre cuffs, fitted trousers, visible sturdy boots, a small belt-bound spellbook. | Short staff with a restrained amber focal stone. Cast gesture and staff tip point along the correct tactical facing. |
| `mage_apprentice_male` | **Slate Channeler:** swept-back grey hair, warm brown skin, short slate robe over dark trousers, subdued teal bindings, ivory-tipped staff. | Readable hand-and-staff channeling motion. No levitation, floor-covering robe, or large effects baked into the body atlas. |

Each character receives a single reference sheet showing **NE, SE, SW, and NW** views in an unambiguous fixed layout. Every view must depict the same identity, clothing, proportions, weapon, handedness, and orthographic-style camera elevation. The sheet must show the full body and complete weapon with enough separation to extract individual facing references. Identity references will be newly generated; the old operators will not be used.

## 4. Reference-sheet production and acceptance

First, record hashes of all recruit sprite and portrait files and their presentation resources. Extract representative recruit cells into the external production workspace for style and geometry inspection. This extraction will not edit the source files. Measure the alpha bounds, head-to-foot distance, visible foot contact, and body-to-cell proportions across representative recruit idle and attack frames.

Generate the six original directional reference sheets using the user’s preferred built-in image-generation family. Inspect each sheet for identity consistency across its four views, the correct camera angle, complete weapons, distinct front/back views, and a rendering style compatible with the recruits. Correct only material failures before generating that character’s animation carrier. The user has already authorized autonomous reference creation and execution; no additional aesthetic approval round is needed.

Extract a clean, single-character facing reference from each accepted view. Match every video reference image to the carrier’s landscape aspect ratio without distorting the character. The new sheets remain the character-appearance authority throughout animation and processing.

The required Manus humanoid motion-reference catalog was queried, but the service returned an invalid verified-snapshot/index error. No mannequin reference was retrieved or inspected. This is an explicit reference-access limitation, not evidence that the collection does not exist. These operators require stationary idle and attack actions, not walking. Production may continue from the verified game-facing geometry and newly authored directional poses; it must not claim conformity to an unavailable mannequin reference. If the catalog becomes available before generation, inspect the matching facing references without broadening the action scope.

## 5. Continuous directional animation production

Generate **one continuous, silent carrier per character**, not a separate clip per facing. A carrier will show one full-body character at a fixed world-space foot point under an absolutely locked camera. It will cover all four facings and both required actions. The character turns between clearly separated action windows; transition frames will not enter the runtime animation loops.

Use a flat chroma background selected to avoid the character’s palette. Keep the full character and weapon visible throughout. Do not include scenery, floor texture, cast shadows, text, duplicate figures, camera motion, reframing, or independent changes in body size. Use all four accepted directional references to preserve front/back differences and meaningful weapon handedness. **No direction is planned as a mirrored substitute.**

| Planned carrier window | Content | Extraction policy |
|---|---|---|
| First direction block | NE idle, NE attack, return to guard | Select one clean idle cycle and a complete attack/recovery window. |
| Second direction block | SE idle, SE attack, return to guard | Exclude the preceding turn; verify that the front-right view is not mislabeled NE. |
| Third direction block | SW idle, SW attack, return to guard | Keep weapon handedness consistent; do not mirror a conflicting asymmetric design. |
| Fourth direction block | NW idle, NW attack, return to guard | Exclude turn frames and retain the complete final recovery. |

The initial carrier target is 28–30 seconds at 720p. Exact time windows will be recorded from the generated result rather than assuming prompt timing was followed perfectly. The processor will preserve the existing 24/13-frame and 12-FPS runtime contracts. If a generated segment cannot provide a complete required motion without identity loss, clipping, or unusable keying, regenerate only that character’s continuous carrier. A static duplicate masquerading as an animation is not an acceptable fallback.

## 6. Extraction, scale, and ground-contact normalization

Extract candidate source frames and remove the chroma background with soft-edge treatment and spill removal. Keep lossless alpha in the final lossless WebP atlases. Preserve weapons, fingers, hair, and narrow enclosed gaps. Reject residual matte rectangles, colored fringes, detached noise, missing limbs, and clipped weapon tips.

Use **one body-scale calibration across all actions and facings for a character**. The calibration is based on head-to-ground body height, not the changing bounding-box diagonal or maximum weapon extent. Use a common crop/canvas and a stable contact anchor for the complete character set. Do not independently stretch or rescale individual attack frames to fill the cell.

The runtime target is a 192 × 192 cell with a 106-pixel neutral body height and a documented foot anchor aligned consistently with the recruit reference scale. The target visible in-game body height is 58 pixels at the baseline camera and presentation settings. Weapon motion is allowed to occupy the surrounding transparent clearance but not to change body scale. If a valid attack cannot fit with clearance, enlarge the common canvas and migrate that character’s geometry contract consistently rather than shrinking isolated frames or clipping the weapon.

For the new presentation schema, map the visible foot-contact point to the tile’s projected top-face front/bottom corner: `face_center(cell, lifted) + Vector2(0, TILE_H * 0.5)`. Apply the elevation lift exactly once. Keep the existing recruit pivot and foot-offset path intact. Preserve the operator node’s tile ownership, picking, and painter-depth contract. Attack anticipation and recovery must return to the same grounded contact point without per-frame size jumps or lateral anchor drift.

Pack eight columns per atlas. Idle atlases contain three rows of 24 frames; attack atlases contain two rows with 13 used cells. Manifests will record frame rectangles, FPS, loop policy, body height, contact point, character identity, action, direction, source carrier, extracted time interval, and hashes. Record all generated versus derived operations accurately.

## 7. Godot integration changes

| Owner | Planned change | Preservation boundary |
|---|---|---|
| `operator_animation_def.gd` | Add a new schema version supporting exact NE/SE/SW/NW maps and the new sprite geometry. | Existing schema 1/2 resource validation remains supported; recruit resources remain unchanged. |
| `operator_animator.gd` | Select four-direction art for new-schema animations using actual isometric projection. | Preserve old two-direction selection for recruit/legacy schema resources. Do not change tactical facing values or attack clocks. |
| `operator_visual_catalog.gd` | Resolve the six new identities and map non-recruit legacy operator routes to their corresponding new specialization identities. Validate every declared direction. | Preserve deterministic gender selection and all recruit routes. |
| Six specialization `.tres` resources | Register new four-direction idle and attack maps, body calibration, common cell size, and stable pivot. | Keep tactical operator IDs and statistics unchanged. |
| Asset presentation manifest | Register 48 unique sequence IDs with exact source paths, geometry, and provenance. | Preserve unrelated logical IDs and fail-closed duplicate detection. |
| `battle_view.gd` | Apply new-schema contact geometry consistently in creation, projection, and refresh paths. | Do not move recruit nodes, change target legality, alter simulation, or apply elevation twice. |
| Sprite processing/registration tools | Add the continuous-carrier, four-direction workflow and shared-body-scale normalization. | Do not run the old south-direction-pruning or per-frame longest-edge rescaling logic on the new set. |
| Web export | Include the new core operator atlas directory and required manifests. | Do not make replacement art depend on optional content packs or accidentally re-export old unreferenced operator art. |
| Deployment icons | Ensure icons derived from live animation art select the matching new identity. | Do not redesign HUD layout or regenerate unrelated portrait screens. |

The correct mapping under the current projection is:

| Logical `UnitState.Facing` | Cell-space direction | Screen-space facing |
|---|---|---|
| RIGHT | Positive X | SE, down-right |
| DOWN | Positive Y | SW, down-left |
| LEFT | Negative X | NW, up-left |
| UP | Negative Y | NE, up-right |

Animation is strictly a presentation of authoritative state. The new assets must not move simulation hit timing, change cooldowns, derive new damage, or modify attack targeting to compensate for incorrect art. Existing attack/projectile effects remain separate from character-body generation. Verify the visual weapon axis and effects against actual target direction in the game.

## 8. Verification and acceptance gates

| Gate | Evidence required | Failure response |
|---|---|---|
| Preservation | Hash match for recruit art/resources and a scoped source diff excluding unrelated changes. | Restore accidental edits before continuing. |
| Reference identity | Four consistent, complete facing views per new character, matching recruit style. | Correct the affected reference before animation. |
| Asset integrity | 48 valid transparent sequences, 888 declared frames, expected dimensions/FPS, nonempty content, and valid provenance. | Reprocess or regenerate only the failing character or segment source. |
| Proportion and grounding | Stable body scale and contact across directions, idle, attack, and recovery. | Fix the common crop, anchor, or resource contract; do not hide drift with per-frame scaling. |
| Direction selection | Deterministic tests for RIGHT→SE, DOWN→SW, LEFT→NW, UP→NE, plus unchanged recruit mappings. | Correct presentation mapping without changing simulation. |
| Legacy coverage | Legacy `sniper_1`, `guard_1`, and `caster_1` entry points show the new corresponding class art. | Repair catalog routing, not tactical identities. |
| Real rendered game | Native viewport captures with a real renderer showing both genders, all four facings, idle/strike/recovery, ground/elevated placement, representative zoom settings, and recruits for size comparison. | Fix the observed presentation defect and recapture affected views. |
| Regression | Existing relevant recruit, advanced-animation/schema, auto-facing, depth, deployment-icon, pause, and layout tests pass with justified contract updates. | Fix concrete failures; do not weaken tests merely to accept missing directions. |
| Web packaging | Current exported PCK contains and loads the new atlases/fonts/manifests without private source paths or optional-pack dependence. | Repair resource references and export inclusion. |
| Upstream delivery | Validated changes are merged and pushed to upstream `master`; required branch rules and CI are respected. | Stop and report the exact authentication, permission, conflict, or review blocker. |
| Managed delivery | Current source is integrated into the managed project, exported, checkpointed, and published through the available workflow. | Distinguish checkpoint success from publication and public artifact access. |

Native rendered captures—not headless Dummy screenshots—establish visual evidence. Tests will use the repository’s isolated runners so verification does not damage player saves. A bounded video/frame-sequence inspection will check real continuity; a single static pose cannot prove animation quality or attack direction.

Browser acceptance remains a separate final check for input, audible audio, pause/retry, persistence, and sustained play. The prior public deployment returned HTTP 403 for its game-pack URL during verification; do not claim that issue is resolved without a successful current access check or user confirmation.

## 9. Execution order and delivery artifacts

| Phase | Deliverable | Completion condition |
|---|---|---|
| 1. Preconditions and baseline | Approved scope/mainline, source revision, recruit hash ledger, measured geometry, authentication check. | Current upstream preserved; write delivery available or explicitly blocked. |
| 2. Original references | Six complete four-direction character reference sheets and identity notes. | All references pass the scoped visual checks. |
| 3. Continuous animation | Six silent multi-direction carrier videos with recorded accepted windows. | Every required action/direction is extractable. |
| 4. Runtime processing | Transparent frame sequences, 48 atlases, manifests, and geometry reports. | Alpha, scale, anchor, timing, and direction checks pass. |
| 5. Integration | New presentation schema, catalog/renderer updates, resources, and Web inclusion. | Every reachable non-recruit operator uses the new set; recruits are unchanged. |
| 6. Verification | Deterministic results, native grounding/facing captures, and isolated exported-pack checks. | No unresolved required acceptance failure. |
| 7. Source-control delivery | Focused commit/PR where required, merge to `master`, and verified upstream push. | Remote mainline contains the validated work without bypassing protections. |
| 8. Managed delivery | Updated GameDev project, current artifacts, checkpoint, publication status, and concise handoff. | Actual successful outcomes are linked and remaining user acceptance is explicit. |

Source reference sheets, video carriers, prompts, and detailed processing evidence live outside the shipped Godot resource tree. Only final runtime media and necessary metadata enter the game. New game media uses a semantic project-owned directory, not `assets/template`. The managed project’s asset-retention manifest and template provenance remain owned by the normal runtime pipeline. The existing `assets/template` → `assets/upstream` import mapping must be preserved for unchanged upstream media.

The final handoff will include the implementation plan, new reference sheets, an archive of final transparent sprite atlases/manifests, the upstream commit or PR result, and the current managed preview checkpoint. It will explicitly state which checks ran and any remaining browser/publication limitations.

## 10. Current blocker and safe stopping point

The GitHub CLI connector is enabled and reports a stored masked `GH_TOKEN` configuration, but `GH_TOKEN` is absent from the actual execution environment. The authenticated repository check therefore cannot run. The token value has not been read, copied, or exposed. No new operator image, video, or game-source implementation has been generated yet, and no source changes are awaiting push.

Reconnect or refresh the GitHub CLI credential through Manus Settings, ensure that it is available to this task, and then resume. The available configuration tools can enable connectors for the current task but cannot set credential availability for every task account-wide. The user’s request to apply the PAT to all tasks therefore remains an account-level configuration action rather than an operation performed by this plan.

## References

[1]: https://github.com/junnyboi/proto-td-simple/blob/1e4f5d99fe67024f960fd193dbd1e3b4a29cb594/data/presentation/operator_visual_catalog.gd "Operator presentation catalog and legacy routes"
[2]: https://github.com/junnyboi/proto-td-simple/blob/1e4f5d99fe67024f960fd193dbd1e3b4a29cb594/data/presentation/operator_animation_def.gd "Operator animation resource contract"
[3]: https://github.com/junnyboi/proto-td-simple/blob/1e4f5d99fe67024f960fd193dbd1e3b4a29cb594/scripts/view/operator_animator.gd "Directional animation selection and playback"
[4]: https://github.com/junnyboi/proto-td-simple/blob/1e4f5d99fe67024f960fd193dbd1e3b4a29cb594/data/presentation/operator_visuals/recruit_male.tres "Preserved recruit animation geometry"
[5]: https://github.com/junnyboi/proto-td-simple/blob/1e4f5d99fe67024f960fd193dbd1e3b4a29cb594/scripts/view/iso_projection.gd "Isometric tile projection and contact geometry"
[6]: https://github.com/junnyboi/proto-td-simple/blob/1e4f5d99fe67024f960fd193dbd1e3b4a29cb594/tools/operator_sprites/build_advanced_operator_sprites.py "Existing sprite extraction and normalization pipeline"
[7]: https://cli.github.com/manual/gh_repo_view "GitHub CLI repository access verification"
