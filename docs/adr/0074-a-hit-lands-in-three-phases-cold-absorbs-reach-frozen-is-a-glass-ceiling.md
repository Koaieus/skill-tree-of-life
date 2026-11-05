---
id: 0074
title: A hit lands in three phases — read, land, settle — on one snapshot; Cold absorbs arriving reach one for one and is spent, Frozen (Cold >= graph degree + 1) is a glass ceiling that holds whole under T and breaks then absorbs at or above it; a medium is capped per node at k x T; Heat and Cold diffuse as one signed temperature
status: accepted
date: 2026-11-05
deciders: owner (phases, dual reach, Cold absorbs, Frozen threshold and glass, the k × T cap, one temperature, Frost → Cold); pass (the phase wording)
supersedes: []
superseded-by: null
revisit-when: "double counting on overlapping reaches proves unreadable, or a reach source that cannot be gathered as a target list appears"
sources: ["#1716", "#1733", "#1444", "#1660", "#1741", "docs/design/elements.md"]
tags: [combat, on-hit, elements, status, reach, determinism, architecture]
---

# ADR 0074 — A hit lands in three phases; Cold absorbs reach, Frozen is a glass ceiling, one temperature

## Context

ADR 0073 gave a hit one reach entry resolved first and left landing resolution open. Reach now has several sources at one landing (the hit's load, a node's Fuel or Charge, an arriving arc) and one counter (Ice's medium), and #1733 R4 wants landing pure on one snapshot. Riders are separate `HitInstance`s ordered at `HitLanding.place()` (ADR 0067) with #1741's order inside; nothing groups them into one landing. Heat already diffuses by #1660's Metropolis rule; Cold resting on nodes (#1444) needed a flow, a bound and a threshold.

## Decision drivers

- **One snapshot:** read and settle are pure functions; no rider reacts mid-landing (#1733 R4).
- **Bounded reach:** a medium's magnitude, and so a blast, a chain or a wall, is bounded per node.
- **Cold priced in reach:** a counter is answered with content or a bigger hit, never a stat or a free thaw.
- **One flow rule:** a member that moves reuses #1660's diffusion, not a second formula.

## Decision

Owner, 2026-11-05. Phases: *"hold it"*. Dual reach: *"the double counting might be a feature! tentative option 2, where union is kept as an easily switched to option if we change our minds. after all it's just a "do you dedupe the list or not" after gathering each reach medium's additional targets"*. Cold on a +20 hit onto 2 Cold: *"cancels sounds good but also possibly OP … if it just goes "poof" yeah idk if that's right"*, then held. Frozen: *"Yes, pure threshold"*; *"Glass holds"*; breaks-then-absorbs picked over breaks-and-passes-whole. Cap: *"option 1 sounds good"*. Temperature: *"option 1, 100%. hell yeah"*. Rename: *"Cold i think. Frozen is a different effect, derived by Cold count (and degree)"*.

1. **Read / land / settle per landing.** Read computes reach from the hit's reach entry plus the node's media as they were before the hit; the Frozen check is here. Land adds damage and every rider in #1741's order (element riders, other statuses, damage; riders before their hit, ADR 0067); nothing reacts. Settle is one pure function of the node as it now stands: netting, the media read charged are spent, copies go out and each runs its own three phases under the once-per-node-per-attack cap. The same settle runs after every world-turn tick.
2. **Dual reach:** every source present at read fires and spends its own stack; target lists are concatenated, not deduplicated — tentative, the dedupe kept as one switch at the gather step.
3. **Cold (Frost renamed) absorbs arriving reach one for one and is spent.** A reach unit is one radius step, one arc, one remaining hop.
4. **Frozen = Cold ≥ T, T = graph degree + 1**, derived at every read, never saved. Reach under T is lost whole and spends nothing; reach ≥ T breaks, then is absorbed 1:1.
5. **A medium is capped per node at k × T**, k a knob (pass number 3).
6. **Heat and Cold diffuse as one signed temperature** `t = heat − cold` under #1660's Metropolis rule, written back as Heat where positive, Cold where negative; sinks per member (Heat deleted on unallocated ground, Cold rests). Burning = Heat ≥ T, effect parked.

## Consequences

- The build needs a hit-scoped landing unit: one read before the first rider, one settle after the last, around `HitLanding.place()`'s list.
- A Cold wall is at most k breaks deep, a Fuel blast and a Charge chain share that bound, and the Cold and Frozen cells of the elements pair table are final.
- Frozen and Burning are derived, so they carry no save row; Cold does (`SaveFile.FORMAT_VERSION` bump when it is built).

## Alternatives considered

### Land reacts immediately
Lost on *one snapshot*: a rider would change what its own hit reads (a Heat rider thawing the Cold its hit lands on).

### Union dedupe of target lists
Lost on the owner's call that double counting may be a feature. **Most likely to be revived** — one switch at the gather step; the `revisit-when`.

### Cancel iff Cold ≥ reach; subtract never spend; shatter spends all Cold; no cap, proportional decay alone
Lost on *Cold priced in reach* and *bounded reach*: "poof" is too strong, unspent Cold makes a wall free to hold, a blade removes T (one pane) not the wall, and without a cap a 100-Cold wall is nigh impossible to remove.

### Reflect sub-T reach; breaks-and-passes-whole; a cracked flag
Reflect lost on *Cold priced in reach* (owner: *"reflect: too powerful, esp being as cheap as 2 Cold on a leaf node"*); passes-whole lost to the owner's pick; a cracked flag is saved state where a derived threshold suffices.

### Two separate flows, then net
Lost on *one flow rule*: two passes and an ordering where one signed formula already nets on both sides of an edge.
