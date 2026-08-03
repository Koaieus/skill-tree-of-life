# Balance harness (#268)

**Informative only — an order-of-magnitude smell test for runaway or non-fun
values. Not a source of truth and never a build gate** (amendment, 2026-08-03).
Real balance is too complex to model faithfully; nobody should read a harness
number here as "the correct value." A human supplies "this plays nice" — the
harness supplies cold, re-runnable numbers and a place to watch a handful of
named ratios drift.

## What this is

An evaluator, not a search: a fixed set of named scenario fixtures
(`balance_scenarios.gd`), each assembling real `Entity`/`SkillNode` instances
via `preload(...).instantiate()` and driving them through the real allocation
(`AllocationSystem`), damage (`Mitigation.apply` / `SkillNode.take_damage`),
and turn-upkeep (`Entity._on_turn_started`) code paths — never a
reimplementation of a combat formula. See `docs/domain/` and
`.claude/rules/stats-system.md` for what those paths actually do.

## Running it

```
mise run balance                                              # full table + snapshot
mise run balance:sensitivity -- mirror_L20 dexterity 5 40 5   # 1-D slice
```

`mise run balance` always exits 0 — a non-zero exit is reserved for the
harness crashing, never for an `OUT` invariant reading (see `invariants.json`'s
header).

## Files

- `balance_fixture.gd` — builds one entity+territory at a target level by
  driving the real level-up path (`Entity._on_xp_replenished`), not by
  re-deriving the D-16 owned-node-count formula. That formula has already
  moved twice (see #268's "your axes moved" comment); driving it for real
  means a future change is picked up automatically.
- `balance_scenarios.gd` — the named scenario fixtures + readout computation.
- `balance_invariants.gd` + `invariants.json` — the ratio-invariant config
  and checker. **Every range ships `TBD`** — filling one in is a #248
  balance-pinning-session decision, never an implementing agent's call (D-13).
- `balance_harness.gd` — glues the above together, formats the table, writes
  the snapshot.
- `run_balance.gd` / `run_sensitivity.gd` — the two `SceneTree` entry points
  `mise.toml`'s tasks invoke.
- `snapshot.md` — committed output of the last `mise run balance` run. A
  balance change shows up as a diff here.

## Snapshot staleness — this is not #274's job

`tools/balance/**` is not in #274's files-owned list. When #274 lands
(`spell_damage` gets a real default, currently `0.0`/absent — every spell
seed changes), the committed `snapshot.md` goes stale against the new spell
numbers. **Refreshing it is a follow-up task, not #274's responsibility** —
#274 must not widen its ownership to touch this directory. Re-run
`mise run balance` and commit the new snapshot once #274 lands (and again
after any future change to a formula this harness reads).

## Known gaps (deliberate — see #268's NOTES)

- No spell/magic-channel readout: `spell_damage` doesn't exist on the board
  yet (#274 is landing it concurrently). Spell reach's ×2 hard cap (D-18) is
  worth a fixture once that stat exists — not invented here ahead of it.
- XP-curve and procgen↔level readouts are undefined until #248 pins those
  axes.
- Filling in real threshold values is a #248 pinning-session task, not this
  harness's.
