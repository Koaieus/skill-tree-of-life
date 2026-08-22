# Handoff: #463 versus transport — the swarmify pass of 2026-08-22

**Spent when** #463's children are filed and the determinism probe has produced a
number. Delete it then.

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

## Board actions taken in this pass

- #463: acceptance spec posted; becomes a hub.
- #461: moved to `Needs design`. Owner: *"if it has open forks it should be in
  Needs design"*, and the separation from #463 is that #461 is looks/UX
  (*"we scaffolded in some crappy menus REAL FAST ... now lets do it more
  properly"*) where #463 is architecture. It does **not** block the lobby child.
- #521 stays open as the derived-state backstop, deliberately **not** merged —
  see #463 decision 8, and the arithmetic above for why it is now the less
  likely branch.
