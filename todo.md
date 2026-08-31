# Lightweight Two-Stage Game Template

- [x] Establish `junnyboi/proto-td-simple` as the canonical simplification repository and synchronize clean `master`.
- [x] Audit deterministic gameplay, campaign/UI, media footprint, infrastructure/branches, and the `proto-scroller` leaderboard reference.
- [x] Publish the dependency-ordered simplification proposal, measured footprint evidence, and implementation acceptance matrix.
- [ ] Approve the S1/S2, Recruit → Defender/Gunner, and compact-save contract.
- [ ] Implement phases 0–8: characterize invariants, replace P16 ownership, build the compact loop, convert media, and prune unreachable systems.
- [ ] Implement the separate local-first leaderboard, select and deploy a hosted backend, then add CI and enable GitHub template mode.

# Unified 21+ Anime-Gacha UI Revamp

- [x] Synchronize clean `master` with `origin/master` and verify Godot 4.7.2 compatibility.
- [x] Audit all 79 non-title UI and dialog states across staging, campaign, roster/training, gacha, Vahalla, battle, and results.
- [x] Generate eight desktop/portrait concept designs with GPT Image 2 using canonical adult Lunaris references.
- [x] Document the unified visual system, preserved-feature ledger, responsive contract, and phased implementation plan.
- [x] Phase 0: commit and push the audit, concepts, contract freeze, and accepted pre-change regression baseline.
- [x] Phase 1: implement shared Lunaris materials, typography, full-safe-area shell behavior, modal focus/veil helpers, and tests.
- [x] Phase 2: revamp Stage Select, Training/roster surfaces, Premium Resonance, Vahalla, and Results while preserving all authority boundaries.
- [x] Phase 3: revamp battle HUD, pause/resign, deployment/spell/tutorial/navigation presentation, and result ceremony without changing battle semantics.
- [x] Phase 4: run full import/boot/focused regressions, English/Chinese parity checks, landscape/portrait visual verification, and error scans.
- [x] Export the Godot 4.7.2 Web bundle and require HTML, JavaScript, WASM, and PCK artifacts with checksums.
- [x] Serve and test the bundle over HTTP/HTTPS; verify browser console, network, canvas, input, and responsive behavior.
- [x] Update the existing `proto-td-web` fullscreen host, run type/build checks, save public checkpoint `4f4e6ce6`, and verify exact-PCK deployment at `https://protohost-sqtjrsla.manus.space/`.
- [x] Increase title-screen wordmark, action buttons, and settings typography by exactly 15%; verify desktop/portrait containment and Start/Settings input flows.
- [x] Remove “resurrected” from the English title synopsis and its Chinese equivalent; align fallback/canon copy and verify landscape/portrait containment.
- [x] Complete a full Simplified Chinese localization and glyph-rendering audit: reach 925/925 catalog parity, including the full Act II narrative, with zero placeholder drift, missing production keys, or unresolved hard-coded visible strings; install the bundled CJK font across global, Aetheria, staging, battle, spell, input, and accessibility paths; repair reviewed gameplay/narrative terminology; regression-lock live locale switching; and visually accept 28 landscape/portrait states with no tofu.
- [x] Gameplay extension: implement Slow Field, unlock it after S6, teach it in S7, carry it into S8, and cover deterministic mechanics plus landscape/portrait visuals.
- [x] Add the first-clear S7 guided Slow Field cast, explicit duration/cooldown UI indicators, and deterministic S7/S8 paired balance telemetry with raw JSON/CSV evidence.
- [x] Refine the Slow Field aura to 0.46 opacity with an 18-second centered rotation, enforced by the native visual harness.
- [x] Convert Mission Control to a full-safe-area workspace, remove its decorative outer frame, and eliminate text/action overflow across 1280×720, 1024×576, 720×1280, and 390×844 layouts.
- [x] Add dedicated cold-blizzard Slow Field cast and expiration cues through GPT Image 2 carrier anchors, audio-bearing video extraction, deterministic mastering, and one-shot presentation lifecycle tests.
- [x] Refit the annotated Stage Clear screen with stage-number outcome copy, adjacent stars, enlarged tally and information typography, unframed Mission Yield rows, generous desktop margins, compact portrait scroll surfaces, and centered fixed 260×96 flat actions.
- [x] Apply the final annotated Stage Cleared spacing pass: keep the stage-clear title on one line inside a uniform 24px header inset, reuse 58px/46px Premium Resonance reveal stars, push metadata right with a 24px LEAKS inset, use uniform 24px Mission Yield/Consequence/Company Intact padding, and widen only Command by 36px with a narrow-portrait clamp; visually accept English and Chinese landscape/portrait plus bottom-scrolled Company Intact states.
- [x] Increase runtime typography by exactly 50% across the game and refit Mission Preparation with a transparent First Stand icon, padded status tabs, 3:1 roster/intelligence split, split information/portrait cards, and 30%-shorter clean actions.
- [x] Add eased staggered Mission Yield reward counters with reduced-motion completion, and apply the same stage-number, metadata, information, responsive, and fixed-action hierarchy to Stage Defeat.
- [x] Repair Mission Yield survivor XP projection to consume the canonical `{hero_id, delta: 100}` receipt schema, regression-lock multiple survivor rows, and visually verify settled `+100 XP` values in landscape and portrait.
- [x] Refit Premium Resonance with a GPT Image 2 Lunaris Return glyph, vertically aligned header, 64px wide-layout gutters, compact one-line guarantee telemetry, 50%-larger padded cards with top-anchored 25% bust zoom, and a 2.5× wider two-line hoverable action.
- [x] Refit the annotated Training roster with text-safe padded filters, right-of-icon faction counts, a Promotion Ready status filter, fixed 560px operator cards with 48×24 padding, a 64px inspector gutter, dossier-first identity layout, Edit-gated fields, and fixed 260×84 bottom actions across desktop, compact, Chinese portrait, and 390px editor states.
- [x] Refit Field Team selection with a 60/40 roster/intelligence split, intelligence-owned Hire Recruit, concise Marks/Hire copy, compact padded Recruit Order, 1.5× faction filters with tighter heraldry/count spacing, responsive operator columns with enlarged portraits, no Field Note, and promoted Loadout hierarchy.
- [x] Apply the annotated Field Team follow-up: dynamically pack every fitting 320px+ operator column, reflow on live viewport changes, rename the recruit module to Hire Recruit, match its title to Mission Intelligence, and target a responsive 660px desktop width with portrait containment.
- [x] Extend Field Team with rarity/level sorting, a draggable and keyboard-reorderable deployment-order rail, visible rarity/level card facts, and reduced-motion-safe hover/focus/selection animation.
- [x] Refine Training with universal 24×12 button padding, a 1,136px two-column ultrawide roster, a transparent gold inspector, tripled selected portrait, enlarged inspector typography, a padded Edit affordance, and fixed centered two-line Recruitment Order sorting.
- [x] Replace Training's global View Paths footer action with a promotion-eligible-only Choose Promotion control directly below the selected operator's Promotion Ready status.
- [x] Remove Training's bulk promotion plan and review/approval screens; apply each selected operator specialization immediately through the existing durable promotion transaction and retry lock.
- [x] Forfeit all survivor XP on voluntary resignation while preserving ordinary clear/leak/base survivor awards; add Space pause/resume before GUI dispatch and cycle the top-right speed selector through 1×, 2×, 4×, and paused (`0×`) with responsive Xvfb verification.
- [x] Implement early enemy variety with an armored S2 Shieldbearer, two-block S3 Breacher, durable S4 Interceptor, real Caster Arts attacks, GPT Image 2/video-to-sprites production assets, deterministic paired balance telemetry, and native landscape/portrait battle acceptance.
- [x] Playtest S2–S4 with guided, two-second slow-polling, and counter-blind policies; keep S2/S3 unchanged, make each S4 Interceptor lead its Drone escort, and regression-lock the resulting 3★→2★→2★ guided difficulty curve with native landscape/portrait acceptance.
- [x] Refit the annotated battle HUD: move live transmissions to the right beneath gameplay controls with a 64px gap, add localized 88×88 speaker visuals (72×72 below 600px) and 12px header spacing, double the landscape recruit selector to 1,360px, give the command deck 24px all-around padding, coordinate compact spell/pan-hint/deployment collisions, and safely suppress impossible short-landscape transmission layouts.
- [x] Enforce at least 24px internal padding throughout painted/textured content containers, replace all Button focus outlines and borders with a slight borderless golden surface tint, preserve independent pointer-hover feedback, and regression-lock responsive Mission, Settings, battle, Premium Resonance, Results, Valhalla, cinematic, and warning layouts.
- [x] Give the Defeated Mission Yield frame exact 64px all-around padding and make campaign authority award surviving deployed units 100 XP on clear, 50 XP on ordinary defeat, and zero XP on resignation; regression-lock English/Chinese Results projection and responsive scrolling.

