# EntityCombat — the live combat-state slice of an Entity

`combat/entity_combat.gd`. The `RefCounted` state half of an `Entity`, split
from the `Node` notification half so that a whole attack — the forced-dealloc
cascade and entity death included — can resolve on a detached SHADOW without
touching `Events`, `AllocationSystem`, or any real `SkillNode` / `Entity`. The
timeline this serves, the shadow-world design and why cloning nodes was the
wrong answer are in `docs/domain/attack-timeline.md` ("The substrate seam");
this page is the class contract.

## `host` is set once and never reassigned

Assigned at construction, no public setter. A shadow has `host == null` and
that null *is* the mute: there is no "simulation in progress" flag, because a
flag can be left unset and a null host cannot be reached. `snapshot()` is the
only hostless-slice factory, and it takes no host argument.

## Ownership is accessed, never stored — on a live slice

`owned()` / `core()` / `board()` are ACCESSORS. On a live slice they read
through `host` on every call and cache nothing: `AllocationSystem` writes
`node.owned_by` and mirrors the navigator without knowing this slice exists,
so a cached read would go stale silently. A shadow falls back to its own
`_owned` / `_core` / `_board`, populated once at `snapshot()` and kept current
by `apply_cascade` — the ONLY place that mutates a shadow's ownership, and it
updates the `NodeCombat` backpointer and the shadow `GraphMirror` together,
never one without the other (or islanding would answer a set the slice itself
disagrees with).

## The cascade is ONE driver with one sanctioned branch

`apply_cascade` is the forced-dealloc cascade for both worlds, with
`cascade_set` as its pure set query. The design's single `if host != null`
branch sits inside the loop body and selects only the STRIP VERB —
`AllocationSystem.force_deallocate` when live, `_strip_one` when shadow.
Everything around that branch — the set, the pre-strip `allocation_level`
read, the SP wound, the `dealloc_damage` chip, the `DeallocEntry` record — is
shared, so a shadow charges the wound and the chip exactly as the live path
does. A hand-written shadow twin of the live loop once agreed on the
deallocation SET and disagreed on its consequences; that parallel-mirrors
shape is what this rules out (`.claude/rules/`, "no parallel mirrors").

`revoke_node` is likewise one body for both worlds: it revokes the dead node's
granted modifiers and swapped effect-sets from `board()`, drops the effects it
sourced from `effects()`, and trims `mirror()` — after which `apply_cascade`
dispatches `_on_node_deallocated`, so `AuraEffect.recompute` rebuilds from the
set the strip just shrank. A shadow's wave N+1 therefore resolves against
POST-cascade armour, which is the multi-wave case the shadow exists for.

The helpers that make this look expensive (`SkillNode.remove_entity_modifiers_from`,
`SkillNode.clear_scaled_effect_sets`) mutate the REAL node, so a shadow never
calls them — it calls their pure read halves (`SkillNode.granted_entity_modifiers`,
`SkillNode.scaled_effect_leaves`) and removes from its OWN board. A real
node's `_scaled_*` dictionaries are never written by a shadow run.

## The live cascade's ENTRY stays on the bus

`Events.skill_node_depleted` → `BattleSystem._on_node_depleted`, which only
computes the VFX layers, emits `cascade_started`, and forwards into
`apply_cascade`. Moving the trigger off the bus would mean giving this class an
`AllocationSystem` reference, and every fixture that writes
`node.owned_by = entity` directly (~50 test files) would silently get a no-op
cascade. The reference is a parameter on `apply_cascade` instead, supplied by
whoever is driving.

## Effect-hook placement

The "one boundary that can rot" rule: an `Effect` hook that changes a number
belongs on `EntityCombat`; a hook that only tells someone belongs on the host.

## A shadow must be freed explicitly

A caller done with a SHADOW calls `free_shadow()` on it. Ordinary refcounting
cannot do it: the instance and its owned `NodeCombat`s form a reference cycle
(see the method's own doc for the exact shape).
