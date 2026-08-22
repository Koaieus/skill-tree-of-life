# Swarm brief — LAN wave 1

**Paste this to the orchestrating agent.** Spent once the four units below are
merged; delete it then.

## What to run

Four units, all `Ready`, all milestoned `LAN 2026-08-31`. Each issue carries its
own `## Acceptance spec` — that comment is the worker prompt, read it in full.

| Unit | Issue | Independent? |
|---|---|---|
| Graph snapshot: wire format + join handshake | **#527** | yes |
| Run-setup replication: `RunConfig` + `ParticipantRoster` | **#528** | yes |
| Stable-sort hitscan results | **#530** | yes |
| MP harness rung 1: AI opponent + verb sweep + turn/seat assertions | **#532** | shares one file with #527 — see below |

**Do NOT pull these**, though they sit nearby:

- **#531** (mount `CommandLink` in `GameRoot` + IP screen) — `Ready`, but read
  its 2026-08-22 comment first: it collides with the harness, and #532 is
  touching that same harness this round. Land it *after* #532, not beside it.
- **#529** (determinism probe) — `Ready` and blocked-by #530. It is the unit that
  *decides the sync model*, so its result is an owner call, not a merge. Run it
  only after #530 lands, and report its numbers rather than acting on them.
- **#533** (harness rung 2) — `Backlog`, blocked-by #527/#528/#531.
- The **upward intent channel** — deliberately unfiled. Its whole content is
  which branch `CommandApplier.submit()` takes, and #529 picks that. If a worker
  proposes writing it, stop them.

## The one file overlap

**`network/world_fingerprint.gd`** — #527 adds a topology fold, #532 adds an
HP/stats fold. Not a fence: land one, rebase the other. **Do not let them invent
two fingerprints**; the end state is one function that folds ownership +
topology + HP/stats, because rung 2 (#533) and the probe (#529) both need all
three.

`network/command_link.gd` is touched by #527 and #528. Ordinary sequencing.

## Context every worker should read first

1. `docs/domain/multiplayer-sync-model.md` — the architecture.
2. `docs/handoffs/lan-versus-transport.md` — the 2026-08-22 design session: the
   three-tier snapshot model, the payload arithmetic, and **the fact that the
   sync model is not settled**. A worker that assumes intent-up/confirm-down is
   assuming a decision nobody has made.
3. `#463`'s two comments — the acceptance spec and the pivot.
4. `.claude/rules/multiplayer-sync.md` and `.claude/rules/multiplayer-harness.md`.

## Three traps already found, so nobody re-finds them

- **`docs/domain/multiplayer-harness.md` is stale**, and #532 fixes it: it says
  the AI bypasses `CommandApplier` per #512. **#512 landed** —
  `ai_controller.gd:156,176,384` submit commands. Anything reasoning from that
  claim is reasoning from a world four days gone.
- **`CommandApplier.is_authority` is written and read by nothing** today
  (`command/command_applier.gd:95`, written by `CommandLink.mode`). #532 gives it
  its first reader — gating a mirror peer's `AiController` so it does not submit
  locally. Do not let a worker repurpose the flag for the upward channel while
  #529 is still open.
- **`WorldFingerprint` folds ownership only, on purpose.** A cast that kills
  nothing and a cast that never ran produce the same number. Any "the
  fingerprints agree" claim is weaker than it sounds until #527/#532 land.

## Verification

`mise run test` — ~110s, prints a verdict, full log at `.godot/gut-last.log`.
Never re-run it to grep it differently. #362 (`test_fan_scene`) is a known
pending, not a regression.

The harness units (#530, #532) also want a real two-process run:

```
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=host --port=9099 --autopilot
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=client --address=127.0.0.1 --port=9099
```

A green suite is **not** a substitute for the owner's eyeball on offline play
being unchanged — that is #463's own gate condition and it is the owner's call,
not a worker's.
