---
id: 0026
title: Systems are always present; "off" is a per-system flag, not a null check and not a base class
status: accepted
date: 2026-09-21
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#1006"
  - "#998"
  - "scenes/game_root.gd"
  - "ui/hud/hud_root.gd"
tags: [architecture, composition-root, systems, scenes]
---

# ADR 0026 — Systems are always present; "off" is a per-system flag, not a null check and not a base class

## Context

`GameRoot` is the per-level composition root and `HudRoot.compose` its UI
counterpart. Both wire a dozen systems, and both express *optionality* as a
null check: `if battle_system != null:` appears 42 times in `game_root.gd` and
52 times in `hud_root.gd` (2026-09-20 smell audit, #998 → #1006). Sandboxes
and test fixtures omit systems; the shipped level never does. So the guards
encode "which systems this scene has" in code rather than in the scene, and a
null check cannot distinguish *intentionally off* from *not wired yet* — a late
or missing injection is silently skipped, which is exactly the false negative
the owner named as the thing to fear.

Three of the flags already exist, parked on the root as `@export`s:
`enable_fog`, `show_ui`, `auto_start_turn`.

Owner (2026-09-21), settling #1006 and then reversing one part of it on review:
*"a null check is a clear signal for an optional system being off, but otoh a
too late injection could give a false negative"* → *"Then indeed option 1
[null-object systems]"*; on a shared `System` parent to hold the flag: *"I do
agree with the above [no base class]. Some systems may even not need an 'off'
but could be inert otherwise or are so by default."* And on recording it:
*"Tentatively going this direction but it's a decision nonetheless. If we ever
decide this needs changed, which we may do e.g. if our collection of systems
needs more uniformity or a suite of wiring helpers, we could simply supersede
it."*

## Decision

1. **Every system is present in every `GameRoot` scene.** The base
   `game_root.tscn` carries them all; inherited scenes never delete one. A
   missing `%System` is a loud `assert` at the top of `_ready`, never a branch.
2. **"Off" is a per-system fact.** A system with a meaningful disabled state
   declares `@export var enabled := true` and guards its *own* public entry
   points with its *own* semantics (no fog = reveal all; no victory = never
   end; no battle = refuse attacks). The three root flags move onto the systems
   they toggle and the root exports are deleted.
3. **No shared `System` base class.** Uniformity is a convention plus a test:
   for every system in the audited "needs an off" set, the property exists and
   a disabled instance's public entry is a no-op.
4. **Not every system needs an off.** One that is inert when unused declares
   nothing — inert-when-unused *is* the null object.

## Consequences

- `GameRoot._ready` and `HudRoot.compose` lose their null branches; "is this
  scene using X" is read off the scene, not inferred from wiring.
- A fixture that wants no fog gets a `VisionSystem` with `enabled = false`, so
  the unit under test still sees the real system's signals and shape.
- Godot's `process_mode = DISABLED` is **not** a substitute and is not used for
  this: these systems are call-driven (the applier calls
  `allocation_system.allocate` directly), so the flag must be checked at each
  entry point regardless of process mode.
- The convention test, not a type, is what a new system must satisfy.
- This is a tentative direction. The named trigger for superseding it: the
  system collection grows to want real shared behaviour — a suite of wiring
  helpers, lifecycle hooks, uniform rebind — at which point a base class or a
  composed `SystemSlot` earns its keep on more than one field.

## Alternatives considered

### Keep optionality by null check, centralise it in a `_wire(system, fn)` helper
**Rejected.** Cosmetic: the guard is written once but the ambiguity between
"off" and "not yet injected" survives, and the scene still does not say which
systems it has.

### A shared `class_name System extends Node` holding `enabled`
**Rejected (owner reversal, 2026-09-21).** The parent would share exactly one
declaration. What "off" *means* is per-system and cannot live in a base, so
every system guards its own doors anyway. A forced inheritance root over
`TurnManager`, `CameraDirector`, `CommandLink` and `VisionSystem` is
composition-over-inheritance broken for one field, and a `System` type invites
"shared" behaviour to accrete that fits three of eleven systems. This is the
alternative most likely to be revived — the trigger above says when.

### `process_mode = DISABLED` as the off switch
**Rejected.** Stops `_process`/`_input`, not direct calls; the systems here are
mostly call- and signal-driven, so it would disable the wrong half.