# Premium Resonance Cinematic Completion

- [x] Replace the fixed 7.44-second result timer with natural `VideoStreamPlayer.finished` completion so every verified eight-second cinematic plays from start to finish.
- [x] Keep result input locked during download/playback, then allow mouse/touch anywhere or keyboard accept/cancel to dismiss the completed reveal and return to Resonance.
- [x] Preserve explicit Skip Reveal, reduced-motion fallback, failure fallback, localization, authoritative pull receipts, and Company Command audio restoration.
- [x] Remove the redundant Confirm Resonance screen; the primary Resonance action now locks once, dispatches exactly one authoritative pull, and proceeds directly to the reveal.
- [x] Refit the annotated browse screen with no outer/intro containers, enlarged Command Deck and guarantee telemetry, gold title-sized Marks, equal hero cards and portraits, minimal card copy, and a fixed flat Resonate action across desktop, compact landscape, and portrait layouts.
- [x] Top-align Premium Resonance browse art, cinematic videos, and static result plates; preserve horizontal centering, cover cropping, top-edge hover pivots, and zero vertical parallax across wide and portrait layouts.

# Company Command Sizing Reimplementation

- [x] Audit the supplied screenshot, measured runtime geometry, decorative safe areas, and mature gacha lobby sizing patterns.
- [x] Generate divider-free Company Command HUD and navigation-rail frames with GPT Image 2; retain all copy, state, focus, and interaction as native Godot controls.
- [x] Recompose standard landscape into segmented HUD, navigation rail, protected hero stage, and 620–700px command deck with explicit per-frame content-safe margins.
- [x] Implement compact-landscape and portrait command-sheet reflow with display-safe-area insets, local scrolling, 72px actions, and typography floors.
- [x] Add English/Chinese exact-resolution layout regressions and accept 1280×720, 1280×1100, 1024×768, and 720×1280 native renders with clean runtime logs.

