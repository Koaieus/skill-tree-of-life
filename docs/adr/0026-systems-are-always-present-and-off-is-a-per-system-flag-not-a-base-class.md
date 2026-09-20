---
id: 0026
title: Systems are always present; "off" is a per-system flag, not a null check and not a base class
status: accepted
date: 2026-09-21
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "the system collection wants real shared behaviour — wiring helpers, lifecycle hooks, a uniform rebind — on more than one field"
sources: ["#1006", "#998", "scenes/game_root.gd", "ui/hud/hud_root.gd"]
tags: [architecture, composition-root, systems, scenes]
---

# ADR 0026 — Systems are always present; "off" is a per-system flag, not a null check and not a base class

## Context

`GameRoot` and `HudRoot.compose` wire a dozen systems as null checks (42
occurrences in `game_root.gd`, 52 in `hud_root.gd`), which can't distinguish
*intentionally off* from *not wired yet* — a late injection is silently skipped.

## Decision drivers

- Off must be distinguishable from not-yet-wired.
- The scene, not the code, says which systems a level has.
- Composition over inheritance.
- Systems are call-driven, so `process_mode` cannot gate them.

## Decision

1. Every system is present in every `GameRoot` scene; a missing `%System` is a
   loud `assert` in `_ready`, never a branch.
2. "Off" is per-system: a system with a meaningful disabled state declares its
   own `@export var enabled := true` and guards its own doors. No shared
   `System` base class — uniformity is a convention plus a test. Not every
   system needs an off; inert-when-unused *is* the null object.

Owner (2026-09-21): *"Some systems may even not need an 'off' but could be inert otherwise or are so by default."* *"If we ever decide this needs changed … we could simply supersede it."*

## Consequences

- `GameRoot._ready` and `HudRoot.compose` lose their null branches; a no-fog
  fixture gets a `VisionSystem` with `enabled = false`, so the unit under test
  still sees the real system's signals and shape.
- A convention test, not a type, is what a new system must satisfy.

## Alternatives considered

### Keep null checks, centralise in a `_wire(system, fn)` helper
**Rejected** — lost on *off vs not-yet-wired*: the ambiguity survives, and the
scene still doesn't say what it has.

### A shared `class_name System extends Node` holding `enabled`
**Rejected (owner reversal)** — lost on *composition over inheritance*: "off"
means something different per system, so each guards its own doors anyway.
Most likely to be revived; see `revisit-when`.

### `process_mode = DISABLED` as the off switch
**Rejected** — lost on *call-driven*: stops `_process`/`_input`, not the
direct calls these systems mostly receive.
