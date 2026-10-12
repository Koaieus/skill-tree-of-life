---
id: 0057
title: A turn has no phases — every per-turn budget is spendable in any order until End Turn, and the input channel picks the verb
status: accepted
date: 2026-10-12
deciders: owner
supersedes: []
superseded-by: null
revisit-when: null
sources:
  - "#1320"
  - "#60"
  - "#1228"
  - "a182834"
  - "docs/design/combat_system.md"
  - "docs/domain/allocation_system.md"
  - "docs/domain/attack_plan_system.md"
  - "systems/player_input_controller.gd"
  - "systems/turn_manager.gd"
tags: [turn, input, combat, allocation]
---

# ADR 0057 — A turn has no phases; the input channel picks the verb

> **Backfill.** The decision shipped as #60 (`a182834`, 2026-06-26); the owner ratified it as an ADR on 2026-10-12 (#1320). The reason below is #60's own.

## Context

The turn was three phases, `CONTRACT → EXPAND → BATTLE`, each gating one family of verbs. Clicking a node is ambiguous — allocate, deallocate, attack from or cast from — and the phases resolved that ambiguity by *time*. #60 (owner, 2026-06-26): *"The 3-phase turn (`CONTRACT → EXPAND → BATTLE`) is a crutch for intent separation, not a structural game mechanic."* The cost it named: optional steps hand-held by confirm modals on phase exit, phase gates (`can_allocate` / `can_deallocate` / `can_act`, `advance_phase`) and UI breadcrumbs threaded through the code, and upkeep scheduling bent around phase starts. The shape was shipped and the docs say so (`docs/design/combat_system.md` § Turn Structure); the reason was recorded nowhere until #1228's ADR sweep named it a candidate.

## Decision drivers

- **Intent separation:** an input must mean one verb, unambiguously.
- **Player freedom:** budgets are spent in any order; unspent is the player's choice, not a modal.
- **Code surface:** a verb's legality is its own budget plus "your turn", with no cross-cutting gate.

## Decision

**One turn, no phases; the input channel picks the verb.** Owner, 2026-10-12 (#1320), ratifying #60.

- Every per-turn budget (`action_points`, `skill_points`, `deallocation_points`, `movement_points`) is an ordinary stat, replenished at turn start and spent in any order until End Turn.
- `PlayerInputController` routes by input channel — allocate is a bare left-click on an unowned node, deallocate is `D` over an owned node, core move starts from a click on the core, attack and cast go through the armed stack — and each verb is gated by "your turn" plus its own budget, in its system.

## Consequences

- `TurnManager` knows initiative and turn start/end only; there is no phase enum, phase signal or phase UI.
- The AI walks budgets, not phases. End Turn warns only about unspent action points, and only while an enemy is visible.
- A new verb is a new channel plus a `can_*` gate; it never has to find a phase to live in.
- Two verbs on the same input need a disambiguating channel (a key, a mode bar, a chooser), since time no longer separates them.

## Alternatives considered

### A phased turn (allocate phase → attack phase …)
**Rejected on intent separation and player freedom.** It separates intent temporally where a channel separates it directly, it forces the player through optional steps, and every verb grows a phase gate. *The alternative most likely to be revived* — by a mechanic that wants an ordering inside a turn (e.g. "attacks happen after allocation"). Such a rule is a gate on that one verb, not a reason to restore phases.

### Not an alternative: a contextual action bar or a commit-style preview
Both were named in #60 as later follow-ups. Each is another input channel or a staging layer inside the one phase, so neither reopens this record.
