---
id: 0037
title: Territory selection is one AllocationPolicy, pick_next(entity, candidates, objective), shared by spawn seeding and any AI picker; callers supply candidates and gate, the policy only picks
status: accepted
date: 2026-07-21
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "A neutral objective proves insufficient to keep tactical intent out of seeding (the entry's own named fallback: split the policy)"
sources:
  - "#275"
  - "#1233"
  - "docs/adr/legacy-mvp-decisions.md#d-24--territory-selection-is-one-policy-spawn-seeding-and-the-ai-share-it"
  - "procgen/placement/allocation_policy.gd"
  - "procgen/placement/greedy_bfs_ball_policy.gd"
  - "procgen/placement/territory_seeder.gd"
  - "entity/controller/ai_controller.gd"
tags: [ai, procgen, allocation, territory, architecture]
---

# ADR 0037 — Territory selection is one policy: spawn seeding and the AI share it

> **Backfilled 2026-09-30** from [D-24](legacy-mvp-decisions.md#d-24--territory-selection-is-one-policy-spawn-seeding-and-the-ai-share-it), dated to its resolution. The owner picked it for a record in the #1224 sweep (*"D-24 one territory policy"*, confirmed *"ADR"*, owner, 2026-09-30, recorded on #1233).

## Context

D-19 made enemies spawn levelled, so they needed territory seeded at spawn (#275). The AI already chose one node to allocate per turn, taking the first frontier match with no scoring. A greedy BFS ball for seeding differed from that only in tie-break and call rate (N picks at spawn, one per turn), and the "weighted growth" follow-up filed against #275 was the AI's missing scoring heuristic. The same work had been filed twice.

## Decision drivers

- One picker, so a spawned enemy's territory is what that AI would have built. D-19's landless elite then reads as legible, not arbitrary.
- Each caller decides what the picker may see: the seeder sees the whole graph, an AI only what it senses. This is the rule `RangeFinder.gather(source, mirror)` follows.
- Apply and gate stay where they are: `force_allocate` (ungated) for seeding, `allocate` (SP/AP-gated) for play.
- Seeding must never inherit combat intent.

## Decision

The resolution adopted 2026-07-21 (D-24): **territory selection is the same thing at two call rates: one shared policy resource, `pick_next(entity, candidates)`.** Callers supply the candidate set; the policy never reaches for `graph`. Callers apply and gate; the policy only picks. The entry point takes an objective argument that the seeder passes as neutral, so tactical objectives stay switchable off. If that is not enough, split the policy rather than let the seeder carry combat intent. This binds any AI node picker, not only the one that existed then.

## Consequences

- The contract is `AllocationPolicy.pick_next(entity, candidates, objective)` (`procgen/placement/allocation_policy.gd:35`). The one implementation is `GreedyBfsBallPolicy`, which ignores `objective` (`greedy_bfs_ball_policy.gd:20`).
- Seeding is built: `TerritorySeeder` loops the policy over the frontier and applies each pick via `force_allocate` (`procgen/placement/territory_seeder.gd:53`, `:56`), injected per level (`scenes/procgen_play_sandbox.gd:58`).
- The AI side is not built. `AIController._pick_frontier_node` scores the frontier with `AiCombatScorer.score_frontier` and never calls an `AllocationPolicy` (`entity/controller/ai_controller.gd:383`). Under this record, that picker is the one that has to move onto the shared contract.
- Once it does, tuning the AI reshapes every spawn. A #268 fixture pinned against one policy version shifts when scoring changes. That coupling is the price of the shared policy, and it should be known in advance.
- "The AI spends all SP each turn" was pinned in the same D-entry. It is a separate AI-behaviour call and is outside this record.

## Alternatives considered

### Two pickers: a spawn seeder and a separate AI chooser
Lost on "one picker": the weighted-growth heuristic would be written twice, and seeded territory would stop resembling played territory. **Most likely to be revived**, through the split named in the Decision, if a tactical objective cannot be neutralised for the seeder.

### The policy reads the graph itself
Lost on "each caller decides what the picker may see": a policy that fetches its own candidates cannot give the seeder the whole graph and a fog-aware AI only its sensed subgraph.

### The policy applies or gates
Lost on "apply and gate stay where they are": seeding is ungated by design, play is gated, and one picker cannot own both.
