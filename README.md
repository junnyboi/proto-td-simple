# Game Template — Deterministic Isometric Tower Defense

This repository is a reusable **Godot 4.7.2** template for a small isometric tower-defense game. It already contains a playable start-to-results loop, deterministic combat, responsive English/Simplified-Chinese UI, pause and speed controls, a first-stage tutorial, runtime tweak controls, local-first leaderboards, and a lightweight Node global leaderboard service.

> **Agent directive:** Reskin presentation before changing game authority. `Game` owns routes, `BattleModel` owns tactical truth, and `CampaignStateV3` plus the save store own strategic truth. UI, art, VFX, audio, and leaderboards must remain projections or bounded services.

## Template snapshot

| Capability | Current implementation |
|---|---|
| Engine | Godot `4.7.2`, Forward Plus; do not silently upgrade the project format. |
| Main loop | Loading → Start → Campaign mission selection → Battle → Results. |
| Stages | Ten authored `StageDef` resources, `s1`–`s10`. A new fork can expose only `s1`/`s2`, but deleting the others is a migration; see [Stage count](#stage-count-one-or-two-stage-forks). |
| Tactical deck | Fixed **repeat-purchase** pool `[recruit, sniper_1, guard_1, caster_1]`: duplicates are legal while DP, an empty cell, and the stage living-unit cap permit them. Fixed-deck retreats refund 50% and have no redeploy cooldown. |
| Core rules | Integer-tick deterministic simulation, explicit paths/waves, ground/elevated placement, weighted blocking, aerial enemies, traps, skills, leaks, stars, restoration cells, and high-threat warnings. |
| UI | Title, Campaign, Battle HUD/deployment deck, pause/settings/resign, Results, and leaderboard. GUI focus supports keyboard/controller accept/cancel; tactical play and map navigation are pointer/touch-first. |
| Tutorial | `FirstStandTutorial` plays on every eligible campaign `s1` attempt; a separate one-time portrait pan hint is also active. |
| Languages | Main player screens use `en-US` and `zh-CN`, catalog validation, a bundled CJK font, and 80–150% text scale. F10 developer tuning and `[TWEAKED]` remain English-only. |
| Tuning | F10 opens 58 local developer overrides. Gameplay overrides can affect campaign and leaderboard runs; `[TWEAKED]` is disclosure only, not eligibility or saved provenance. |
| Leaderboard | Every accepted `s1`–`s10` clear or defeat records locally first; optional Node synchronization is summary-only and non-authoritative. |
| Audio | Central `Music` uses two crossfade players; `Sfx` uses eight round-robin voices. Both use direct streaming; browser AudioContext unlock is best-effort. |
| VFX | Procedural/transient 2D nodes through `JuiceLayer`; no `GPUParticles2D`/`CPUParticles2D` dependency. |
| Web delivery | Web is the only checked-in export preset. Advanced operator art packs are optional and stage as three verified PCKs; host argument injection remains a manual integration. |

## Quick start

```bash
git status --short
godot --version                 # must be 4.7.2.stable-compatible
godot --path .
```

The main scene is `res://scenes/loading.tscn`. Loading opens the Start screen. **Start always opens Campaign mission selection**; even a durable interrupted mission resumes only after the player explicitly selects that mission.

`Loading` is a fixed **1.8-second visual bridge plus a 0.35-second fade**. Its progress is cosmetic: it does not poll assets, validate campaign data, or wait for content packs, and it has no boot error/retry state. Optional pack configuration begins later at Title.

For a safe import and bounded boot:

```bash
tools/run_godot_isolated.sh --headless --import
tools/run_godot_isolated.sh --headless --fixed-fps 60 --quit-after 120
```

Use `tools/run_godot_test.sh` for supported headless GDScript targets under `test/` or `tests/`; use `tools/run_godot_isolated.sh` for imports, controlled Godot tools, and visual harnesses. Both isolate `user://` and add fail-closed guards, but source-linked files and the shared `.godot` import cache are not immutable. Direct repository-test invocations intentionally fail closed to protect playable saves.

## Architecture: know what you are allowed to change

| Layer | Source of truth | Safe responsibility | Never do here |
|---|---|---|---|
| Boot and routes | `project.godot`, `autoloads/game.gd` | Loading, screen swaps, launch/result sequencing. | Replace `Game.content` or call raw scene changes from arbitrary UI code. |
| Tactical simulation | `sim/battle_model.gd`, plain `sim/*` state | Validate actions, advance ticks, determine terminal outcome. | Derive damage, legality, rewards, or results in the view. |
| Strategic campaign | `sim/campaign_state_v3.gd`, `sim/campaign_v3_*` | Commands, receipts, stage progression, rewards. | Mutate campaign dictionaries or saves directly. |
| Durable saves | `sim/campaign_save_store.gd`, `sim/campaign_runtime_authority.gd` | Exact-byte compare-and-swap, recovery, certified publication. | Recreate a command when retrying a failed save. |
| Authored content | `data/**/*.tres`, matching schemas | Stages, operators, enemies, traps, skills, campaign data. | Treat loaded resources as mutable runtime state. |
| UI and view | `scripts/ui/*`, `scripts/view/*` | Input adaptation, layout, animation, localization, state projection. | Become a second tactical or strategic authority. |
| Presentation services | `Art`, `Music`, `Sfx`, `JuiceLayer` | Resolve and present assets. | Affect battle hashes, tickets, saves, or gameplay RNG. |
| Runtime tweaks | `RuntimeTweakCatalog`, `TweakControls` | Sanitize and persist local deltas; adapt copied inputs. | Write `_values` or source `.tres` files directly. |
| Leaderboard | `autoloads/leaderboard.gd`, `server/leaderboard_server.mjs` | Local ledger and optional global standings. | Gate mission completion or claim authenticated anti-cheat. |
| Optional packs | `autoloads/content_pack_loader.gd` | Verified, cached, add-only presentation resources. | Replace core files or make gameplay depend on a download. |

### Runtime-global lifecycle

Autoload declaration order is an integration boundary. `project.godot` initializes `TestRunGuard`, `CursorManager`, `I18n`, `Music`, `TextScale`, `UiFeedback`, `ContentPacks`, `Leaderboard`, `Game`, `Sfx`, then `TweakControls`. Later services may rely on earlier state. A new persistent service needs explicit exit cleanup and must join Clear Player Data if it writes or retains user state.

### Route, result, and integrity contract

`Game` is the only route owner. `_swap_content()` mounts a candidate before retiring the incumbent; strict startup validation and rollback apply specifically to Battle candidates (`startup_succeeded` plus a `BattleModel`). Do not infer equivalent rollback guarantees for every non-Battle screen. `Game.start_battle()` and non-campaign `start_stage()` are compatibility/test seams, not the normal Title flow. [1]

Campaign stages durably commit `begin_attempt` before Battle opens. One unresolved ticket restricts post-restart selection to its matching stage; selecting it starts a **fresh battle from that ticket**, not a mid-battle resume. There is no tactical action log, restorable battle snapshot, or committed-attempt abandon action.

At terminal state, Battle renders its stamp/audio, waits one frame to prepare the result, and a second frame to commit `resolve_attempt`. Continue remains disabled until that durable commit succeeds; failure exposes **Retry Finalization** and blocks Results navigation. Retry the retained `CampaignMutation` against the same preimage; never reconstruct its command, ticket, or outcome. [1] [2]

The production slot is `user://campaign_v1.json` despite V3 contents. Main, `.tmp`, `.bak`, and `.invalid` form a conservative recovery protocol: valid main wins; recovery candidates must not conflict; unrecoverable candidates are quarantined before a fresh generation. Legacy/pre-command data may decode as migration input but cannot continue as an authenticated V3 command ledger, so the runtime rolls it into a fresh Recruit generation. Clear persisted player data only through `Game.clear_player_data()`.

> **Integrity boundary:** Tickets and outcomes are canonical SHA-256 self-consistency documents checked against local trusted hashes; they are not digital signatures, replay proofs, or server-certified combat. V3 resolution validates ticket/outcome consistency but does not re-simulate tactics. `state_hash()` is a signed 64-bit FNV-1a dynamic-state divergence digest, not a complete content/configuration fingerprint. `BattleSnapshot` is an aggregate HUD/result projection and has no restore API. [2]

### Current campaign loop

A new V3 campaign begins with **five persistent Recruit witnesses**, **120 Marks**, no clears, no campaign traps/entitlements, and one 80-Mark Recruit contract. The witness roster is not the tactical deck: shipping Campaign launch tickets the first persistent hero as a witness, while Battle deploys the fixed repeat-purchase four-card pool.

Stages unlock sequentially. S1 starts available; any 1–3-star clear unlocks the next stage; cleared stages remain replayable; stars only improve. Every first clear grants **40 Marks**, plus Spike Plate at S2 and Tar Pit at S3. A successful replay grants **20 Marks**; defeat grants none. Marks cap at 1,000,000,000. [3]

The active Campaign screen contains operation cards, Back, and Settings only. It has no shipped squad selector, Barracks, recruitment, promotion, training, memorial, or roster screen. Results currently grant no permanent death, XP, class entitlement, or promotion. Related classes, commands, fields, and helpers are extension/compatibility surfaces, not live progression.

## Recommended fork workflow

1. **Create a style brief.** Define genre, audience, palette, lighting, character proportions, UI materials, icon language, and audio identity before generating assets.
2. **Rename presentation first.** Update `project.godot` title, both localization catalogs, and UI copy through `UiCopy`; do not rename internal IDs yet.
3. **Choose the visible stage scope.** Start with `s1` and `s2`. Hide later stages before attempting a destructive campaign-schema reduction.
4. **Reskin shared UI.** Change shared style helpers, frames, icons, cursors, and fonts before editing individual screens.
5. **Replace world art.** Generate title/loading art, Campaign backdrop, terrain surfaces, endpoints, and optional restoration/high-threat art.
6. **Replace characters.** Start with the five core visual templates and core enemy set. Keep logical IDs, frame geometry, feet/pivots, and import policy stable.
7. **Replace audio.** Generate one loopable BGM master, then replace static SFX behind existing logical cue IDs.
8. **Tune rather than fork.** Use F10 controls for rapid iteration, then promote accepted values into authored resources/catalog defaults.
9. **Translate and test.** Update English and Simplified Chinese together, then run only the focused gates affected by the change.
10. **Export and host.** Export the Web preset, run the same-origin leaderboard service if required, and perform one browser smoke.

## Full reskin asset plan

### Minimum asset set

| Asset group | Minimum playable fork | Complete reskin | Contract |
|---|---:|---:|---|
| Loading/title background | 1 | 1 | `assets/loading/lunaris_reliquary_loading.png`, 2560×1440, 16:9, top-pinned cover crop. |
| Campaign background | 1 | 1 | `assets/loading/command_backdrop.png`, currently 1920×1080. |
| Terrain surfaces | 4–6 | 11 | 512×512 seamless textures in `assets/terrain/proto_isometric/`; renderer UV-maps them onto isometric diamonds. |
| Core operator templates | 5 | 11 | Core: `recruit_female`, `recruit_male`, `sniper_1`, `guard_1`, `caster_1`. Complete catalog also includes six gendered specialization templates. |
| Portraits | 5–8 | 17 | Current portrait files are 512×512; keep stable logical portrait IDs where possible. |
| Enemy bodies | 4 | 9 | Eight static 640×640 enemies plus Grunt’s directional route/fallback. |
| World foregrounds | 2 | 3 | Spawn portal, base crystal, and optional restoration seal under `assets/world/`. |
| UI frame textures | 4 | 8 | Nine-slice-compatible transparent frames under `assets/ui/staging/frames/`. |
| UI icons | 4 | 8 | Transparent icons under `assets/ui/staging/icons/`. |
| Cursors | 3 | 11 | 32×32 semantic cursors; update hotspots with dimensions. |
| Tutorial callouts | 3 | 3 | Route, deploy gesture, and block shield art under `assets/tutorial/`. |
| Combat VFX | 5 | 7+ | Five common small effects plus high-threat art; retain alpha, footprint, and filter assumptions. |
| BGM | 1 | 1 master | Loopable 48 kHz stereo OGG, routed through existing logical cue resources. |
| SFX | Existing set | Existing set or replacements | Short static WAVs routed through `assets/sfx/catalog.tres`. |

### Image-generation workflow

Use **GPT Image 2** for new images and UI art. Generate high-resolution masters first; keep prompts, references, model/version, and provenance outside the runtime asset tree, then commit only optimized runtime derivatives and required metadata.

1. Generate one representative **visual target** containing the world palette, one operator, one enemy, terrain, and UI material cues.
2. Lock a reusable style vocabulary: perspective, line weight, rendering method, saturation, material response, silhouette complexity, and lighting direction.
3. Generate every requested item as a standalone image. Do not ask the model to pack unrelated runtime assets into one board.
4. Generate text-free game art. UI copy is rendered by Godot so it can localize and scale.
5. Inspect each master once for crop, anatomy, perspective, alpha/fringe, and consistency. Regenerate only a critical failure.
6. Downscale/crop/convert with deterministic image processing. Preserve aspect ratio and alpha; never stretch art to meet a target.
7. Replace files behind stable IDs when possible, import in Godot, then run the matching focused test.

#### Prompt templates

**Title/loading background**

```text
Create a 16:9 game title background for an isometric tactical tower-defense game.
Subject: [world, landmark, atmosphere].
Composition: 2560x1440, strongest focal detail in the upper half, horizontally centered, lower third quiet enough for UI, portrait-safe central subject, no critical detail near edges.
Style: [locked style vocabulary and palette].
Text/content: no text, no logos, no UI.
Constraints: opaque background, no characters cut by the frame, readable after a top-pinned cover crop.
Avoid: centered-vertical composition that loses the subject in portrait, busy UI zone, fake typography.
```

**Seamless terrain surface**

```text
Create a seamless square terrain material for an isometric tower-defense board.
Subject: [sand / wetland / snow / basalt / ruin material].
Composition: 512x512 tileable surface texture, uniform scale, no baked diamond border, no isolated landmark, no directional camera perspective.
Style: [locked style vocabulary], readable at small size.
Text/content: no text.
Constraints: seamless on all four edges, restrained lighting, no hard shadow that reveals repetition.
```

**Operator static master**

```text
Create one full-body adult tactical-chibi operator for a game sprite.
Subject: [role, age 21+, face/hair anchors, outfit, weapon, palette].
Composition: locked isometric three-quarter NE view, orthographic feel, feet fully visible on one ground line, centered with generous transparent clearance, readable silhouette.
Style: [locked style vocabulary], production game asset.
Text/content: no text.
Constraints: true transparent background, one character only, no floor shadow unless requested, clean alpha, consistent body/head ratio across the roster.
Avoid: cropped equipment, perspective drift, duplicate limbs, colored fringe, camera tilt.
```

**UI frame/icon**

```text
Create a transparent game UI [nine-slice frame / icon] for [semantic role].
Composition: isolated object, symmetric corners for scalable frames, protected empty center for content, crisp silhouette at runtime size.
Style: [locked material and palette].
Text/content: no text.
Constraints: true alpha, no glow clipped by canvas, no embedded labels or numbers.
```

### Lightweight static-character recipe

The runtime currently expects animation-shaped resources. The safest lightweight reskin is to keep those contracts while using one approved pose:

- Core operator strips live under `assets/sprites/operators/animated/{caster_1,guard_1,sniper_1,recruit_female,recruit_male}/`.
- Each template needs `idle_ne`, `idle_nw`, `attack_ne`, and `attack_nw`.
- Core strips use 192×192 cells: idle is 24 horizontal cells (`4608×192`) and attack is 13 (`2496×192`). Duplicate one static pose into every required cell if no authored animation is desired.
- Preserve the resource-defined pivot and feet line. Recruit uses a special 148/192 ground-line contract; do not bottom-lock it blindly.
- Advanced specialization art uses 640×640 cells, 8 columns, 24 idle and 13 attack frames at 12 FPS, NE/NW only, bottom-center pivot, and recorded provenance. It can remain optional content.
- If adding procedural bob, jump, squash, or recoil, implement it only in the presentation animator/view. Never modify model position, pathing, range, or collision from visual transforms.
- For a simple fork, keep NE and NW. Mirror only when costume/weapon asymmetry permits it; otherwise generate both views.

Static enemies use one transparent 640×640 image each under `assets/sprites/enemies/static/`. The Grunt is the directional animated exception. Either preserve it or repeat a static directional pose across its existing 25-frame sheets; do not change the manifest contract casually.

### Art routing and filter rules

Battle-facing assets resolve through `scripts/view/art.gd` and three manifests:

- `assets/manifest.tres`
- `assets/act1_shared_manifest.tres`
- `assets/enemy_static_manifest.tres`

`Art` serves only those three merged manifests. Terrain, restoration, loading/UI/cursor assets, and several world assets are direct preloads. A duplicate logical ID anywhere makes aggregate lookup fail closed rather than override; an individually missing advanced atlas requests its optional pack while retaining core/`ColorRect` fallback. Prefer replacing source files behind stable IDs.

Visible terrain does not route through manifest or `StageArtTheme` tile IDs. It is directly preloaded by `scripts/view/proto_isometric_terrain.gd`; change its textures and `BIOME_PROFILES`. Keep painter depth stable: terrain/platform is `3*(x+y)`, enemies `+1`, operators `+2`; traps, restoration, and endpoints use `+1`. `E`/`X` platforms occlude actors behind them but not occupants. StageArtTheme is required for S1–S3 preflight, although most of its terrain/backdrop/prop selection fields are not consumed by the renderer.

Keep filtering intentional:

| Surface | Policy |
|---|---|
| Legacy pixel sprites, traps, common tiny VFX | Nearest. |
| Terrain textures | Linear and repeating. |
| Static 640×640 enemies, endpoints, restoration/high-threat art | Linear with mipmaps. |
| Generated advanced WebP operators | Lossy import quality `.92`, generated mipmaps, and `compress/high_quality=false`; current operator `TextureRect`s inherit project nearest filtering unless overridden. |

There is no current full-screen post-processing filter. `threshold_material.tres` is UI-tier data, not a shader. Add a color-grade/filter only as a presentation `CanvasLayer`/shader layer, keep it out of model state, place it so HUD readability is intentional, expose an accessibility-safe disable path, and classify any tweak as cosmetic.

## UI, HUD, and alignment rules

Most UI is built in GDScript even when a `.tscn` root exists. Preserve runtime-created node names used by tests, focus graphs, and integrations.

| Surface | Layout rule | Input/authority rule |
|---|---|---|
| Screen routes | Full-rect roots; route through `Game._swap_content()`. | Screens project state; never replace/free `Game.content` directly. |
| Shared screens | Use `AetheriaScreenShell`; Campaign/Results use `full_safe_area=true`. | Prefer flow/grid/scroll composition over fixed desktop coordinates. |
| Dialogs | Use `LunarisDialogSheet`; body-only scrolling, responsive stacked actions. | Full-viewport input barrier, focus trap/return, consume Cancel. |
| Title | Keep `EntryScroll`, fixed footer dock, responsive wordmark, and top-aligned cover. | Start disables during initialization and opens Campaign, never Battle directly. |
| Campaign | Header becomes one column in portrait; mission cards remain in `CampaignScroll`. | Locked cards are disabled; a pending attempt makes only its stage selectable. |
| Battle relayout | `BattleView._relayout()` must fit the map before relaying out every grid-coupled overlay. | Do not add competing resize handlers that read stale grid scale/pan. |
| Battle HUD | Wide `(16,8)`, viewport width minus 32, height 100. Compact/portrait `(12,8)`, half-width, height 164. | Snapshot projection only; no tactical writes. |
| Deploy deck | Bottom-left, local vertical scroll, 16 safe margin, 24/32 panel padding, 12 gap, 288×76 slots. | Highlights and actions use `BattleModel.can_*` and `apply_action()`. |
| Command deck | Right inset 16; y=112 landscape/180 portrait; three 112×48 controls; 4 columns or 2 on narrow/portrait. | Owns Pause/Speed/Resign and first-pass Space/Q/E interception. |
| Pause | Full-viewport input stop; two actions in a centered responsive panel. | Snapshot exact tactical speed, set it to zero, and restore only after exit. |
| Tutorial | Left-aligned card in landscape, above deployment controls; responsive portrait stack. | Preserve `ROUTE → DEPLOY → BLOCK → LIVE` and signal-driven gates. |
| Leaderboard | Shared title/results dialog, local vertical scroll, responsive identity/actions. | Projection over `/root/Leaderboard`; preserve stable runtime node names. |

### Cross-cutting UI rules

- Use shared styles in `scripts/ui/components/lunaris_ops_style.gd`, `aetheria_theme.gd`, and `staging_skin.gd`; preserve normal, hover, pressed, focus, and disabled states.
- Keep a **24 px minimum panel content inset** unless a tested compact component has a documented exception.
- Use wrapping, responsive reflow, and local vertical scrolling. Do not shrink or clip text to force a desktop layout into portrait or Chinese.
- Keep dynamic controls `FOCUS_ALL`, preserve visible focus styling, restore focus after modals/reflow, and keep accessible names/descriptions synchronized with visible copy.
- `TextScale` is the only global font scaler. Test important layouts at 80%, 100%, 120%, and 150%.
- Background art must ignore mouse input. Modal veils must stop it.
- Space is both UI Accept and Battle Pause. `BattleControls._input()` must continue to claim Space/Q/E before GUI dispatch.

### Active input and interaction contract

| Interaction | Current behavior |
|---|---|
| GUI focus | Enter, keypad Enter, Space, or Joypad A accepts; Escape or Joypad B cancels. Normal directional focus uses Godot's built-in UI mappings. |
| Battle pause/speed | Space toggles pause; Q/E step `0×/1×/2×/4×`. There is no explicit controller binding for battle pause or speed. |
| Tactical play | Deployment, trap placement, unit selection, recall, and healing-target selection are pointer/touch-first; no gamepad tactical cursor exists. UI legality and overlays must query `BattleModel`. |
| Map navigation | Landscape uses middle drag and wheel/Shift-wheel. Portrait uses primary/touch drag after a 10 px threshold, with view-only rubber-band/inertia. There is no keyboard/controller pan route. |
| Pause menu | Escape snapshots the exact tactical speed, sets tick delivery to zero, blocks world/deploy input, and exposes Settings plus confirmed Resign. Closing restores the prior speed. |
| Escape caveat | `DeployBar` cancels selection/placement/heal intent but does not consume Escape, so the same press can also open Battle pause. Right-click cancels intent without that fallthrough. |

GUI/controller support therefore does **not** mean controller-complete tactical play. New controls need explicit InputMap actions, focus behavior, cursor/touch equivalents, modal gating, and focused tests. [8]

### Preferences, accessibility, and reset

`user://view_preferences.cfg` stores one validated presentation batch: locale (`en-US`/`zh-CN`), global Music enabled, Master/Music/SFX volumes, Master mute, background downloads, reduced motion, frame limit (`0/30/60/120`), and text scale (`0.80`–`1.50` in `0.05` steps). Settings previews a snapshot live; Apply atomically writes the complete valid batch; Back/Escape restores the snapshot. The Title quick-language control intentionally persists immediately. Despite its historical name, `title_music_enabled` controls the global Music service beyond Title. [7]

Dialogs are functional input/focus barriers. They suppress background focus, begin destructive confirmations on a safe Cancel action, announce status, keep overflow copy scrollable/focusable, and restore a valid invoking target. `CursorManager` supplies semantic cursor roles, while `UiFeedback` supplies global enabled-button press feedback. Reduced motion remains presentation-only and is not exhaustive: First Stand and the portrait pan hint still pulse.

**Clear Player Data** requires explicit confirmation and recursively deletes persisted `user://` contents, including campaign artifacts, preferences, local leaderboard data, cached packs, and tweak deltas. It is non-transactional: a removal failure can leave surviving artifacts and reports an error rather than routing to Title. A successful clear resets campaign/leaderboard authority, but currently loaded F10 values/pending writes and mounted content packs can survive in the running process; do not promise a fully fresh runtime without restart.

## Stage authoring and isometric mechanics

Each stage is a `data/stages/<id>.tres` `StageDef`. The map, paths, waves, capacity, leak allowance, and special mechanics are data; the battle scene projects them.

### Grid and placement

| Glyph | Meaning | Enemy path | Operator placement | Trap placement |
|---|---|---|---|---|
| `.` | Void | No | No | No |
| `G` | Ground | Yes | Ground operators | Only when the cell is on a declared route |
| `E` | Elevated | No | Elevated operators | No |
| `S` | Spawn | Yes | No | No |
| `B` | Base | Yes | No | No |
| `X` | Legacy blocked/raised platform | No | Elevated operators | No |

Rules:

1. Keep every `grid_rows` row the same width and use only `. G E S B X`.
2. Paths are explicit ordered integer grid coordinates, not pixels. Start on `S`, end on `B`, move one cardinal cell per step, and traverse only `G/S/B`.
3. Waves are chronological dictionaries `{ "enemy_id", "path_idx", "tick" }`. Same-tick order affects IDs and ties, but `WaveTimeline` currently sorts only by tick and has no explicit source-index tie-breaker. Do not rely on preserved source order until code and tests guarantee it.
4. `wave_starts` defines UI wave windows, not spawns. It must start at `0` and strictly increase.
5. UI must call `BattleModel.can_deploy_at()` and `can_place_trap_at()` rather than duplicate cell rules.
6. Portrait mode chooses a rotated runtime copy at Battle startup. It rotates grid, paths, and cell-indexed metadata together; it does not live-rotate an active Battle when the viewport changes.
7. Isometric projection uses 64×32 diamonds and a 16 px elevation lift. Grid cells remain authority; screen position is presentation.
8. Defeat is `leaked > leak_limit` or `base_hp <= 0`. A leak limit of 3 allows exactly three leaks; the fourth loses.

> **Validation boundary:** these are authoring requirements, not a complete production preflight. `test/stage_redesign_smoke.gd` is the practical gate for grids, glyphs, paths, waves, starts, and enemy references. Malformed resources can otherwise fail late or behave inertly.

### Stage count: one- or two-stage forks

The fastest fork can **present only `s1` and `s2`** while retaining compatibility resources. Do not simply delete `s3`–`s10`: current campaign normalization, rewards, environment identity, save compatibility, and leaderboard validation assume contiguous `s1`–`s10`.

A true one/two-stage reduction must update together:

- stage resources and contiguous `campaign_index` values;
- `data/campaigns/p16_v3.tres` reward rows;
- `CampaignDef.P16_V3_ENVIRONMENT_SHA256` and the matching resource hash;
- campaign codecs/context and old/pending save policy;
- leaderboard stage validators in both GDScript and Node;
- localization, tests, and any stage-specific art/audio routing.

For a new game built quickly, keep the compatibility shell, edit `s1`/`s2`, hide later cards, and perform destructive pruning only after the new loop is approved. `campaign_index` and contiguous `s1`–`s10` content govern current progression; `StageDef.requires` is unconsumed metadata, and `recovery_roster` is legacy compatibility data rather than deck authority.

### Unique tactical mechanics

- **Deterministic ticks:** `BattleModel` uses fixed phase order and integer state. One tile equals `1,000,000` path units; per-tick speed is floored once at spawn.
- **Phase order:** expire effects → regenerate DP/SP → move/block/leak existing enemies → trigger traps → restoration → unit then enemy combat → spawn → terminal check → increment tick.
- **Blocking:** ground enemies consume weighted block capacity; overflow continues walking rather than queueing. Block links are bidirectional and release atomically on kill, retreat, enemy death, or capacity-effect expiry.
- **Aerial enemies:** use normal routes but bypass blocking and both shipped trap modes. Gunner is the only stock anti-air attacker. Mage is ground-only and its splash excludes aerials; Recruit/Swordmaster require blocked targets. Damage stagger still slows aerial movement. Drone's blocker-only policy finds no stock target; Interceptor attacks the nearest unit in Chebyshev range 2.
- **Targeting:** the policy vocabulary is closed and fail-closed. Operators acquire through an omnidirectional union of range rotations; automatic NW/NE facing is presentation only and never gates damage/range.
- **Damage:** Physical is `max(raw-defense, ceil(raw/20))`; Arts is `max(floor(raw*(1000-resistance)/1000), ceil(raw/20))`. Thus valid positive hits retain a 5% floor, even at 1000‰ resistance. Route model-level hostile damage through `BattleModel._damage_enemy()`, which owns mitigation, stagger, kill accounting, and block release. Stagger delays movement but does not suppress enemy attacks; stun suppresses both.
- **Skills:** Skill activation, Mend, deployment, retreat, trap placement, and resign are `BattleModel.apply_action()` verbs, but several verbs/effects have no shipped content.
- **Traps:** Spike Plate is 4 DP, 20 Physical ON_ENTER damage, and three charges. Tar Pit is 6 DP and applies a permanent strongest-only 500‰ slow sampled from the enemy's start cell. Units and traps may share a cell. Campaign unlocks filter cards in UI only; model/ticket trap authorization is not enforced for programmatic callers.
- **Restoration:** S9 `(6,3)` and S10 `(5,2)`, `(3,4)` heal damaged non-aerial ground enemies for 8 HP every 90 ticks after movement/traps and before combat. It is gameplay/state-hashed, not decoration.
- **High-threat warnings:** stage-authorized presentation is keyed to wave-window indexes. Only the S9 `green_cage` route is active; unknown IDs silently produce no warning.
- **Speed:** button cycle is `1× → 2× → 4× → Pause`; Q decreases, E increases, Space toggles pause. Speed changes tick delivery, never phase order.
- **Presentation slowdowns:** deploy/tutorial/selection effects use view-time tags. Do not confuse `Engine.time_scale` with tactical `ticks_per_frame_scale`.

| Mechanism | Current contract |
|---|---|
| Simulation | Default is 30 ticks/s with uncapped catch-up in `BattleView`; newly spawned enemies first act on a later tick because spawn occurs after combat. |
| Battle pause/speed | Space toggles tick delivery; Speed cycles `1× → 2× → 4× → 0×`; Q/E step those values. This changes `ticks_per_frame_scale`, not SceneTree state. |
| Presentation holds | `BattleView` owns `Engine.time_scale` through minimum-valued tags: tutorial `0`, deploy drag `0.3`, selected-unit panel `0.75`. Use `juice_time_push/pop`, not competing global writes. |
| F10 panel | Pauses the whole SceneTree while its always-processing UI remains active, then restores the prior paused state. |
| Default economy | Base HP 10; start DP 10; DP cap 99; passive DP and skilled-unit SP each advance every 30 ticks; retreat refund 50%; enemy damage stagger 8 ticks. |

A clear requires an exhausted timeline and no living enemy. Defeat is `leaked > leak_limit` **or** `base_hp <= 0`. Stars are 3 at zero leaks, 2 at one or two leaks, and 1 for another clear within the leak limit. S8 has leak limit 2, so it has no one-star clear. Shipped leak hit-stop is disabled (`0` frames). Tactical code currently makes no random draw; `run_seed` is identity/future-extension data rather than active combat variance.

Actions reject invalid/wrong-arity/post-terminal requests without tactical mutation. Units and enemies remain append-only after death, leak, or retreat so IDs/history stay stable; only exhausted ON_ENTER traps are erased. When adding outcome-affecting state, update `BattleHash`, snapshots, tickets, outcomes, codecs, and deterministic tests in the same change. Serialized enum values are append-only; never reorder them.

## Operators, enemies, and balance

Balance sources are `data/config/game.tres`, `data/operators/`, `data/skills/`, `data/target_policies/`, `data/enemies/`, `data/traps/`, and `data/stages/`. The nine active enemy IDs are `grunt`, `runner`, `shieldbearer`, `breacher`, `drone`, `interceptor`, `spellcaster`, `heavy`, and `mini_boss`. Keep full encounter/stat matrices in a versioned content reference rather than hard-coding them into this field manual.

The fixed deck is an unlimited repeat-purchase pool bounded by current DP, one-unit-per-cell occupancy, and stage living-unit capacity (`s1` 3; `s2`–`s3` 4; `s4`–`s5` 5; `s6`–`s10` 6). Fixed-roster retreat refunds `floor(cost × 50%)` subject to the DP cap and creates no cooldown. The hard-coded 10-second standard and 3-second Vanguard cooldowns apply only to non-fixed compatibility modes.

Shipping manual full-SP skills are Gunner **Deadeye** (2× ATK, 15 SP, 150 ticks), Swordmaster **Flurry** (0.5× interval, 15 SP, 150 ticks), and Mage Apprentice **Conflagration** (3×3 to 5×5 ground-only splash, 25 SP, 150 ticks). Recruit has no skill. `mend`/`HEAL_TARGET`, DP burst, block bonus, stun, healer/Defender/Vanguard classes, and `no_automatic_target` are implemented extension or compatibility seams, not shipped deck mechanics. No current operator heals allies; restoration heals enemies only.

Ground operators may use any `G` cell; traps require a routed `G`; elevated operators use `E` or legacy `X`; one living unit occupies a cell. Deployment facing is validated then normalized to NW, while target-driven NW/NE facing remains visual only.

`BattleView` duplicates authored stage/config/operator/enemy inputs at battle startup; units and enemies then copy required data at deploy/spawn. Do not mutate source `.tres` resources or retroactively retune materialized state. Content changes that affect campaign context require environment-hash, save, and migration review. Campaign witness/ticket identity remains separate from the fixed deploy deck; current witness participation counters are not reliable evidence of fixed-deck tactical use.

The result path deliberately grants **no permanent death, memorial, XP, or class unlocks**. Restoring persistent person progression is a campaign-schema, UI, ticket, migration, and balance redesign—not a cosmetic toggle.

## VFX and particle effects

`BattleView` detects authoritative model edges; `scripts/view/juice_layer.gd` renders and ages transient visuals. `data/juice_config.tres` is the principal, not exhaustive, juice source: some counts/geometry remain in `JuiceLayer`, static-enemy death profiles live in `EnemyAnimator`, and Act II/defeat overlays own separate constants. Most JuiceLayer state is render-frame based, while static-enemy deaths are second-based.

This template draws “particles” with `TextureRect`, `Line2D`, `Polygon2D`, and procedural `_draw()` nodes rather than Particle2D systems. Keep them presentation-only and preserve:

- map transform compensation during pan/zoom/resize;
- tile/entity z-order and raised-platform occlusion;
- transparent sprite-backed trap parents;
- reduced-motion static alternatives;
- no use of gameplay RNG for visual scatter.

To add `GPUParticles2D`, keep emission event detection in `BattleView`, pool the visual emitter, seed only presentation randomness, provide a reduced-motion fallback, and never write model state from the emitter.

## Audio generation and integration

### One-BGM template workflow

Use Manus built-in **`manus-tools/generate_music`**—backed by the preferred latest available music model—to generate one original loop. Use one call for tracks up to 180 seconds. The prompt must begin with total duration, BPM, and vocal policy; describe genre, key, mood, instrumentation, density, structure, space, and production; do not reference artists or existing songs.

Example:

```text
Instrumental only, no vocals. Create a 120-second seamless-loop tactical fantasy-electronic score at 112 BPM in D minor. Focused, mysterious, and resilient rather than bombastic; hybrid frame drums, muted taiko, low strings, glassy synth arpeggios, restrained brass swells, warm sub bass, sparse high chimes, medium-low density, dark-neutral brightness, wide but clean game mix with controlled transients and no sudden loudness jumps. [0:00-0:20] establish a calm deploy-planning pulse, intensity 3/10. [0:20-0:55] add rhythmic motion for early waves, intensity 5/10. [0:55-1:30] broaden harmony and percussion for pressure without a melodic reset, intensity 6/10. [1:30-2:00] return smoothly to the opening harmonic and rhythmic state so the final bar loops into the first bar without a click or cadence. Instrumental only, no vocals.
```

Then:

1. Save the high-resolution generated master outside the runtime asset tree.
2. Trim only if necessary, verify a clean musical loop, and convert to 48 kHz stereo Vorbis OGG.
3. Point existing `AudioCue.stream_path` values to the one runtime OGG while retaining logical cue IDs used by Title, Campaign, Battle, and Results.
4. Keep cue BPM, meter, loop flag, approved surfaces, and catalog/profile mapping truthful.
5. A one-master reskin is supported by deliberately mapping all logical routes to one source; it is not the shipped topology. Preserve truthful BPM, meter, and loop metadata because adaptive scheduling consumes them.
6. Current terminal behavior plays victory/defeat SFX **and** crossfades to an eight-second non-looping Music result cue before persistence. Results does not restart a background cue after that result track ends.

Direct `Music.play_cue()` and Act II identical-cue state changes no-op. Ordinary high/critical and boss/boss-critical adaptive transitions can restart an identical mapped cue at a scheduled boundary; do not generalize no-restart behavior without preserving and testing route-specific policy.

Battle's adaptive director is presentation-only: it derives routine/high/critical/boss states from projected pressure, waits for stability (default hold 8 seconds; critical 0.15 seconds, ordinary escalation 0.75, de-escalation 3), and schedules cue changes to musical bar boundaries from profile BPM/meter. Its elapsed clock advances only while tactical tick delivery is positive and hit-stop is inactive; it never changes model state.

All BGM must go through `autoloads/music.gd`; all effects through `autoloads/sfx.gd`. Do not add scene-local competing `AudioStreamPlayer`s. Preserve two BGM crossfade players, eight SFX voices, `Music`/`SFX` buses sending to `Master`, and direct-stream Web playback.

### Small SFX

The repository currently ships static WAVs and contains **no** Lyria integration, ElevenLabs integration, or Godot procedural SFX generator. The runtime seam is `assets/sfx/catalog.tres`.

Preferred replacement flow:

1. In Manus, inspect connector availability with `manus-config config load --search eleven` before assuming ElevenLabs is enabled.
2. If an ElevenLabs SFX connector is enabled and authorized, generate short, dry, isolated one-shots: UI click 80–150 ms, reject 120–250 ms, deploy 300–900 ms, hit/trap 100–500 ms, victory/defeat 0.8–1.5 s. Request no voice, no music bed, no long reverb tail, and no leading silence.
3. Export/convert to 48 kHz stereo WAV, normalize conservatively, trim silence, and replace the static file behind a stable direct cue ID.
4. Add gameplay-specific semantic names as one-level aliases to direct catalog entries; do not create alias chains or put file paths in gameplay code.

If ElevenLabs is unavailable, an agent may add an **offline authoring tool** using Godot `AudioStreamWAV`/PCM data and `save_to_wav()` to synthesize basic sine/noise/envelope cues. Keep it under `tools/audio/`, run it only during asset production, and commit the generated WAVs. Do not make runtime `AudioStreamGenerator` a game dependency merely to create clicks and impacts.

`UiFeedback` is the global enabled-button `ui_click` requester, but several handlers also request that cue. `Sfx` deduplicates the resolved direct ID once per process frame, so these usually produce one audible start. Routine hover/back/confirm/menu IDs are intentionally muted by policy.

SFX aliases are one level and must resolve to a direct entry. Every newly authored active skill ID needs a direct SFX entry or alias because Battle requests its logical skill ID. The browser AudioContext hook is an inline export-preset, best-effort unlock wrapper; it does not guarantee autoplay or recovery from browser policy failure.

## Runtime tweak UI and sandbox handoff

Press **F10** to open the schema-driven 58-control developer panel. Controls span UI, gameplay, audio, player, enemies, and environment; 26 are `GAMEPLAY` and 32 are `COSMETIC`. Each descriptor declares `LIVE`, `NEXT_BATTLE`, `NEXT_DEPLOY`, `NEXT_SPAWN`, `NEXT_CUE`, or `NEXT_TRANSITION`.

> **Integrity limitation:** F10 is an unauthenticated local override layer. A non-default gameplay value can change direct and campaign battle inputs and still grant campaign rewards and local/global leaderboard records. `[TWEAKED]` is a live HUD suffix only: it is not latched, serialized in tickets/outcomes/saves/submissions, or used as an eligibility gate. Resetting controls can remove the marker after already-materialized units or enemies were tuned.

To add a control:

1. Add one descriptor in `scripts/tuning/runtime_tweak_catalog.gd` with a stable ID, type, default, range, step, unit, apply mode, and honest `GAMEPLAY`/`COSMETIC` classification.
2. Read it at the advertised boundary through `TweakControls` or the appropriate view/audio consumer.
3. Adapt deep-copied resources from immutable baselines; never modify loaded source resources or retroactively rewrite existing entities.
4. Add a focused test. Preserve truthful `[TWEAKED]` disclosure, and decide explicitly whether durable progression/leaderboards should accept the changed run.

The panel is an always-available raw-F10 `CanvasLayer`. It pauses the SceneTree, stores only non-default deltas in `user://runtime_tweaks.cfg`, debounces writes by 0.35 seconds, flushes on close, then restores the prior paused state. Its schema version is written but not enforced/migrated; invalid loads are silent and failed saves have no retry.

Local deltas are saved to `user://runtime_tweaks.cfg`. In a native/editor sandbox, locate and copy the file with:

```bash
find "${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata" \
  -name runtime_tweaks.cfg -print
# Then copy the chosen file to a review path, for example:
# cp "/resolved/path/runtime_tweaks.cfg" /home/ubuntu/runtime_tweaks.cfg
```

Treat that file as a tuning handoff, not source authority. Promote values according to their adapter. Absolute GameConfig values must change both `data/config/game.tres` and their matching catalog defaults because catalog defaults overwrite copied config fields at battle startup. Relative player/enemy multipliers, bonuses, spawn timing/count, and leak bonuses must be either retained as non-identity catalog defaults **or** baked into authored data with catalog defaults reset to identity; doing both double-applies the change. Existing entities do not retroactively adopt `NEXT_DEPLOY`/`NEXT_SPAWN` changes.

Browser `user://` is browser storage. The project has no tweak server, export/import, cloud sync, or Web-to-sandbox synchronization; implement a versioned exchange format before claiming one exists.

## Tutorial and onboarding

`scripts/ui/first_stand_tutorial.gd` is the live battle tutorial. It appears when the stage is `s1`, campaign mode is active, and `ui.tutorial_hints_enabled` is true. Current behavior intentionally replays on later eligible S1 attempts.

Preserve the state machine:

1. `ROUTE`: show route and explain spawn-to-base flow; battle held.
2. `DEPLOY`: enable operator placement; advance only after a successful deployment signal.
3. `BLOCK`: explain interception/blocking; battle held.
4. `LIVE`: release the hold, re-enable normal controls, then auto-dismiss.

First Stand advances on any successful operator deployment, not specifically Recruit or a recommended cell, and stores no completion flag. LIVE releases its time hold and auto-dismisses after six seconds. A separate portrait map-pan hint appears only when pan range exists, lasts up to seven seconds, persists completion after a successful pan, and is independent of `ui.tutorial_hints_enabled`.

The generic `CommandCenterTutorial`, command/post-mission request APIs, and their preference completion flags are not consumed by an active screen. Do not advertise them as live. If a fork wants one-time onboarding, create a deliberate consumed route and update replay, reset, localization, accessibility, and lifecycle tests.

## English and Simplified-Chinese support

Main screens and ordinary player-facing copy must flow through `scripts/ui/components/ui_copy.gd` and `I18n`, not hard-coded strings. The active F10 launcher/panel/catalog and Battle `[TWEAKED]` suffix are current English-only developer-tool exceptions; localize and subscribe them to locale changes before claiming universal bilingual coverage.

- Update `localization/en-US.json` and `localization/zh-CN.json` together.
- Preserve canonical root order, sorted keys, LF line endings, final newline, nonempty strings, and exact placeholder-name parity.
- Add typed placeholder schemas before calling `UiCopy.format_text()`.
- Subscribe cached UI to `I18n.locale_changed` and refresh visible and accessible text together.
- Preserve `assets/fonts/GameTemplateTDSansSC.otf` and display-to-body fallback for CJK glyphs.
- Repair layout with wrapping, scrolling, and responsive composition, never by clipping Chinese or shrinking below the shared hierarchy.

## Local and global leaderboards

The Title and Results screens share one dialog. After an accepted direct result or durable campaign resolution, every valid `s1`–`s10` **clear or defeat** creates a local record. Score version 1 is `max(0, clear*2,000,000 + stage*100,000 + stars*20,000 + kills*50 - leaks*500)`. The local ledger retains its best 50 rows, the UI shows 10, and the FIFO pending queue keeps only its newest 100 submissions.

Remote synchronization is best-effort, sequential, and trigger-driven: startup pending work, a new result, dialog open/tab/refresh. It has an eight-second timeout and no periodic retry/backoff. An error leaves the queue front pending and may leave stale global rows visible. Networking never blocks rewards, Results, or navigation. Native/headless defaults are offline (`leaderboard/api_base_url=""`; `leaderboard/enable_in_headless=false`); browser builds use an HTTP(S) page origin where available.

The optional zero-dependency Node 22 service exposes `GET /api/health`, `GET /api/leaderboard?limit=`, and `POST /api/leaderboard`; it serves `build/web` on `127.0.0.1:3000` by default. It recomputes bounded client summaries and retains only the top 1,000 JSON records. Submission IDs are deduplicated **only while their records remain retained**: at capacity, a low score can receive `201` with no rank, be discarded, and later be accepted again under the same ID. There are no accounts, credentials, replay/hash/ticket verification, server simulation, or gameplay-plausibility checks. This is a community board, **not anti-cheat**. [6]

```bash
npm run dev
npm run test:leaderboard
```

Production must configure a durable writable data path plus TLS, reverse proxy/firewall, process supervision, monitoring, backups, origin policy, and rate-limit review. The bundled service has no backup/migration/multiprocess coordination; corrupt top-level server JSON prevents normal boot.

For a one/two-stage fork, update allowed stage IDs in both `autoloads/leaderboard.gd` and `server/leaderboard_server.mjs`, bump/migrate score policy deliberately, and update tests and localized formula copy.

## Web export and optional packs

Web is the only checked-in export preset; `build/web` is generated and ignored. With matching Godot 4.7.2 Web templates installed:

```bash
godot --headless --path . --export-release "Web" build/web/index.html
npm run dev
```

The core build remains playable without advanced specialization art. Optional pack specifications must be user arguments in the form `--content-pack=id|http(s)-url|bytes|sha256`; accepted IDs are `operator-gunner`, `operator-mage-apprentice`, and `operator-swordmaster`. Packs download serially, are capped at 64 MiB and 180 seconds, verify exact bytes/SHA-256, cache under `user://content-packs`, and mount add-only with `load_resource_pack(path, false)`. Missing, disabled, failed, or unconfigured packs retain core/placeholder art and never block gameplay. Background prefetch defaults on; foreground requests remain allowed when it is disabled. [5]

`tools/stage_web_content_packs.sh` validates the exact eight-file female/male × idle/attack × NE/NW atlas contract for each retained class and emits three verified PCKs plus `manifest.tsv`. Its end-to-end regression checks every manifest row against the generated file's size and SHA-256. Export and `npm run dev` still do **not** translate that manifest into Godot user arguments; the host must provide immutable/cache-safe pack URLs and the matching `--content-pack` values. Do not claim fully automated advanced-pack deployment until host injection, cross-origin policy, actual browser mount/hash behavior, and a browser smoke pass exist. [5]

## Focused validation matrix

Documentation-only edits need `git diff --check` and path/command validation. For source/assets, run the smallest relevant gate on the final candidate.

| Change | Minimum focused checks |
|---|---|
| Start/Campaign routing | `tests/start_screen_flow_test.gd`, `tests/campaign_back_navigation_test.gd` |
| Save/result/campaign | `tests/campaign_save_fast_path_test.gd`, `tests/terminal_result_flow_test.gd`, `tests/no_permadeath_test.gd` |
| Stage/path/elevation | `test/stage_redesign_smoke.gd`, `test/stage_orientation_smoke.gd`, `test/map_navigator_orientation_smoke.gd`, `tests/elevated_platform_accessibility_test.gd`, `tests/restoration_lattice_test.gd` |
| Combat/targeting/facing | Relevant deterministic test plus `tests/operator_auto_facing_test.gd` and `tests/battle_health_and_depth_test.gd` as applicable |
| Pause/speed/input | `tests/battle_pause_menu_test.gd`; use `tests/controller_accessibility_test.gd` only for GUI mappings, not controller-complete tactics |
| Tutorial/warnings | `tests/first_mission_tutorial_replay_test.gd`, `tests/high_threat_wave_warning_test.gd` |
| UI/responsive style | Relevant layout/focus/dialog/cursor test plus one representative visual capture when pixels changed |
| Localization/font | `tests/localization_ui_parity_test.gd`, `tests/chinese_primary_flow_ui_test.gd`, and affected text-scale tests |
| Art/manifests/terrain/packs | `tests/advanced_operator_schema_test.gd`, `tests/enemy_static_sprite_test.gd`, `tests/web_content_pack_test.gd`, `tests/web_content_pack_staging_test.sh`, `test/agent4_isometric_renderer_smoke.gd` as applicable |
| Music/SFX/Web audio | `tests/music_redesign_test.gd`, `tests/ui_audio_direction_test.gd`, `tests/web_audio_unlock_test.gd` as applicable |
| Runtime tweaks | `tests/runtime_tweak_controls_test.gd`, `tests/runtime_tweak_battle_integration_test.gd` |
| Leaderboard | `tests/leaderboard_service_test.gd`, `tests/leaderboard_ui_test.gd`, `npm run test:leaderboard` |
| Player-data reset | `tests/player_data_clear_test.gd` |

Example:

```bash
tools/run_godot_test.sh tests/start_screen_flow_test.gd
tools/run_godot_test.sh tests/battle_pause_menu_test.gd
npm run test:leaderboard
```

### Audit baseline caveats

The readiness regressions follow current shipped contracts: pack staging enforces eight exact resources per retained class; Web-audio coverage derives active skill IDs from shipped operator resources instead of retired skills; and the global typography test reads the intentional Title Settings `TITLE_FONT_SCALE = 1.5` constant directly. Dormant skill names in compatibility tests or localization do not become shipped audio requirements merely by existing.

No tracked CI/workflow exists. This matrix is manual guidance; no automation currently runs Godot/Node gates, Web export, pack staging/mounting, browser smoke, or publication. Web export requires matching Godot 4.7.2 templates in the actual environment.

## Common failure modes

- **Changing view code to fix gameplay.** Put outcome logic in `BattleModel`; project it afterward.
- **Editing only `grid_rows`.** Move paths, restoration cells, stage themes, and tests with map topology.
- **Treating `X` as void.** It is a legacy raised/elevated placement cell in current behavior.
- **Assuming equal-tick wave source order is guaranteed.** It affects IDs/ties, but the current timeline has no explicit source-index secondary key.
- **Reordering tick phases.** This changes movement, traps, restoration, attack prevention, spawn delay, and outcomes.
- **Using screen coordinates for paths or rules.** Author integer grid cells; isometric projection is visual only.
- **Changing campaign content without environment/save review.** Existing/pending saves and tickets may become invalid.
- **Deleting later stages to make a two-stage game.** Hide first; migrate codecs, rewards, hashes, leaderboard, and tests before deleting.
- **Adding duplicate art IDs.** Manifest loading fails closed; replacement is not precedence.
- **Reskinning only `assets/manifest.tres`.** Terrain, loading/title, Campaign, UI frames/icons, cursors, and some world art use direct preloads.
- **Changing every texture to the same filter.** Pixel art, terrain, and large downsampled art have different requirements.
- **Putting gameplay writes in VFX/particles/audio.** Presentation must not affect hashes, tickets, saves, or RNG.
- **Adding scene-local audio players.** Use `Music` and `Sfx` services.
- **Hard-coding English.** Update both catalogs and accessibility copy through `UiCopy`.
- **Running tests directly.** Use the isolated wrapper or risk playable data.
- **Calling tickets/outcomes signed or combat-certified.** They are local canonical self-hashes without replay/server verification.
- **Calling the leaderboard secure.** It is local-first and server-recomputed, not replay-authenticated.
- **Treating `[TWEAKED]` as an eligibility gate.** Tweaked runs currently earn progression and leaderboard records.
- **Treating a pending ticket as a mid-battle save.** Restart launches a fresh battle from the ticket.
- **Trusting UI-only trap unlocks as model authorization.** Programmatic placement currently bypasses campaign entitlement filtering.
- **Claiming tweak sync exists.** Native config can be copied; browser export/import is not implemented.
- **Claiming optional packs deploy automatically.** Staging is currently broken and no manifest-to-launch-argument integration exists.

## Key path index

| Concern | Primary paths |
|---|---|
| Project/boot/input/autoloads | `project.godot`, `scenes/loading.tscn`, `scripts/ui/loading.gd`, `autoloads/test_run_guard.gd` |
| Routes/session | `autoloads/game.gd` |
| Campaign authority/save | `sim/campaign_state_v3.gd`, `sim/campaign_runtime_authority.gd`, `sim/campaign_save_store.gd` |
| Tactical model | `sim/battle_model.gd`, `sim/pathing.gd`, `sim/targeting.gd`, `sim/battle_hash.gd` |
| Stage/gameplay data | `data/stage_def.gd`, `data/stages/`, `data/config/game.tres`, `data/operators/`, `data/enemies/`, `data/traps/` |
| Isometric rendering | `scripts/view/iso_projection.gd`, `scripts/view/proto_isometric_terrain.gd`, `scripts/view/iso_grid_builder.gd` |
| Screen UI | `scripts/ui/title.gd`, `scripts/ui/stage_select.gd`, `scripts/ui/results.gd`, `scripts/ui/title_settings.gd` |
| Battle UI | `scripts/view/battle_view.gd`, `scripts/view/battle_hud_presenter.gd`, `scripts/ui/deploy_bar.gd`, `scripts/ui/battle_controls.gd` |
| Shared UI skin | `scripts/ui/components/lunaris_ops_style.gd`, `aetheria_theme.gd`, `staging_skin.gd`, `data/presentation/ui/` |
| Tutorial | `scripts/ui/first_stand_tutorial.gd`, `assets/tutorial/` |
| Art | `scripts/view/art.gd`, `assets/*.tres`, `data/presentation/operator_visual_catalog.gd` |
| VFX | `scripts/view/juice_layer.gd`, `data/juice_config.tres` |
| Audio | `autoloads/music.gd`, `autoloads/sfx.gd`, `assets/music/catalog.tres`, `assets/sfx/catalog.tres`, `data/presentation/audio/` |
| Localization/fonts | `autoloads/i18n.gd`, `scripts/ui/components/ui_copy.gd`, `localization/`, `assets/fonts/` |
| Tweaks | `scripts/tuning/runtime_tweak_catalog.gd`, `autoloads/tweak_controls.gd`, `scripts/tuning/runtime_tweak_panel.gd` |
| Leaderboard | `autoloads/leaderboard.gd`, `scripts/ui/components/leaderboard_dialog.gd`, `server/leaderboard_server.mjs` |
| Safe tests | `tools/run_godot_test.sh`, `tools/run_godot_isolated.sh` |
| Web export/packs | `export_presets.cfg`, `tools/stage_web_content_packs.sh`, `autoloads/content_pack_loader.gd` |

## Implementation references

[1]: https://github.com/junnyboi/proto-td-simple/blob/master/autoloads/game.gd "Game route and result lifecycle"
[2]: https://github.com/junnyboi/proto-td-simple/blob/master/sim/battle_model.gd "Deterministic battle authority"
[3]: https://github.com/junnyboi/proto-td-simple/blob/master/sim/campaign_v3_attempts.gd "Campaign attempts, progression, and rewards"
[4]: https://github.com/junnyboi/proto-td-simple/blob/master/data/stage_def.gd "Stage data contract"
[5]: https://github.com/junnyboi/proto-td-simple/blob/master/autoloads/content_pack_loader.gd "Optional content-pack runtime"
[6]: https://github.com/junnyboi/proto-td-simple/blob/master/server/leaderboard_server.mjs "Leaderboard and static Web server"
[7]: https://github.com/junnyboi/proto-td-simple/blob/master/scripts/view/view_preferences.gd "Preferences and atomic batch persistence"
[8]: https://github.com/junnyboi/proto-td-simple/blob/master/scripts/ui/battle_controls.gd "Battle input, pause, speed, and resign controls"

## Contribution discipline

Use ordinary branches and commits. Never rewrite shared `master`. Preserve compatible concurrent changes constructively. Run one proportional verification pass on the final candidate, then commit and push. Documentation-only changes do not require an engine release ritual—machinery appreciates restraint, even if it rarely receives any.
