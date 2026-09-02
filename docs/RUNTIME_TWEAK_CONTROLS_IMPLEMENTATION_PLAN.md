# Runtime tweak controls: audit and implementation plan

## Outcome

Add an always-available in-game tuning surface, modeled on the descriptor/catalog/service/panel architecture in `junnyboi/proto-scroller`. The tower-defense implementation exposes 58 typed controls across UI, gameplay, audio, player, enemies, and environment without mutating authored `.tres` resources.

The `TWEAK CONTROLS` launcher is owned by a global `CanvasLayer`, stays 16 px from the bottom-right corner in landscape and portrait, renders at exactly 50% opacity while idle, and becomes fully opaque on hover. It remains visible while the modal is open. F10 is the keyboard shortcut; Escape or Resume closes the modal.

## Codebase audit

The current game already has clean tuning boundaries that can be reused rather than bypassed:

- `GameConfig`, `StageDef`, `OperatorDef`, `EnemyDef`, and `SkillDef` are the authoritative battle inputs.
- `BattleView` creates the battle model, owns presentation nodes, and is the correct adapter boundary between runtime settings and simulation resources.
- `Music`, the Master/Music/SFX audio buses, and the dynamic music director own audio behavior.
- `TextScale` owns accessibility font scaling and must remain composable with runtime multipliers.
- `MapNavigator` owns pointer, touch, trackpad, and wheel panning.
- Terrain, landmarks, shadows, health bars, HUD, tutorial overlays, and the combat effect layer are already addressable presentation nodes.

The scroller reference separates metadata, values, persistence, and UI. This implementation keeps that separation:

1. `RuntimeTweakCatalog` is the typed source of truth for labels, descriptions, defaults, bounds, steps, integrity, and application timing.
2. `TweakControls` owns values, delta-only persistence, launcher/modal lifetime, and resource adapters.
3. `RuntimeTweakPanel` renders native controls from descriptors and contains no battle rules.
4. `BattleView`, `Music`, and `MapNavigator` consume values at explicit runtime boundaries.

## Application boundaries

| Boundary | Meaning |
| --- | --- |
| Live | Applies immediately to the current screen or battle. |
| Next battle | Rebuilds battle configuration or the deterministic stage schedule when a battle opens. |
| Next deploy | Changes the runtime operator definition used by future deployments; existing operators retain their current simulation state. |
| Next spawn | Changes the runtime enemy definition used by future spawns; existing enemies retain their current simulation state. |
| Next cue | Changes playback properties when the next music cue starts. |
| Next transition | Changes the duration of the next music crossfade. |

Gameplay-affecting non-default values mark the battle HUD as `TWEAKED`. Authored resources stay untouched: definitions and stages are deep-duplicated before tuning, and spawn multiplication preserves deterministic ordering.

## Implemented control inventory

### UI — 8 controls

| Control | Default / range | Applies | Runtime owner |
| --- | --- | --- | --- |
| Text scale | 1.00×; 0.80–1.50 | Live | Composes with the current `TextScale` accessibility value. |
| Battle HUD scale | 1.00×; 0.75–1.50 | Live | Battle status panel transform. |
| Battle HUD opacity | 1.00×; 0.35–1.00 | Live | Battle status panel modulation. |
| Health-bar width | 1.00×; 0.50–2.00 | Live | Operator and enemy health-bar sizing. |
| Health-bar height | 1.00×; 0.50–2.00 | Live | Operator and enemy health-bar sizing. |
| Tutorial hints | On | Next battle | First-mission and map-navigation tutorial gates. |
| Map-hint opacity | 1.00×; 0.00–1.00 | Live | Map navigation overlay. |
| Tweak-panel opacity | 0.96; 0.65–1.00 | Live | Tweak panel surface. |

### Gameplay — 11 controls

| Control | Default / range | Applies | Runtime owner |
| --- | --- | --- | --- |
| Core health | 10; 1–100 | Next battle | `GameConfig.base_hp_start`. |
| Starting DP | 10; 0–99 | Next battle | `GameConfig.dp_start`, clamped to tuned cap. |
| DP cap | 99; 10–999 | Next battle | `GameConfig.dp_cap`. |
| DP regeneration | 1.0 s; 0.1–5.0 | Next battle | Converted to deterministic simulation ticks. |
| Retreat refund | 50%; 0–100 | Next battle | `GameConfig.retreat_refund_percent`. |
| SP regeneration | 1.0 s; 0.1–5.0 | Next battle | Converted to deterministic simulation ticks. |
| Damage stagger | 8 ticks; 0–30 | Next battle | Enemy post-hit movement stagger. |
| Spawn timing | 1.00×; 0.25–3.00 | Next battle | Stage spawn ticks and wave starts. |
| Enemy quantity | 1×; 1–4 | Next battle | Deterministic copies of authored spawn entries. |
| Leak-limit bonus | 0; -2–20 | Next battle | Added to authored stage leak limit. |
| Simulation rate | 1.00×; 0.25–3.00 | Live | Multiplies the active 1×/2×/4× battle speed. |

### Audio — 8 controls

