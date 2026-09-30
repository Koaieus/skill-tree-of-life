---
id: 0036
title: A CoreClass is a leaf that never references another CoreClass; shared parts are file-backed packs and effects dropped into its typed arrays
status: accepted
date: 2026-08-04
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "Two core classes need the same behaviour hook (on_turn_started / apply override) and Effect cannot carry it"
sources:
  - "#279"
  - "#1232"
  - "docs/adr/legacy-mvp-decisions.md#d-27--a-coreclass-is-a-leaf-reuse-lives-inside-its-typed-arrays"
  - "entity/core/core_class.gd"
  - "stats_system/composite_stat_modifier.gd"
  - "stats_system/packs/attribute_baseline.tres"
  - "systems/loot_system.gd"
tags: [entity, core-class, stats, loot, authoring, architecture]
---

# ADR 0036 — A CoreClass is a leaf; reuse lives inside its typed arrays

> **Backfilled 2026-09-30** from [D-27](legacy-mvp-decisions.md#d-27--a-coreclass-is-a-leaf-reuse-lives-inside-its-typed-arrays), dated to its third and final resolution. The owner picked it for a record in the #1224 design-doc sweep: *"for the most important decisions some ADR might be warranted"* (owner, 2026-09-30).

## Context

Every enemy class needed a mostly-similar batch of attribute, offensive and defensive modifiers, and each `.tres` hand-declared them (#279). Two mechanisms on `CoreClass` itself shipped and were reverted: `inherits: CoreClass` (`59d2444`), then `composes: Array[CoreClass]` with DFS, dedupe and a cycle guard (`1ff127e`). A shared base became a class of its own, so `CoreClass.load_all()` returned it as a phantom sixth class. Meanwhile `effects: Array[Effect]` already composed by reference; only `modifiers` lacked a container, and `CompositeStatModifier` already was one.

## Decision drivers

- Change one `.tres` and every class using it changes: reuse by reference, authorable in the inspector.
- Each array composes independently; taking a base's modifiers must not force taking its effects.
- Shared parts must stay out of the class registry.
- Zero new API on `CoreClass`.

## Decision

- The requirement: *"author stuff and plug it into any enemy, reuse it across multiple enemy definitions, and if it needs to change — change 1 `.tres` and every class composing it gets the change"* (owner, via #279, recorded in D-27).
- The call (resolution adopted 2026-08-04): **a `CoreClass` `.tres` is a flat leaf and never references another `CoreClass`.** Shared modifier batches are file-backed `CompositeStatModifier` `.tres` in `modifiers`; shared effects are file-backed `Effect` `.tres` in `effects`. Packs live outside `entity/core/`. Stacking is pure append; "weaker than the base" is a negative modifier, never an override by `stat_id`.
- One boolean settles loot atomicity per pack: `CompositeStatModifier.loots_as_unit` (default `true`).

## Consequences

- `CoreClass` has no composition field; `modifiers: Array[StatModifier]` and `effects: Array[Effect]` are the reuse surface (`entity/core/core_class.gd:120`, `:130`). `apply()` grants each entry as-is (`core_class.gd:160`).
- The first shared pack is `stats_system/packs/attribute_baseline.tres` (`loots_as_unit = false`), referenced from `basic_enemy_core.tres` and `ninja_core.tres`.
- The flag is declared at `stats_system/composite_stat_modifier.gd:49`. Loot is the only consumer that keeps a pack whole: `LootSystem._expand_for_loot` splits a `false` pack into per-leaf candidates (`systems/loot_system.gd:623`).
- Behaviour reuse is not solved here: two classes wanting one turn hook still subclass `CoreClass` separately. If it is solved, `Effect` is where it would go, which keeps the leaf rule true.
- This is the `CoreClass` instance of "compose through a plural array, never a parent link or inheritance". No ADR records that as a general principle.

## Alternatives considered

### `inherits: CoreClass`, base-first append (`59d2444`)
Lost on "each array composes independently": inheritance is all-or-nothing per entry, so a child gets a base's effects along with its modifiers.

### `composes: Array[CoreClass]` with DFS and a cycle guard (`1ff127e`)
It was right that composition beats inheritance, but it composed the class instead of the array. Lost on the same driver and on registry pollution. **Grounds since weakened:** the registry argument was that a shared base showed up in `load_all()` for the #322 DAG check *and* a future class-select UI. The UI half is dead: runtime picking reads the authored `core_class_roster.tres` through `pickable_for()` (`core_class.gd:69`, #640), and `load_all()` is editor- and test-only. The DAG-check half still holds. D-27's claim that loot reads the class's own `.tres` is also stale: `LootSystem._core_modifiers` now reads the entity's `core_modifiers` register (`loot_system.gd:612`, #323). The loot atomicity argument is unaffected. **Most likely to be revived** if behaviour reuse forces a class-level mechanism after all.

### Factory helpers, or copy at authoring time
Lost on "change one `.tres`": duplication moves into code or gets copied, and inspector authoring is lost.
