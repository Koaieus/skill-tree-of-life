---
id: 0030
title: A parent stat invalidates its children through the board-wired link, never through its value_changed signal; parent edges order the batch flush
status: accepted
date: 2026-09-28
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "A parent's child fan-out shows up in a profile, or a board grows a second dirty-propagation edge kind beside formulas and parents"
sources:
  - "#1155"
  - "docs/adr/0029-related-stats-compose-through-parents-folded-at-read-and-every-stat-takes-every-bin.md"
  - "stats_system/stat.gd"
  - "stats_system/stat_board.gd"
tags: [stats, architecture, performance]
---

# ADR 0030 — A parent invalidates its children through the link, not the signal

## Context

ADR 0029 decision 1 folds a stat's declared parents' bins in at read and records
the owner's late-night invalidation framing, *"a single signal subscription per
parent would suffice"*; the hub (#1154) asked for that clause to be confirmed or
superseded during `/swarmify` of #1155. `Stat.get_value()` is memoized behind
`_value_dirty`, and `StatBoard.begin_batch` defers every `value_changed` SIGNAL
to `end_batch` under the contract *"defers notification, never value"*. A child
dirtied only by its parent's signal breaks that: the parent's bins move, its
signal waits, the child's memo stays warm and stale until the flush. The flush
also sorts by formula depth so each stat emits once after its sources; an edge
the sort does not know about forces the second round batching exists to remove.

## Decision

1. **The board wires the link, both ways**, at its three registration sites
   (typed-field init, `_register_minted`, `clone_live`), from `StatRegistry`'s
   flattened ancestor list. Board-local: a node board's `damage` parents the
   node board's `blade_damage`, never the entity's.
2. **A parent's dirty path marks each linked child dirty by direct call** —
   the parent's `_emit_value_changed` calls the child's — so the child's memo
   is dirty in the same call the parent's bins moved and its signal coalesces
   under a batch like its own modifiers' would. No parent→child signal
   subscription exists; `value_changed` stays what consumers watch.
3. **Parent edges join the flush ordering** (`_sorted_dirty_wave`), so a
   parent emits before its children, each once per settle.

Owner, 2026-09-28: *"Link propagation"*. ADR 0029's fold-at-read stands; only
its mechanism sentence is narrowed here.

## Consequences

- The batch invariant holds for parented stats; one dirtying path serves own
  bins and every ancestor's, so a third cause cannot skip the memo.
- Linking is a board pass, never a stat self-wire: `Stat._board` is set only on
  the first `add_modifier`, so an unmodified stat has no board to ask.

## Alternatives considered

### Signal subscription per parent (ADR 0029 as written)
**Rejected**: stale child memo mid-batch, and the child emits before its
parent unless the sort learns the edge anyway.

### Version-counter pull (bins carry a write counter, child compares on read)
**Rejected** on taste: correct, but per-write bookkeeping on every bin plus the
signal subscription and the ordering regardless. **Most likely revived** if
link fan-out ever shows in a profile.
