# Repository Agent Instructions

## Risk-based verification

Use the smallest gate that matches the change:

- **Instructions, documentation, audit reports, or release metadata only:** run formatting/diff checks only. Do not launch Godot, capture screenshots, export, or browser-test unless explicitly requested.
- **Routine `git pull, export web bundle and redeploy`:** run one isolated bounded boot **or** one focused regression, export artifact/count/hash checks, and one browser smoke test on the final managed host. Do not test both local and managed browsers unless the managed host fails or the loader/export changed.
- **Localized runtime or UI changes:** run direct import plus one to three focused tests for the touched system. Add one representative visual capture only when pixels/layout changed.
- **High-risk changes**—save/persistence, economy authority, migrations, destructive data actions, engine/export settings, loader/WASM, audio routing, security, or content-pack integrity—run the focused tests needed for that risk. Expand scope only when a focused check fails or exposes broader coupling.

Never run the full suite by default. Do not repeat already-passing tests after compatible merges unless their code changed. Do not capture both landscape and portrait unless responsive behavior changed. Do not probe every unchanged managed film or pack on every deployment; verify only new/changed objects plus one final runtime load. If a regenerated artifact is byte-identical to the deployed object, reuse it and update release metadata without re-uploading.

## Isolate test user data

Every Godot test or visual harness must use a unique disposable `user://` directory. Use `tools/run_godot_test.sh tests/<name>.gd` for SceneTree tests and `tools/run_godot_isolated.sh <godot arguments...>` for boot or visual checks. Never run repository tests directly against the playable `Game template - TD` application-data directory.

Tests that exercise campaign slots must preserve and restore every slot artifact during cleanup. If shared player data may have been touched, stop and rerun only in isolation.

> Standing rule: **sync once, assess risk, run the minimum relevant gate, export once, and deploy—no ceremonial verification marathons.**