# Approved Unified Interface Continuation

- [x] Preserve the user-approved concept and implementation plan verbatim under repository-root `docs/`.
- [x] Audit the synchronized runtime against all eight approved concept targets after the latest upstream feature integrations.
- [x] Close material visual/interaction gaps while preserving every authoritative behavior contract.
- [x] Run final Web export, direct/managed browser, WebDev checkpoint, and source push gates on the accepted implementation.
- [ ] Promote WebDev checkpoint `04dc9aae` through **Publish**, then verify public exact PCK `index-71c395e_a7c079ae.pck`, input, cinematic transport, geometry, and console.

# Faction-Led Soundtrack Redesign

- [x] Phase 0: remove rejected staging/battle music and obsolete pack infrastructure; retain `Astra Memoriam` for loading/title only; publish the canonical proposal.
- [x] Phase 1: implement data-driven `AudioCue`/`MusicProfile` resources, bar-quantized horizontal-state transitions, hysteresis, silence fallback, and regression seams.
- [x] Phase 2: generate, review, master, and integrate the Lunaris Company Command staging loop with Lyria 3 Pro.
- [x] Phase 3: generate and integrate Lunaris early-campaign and Air Raid adaptive battle suites for S1–S4.
- [x] Phase 4: generate and integrate Lunaris late-campaign, Gatecrasher boss, results, and tactical transition cues for S5–S8.
- [x] Produce and route the moon-glass UI click, back, confirm, menu-open, and menu-close suite through GPT Image 2 carrier anchors and audio-capable video extraction.
- [x] Produce a dedicated quiet moon-glass hover cue and bind it globally to eligible interactive controls with readiness, debounce, disabled/hidden suppression, semantic opt-out, and lifecycle coverage.
- [x] Escalate battle music below 30% base health through urgent next-bar critical/boss-critical states and an 8% tempo lift with hysteretic recovery.
- [ ] Phase 5: complete loudness, SFX-masking, mono/mobile, accessibility, Web packaging, playthrough, and release validation.
- [ ] Phase 6: produce Solcrest, Crimson, and Vesper suites only as their playable faction content enters production.

# Annotated Battle Map Overhaul

