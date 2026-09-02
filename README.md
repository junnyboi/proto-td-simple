# Game template - TD
This is designed to be a lightweight game template for tower defense style games.

## Run

Open the repository in Godot 4.7.2 or run:

```bash
godot --path .
```

The main scene is `res://scenes/loading.tscn`. Loading opens the start screen, and
the campaign screen is entered only after the player activates **Start**.

## Basic development check

For runtime changes, verify the final candidate with a direct import and bounded boot:

```bash
tools/run_godot_isolated.sh --headless --import
tools/run_godot_isolated.sh --headless --fixed-fps 60 --quit-after 120
```

Documentation-only changes do not require an engine check. Run focused tests or manual previews when they are useful for the code being changed. Web export and browser checks are release-only.

Run SceneTree tests through `tools/run_godot_test.sh`. Each invocation receives a unique disposable `user://` directory and log, so tests can never replace a campaign belonging to the editor or playable game. Direct `godot --script` launches for files under `tests/` or `test/` fail closed.

## Contributions

Use ordinary Git branches and commit messages. Validate once on the final candidate tree. Revalidate after conflict resolution only when the resolved code changes behavior. Never rewrite `master`; `--force-with-lease` is acceptable on a contributor-owned feature branch.
