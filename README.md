# Game Template — Deterministic Isometric Tower Defense

This repository is a reusable **Godot 4.7.2** template for a small isometric tower-defense game. It already contains a playable start-to-results loop, deterministic combat, responsive English/Simplified-Chinese UI, pause and speed controls, a first-stage tutorial, runtime tweak controls, local-first leaderboards, and a lightweight Node global leaderboard service.

> **Agent directive:** Reskin presentation before changing game authority. `Game` owns routes, `BattleModel` owns tactical truth, and `CampaignStateV3` plus the save store own strategic truth. UI, art, VFX, audio, and leaderboards must remain projections or bounded services.

## Template snapshot

| Capability | Current implementation |
|---|---|
| Engine | Godot `4.7.2`, Forward Plus; do not silently upgrade the project format. |
| Main loop | Loading → Start → Campaign mission selection → Battle → Results. |
| Stages | Ten authored `StageDef` resources, `s1`–`s10`. A new fork can expose only `s1`/`s2`, but deleting the others is a migration; see [Stage count](#stage-count-one-or-two-stage-forks). |
| Tactical deck | Fixed repeatable roster: Recruit, Gunner, Swordmaster, Mage Apprentice via IDs `[recruit, sniper_1, guard_1, caster_1]`. |
| Core rules | Integer-tick deterministic simulation, explicit paths/waves, ground/elevated placement, blocking, aerial enemies, traps, skills, leaks, stars, restoration cells, and high-threat warnings. |
| UI | Start, Campaign, Battle HUD/deployment deck, pause/settings/resign, Results, leaderboard, responsive shells, keyboard/controller support. |
| Tutorial | `FirstStandTutorial` on eligible campaign `s1` plays; currently replayable, not one-time. |
| Languages | `en-US` and `zh-CN`, custom catalog validation, bundled CJK font, 80–150% text scale. |
| Tuning | F10 runtime tweak panel with 58 typed controls and local `ConfigFile` persistence. |
| Leaderboard | Offline-first local records plus optional same-origin Node global board. |
| Audio | Central `Music` and `Sfx` autoloads; static OGG/WAV assets; browser audio-unlock shim. |
| VFX | Procedural/transient 2D nodes through `JuiceLayer`; no `GPUParticles2D`/`CPUParticles2D` dependency. |

## Quick start

```bash
git status --short
godot --version                 # must be 4.7.2.stable-compatible
godot --path .
```

The main scene is `res://scenes/loading.tscn`. Loading opens the Start screen. **Start always opens Campaign mission selection**; even a durable interrupted mission resumes only after the player explicitly selects that mission.

For a safe import and bounded boot:

```bash
tools/run_godot_isolated.sh --headless --import
tools/run_godot_isolated.sh --headless --fixed-fps 60 --quit-after 120
```

Run test scripts only through `tools/run_godot_test.sh`. The wrapper creates a disposable `user://`; direct `godot --script tests/...` runs fail closed to protect playable saves.

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

### Route and save contract

`Game._swap_content()` creates and validates a candidate screen before retiring the current screen. Battle candidates must report successful startup and contain a `BattleModel`; otherwise the previous route is restored. Keep this transaction.

Campaign stages commit a durable `begin_attempt` before Battle opens. Terminal UI waits one frame, prepares the result, waits another frame, and durably commits `resolve_attempt` before enabling Continue. A retryable write must retry the retained `CampaignMutation` against the same preimage; never reconstruct the command, ticket, or outcome.

The production campaign slot is `user://campaign_v1.json` despite containing V3 data. Its `.tmp`, `.bak`, and `.invalid` siblings are one recovery protocol. Clear player data only through `Game.clear_player_data()`.

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

Duplicate logical IDs fail closed; a later manifest does **not** override an earlier one. Prefer replacing source files behind existing IDs.

Visible terrain does not route through manifest or `StageArtTheme` tile IDs. It is directly preloaded by `scripts/view/proto_isometric_terrain.gd`; change its textures and `BIOME_PROFILES`.

Keep filtering intentional:

| Surface | Policy |
|---|---|
| Legacy pixel sprites, traps, common tiny VFX | Nearest. |
| Terrain textures | Linear and repeating. |
| Static 640×640 enemies, endpoints, restoration/high-threat art | Linear with mipmaps. |
| Generated advanced WebP operators | High-quality lossy import with mipmaps; preserve schema tests. |

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
3. Waves are chronological dictionaries `{ "enemy_id", "path_idx", "tick" }`. Preserve source order for equal ticks because it affects deterministic IDs and ties.
4. `wave_starts` defines UI wave windows, not spawns. It must start at `0` and strictly increase.
5. UI must call `BattleModel.can_deploy_at()` and `can_place_trap_at()` rather than duplicate cell rules.
6. Portrait mode rotates a runtime copy of the grid, paths, and all cell-indexed metadata. Never author a second portrait map or pre-rotate source data.
7. Isometric projection uses 64×32 diamonds and a 16 px elevation lift. Grid cells remain authority; screen position is presentation.
8. Defeat is `leaked > leak_limit` or `base_hp <= 0`. A leak limit of 3 allows exactly three leaks; the fourth loses.

### Stage count: one- or two-stage forks

The fastest fork can **present only `s1` and `s2`** while retaining compatibility resources. Do not simply delete `s3`–`s10`: current campaign normalization, rewards, environment identity, save compatibility, and leaderboard validation assume contiguous `s1`–`s10`.

A true one/two-stage reduction must update together:

- stage resources and contiguous `campaign_index` values;
- `data/campaigns/p16_v3.tres` reward rows;
- `CampaignDef.P16_V3_ENVIRONMENT_SHA256` and the matching resource hash;
- campaign codecs/context and old/pending save policy;
- leaderboard stage validators in both GDScript and Node;
- localization, tests, and any stage-specific art/audio routing.

For a new game built quickly, keep the compatibility shell, edit `s1`/`s2`, hide later cards, and perform destructive pruning only after the new loop is approved.

### Unique tactical mechanics

- **Deterministic ticks:** `BattleModel` uses fixed phase order and integer state. One tile equals `1,000,000` path units.
- **Phase order:** expire effects → regenerate DP/SP → move/block/leak existing enemies → trigger traps → restoration → unit then enemy combat → spawn → terminal check → increment tick.
- **Blocking:** ground enemies consume weighted block capacity; overflow continues walking. Block links are bidirectional and release atomically.
- **Aerial enemies:** bypass blocking and traps. Elevated ranged units are the intended counter.
- **Targeting:** closed policies use canonical ties. Operators acquire targets omnidirectionally; facing is automatic visual NE/NW state, not attack-cone legality.
- **Damage:** integer Physical/Arts mitigation with a 5% minimum for valid positive hits. Route enemy damage through `EnemyDamage.apply()` so stagger and kill accounting remain correct.
- **Skills:** Skill activation, Mend, deployment, retreat, trap placement, and resign are `BattleModel.apply_action()` verbs.
- **Traps:** Spike Plate is ON_ENTER damage with charges; Tar Pit is a permanent ground-cell slow aura. Units and traps may share a cell.
- **Restoration:** selected route cells heal damaged non-aerial ground enemies at deterministic intervals. It is gameplay/state-hashed, not decoration.
- **High-threat warnings:** stage-authorized presentation keyed to wave-window indexes. Keep them out of simulation authority.
- **Speed:** button cycle is `1× → 2× → 4× → Pause`; Q decreases, E increases, Space toggles pause. Speed changes tick delivery, never phase order.
- **Presentation slowdowns:** deploy/tutorial/selection effects use view-time tags. Do not confuse `Engine.time_scale` with tactical `ticks_per_frame_scale`.

When adding outcome-affecting state, update `BattleHash`, snapshots, tickets, outcomes, codecs, and deterministic tests in the same change. Serialized enum values are append-only; never reorder them.

## Operators, enemies, and balance

Balance sources are:

- `data/config/game.tres` for base HP, tick rate, DP/SP cadence, refund, and stagger;
- `data/operators/*.tres`, `data/skills/*.tres`, and `data/target_policies/*.tres` for operators;
- `data/enemies/*.tres` for hostile archetypes;
- `data/traps/*.tres` for traps;
- `data/stages/*.tres` for maps and spawn schedules.

Definitions are copied into runtime state at deploy/spawn/place. Do not mutate already materialized units because a tweak changed a resource.

The current primary battle roster is fixed and repeatable. Campaign witness/ticket identity is intentionally separate from the deploy deck. The current result path also deliberately grants **no permanent death, memorial, XP, or class unlocks**. Restoring XP/specialization is a campaign-schema and balance redesign, not a cosmetic toggle.

## VFX and particle effects

`BattleView` detects authoritative model edges; `scripts/view/juice_layer.gd` renders and ages transient visuals. Tune ordinary effect counts, colors, lifetimes, shake, and opacity in `data/juice_config.tres`.

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
5. Map all battle intensity states to the same cue if dynamic stems are not wanted. Repeated same-cue requests must remain no-restart.
6. Decide explicitly whether Results continue the shared loop or use short victory/defeat SFX; update music tests with that product decision.

All BGM must go through `autoloads/music.gd`; all effects through `autoloads/sfx.gd`. Do not add scene-local competing `AudioStreamPlayer`s. Preserve two BGM crossfade players, eight SFX voices, `Music`/`SFX` buses sending to `Master`, and direct-stream Web playback.

### Small SFX

The repository currently ships static WAVs and contains **no** Lyria integration, ElevenLabs integration, or Godot procedural SFX generator. The runtime seam is `assets/sfx/catalog.tres`.

Preferred replacement flow:

1. In Manus, inspect connector availability with `manus-config config load --search eleven` before assuming ElevenLabs is enabled.
2. If an ElevenLabs SFX connector is enabled and authorized, generate short, dry, isolated one-shots: UI click 80–150 ms, reject 120–250 ms, deploy 300–900 ms, hit/trap 100–500 ms, victory/defeat 0.8–1.5 s. Request no voice, no music bed, no long reverb tail, and no leading silence.
3. Export/convert to 48 kHz stereo WAV, normalize conservatively, trim silence, and replace the static file behind a stable direct cue ID.
4. Add gameplay-specific semantic names as one-level aliases to direct catalog entries; do not create alias chains or put file paths in gameplay code.

If ElevenLabs is unavailable, an agent may add an **offline authoring tool** using Godot `AudioStreamWAV`/PCM data and `save_to_wav()` to synthesize basic sine/noise/envelope cues. Keep it under `tools/audio/`, run it only during asset production, and commit the generated WAVs. Do not make runtime `AudioStreamGenerator` a game dependency merely to create clicks and impacts.

`UiFeedback` already owns one `ui_click` request per enabled button press. Avoid duplicate click calls. Current routine hover/back/confirm/menu cues are intentionally muted by policy even when files exist.

## Runtime tweak UI and sandbox handoff

Press **F10** to open the schema-driven tweak panel. Controls cover UI, gameplay, audio, player, enemy, and environment values. Each descriptor declares an application boundary such as `LIVE`, `NEXT_BATTLE`, `NEXT_DEPLOY`, `NEXT_SPAWN`, `NEXT_CUE`, or `NEXT_TRANSITION`.

To add a control:

1. Add one descriptor in `scripts/tuning/runtime_tweak_catalog.gd` with a stable ID, type, default, range, step, unit, apply mode, and honest `GAMEPLAY`/`COSMETIC` classification.
2. Read it at the advertised boundary through `TweakControls` or the appropriate view/audio consumer.
3. Adapt deep-copied resources from immutable baselines; never modify loaded source resources.
4. Add a focused test. A non-default gameplay tweak must retain the `[TWEAKED]` HUD disclosure.

Local deltas are saved to `user://runtime_tweaks.cfg`. In a native/editor sandbox, locate and copy the file with:

```bash
find "${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata" \
  -name runtime_tweaks.cfg -print
# Then copy the chosen file to a review path, for example:
# cp "/resolved/path/runtime_tweaks.cfg" /home/ubuntu/runtime_tweaks.cfg
```

Treat that file as a tuning handoff, not source authority. Promote accepted values into the corresponding `.tres` resources and matching catalog defaults, then test once. Browser `user://` is browser storage; the project currently has no tweak export/import or cloud sync. Implement and test an explicit versioned export/import format before claiming Web-to-sandbox synchronization.

## Tutorial and onboarding

`scripts/ui/first_stand_tutorial.gd` is the live battle tutorial. It appears when the stage is `s1`, campaign mode is active, and `ui.tutorial_hints_enabled` is true. Current behavior intentionally replays on later eligible S1 attempts.

Preserve the state machine:

1. `ROUTE`: show route and explain spawn-to-base flow; battle held.
2. `DEPLOY`: enable operator placement; advance only after a successful deployment signal.
3. `BLOCK`: explain interception/blocking; battle held.
4. `LIVE`: release the hold, re-enable normal controls, then auto-dismiss.

The generic `CommandCenterTutorial` component exists, but its request APIs are not currently consumed by a runtime screen. Do not claim it is active. If a fork wants one-time onboarding, add a deliberate `ViewPreferences` completion flag and update replay, reset, localization, and lifecycle tests.

## English and Simplified-Chinese support

Visible copy must flow through `scripts/ui/components/ui_copy.gd` and `I18n`, not hard-coded screen strings.

- Update `localization/en-US.json` and `localization/zh-CN.json` together.
- Preserve canonical root order, sorted keys, LF line endings, final newline, nonempty strings, and exact placeholder-name parity.
- Add typed placeholder schemas before calling `UiCopy.format_text()`.
- Subscribe cached UI to `I18n.locale_changed` and refresh visible and accessible text together.
- Preserve `assets/fonts/GameTemplateTDSansSC.otf` and display-to-body fallback for CJK glyphs.
- Repair layout with wrapping, scrolling, and responsive composition, never by clipping Chinese or shrinking below the shared hierarchy.

## Local and global leaderboards

The title and Results screens share one leaderboard dialog. Mission results are recorded locally before networking; failed global submissions remain queued in `user://leaderboard.json` and retry on later sync triggers. Networking never blocks rewards, Results, or navigation.

The global service is a zero-dependency Node 22 server:

```bash
# First export the Godot Web preset to build/web/index.html.
npm run dev
# Service and parity tests:
npm run test:leaderboard
```

Browser builds use their page origin for `/api/leaderboard`; native builds use `leaderboard/api_base_url`. Production must set `LEADERBOARD_DATA_FILE` to a durable writable absolute path and add TLS, reverse proxy/firewall, process supervision, monitoring, and backups.

Keep client and server score version, formula, stage validation, name normalization, sorting, and bounds synchronized. The current server recomputes scores and deduplicates IDs, but it validates client summaries rather than signed replays; it is a lightweight community board, **not anti-cheat**.

For a one/two-stage fork, update allowed stage IDs in both `autoloads/leaderboard.gd` and `server/leaderboard_server.mjs`, bump/migrate score policy deliberately, and update tests and localized formula copy.

## Focused validation matrix

Documentation-only edits need `git diff --check` and path/command validation. For source/assets, run the smallest relevant gate on the final candidate.

| Change | Minimum focused checks |
|---|---|
| Start/Campaign routing | `tests/start_screen_flow_test.gd`, `tests/campaign_back_navigation_test.gd` |
| Save/result/campaign | `tests/campaign_save_fast_path_test.gd`, `tests/terminal_result_flow_test.gd`, `tests/no_permadeath_test.gd` |
| Stage/path/elevation | `test/stage_redesign_smoke.gd`, `test/stage_orientation_smoke.gd`, `tests/elevated_platform_accessibility_test.gd` |
| Combat/targeting/facing | Relevant deterministic test plus `tests/operator_auto_facing_test.gd` |
| Pause/speed/input | `tests/battle_pause_menu_test.gd`, `tests/controller_accessibility_test.gd` |
| Tutorial | `tests/first_mission_tutorial_replay_test.gd` |
| UI/responsive style | Relevant UI test plus one representative visual capture when pixels changed |
| Localization/font | `tests/localization_ui_parity_test.gd`, `tests/chinese_primary_flow_ui_test.gd`, text-scale tests |
| Art/manifests/terrain | `tests/advanced_operator_schema_test.gd`, `tests/enemy_static_sprite_test.gd`, `test/agent4_isometric_renderer_smoke.gd` as applicable |
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

At audited commit `b2b0eb6b`, targeted domain checks largely passed, but the tree was **not release-clean**. Known review items included localization scanner/key drift, Chinese Campaign-flow key consumption, a title-settings font-scale policy mismatch, missing SFX aliases expected by the Web-audio test, and a battle UI-layout regression path. No tracked CI workflow runs the Godot suite. Re-run affected checks against the current revision and fix causes rather than deleting assertions. Web export also requires matching Godot 4.7.2 Web templates in the actual export environment.

## Common failure modes

- **Changing view code to fix gameplay.** Put outcome logic in `BattleModel`; project it afterward.
- **Editing only `grid_rows`.** Move paths, restoration cells, stage themes, and tests with map topology.
- **Treating `X` as void.** It is a legacy raised/elevated placement cell in current behavior.
- **Reordering equal-tick waves or tick phases.** This changes deterministic IDs, targeting, and outcomes.
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
- **Calling the leaderboard secure.** It is local-first and server-recomputed, not replay-authenticated.
- **Claiming tweak sync exists.** Native config can be copied; browser export/import is not implemented.

## Key path index

| Concern | Primary paths |
|---|---|
| Project/boot/input | `project.godot`, `scenes/loading.tscn` |
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

## Contribution discipline

Use ordinary branches and commits. Never rewrite shared `master`. Preserve compatible concurrent changes constructively. Run one proportional verification pass on the final candidate, then commit and push. Documentation-only changes do not require an engine release ritual—machinery appreciates restraint, even if it rarely receives any.
