---
status: exploring
---

# Click grammar — open threads

The shipped grammar (left pushes, right pops one level) is
[docs/domain/click-grammar.md](../domain/click-grammar.md). What follows is
not built.

## Core-move on the generic pop

Core-move still cancels on a re-click of its source through a dedicated
branch in `CoreMoveMode.handle_left_click`, and has no "armed,
no origin" level: both doors (clicking the core, the Move Core card) arm it
with the core already set as source. The candidate: give it the attack modes'
shape — the card arms, clicking the core sets the origin, clicking a landing
resolves — and let a click on the source fall through to the generic
invalid-target pop, retiring the special case.

## Idle right-click pin/unpin

With nothing armed, right-click toggles the hovered node's pin. It is a
debug-era leftover, not a deliberate grammar choice; the candidate
replacement is hover + `I`.
