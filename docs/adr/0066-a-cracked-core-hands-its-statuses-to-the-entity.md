---
id: 0066
title: A cracked core hands every status on its node to the entity — the crack transition in NodeCombat's damage door moves the rows through StatusHost.transfer_all_to; supersedes 0024 §3's "the two hosts never merge rows" in part
status: accepted
date: 2026-10-17
deciders: owner+agent
supersedes: [0024]
superseded-by: null
revisit-when: "the moved row's resistance gate, add-not-refold or applier-less arrival (the tentative pass picks) produces a case the owner wants to read differently — e.g. an entity-resisted row that should stay on the node"
sources:
  - "#1686"
  - "#1562"
  - "#994"
  - "combat/node_combat.gd"
  - "combat/status_host.gd"
  - "test/unit/combat/test_core_crack_status_move.gd"
tags: [combat, status, architecture, entity]
---

# ADR 0066 — A cracked core hands its statuses to the entity

## Context
ADR 0024 gave statuses two hosts: a core node's own rows while its shell holds, the entity's once the shell is at 0 (the fall-through, decided at land). Its §3 also said rows already node-hosted stay node-hosted and the two hosts never merge. That was safe while a hit's status rider landed *after* its damage: the arrow that cracks the core saw `hp.current == 0` and sent its own poison through (#994, owner 2026-09-20). #1562 lands riders *before* their hit, so that arrow's poison would land on the still-intact node and stay there, breaking #994's promise.

## Decision drivers
- #994's *"an arrow that cracks the core sends its own poison through"* holds whatever the rider order.
- One owner of "where a cracked core's statuses live"; never a parallel `apply_status`.
- Shadow, replay and live agree without a new field on the wire.
- The move is visible on the mutation clock, as the fall-through is (ADR 0024 §7).

## Decision
- Owner, 2026-10-17 (`/swarmify` #1562): **"When a core cracks, every status on its node moves to the entity."** "Cracks" means the core node's `hp.current` crosses from > 0 to ≤ 0.
- Owner, 2026-10-17: it moves **every** row on the core node, including rows from earlier turns, not just the cracking hit's rider — chosen knowing it widens #994's scope.
- Every other ADR 0024 rule stands: no migration on a core move (§2), no migration back when the shell regens, the fall-through for a status landing on an already-cracked core, the entity-wide scope (§4).

So: `NodeCombat.take_damage`'s core branch sees the crack (`before > 0` and `hp.current <= 0`) and calls `EntityCombat.receive_statuses_from`, which runs `StatusHost.transfer_all_to` — the one entry point. It runs **before** the overflow chip, so a lethal overflow's death strip never meets the rows on the node. A replay lands the recorded damage through the same door, so the move is reproduced, never shipped.

Tentative pass picks (2026-10-17, not owner calls, revisitable): a moved row **adds** its stacks into the entity's row of the same def and key through `StatusHost.adjust_power` (no attacker re-fold, no reapply policy, no applier, a fresh decay ramp); the entity host's `blocks` gate applies (ADR 0024 §4, "resistance from the host that received"), and a blocked row is **dropped**, not left on the node; the node row leaves through `remove_row`, so its `_on_removed` undoes its node effect but nothing reaches a removal spill — a move, not a death.

## Consequences
- The cracking hit's rider reaches the entity in either rider order.
- More reaches the entity: every row on the core, from any turn. An entity-hosted Curse already raises `min_damage_taken` on every node (ADR 0024's tuning door is entity `<type>_resistance`).
- A sandpile def (corruption) that moves onto the entity piles on the entity's core pile and may topple from there — a topple, not a removal spill.
- Presentation needs no new cue: both hosts' `_on_statuses_changed` fire inside the damage reveal, so the node's icon row loses the row and the core bar / hero card gains it on the same clock tick.
- An entity that already blocks a def silently loses that node row on a crack.

## Alternatives considered
### Keep 0024 §3: rows stay on the node (superseded)
Loses the first driver once riders land before their hit; the cracking arrow's own poison stays on the shell.
### Move only the cracking hit's rider
Needs the move to know which row came from which hit; the owner chose every row.
### Ship the move on the record as a settle-style op
Unneeded: the crack replays through the same damage door, so the move reproduces. Most likely revived if a replay ever lands damage through a different door.
### Leave a resisted row on the node
Would keep two hosts live for one def on a cracked core; dropping matches "resistance from the host that received" and is a one-line flip in `transfer_all_to`.
