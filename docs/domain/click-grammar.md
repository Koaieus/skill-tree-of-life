# Click grammar — left pushes, right pops

The one input grammar allocation, targeting and every armed verb share. The
mechanism lives in `systems/player_input_controller.gd`, `systems/armed/armed_stack.gd`
and the `systems/armed/*_mode.gd` levels; this doc is the grammar they implement.
Direction for its rework: ADR 0034, implemented by #1223.

## The rule

**Left-click pushes forward. Right-click pops exactly one level off a state
stack and ignores which node was clicked** — it behaves like Backspace, not
like a click on a thing. Esc is the same pop.

```
idle / Manage                   (nothing armed)
  ↓ left-click a tray verb / a mode-eligible node
mode armed, no origin           (e.g. Melee selected, no pivot yet)
  ↓ left-click an origin-eligible node
origin set, selecting targets   (pivot locked, picking members/target)
```

- **Left-click** arms a mode, sets the origin, or resolves a target / toggles
  a blade member — whatever the current level expects.
- **Right-click** from "origin set" clears the origin **and everything built
  on it** (blade members, target) in one step, back to "mode armed, no
  origin". A second right-click exits the mode to idle. **Two pops, worst
  case, from anywhere to idle**; three in Melee with a temp-upgrade card armed
  on top. There is no flat "cancel everything" shortcut.
- **Re-pivoting is pop-then-push**: right-click clears the pivot, left-click
  sets the new one. Right-click never re-pivots, so one button never means two
  things depending on the node under it.
- **Nothing armed**: right-click toggles the pin of the hovered node instead
  (a no-op over empty space).

## Self-targeting falls through to a pop

Left-clicking the armed origin again runs the mode's ordinary target check. A
legal target resolves normally; an illegal one (Melee: the pivot is never a
blade member) **pops, silently** — no `shake_denied`, since it is the expected
"never mind", not an error. `AttackPlan.pop()` is the one primitive both paths
call.

## The stack, in pop order

`ArmedStack.branch()` is the active root-to-leaf path of a statechart: a real
push/pop stack, seat-local, never synced. `ManageMode` is the unpoppable root
(its native click is allocate, so the Allocate card is active iff the stack
is at root); every other level is pushed on it. `pop_top()` pops the top;
`pop(mode)` pops that level and everything above it ("pop me" — `StakeMode`
pops itself when its command lands). Arming a top-level mode while another
is up switches: pop to root, then push. Mid-swing the stack is frozen — a pop
is refused until the launch releases the attack level.

| Level | Sits on | Armed while | Pop clears |
|---|---|---|---|
| `MassActionMode` | whatever is top | a distant-allocate / would-island-deallocate click awaits confirmation | the pending request |
| `TempUpgradeMode` | `AttackPlanMode` | a temp-upgrade card (Clamp, Spikes…) is armed inside a Melee plan | just the arm — never the pivot/members under it |
| `AttackPlanMode` (interim, #1223 splits it) | `ManageMode` | an attack plan is live | one level of the plan (table below); at the floor, the plan itself |
| `CoreMoveMode` | `ManageMode` | core-move targeting has a source | the source |
| `StakeMode` / `ExtractMode` / `DeallocateMode` | `ManageMode` | that card is armed (Allocate is not a level) | the verb |

The viewport armed-mode glow reads the same branch **base-first** — the base
of the stack decides the colour while the badge and the pop read the top.
Opposite ends, on purpose.

## Per-mode shape

| Mode | Origin (left-click) | Leaf (left-click) | `pop()` clears |
|---|---|---|---|
| Melee | pivot (an owned node) | blade members, toggled, cap `blade_size` | pivot + all members |
| Melee + temp upgrade | *(the card, armed from the command tray)* | a blade member; the arm stays set for repeat placement | the arm only |
| Ranged | *(none — firing positions are derived)* | the target, retargeted directly: a visible hostile, or any sensed node while the quiver holds scout arrows | the target |
| Magic | *(none — the cast-from node is auto-picked from the spell's reach union)* | the spell target, directly | source + target |

Ranged and Magic are two-level: `pop()` is gated on the **target**, since a
null source is their resting state. See `MagicAttackPlan` and
`SpellTargetUnion` for the source pick.

## Core-move

Two doors arm it with the player's own core as the source: left-clicking the
core, or the **Move Core** tray card. It has no "armed, no origin" level — the
source is always the core. Then:

- left-click an owned node → commit the move along the owned path, clear;
- left-click the core again → cancel (a dedicated branch, not the generic
  self-target pop);
- left-click an unowned / enemy node → cancel **and fall through**, so the same
  click still allocates.

Dragging from the core is the same state machine, accelerated. The routing is
`CoreMoveMode.handle_left_click`.

## Where it lives

- `AttackPlan.pop()` / `handle_right_click` — the shared pop; `false` means
  the plan was at its floor.
- `PlayerInputController._unhandled_input` — right-click is global, not a
  per-node signal; `pop_armed_level` pops the top level (`false` at root
  falls through to pin-toggle / the pause menu), and `AttackPlanMode` exits
  the plan when nothing was left to pop.
- `docs/domain/attack_plan_system.md` — the attack-plan architecture this
  grammar rides on.
