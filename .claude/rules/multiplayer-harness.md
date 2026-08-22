---
description: The two-process multiplayer harness — why two OS processes, what mirrors, what deliberately does not
paths:
  - "network/**"
  - "addons/mp_sandbox/**"
  - "scenes/dev/mp_dev_sandbox.gd"
---

The sandbox host's **Multiplayer** tab launches **two OS processes** of
`scenes/dev/mp_dev_sandbox.tscn` over ENet on localhost. Never "simplify" it to
two viewports in one process: `Events` is a process-global bus carrying live
node/entity references and every listener connects unscoped, so world B's
`VictorySystem` would latch on world A's death.

**One direction only, on purpose.** The host broadcasts confirmed commands; the
client applies them through its own `CommandApplier` and is otherwise a frozen
spectator. An intent channel upward is #463 (`Needs design`) — don't open it
here. Two instances prove *host acts → client mirrors*, never two people playing.

**A verb that does not cross is a missing submission site, not a transport gap.**
The link mirrors everything `CommandApplier` handles — grep who raises the
command before suspecting the wire.

**A `✗ DIVERGED` line is the harness working.** Chase divergence only on the
verbs `CommandApplier` actually handles — which is now every one of them:
attacks since #511 (`--autopilot` casts one) and loot since #522. As of #527
the fingerprint folds ownership + topology (edges) + accumulated per-node
state (stake/allocation/regen, HP quantized to int) — NOT derived `StatBoard`
totals, so a stat recompute that changes nothing accumulated still won't move
it; every effect the fold DOES cover is pinned by tests, not by the overlay.

**`--probe` measures the RESOLVE half of an attack, never the LAND half (#529).**
The client-only determinism probe re-resolves each received `launch_attack` from
`(plan, seed)` and diffs the hit set, order, arrival clock, crit tiers, costs and
timeline — *not* effective damage, HP numbers, the reclassified kind, the
`FLAG_GATED` bit or the dealloc sets, which `AttackRecord`'s own contract says a
peer cannot re-derive. So don't widen the diff to "the whole record" — that
reports 100% divergence for structural reasons. Its `skipped` column is
`CommandLink` declining to compare (queue non-empty / superseded), **not** a
pass, and `exempt` is loot's host-only roll working as designed.

See docs/domain/multiplayer-harness.md and docs/domain/determinism-probe.md.
