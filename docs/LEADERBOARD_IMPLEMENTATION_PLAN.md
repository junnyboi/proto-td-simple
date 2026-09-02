# Local and global mission leaderboard implementation plan

## Goal

Add an offline-first mission leaderboard to the current simplified tower-defense flow. A reusable dialog opens from the start screen and from a button on every mission-results screen. The dialog supports an editable saved username plus Local and Global standings; it never opens automatically after a mission.

## Player experience

1. The start screen exposes **Leaderboard** beside the existing entry actions.
2. Completing either a campaign or direct mission immediately records the result locally.
3. The results screen exposes **Leaderboard** without interrupting the existing retry, next-mission, and navigation paths.
4. The dialog opens on the Local tab, highlights the latest local result, edits a normalized 16-character username, and allows switching to or refreshing the Global tab.
5. Loading, live, offline, error, empty, and queued-submission states remain explicit. Network state never blocks mission completion or navigation.
6. Offline submissions remain in a bounded FIFO queue and retry on the next result, dialog open, or manual refresh.

## Score model

Score contract version 1 is calculated from the accepted mission ledger:

```text
2,000,000 × mission clear
+ 100,000 × mission number (s1…s10)
+  20,000 × stars
+      50 × kills
-     500 × leaks
```

The score is clamped to zero. The Node service ignores any client-supplied score and recomputes it after validating the ledger. Records sort by score descending, then oldest server timestamp, then submission ID for stable ties.

## Architecture

### Godot service

- `autoloads/leaderboard.gd` owns the username, top 50 local records, up to 100 pending global submissions, the global top 10 projection, and one serial `HTTPRequest`.
- State persists atomically to `user://leaderboard.json`, with a temporary file and recoverable backup during replacement.
- Browser exports resolve the API from `window.location.origin`; native builds use `leaderboard/api_base_url`. Headless networking is disabled except through the explicit test seam.
- `Game.commit_prepared_result()` records only after the tactical result or campaign resolution is accepted. It publishes the generated submission ID and score into `Game.last_result` for presentation without changing campaign authority.
- Clear Player Data stops the HTTP writer, removes the saved leaderboard with the rest of `user://`, and resets the live service projection.

### Shared in-game dialog

- `scenes/ui/components/leaderboard_dialog.tscn` and its script implement one modal used by both title and results.
- Local and Global tabs reuse the existing Lunaris visual language, keyboard/controller focus loop, Escape close behavior, safe margins, scrollable rows, localization, and text scaling.
- Username edits save locally on Save, Enter, focus loss, or close. Historical submissions keep the name under which they were completed; the new name applies to later missions.

### Global service

- `server/leaderboard_server.mjs` is a zero-dependency Node 22 service that hosts `build/web` and provides:
  - `GET /api/health`
  - `GET /api/leaderboard?limit=10`
  - `POST /api/leaderboard`
- POST validates the score version, submission ID, normalized username, stage ID, outcome, stars, kills, and leaks; it recomputes the score, deduplicates by submission ID, and atomically retains the best 1,000 records.
- The host applies request-size limits, bounded per-address submission rate limiting, same-origin security headers, optional configured CORS, safe static-path resolution, and generic internal errors.
- Production should set `LEADERBOARD_DATA_FILE` to durable storage. `HOST`, `PORT`, `WEB_ROOT`, and `LEADERBOARD_ALLOW_ORIGIN` are configurable.

## Data contract

Submission:

```json
{
  "submission_id": "1725253200-93f0b57d27ce4f3e9dfc6b8be1bb6ba2",
  "name": "COMMANDER",
  "stage_id": "s4",
  "victory": true,
  "stars": 3,
  "kills": 42,
  "leaks": 1,
  "score_version": 1
}
```

Public entry:

```json
{
  "rank": 1,
  "name": "COMMANDER",
  "score": 2461600,
  "stage_id": "s4",
  "victory": true,
  "stars": 3,
  "created_at": "2026-09-02T05:00:00.000Z"
}
```

## Verification plan

- Direct import and one bounded isolated boot.
- Focused Godot service test for score parity, normalization, ordering, atomic persistence, reload, and offline queueing.
- Focused Godot UI test for both buttons, modal behavior, tab switching, result non-auto-open behavior, and username editing.
- Existing Clear Player Data regression with a leaderboard artifact and live-service reset assertion.
- Node API tests for validation, score recomputation, sorting, deduplication, persistence, security/static hosting, plus a real Godot `HTTPRequest` submission round trip.
- One representative 1280×720 visual capture because title/results pixels changed; no portrait capture because the responsive behavior is covered structurally and the project rule requests one representative view for localized UI changes.

## Deployment

Export the Web preset to `build/web`, then run:

```bash
npm run dev
```

The game and `/api/leaderboard` will share `http://127.0.0.1:3000` by default. Deployment should keep the exported game and API on the same origin and mount durable storage for the leaderboard data file. The prototype has no account or signed-session system, so server validation limits malformed submissions but does not make a client-reported game cheat-proof.
