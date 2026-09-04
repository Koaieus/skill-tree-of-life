# Handoff: one real automated multiplayer run (rung 4)

Written 2026-09-04 against master `de43c47`, for the next session that wants to
build the end-to-end test. **The assessment and the plan live on #754** — this
file only says where things are and what order to take them in.

## State

- **Authoritative:** #754 (the plan + acceptance), `docs/domain/multiplayer-harness.md`
  (rungs 1-3 and the new "A link that ends mid-run" section), #665 (the owner's
  two-machine smoke test — rung 4 does *not* close it).
- **Verdict already reached (see #754):** on this machine, two headless
  processes, no Docker, a mise task rather than a GUT test. Do not re-open
  Docker or "two worlds in one SceneTree"; the doc's reasons still hold.
- **What exists to build on:** rung 3 (`MetaRoot._drive_lobby_from_cmdline`,
  `GameRoot._announce_first_turn_for_rung_3`) drives the shipped menu in two
  processes and prints a fingerprint at first turn. `GameRoot.hand_seat_to_ai`
  (883fa11) is the autoplay primitive. The playground tab
  (`addons/mp_sandbox/mp_sandbox_panel.gd`) launches scene pairs but not rung 3.

## Order

1. #754 items 1-3 (autoplay flag, verdict + quit, `mise run mp:e2e`) — one warp.
   Item 4 (small preset, zero AI delay) is part of the same unit; without it the
   run is minutes long.
2. #754 item 6 (playground tab row) — small, can ride the same warp or follow.
3. #754 item 5 (`--drop-after`, the disconnect leg) — a second unit; it needs
   the first green.

## Couplings

- The autoplay flag and the rung-3 flag must share the "read nothing by default"
  contract; a test that parses arguments breaks the GUT run (`_RUNG3_FLAG` is
  the model).
- The verdict line's `WorldFingerprint.describe` is what makes two logs
  comparable; a run-end fingerprint that includes anything presentation-side
  (VFX state, camera) will never match. Keep it on the graph.
- #748 (the suite hangs when the GUT pre-run hook fails to load) is unrelated
  but is the trap a fresh worktree hits first; check `.godot` before blaming
  rung 4.

## Delete when

#754 is closed, or the owner decides rung 4 is not wanted (then close #754 with
the reason and delete this file in the same commit).