- [x] Phase 1: integrated GPT Image 2 + video-to-sprites photon portal and holy-crystal pedestal loops on every SPAWN/BASE tile; removed all blocked/elevated platform props across S1-S8; added endpoint, reduced-motion, clean-platform, and endpoint-aware map-fit regressions; visually accepted S2/S4; committed and pushed.
- [x] Phase 2: centered and enlarged the First Stand tutorial with 40 px heading, 28 px body, 260×84 high-contrast actions, and safe portrait reflow; doubled Recruit and Pause/Speed/Resign typography and targets; centered responsive grids and added first-button left insets; extended layout regressions; visually accepted landscape/portrait; committed and pushed.
- [x] Phase 3: passed direct import, bounded boot, all 39 standalone regressions plus all 6 repository smokes, clean Xvfb landscape/portrait input checks, Web export/HTTP/browser gates, updated the existing `proto-td-web` fullscreen host, and saved final checkpoint `6c50b142`; public Publish remains the explicit handoff because no direct publish tool is exposed.
- [x] Endpoint quality rebuild: preserved 589×600 portal and 401×600 crystal source frames in ≤4096px row-major atlases, displayed them at one-tile size with mipmapped linear filtering, verified native/Web sharpness, pushed master, and updated WebDev checkpoint `8b492ecd`.
- [x] Phase 4: applied the annotated in-battle UI corrections—doubled and centered the HUD with a 48px left inset, removed manual CENTER, compacted and rounded battle/deployment controls, left-aligned and responsively refit the First Stand tutorial, renamed its action to NEXT, and installed the approved English/Chinese route copy; passed import, bounded boot, all 50 current tests/smokes, strict error scans, and four clean Xvfb tutorial/live landscape/portrait captures.

# Act II Technical Scaffold — Historical Record

- [x] Audit progression, balance, stage architecture, save compatibility, and available combat systems for the stable S9–S16 technical scaffold; narrative findings were later superseded by the Anima War canon.
- [x] Generate and retain four non-canon historical concept boards plus a 600px repair-platform runtime seal with a 1920px master.
- [x] Preserve the superseded proposal as historical evidence until the Anima War rewrite replaced its narrative authority.
- [x] Implement stable S9–S16 maps, deterministic repair-platform behavior and Slow Field suppression, sixteen-stage progression/rewards, historical save restore, narrative slots, Act labels, and complete regression coverage; active story copy now follows `NARRATIVE_CANON.md`.
- [x] Pass Godot 4.7.2 import/boot, all current tests and smokes, strict 925/925 localization audit, landscape/portrait Xvfb checks, exact Web export/HTTP/browser gates, forward-only `proto-td-web` reconciliation, TypeScript/build checks, and checkpoint `7da5e373`.

# Advanced Operator Video-to-Sprites Release

- [x] Freeze eleven canon-aligned, restrained non-premium specialization briefs and generate 22 GPT Image 2 male/female reference sources plus 44 isometric NE/SE keyframes.
- [x] Generate and archive 88 silent four-second image-conditioned carriers; deterministically produce 176 quality-92 VP8 atlases with lossless alpha, 640×640 cells, 24-frame idle and 13-frame attack at 12 FPS, and exact-alpha NW/SW mirrors.
- [x] Version the manifest and animation schemas, register 22 class/gender resources plus 176 provenance rows, route canonical class identity after premium overrides, preserve classless legacy fallback, and remove the 192px animator assumption.
- [x] Add processor, registrar, schema, row-boundary, routing, premium-precedence, live-animator, generated-cache, and Xvfb visual-matrix coverage; repair three hidden keyed-collapse frames and validate all 88 authored records / 176 outputs.
- [x] Run the synchronized full 68-gate repository baseline, bounded boot, final error scans, and a 16-gate regression after the second forward reconciliation.
- [x] Commit and push the reconciled release to `master` without rewriting shared history.
- [x] Preserve every 560–640px source cell while configuring all 176 class/gender and 24 enemy-variant imports for quality-0.92 compressed storage plus mipmaps; reduce the reconciled Web PCK from 802,693,488 to 527,756,580 bytes and pass heavy-class plus S2/S3/S4 visual matrices.
- [x] Audit the compressed advanced sprites in live combat: measure all 176 atlases against composited PSNR/RGB/alpha/edge guards; inspect 11 complete close-up matrices and 66 landscape/portrait BattleView idle/attack frames with full gender/facing coverage; adjudicate Gunner against source frames; approve quality 0.92 for every class; add reusable fidelity/routing/capture regressions; and pass all 79 repository gates.
- [x] Export the optimized Godot revision, verify HTML/JS/WASM/PCK over HTTP and in Chromium, confirm WebGL 2 with 8192px textures, and reach Title plus Company Command without console, page, or request errors.
- [x] Layer the release onto the newest `proto-td-web` host with the exact 202,817,120-byte core and eleven class-scoped packs; pass type/build, managed HTTP, WebGL, fullscreen geometry, native input, responsive visual, and clean-console gates; save the final managed checkpoint.

