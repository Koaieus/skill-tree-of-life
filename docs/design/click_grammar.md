# Click grammar — left commits/arms, right pops

Settles #411, surfaced while swarmifying #404 (shared targeting-mode input):
#404's spec had claimed right-click was already the universal "cancel armed
mode" gesture, citing attack plans' right-click handling as precedent. That
didn't hold up — before this doc, right-click was three different things
(melee/magic setup-step, ranged clear-selection, idle pin/unpin) plus a
left-only precedent (core-move). This doc is the one settled grammar node
allocation and targeting — the game's central verb — uses everywhere.

## The rule

**Left-click always pushes forward. Right-click always pops exactly one
level off a state stack**, and ignores which node was clicked — it isn't a
click on a *thing*, it's closer to pressing Backspace once.

```
idle / Manage             (nothing armed)
  ↓ left-click a tray verb / a mode-eligible node
mode armed, no origin      (e.g. Melee selected, no pivot yet)
  ↓ left-click an origin-eligible node
origin set, selecting targets   (pivot/source locked, picking members/target)
```

- **Left-click** arms a mode, sets/locks the origin, or resolves a
  target/toggles a blade member — whatever the current level expects.
- **Right-click** pops one level: from "origin set" (with or without a
  target/blade members already picked) back to "mode armed, no origin" —
  clearing the origin AND everything built on it in one step, since blade
  membership / target validity are derived from the origin and can't
  outlive it. A second right-click, now at "mode armed, no origin", exits
  the mode entirely back to idle/Manage. **Two pops, worst case, from
  anywhere in the stack to idle** — there is no separate flat "cancel
  everything" shortcut, and none is needed.
- **Re-pivoting/re-sourcing mid-plan is pop-then-push**, not a shortcut:
  right-click clears the origin, then left-click the new one. The old
  behavior — right-clicking a *different* node instantly re-pivoted — let
  one button mean two different things depending on which node it landed on
  (origin-eligible vs. blade-eligible). That ambiguity is exactly what this
  grammar removes; the fix applies uniformly to melee's pivot and magic's
  source.

## Self-targeting resolves through ordinary target validity, no special case

Clicking the armed origin node again is just a left-click like any other —
it runs through the mode's normal targeting check:

- If the origin is a **legal target** (a heal spell whose source can equal
  its target) → resolves normally, cast lands on self.
- If the origin is **not** a legal target (melee: the pivot is never a
  valid blade member; an attack spell that excludes self; core-move: a
  0-hop move isn't valid) → falls through to a **pop** — silent, no
  `shake_denied` — because this is the expected "never mind," not an error.

This is why `pop()` lives on `AttackPlan` as a named, reusable primitive
(`attack/plan/attack_plan.gd`) rather than being buried inside the
right-click handler: both right-click and this self-click fallthrough call
the exact same one-level pop. It retires core-move's dedicated
self-click-cancel branch as special code — self-isn't-a-valid-target is now
one mechanism, not a per-mode exception.

## Per-mode shape

| Mode | Origin (left-click, unset → set) | Leaf level (left-click) | `pop()` clears |
|---|---|---|---|
| Melee | pivot | blade members (toggle, cap = `blade_size`) | pivot + all blade members |
| Ranged | *(none — firing positions are derived, not chosen)* | target (direct left-click retarget, no origin to pop first) | target |
| Magic | source | spell target | source + target |

Ranged has only two states (armed / target-set) because there's no
separate origin-selection step — a left-click on a different hostile node
retargets directly, and `pop()` just clears the target. It's the mode
needing the smallest change: right-click used to only pop when it landed
on the current target (`node != target → no-op`); now, matching the
node-independent rule above, it pops regardless of where you click.

## Scope boundary: right-click needs a node under the cursor

`right_clicked` is a per-`SkillNode` signal — "right-click pops" still
requires the cursor to be over *some* node when it fires; there is no
global/empty-space right-click binding here. A HUD affordance that reads
the armed-mode state independent of cursor position is `#412`'s concern,
not this one.

## Core-move stays two-level, deliberately, until #338

Core-move (left-click own core arms it, left-click a neighbour commits,
left-click the armed source again cancels) does **not** get this three-level
treatment yet. Today it has no tray-button arm step ahead of it — clicking
the core *is* the arm step, so there's no "mode armed, no origin" level to
pop back to; it's already at floor. #338 is about to add a "Move Core"
Manage-tray button, which puts core-move on the same three-level shape as
the attack modes (tray button arms → click own core sets origin → click a
neighbour resolves) — that refactor, including retiring core-move's
self-click-cancel branch in favor of the generic invalid-target-pop path
above, happens once #338 lands, not here.

## Out of scope

- Idle right-click pin/unpin on the context panel (debug-era leftover, not
  a deliberate design choice) — candidate for hover+`I` instead, tracked
  separately.
- Any HUD/viewport visual indicator of the currently-armed mode (`#412`) —
  a visuals-only consumer of this doc's "armed-mode" concept, not a grammar
  decision.

## Engineering pointers

- `attack/plan/attack_plan.gd` — `pop()` is the shared primitive;
  `_on_node_right_clicked` defaults to calling it and returning whether
  there was anything to pop.
- `systems/player_input_controller.gd`'s `_route_battle_click` — when
  `_on_node_right_clicked` returns `false` (nothing left to pop), it calls
  `battle_system.cancel_attack()` instead of falling through to the
  idle pin-toggle channel.
- See `docs/domain/attack_plan_system.md` for the wider attack-plan
  architecture this grammar rides on.
