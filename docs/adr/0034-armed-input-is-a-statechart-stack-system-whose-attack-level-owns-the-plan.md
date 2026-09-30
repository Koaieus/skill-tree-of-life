---
id: 0034
title: Armed input is a statechart held as a push/pop stack system, a sibling of BattleSystem; levels change only on events, and the attack level owns the in-progress plan
status: accepted
date: 2026-09-30
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "Two seats need to build plans at the same time on one machine, or a non-input system needs to read a plan before it is launched"
sources:
  - "#1220"
  - "#1222"
  - "#1223"
  - "#1241"
  - "docs/design/click_grammar.md"
  - "systems/player_input_controller.gd"
  - "systems/attack_plan_slot.gd"
tags: [input, ui, attack, architecture]
---

# ADR 0034 — Armed input is a statechart stack system; its attack level owns the plan

## Context

`click_grammar.md` described a state stack, but the code was five fixed slots (`_armed_modes`) reading five unrelated fields. Nesting was array order, mutual exclusion was hand-written, clicks went through a `_route_*` chain whose order was held by comments, and the pop grammar lived partly on `AttackPlan`. `AttackPlanSlot` held the in-progress plan and had two writers, which `mp_dev_sandbox.gd` documents as "stomping". Plans are seat-local: they cross the wire only in `LaunchAttackCommand`, and the AI builds its own plan and passes it to `launch_attack(plan)`.

## Decision drivers

- One owner per fact: the plan owns *which nodes*; the stack owns *what the next click means*.
- Levels change on events (a click, a command landing, `attack_launched`, `reform_blade()`), never by watching another object's fields.
- Plans are seat-local until launch.
- Tests assert stack shape (`[Manage, Melee, Blade]`), so each red has one cause.

## Decision

- "since armaments are a *stack*, i'd think they got an api for saying 'pop me'" (owner, 2026-09-30)
- "pivot (just base `melee`) and `blade` (on top of `melee`) as 2 separate stacks i think is still the cleanest. potentially, the `blade` stack gets a ref to it's parent `melee` stack" (owner, 2026-09-30)
- "having no state defaults to the `manage` tab being selected … deallocate, stake, extract, etc then each are real stacks on top of this" (owner, 2026-09-30)
- "enter melee attack mode, plan arises with that stack layer, is stored for easy retrieval by the responsible system, armed stack system … and battle system remain siblings" (owner, 2026-09-30)

In short: `ArmedStack` is a Node system and a sibling of `BattleSystem`. Its active branch is a statechart path with Manage as the unpoppable root. Arming a top-level mode switches (pop to root, then push). A child level takes its parent by constructor, and Blade and Target are levels. The attack level creates the plan on push and drops it on pop. `BattleSystem` resolves and replays a plan it is handed.

## Consequences

- `AttackPlan` has no click grammar; it is intent data plus validation and resolution, built through named methods.
- The double-driver stomping on the slot cannot happen: the slot is gone.
- Mutual exclusion and nesting are structural. A mode's pop policy (Stake is a one-off) lives on the mode.
- Anything that reads the in-progress plan depends on the seat's stack, not on `BattleSystem`.

## Alternatives considered

### Stack follows the plan (listens to `attack_plan_changed` / `state_changed`)
Lost on the events-only driver: the attack level's lifetime would be controlled from outside the stack, and it forced a pop-ordering rule. **Most likely to be revived** if a non-input writer of the plan appears.

### Slot stays in `BattleSystem`, with the stack as its only writer
Lost on one owner per fact. Its only grounds were that the host reads the slot to check temp-upgrade toggles, and that reading turned out to be a bug (non-host players are refused), not a need. Dead with ADR 0035.

### One Melee level; pivot→blade stays inside the plan
Lost on one owner per fact: seat-local click grammar stays inside a domain object the AI and the resolver share.
