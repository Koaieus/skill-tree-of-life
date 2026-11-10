Where do the three element counts live on the inner tree, and how often does a card offer one? Sibling of the elements hub #1716, not a child: nothing in the first build waits on it.

## Problem

The first build gives every entity 1 in each element count and in Catalyst (the dev sandbox Player 3), an interim rule (`docs/design/elements.md` § Acquisition). The owner's direction after that (2026-11-09): *"later i think all should start at 0 and gains be linked to "core skilltree / inner skilltree" or core class, or some starting modifier passed from metagame, and still some found on the board (e.g. a bespoke skillnode inherited scene [== a Keystone] such as one that gives "+1 Fire | but also generates 2 Heat / turn"), that kinda content"*.

`docs/design/apex_inner_tree.md` is six schools × two aspects today. Elements hang off the three attack schools only (Fire in STR's pool, Ice in DEX's, Lightning in INT's), and a school never scales what it houses (ADR 0059).

## Forks

1. **The shape.** (a) a third ring around the six-school tree, one arc per element, sitting on its school's sector; (b) a three-spoke tree of its own beside the aspect tree; (c) no inner-tree seat: element counts come only from the core class, a metagame starting modifier and board finds (pool rolls, keystones #1787). No pick yet — the doc names (a) and (b) only as candidates.
2. **The card offer's cadence.** How often a level-up or reward card offers an element count against an aspect count, and whether an element card is offered before the entity holds any of that element.
3. **When the starter 1 goes away.** The interim starter is the stat's default on every entity (owner, 2026-11-10: *"every entity. and possibly later we can decide to replace it with statmodifiers innate, meaning they can get looted too."*). Which of the sources above has to exist before the default drops to 0.

## Notes

- Element counts are meant to run 0..5, 10 at most (owner, 2026-11-10: *"leaning towards having `x_element` counts be 0..5 or maybe 0..10 at best"*), so a seat that grants +1 is a large grant.
- Generator keystones are #1787; the Cold spell is #1789.

Intended lane: Needs design.
