---
id: 0065
title: A stat may be a pipeline over another entity's value — armor_pierce's bins fold the defender's FINAL armor (clamped at 0, positive armor only), stamped on the hit as FoldTerms by its producer; its own value is inert
status: accepted
date: 2026-10-17
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "a second pipeline stat needs a readout that FoldTerms.describe cannot carry, or an attacker effect must act inside the defender's armor bins (the merged-bins alternative)"
sources:
  - "#1401"
  - "#395"
  - "#1203"
  - "attack/formulas/mitigation.gd"
  - "combat/node_combat.gd"
  - "docs/domain/defense-axes.md"
tags: [stats, combat, mitigation, armor, architecture]
---

# ADR 0065 — A stat may be a pipeline over another entity's value

## Context
#395 asked for an attacker-side counter to armor, open between flat and %. Every stat so far folds its own `base_value`; the fold itself (`ModifierBins.resolve` → `FoldTerms.fold(base)`) already takes any input, and `FoldTerms.describe` prints a transform rather than a number. Damage replays as recorded post-mitigation TRUE amounts (`AttackRecord`), and the shadow world resolves attacks before the live world replays them, so whatever the attacker contributes must be a snapshot taken when the hit is built.

## Decision drivers
- Flat and % both, in one predictable order, without two stats.
- Pierce never makes a hit bigger; breaking armor below 0 stays `armor_break`'s role.
- Shadow, replay and AI scorer see exactly what the live door lands.
- A readout that predicts what lands, without a meaningless bare number.

## Decision
- Owner, 2026-10-17 (#1401): *"an armor penetration stat whose bins act as entrypoint for an enemy armor value, the pipeline it enters. so collecting a -3 BASE_ADD for it would lower the input by 3. a 0.5 MULTIPLY would halve it. 0.5 MULT and a -5 ADD_BONUS would half it first (penetrate 50%) then lower it by 5. a persistent readout of this value would be gibberish though, it relies on an input value to make sense, it would need to ride the pipeline"*.
- Owner picks, 2026-10-17 (#1401): "Pierce stops at 0"; "Pierce id, 'Enemy armor' lines"; "Declared on the hit".
- Owner, 2026-10-17 (#1401): *"toggle on producer or hit (likely both, producer sets it on hit), or maybe even it attaches a copy or ref of the bins to overlay"*.

So: `armor_pierce` is one INT stat whose value nothing reads. `NodeCombat.get_local_terms` returns its node-local merge as `FoldTerms`; `Mitigation.pierce_terms` overlays the producer's own modifiers and the producer stamps the result on `DamageInstance.armor_pierce` (null = none). `Mitigation.effective_armor` folds it over the defender's final armor only when that armor is > 0, clamps at 0 and floors to whole once; the floor applies last. The two pipelines are never merged (tentative pass pick, 2026-10-17).

## Consequences
- Flat, % and "ignore armor" (one SET 0) are one stat; content authors exceptions per producer, not per attack kind.
- Nothing new crosses the network: the record carries post-mitigation amounts.
- A pipeline stat's value is meaningless; surfaces must exclude it or render `describe()`.

## Alternatives considered
### Separate flat and % stats
Two stats, two readouts, and an order the code would have to invent; lost on the first driver.
### Reading the attacker at impact
Breaks the snapshot driver: the replay and the shadow world would see later board changes.
### A raw fold with no clamp
−4 armor × 0.5 → −2 makes a broken target *less* vulnerable, and −5 ADD_BONUS turns pierce into bonus damage; lost on the second driver.
### Merging pierce into the defender's armor bins (most likely revived)
Is what `armor_break` already is; a clamp needs the final value and SET 0 becomes a priority fight. A one-hit version is a short `armor_break` status. Neighbours: ADR 0029 (family parents fold bins, never base), ADR 0016 (INT floors once).