| Control | Default / range | Applies | Runtime owner |
| --- | --- | --- | --- |
| Master gain | 1.00×; 0.00–1.50 | Live | Multiplies the current Master bus level. |
| Music gain | 1.00×; 0.00–1.50 | Live | Multiplies the current Music bus level. |
| SFX gain | 1.00×; 0.00–1.50 | Live | Multiplies the current SFX bus level. |
| Music enabled | On | Live | Music bus mute composition. |
| SFX enabled | On | Live | SFX bus mute composition. |
| Dynamic battle music | On | Live | Threat/health state updates in `BattleView`. |
| Music pitch | 1.00×; 0.75–1.25 | Next cue | New music transitions and cues. |
| Music crossfade time | 1.00×; 0.00–2.00 | Next transition | `Music` transition duration. |

### Player — 11 controls

| Control | Default / range | Applies | Runtime owner |
| --- | --- | --- | --- |
| Operator health | 1.00×; 0.25–5.00 | Next deploy | Runtime `OperatorDef.hp`. |
| Operator attack | 1.00×; 0.25–5.00 | Next deploy | Runtime `OperatorDef.atk`. |
| Operator defense | 1.00×; 0.00–5.00 | Next deploy | Runtime `OperatorDef.defense`. |
| Operator resistance | +0‰; -500–1000 | Next deploy | Clamped runtime resistance. |
| Operator attack speed | 1.00×; 0.25–4.00 | Next deploy | Runtime attack interval. |
| Deployment cost | 1.00×; 0.25–3.00 | Next deploy | Runtime DP cost. |
| Block bonus | +0; -3–8 | Next deploy | Runtime block capacity. |
| Skill SP cost | 1.00×; 0.25–3.00 | Next deploy | Duplicated runtime `SkillDef`. |
| Operator visual scale | 1.00×; 0.50–2.00 | Live | Artwork only. |
| Operator visual tint | White | Live | Artwork only. |
| Operator animation speed | 1.00×; 0.00–3.00 | Live | Presentation clock only. |

### Enemies — 10 controls

| Control | Default / range | Applies | Runtime owner |
| --- | --- | --- | --- |
| Enemy health | 1.00×; 0.25–5.00 | Next spawn | Runtime `EnemyDef.hp`. |
| Enemy attack | 1.00×; 0.00–5.00 | Next spawn | Runtime `EnemyDef.atk`. |
| Enemy defense | 1.00×; 0.00–5.00 | Next spawn | Runtime `EnemyDef.defense`. |
| Enemy resistance | +0‰; -500–1000 | Next spawn | Clamped runtime resistance. |
| Enemy attack speed | 1.00×; 0.25–4.00 | Next spawn | Runtime attack interval. |
| Enemy movement speed | 1.00×; 0.25–4.00 | Next spawn | Runtime tile speed. |
| Enemy leak damage | 1.00×; 0.00–5.00 | Next spawn | Runtime core damage. |
| Enemy visual scale | 1.00×; 0.50–2.00 | Live | Artwork only. |
| Enemy visual tint | White | Live | Artwork only. |
| Enemy animation speed | 1.00×; 0.00–3.00 | Live | Presentation clock only. |

### Environment — 10 controls

| Control | Default / range | Applies | Runtime owner |
| --- | --- | --- | --- |
| Backdrop color | `#11131f` | Live | Battle background. |
| Backdrop brightness | 1.00×; 0.25–2.00 | Live | Battle background luminance. |
| Terrain tint | White | Live | Terrain and landmark artwork. |
| Terrain opacity | 1.00×; 0.25–1.00 | Live | Terrain and landmark artwork. |
| Shadow opacity | 1.00×; 0.00–2.00 | Live | Operator/enemy ground shadows. |
| VFX opacity | 1.00×; 0.00–2.00 | Live | Combat effect layer. |
| Screen shake | 1.00×; 0.00–3.00 | Live | Battle camera shake amplitude. |
| Map pan sensitivity | 1.00×; 0.25–3.00 | Live | Mouse, touch, trackpad, and wheel navigation. |
| Endpoint landmark scale | 1.00×; 0.50–2.00 | Live | Spawn/core landmarks. |
| Restoration-seal opacity | 0.88; 0.00–1.00 | Live | Act II restoration lattice. |

## Delivery phases

1. **Catalog and service:** define and validate typed descriptors; store sanitized values; persist only non-default deltas to `user://runtime_tweaks.cfg` with a short debounce.
2. **Global UI:** register the autoload; construct the responsive panel and always-on launcher; support search, category filters, sliders/spin boxes/toggles/color pickers, per-control reset, Reset All, F10, Escape, and exact pause-state restoration.
3. **Runtime adapters:** deep-duplicate battle configuration/resources, apply next-battle/deploy/spawn controls at their stated boundaries, and route live presentation/audio/navigation values to their existing owners.
4. **Integrity and interoperability:** label gameplay-modified battles, preserve authored resources and deterministic schedules, and compose audio/text scaling with existing settings changes.
5. **Verification:** validate editor import, catalog/persistence/launcher/modal behavior, portrait layout, configuration adapters, direct-battle integration, and one representative 1280×720 visual capture in isolated user-data directories.

## Acceptance criteria

- The launcher is present on every scene, bottom-right at a 16 px margin, 50% opaque at rest, and 100% opaque on hover.
- All six requested categories are searchable and expose the 58 controls above with honest application timing.
- Reset All produces no modified deltas; saved data contains only non-default values.
- Opening the panel pauses battle activity and closing it restores the exact prior pause state.
- Current settings remain authoritative baselines for text and bus volume; tweak values act as reversible multipliers.
- Battle configuration, operator deployment, enemy spawning, live presentation, audio, and navigation each respond at their documented boundary.
