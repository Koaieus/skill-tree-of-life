# Handoff: #463 versus transport — the swarmify pass of 2026-08-22

**Spent when** #529's determinism probe has produced a number and the sync model
is chosen. Delete it then.

**Two of the three halves have now fired.** The children are all filed *and
closed* (#527/#528/#530/#531 landed 2026-08-23), and **the probe has reported —
twice, clean**: 773 commands, zero divergences, `skipped: 0` on every verb, 31/31
attacks re-derived, re-run at `4174f36` after #545. Both tables are comments on
#463.

**What is left of this file is the model choice alone**, and it is an unmade
owner decision, not a missing measurement. Note that
`docs/domain/multiplayer-sync-model.md` still presents lockstep as *rejected*,
and every ground it rejected on has since been retired (#530, #512, and the
host-only loot exemption in `.claude/rules/multiplayer-sync.md`) — see
`docs/handoffs/domain-doc-alignment-2026-08-23.md`, item 1.

The **acceptance spec lives on #463** (comment of 2026-08-22) and is the
authority for decisions 1–8. This file carries only what the spec cannot: the
back-and-forth that produced it, and the late pivot that partially supersedes it.

## The one-paragraph version

#463's body is stale — roughly 60% of what it scoped has already shipped
(`network/` has the seam and both transports, `CommandLink` mirrors every verb,
`Entity.entity_id` landed with #509, and the whole gate #474/#475/#458 is
cleared). What remains is a graph snapshot, run-setup replication, an upward
channel, and a lobby. Late in the session the owner pulled toward **lockstep +
snapshot recovery** instead of intent-up/confirm-down, and that question is
being settled **by measurement, not argument**.

## The framing that replaced the body's

> **Everyone knows everything. The host is the referee for the handful of
> moments that have no reproducible answer.**

Not "host knows all, client knows just-enough". Everything downstream follows
from this.

## The pivot — read this before implementing child 3

The spec's decision 5 says the client does not pre-simulate and applies the
host's confirmed command. **That is now provisional.** The owner's closing call:

> *"lockstep + some backup/recovery mechanism sounds more and more
> interesting"* — and, on the determinism tax, *"1 for sure. i think this game
> is supposed to be just that, no funky RNG. if you roll locally, broadcast the
> seed you rolled it with and everyone should agree."*

Two things changed lockstep's odds mid-session:

1. **Child 1 is a correction channel.** Classic lockstep aborts on desync
   because it has none. A full graph snapshot at ~20–80 KB / 1–7 ms on LAN turns
   desync into resnapshot.
2. **Turn gating deletes lockstep's ordering problem.** Decision 4 ("not your
   turn, you can't do shit") means exactly one command producer exists at any
   moment. No tick sequencing, no input-delay buffer, no rollback — which is
   most of what makes lockstep miserable elsewhere.

What lockstep buys here: the VFX-duration lag disappears outright (every peer
resolves the same plan+seed at the same instant), total host/client code
symmetry, and a tiny wire. #511's populated-record `LaunchAttackCommand` is not
wasted — it becomes the recovery / late-joiner path.

What it costs: a **permanent project-wide determinism constraint** on all future
gameplay code, and genuinely nasty desync debugging (partly mitigated —
`CommandLink` already fingerprints per command). The owner accepted the
constraint deliberately, as a discipline they want anyway.

## The decision procedure

**Children 1 and 2 are model-independent and are needed under both models.**
Build them; no bet is made. The model choice lives entirely in child 3, and is
decided by a **determinism probe**: in the existing two-process harness, have
the mirroring client *also* re-resolve each command locally and compare its
result against the host's, logging mismatches without changing gameplay.

- Probe runs clean over a few hundred commands → take lockstep.
- Probe lights up → you have the divergence list instead of a hunch.

The probe is also what would have caught the hitscan-ordering question
empirically rather than by argument.

## Two claims that were argued and then corrected — do not re-litigate from the wrong side

- **"Physics queries make attacks irreproducible."** Overstated. Only the
  hitscan is used; scan *positions* come from XPBD. Owner: *"same input -> same
  scans -> different order per scan? just stable-sort those and voila."* Filed
  separately; it is a prerequisite for the probe meaning anything.
- **"Rotating authority forecloses fog."** Withdrawn. The owner's fog vision
  withholds *derived* state (see an enemy node's local health/armor/granted
  modifiers, but you cannot assemble the entity's totals until you see its
  Core) — that is tier 3, so full replication of tiers 1–2 is compatible with
  it. Rotating authority was dropped for the real reason instead: it buys ~1 ms
  on LAN against a handover-quiesce protocol. See #463 decision 4.

## The perf question the owner raised, with the arithmetic

Worry: a big entity picking +1 CON at 100+ owned nodes triggers a derived
recalc across every node's health bin, possibly 5× during one attack.

The pinned number is FOCUS/#470: **`force_allocate` worst case 5.9 ms at 200
owned**. Five recalcs in one attack is ~30 ms at 200 owned.

Under lockstep each peer pays that on its own machine, in parallel, so wall
clock is unchanged from single-player. Under a delta-broadcast model (#521) the
host pays the same 30 ms **plus** serialising ~1000 stat deltas, and the peer
pays deserialise + apply. **Recompute is strictly cheaper**, which is what the
owner argued. #470 (dirty-mark / batched flush) is the filed fix if a slow
machine makes it bite.

## What was filed

| Unit | Issue | Note |
|---|---|---|
| Graph snapshot: wire format + join handshake | **#527** | model-independent |
| Run-setup replication: `RunConfig` + roster | **#528** | model-independent |
| Mount `CommandLink` in `GameRoot` + type-an-IP screen | **#531** | model-independent; carries the calendar risk (UI) and the node-path trap |
| Determinism probe — produces the number | **#529** | blocked-by #530 |
| Stable-sort hitscan results | **#530** | not a child; gates #529 |
| The upward channel | *unfiled, on purpose* | #529's result picks its shape |

All five are `Ready` and milestoned `LAN 2026-08-31`. #527/#528/#529 are
sub-issues of #463; #530 and #531 are not children of the hub's DAG in the same
way (#530 is a prerequisite, #531 is the integration).

**Do not file the upward-channel unit before #529 reports.** Its whole content
is the `submit()` branch, and which branch to write is the open question.

### The harness ladder, filed 2026-08-22 in the same session

| Rung | Issue | State |
|---|---|---|
| 1 — existing `mp_dev_sandbox`, no state crosses | **#532** | `Ready` |
| 2 — procgen'd scene, graph + run settings cross | **#533** | `Backlog`, blocked-by #527/#528/#531 |
| 3 — the client acts and it round-trips | *unfiled* | needs the upward channel |
| 4 — the real menu sets up a lobby | #531 + #461 | — |

Rung 1's value is precisely that **no state crosses by construction**, so a
divergence there is a messaging bug and cannot be a serialization bug. That is
what makes rung 2's failures diagnosable.

**#532 found a stale justification worth knowing about:** `mp_dev_sandbox.gd`'s
docstring and `docs/domain/multiplayer-harness.md` both say Blue must be human
because "the AI still calls `AllocationSystem` / `BattleSystem` directly
(#512)". #512 landed; `ai_controller.gd:156,176,384` submit commands. Restoring
the AI exposes a real trap — `GameRoot._ensure_controllers` attaches an
`AiController` on BOTH peers, so a mirror peer's AI would submit locally. That is
where `CommandApplier.is_authority` finally gets its first reader.

**`world_fingerprint.gd` is #527's alone.** The richer fold (ownership +
topology + accumulated int state, HP quantized, derived totals excluded) is
downstream of #527's tier-2 read accessors, not beside them — so #527 lands the
whole contract and #532 writes assertions against `compute()` as-is. See
`docs/handoffs/swarm-brief-lan-wave-1.md`.

**#531 collides with the harness** — `mp_dev_sandbox.tscn` already mounts its own
`Transport` + `CommandLink` as direct children and reads them as `$Transport` /
`$CommandLink`, and the chain is `mp_dev_sandbox` -> `dev_sandbox` ->
`game_root`. Warned on #531; the harness must SWAP the inherited transport, not
add a second.

## Other board actions
- #461: moved to `Needs design`. Owner: *"if it has open forks it should be in
  Needs design"*, and the separation from #463 is that #461 is looks/UX
  (*"we scaffolded in some crappy menus REAL FAST ... now lets do it more
  properly"*) where #463 is architecture. It does **not** block the lobby child.
- #521 stays open as the derived-state backstop, deliberately **not** merged —
  see #463 decision 8, and the arithmetic above for why it is now the less
  likely branch.