# Act II Balance, Transitions, and Unique Score

- [x] Playtest S9, S12, and S16 under field, standard, and rapid deterministic policies; preserve JSON/CSV telemetry and a written tuning report.
- [x] Retune S9 lane windows, S12 continuous three-lane cadence, and S16 four-wave breathing room plus two-leak tolerance; regression-lock final difficulty envelopes.
- [x] Generate, preserve, master, checksum, catalog, and route eight unique looped Act II battle tracks with clean loudness, true-peak, and silence analysis.
- [x] Add responsive Restoration-seal entry and terminal transitions with local simulation hold, cue continuity, and reduced-motion behavior; accept landscape and portrait Xvfb captures.
- [x] Reconcile and push shared master, export/serve/browser-test the exact Godot Web release, advance the forward-only `proto-td-web` host, and save managed checkpoint `ac19895c`.

# High-Threat Wave Warnings

- [x] Author presentation-only escalation boundaries for S9 waves 2–3, S12 waves 2–3, and S16 waves 2–4 without changing the balanced simulation.
- [x] Generate and retain six distinct GPT Image 2 warning/particle masters; ship 600px transparent, mipmapped, quality-0.92 runtime derivatives.
- [x] Add localized stage-specific warning panels, portal-local emblem pulses and particles, warning-first transmission sequencing, terminal cleanup, and responsive reduced-motion behavior.
- [x] Add all-stage metadata validation plus permanent warning, asset, particle-count, and accessibility regression coverage; accept S9/S12/S16 landscape and S16 portrait captures.
- [ ] Reconcile and push shared master, export and browser-test the exact Godot Web release, layer it onto the newest `proto-td-web` host, and save the final checkpoint.

# Promoted Operator Portrait Continuity

- [x] Preserve canonical Recruit portrait identity while deriving the visible female/male specialization portrait from each non-premium operator's current promoted class.
- [x] Apply the shared presentation resolver to Training roster/dossier, Field Team cards, and Valhalla dossiers while preserving premium portrait precedence.
- [x] Add 11-class × two-gender routing, second-stage continuity, idempotency, real promotion/save restoration/receipt, Field Team texture, premium, and fallen-operator regression coverage.
- [x] Pass focused affected tests, the full Godot 4.7.2 baseline with zero failures, and representative landscape/portrait Xvfb visual acceptance.
- [x] Reconcile and push shared master, export source `16e8586` into the exact 231,526,672-byte core, pass local and managed HTTP/WebGL/geometry/input/console gates, advance the newest forward-only `proto-td-web` host, and save the final checkpoint.

# Elevated Platform Accessibility

- [x] Reproduce the user-reported rejection and trace it to 61 empty `BLOCKED` cells rendered identically to the 64 deployable elevated cells.
- [x] Audit S1–S16 and unify all 125 visible raised faces into one elevated placement and hit-test domain, including 61 historical `X` cells.
- [x] Preserve serialized stage topology, deterministic fingerprints, save/replay ancestry, ground-only placement, paths, and accepted balance heuristics.
- [x] Add landscape/portrait hit-testing plus StageDef, ticket, and BattleModel coverage for Mage Apprentice, Sorcerer, Gunner, Sniper, and Witch Doctor on every platform.
- [x] Capture a real S2 battle with Gunner and Mage Apprentice deployed on the two formerly blocked center platforms in landscape and rotated portrait orientation.
- [x] Pass the authoritative full baseline with zero failures and an independent code audit with no confirmed runtime defect.
- [x] Reconcile with concurrent campaign, facing-map, speed-control, and Field Team work; regress once and push shared master without rewriting history.
- [x] Export/browser-test exact runtime `8dee659b`, layer it onto the newest `proto-td-web` host, and adopt checkpoint `87858a44` after final managed hash/range/runtime verification.
