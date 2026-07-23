# Status tags — a proposed second grant channel (design doc, not yet implemented)

> Lives in `docs/design/` because the tag-set mechanic below doesn't exist
> yet. Once it's implemented, move this back to `docs/domain/` (it was
> originally drafted there) and update it to reflect the actual shape shipped.

Prompted by designing **LifeLine** (already stubbed in
[effect-system.md](effect-system.md)'s Deferred section: *"kept alive despite
being islanded" ... needs a query hook with a return value inside
`nodes_islanded_by_removing_set` / the cascade, not a fire-and-forget
notification and not a modifier grant*). Working through that surfaced a
broader question: nodes and entities are going to accumulate presence/absence
markers ("has_lifeline", eventually poisoned/stunned/rooted/marked/...) that
don't reduce to a numeric stat contribution. Do they need their own system?

**Short answer: yes for the marker itself, no for the mechanic it triggers.**
Read on for why, and where the line falls.

## Why not `ScalarStat` with a bool reading (e.g. `has_lifeline` as a stat that's 0 or 1)

Tempting because the grant/revoke plumbing already exists — `EffectContext.grant`
lands a `StatModifier` (SET op) and the ledger handles revocation for free. It
breaks down for reasons specific to what `StatBoard` is *for*:

- **Every stat needs a permanent `StatDef` + a slot in every authored
  `StatBoard` .tres** (`stats_system/defs/`, `default_entity_board.tres`, per
  `.claude/rules/stats-system.md`). That's fine for ~20 stable numeric stats
  (armor, strength, health...) that every entity always carries. It's the
  wrong ceremony for an open-ended, effect-authored vocabulary where most
  entities never see most flags, and new ones (poison, stun, mark, root...)
  are exactly the kind of content designers will want to add without touching
  every board.
- **The modifier pipeline computes magnitude** — `(base + ΣADD_BASE) ×
  (1+ΣINCREASE/100) × ΠMULTIPLY + ΣADD_BONUS`, with `SET` as a priority-ranked
  override. Reading "is this true" back out of that pipeline (`value > 0`)
  works mechanically but is answering a yes/no question with arithmetic built
  for magnitude composition. It's the same shape mismatch `.claude/rules/`
  already warns about elsewhere in this codebase (don't force a concept
  through infrastructure built for a different one).
- **UI fallout.** "Hide unless true in most/all UI" is not what the stat UI
  (`attributes_panel`, `stat_board_visualizer`) does today — it enumerates
  registered stats. A bool-stat status flag would need bespoke per-stat
  visibility rules bolted onto UI that wasn't built for that, for *every* flag
  you add.
- It would work fine for exactly one flag if you were certain it'd never
  generalize — but the premise of this question ("a lot more" flags) says it will.

## Proposed shape: a refcounted tag set, sibling to `node_board`

Add a second grant target type alongside `StatModifier`, reusing the exact
same discipline `EffectContext`/`EffectInstance` already enforce for
modifiers — source-tracked, ledgered, revoked by `revoke_all()`:

- **`EffectContext.grant_tag(tag: StringName, target: Variant = null)`** /
  **`revoke(handle)`** — same shape as `grant(mod, target)`, `target` null =
  entity-wide, a `SkillNode` = node-scoped. Records a ledger row (extend
  `EffectInstance`'s grant list, or a parallel one) so `revoke_all()` sweeps
  tag grants and modifier grants uniformly — no new remembering at call sites.
- **Storage is refcounted**, not a bare bool, because multiplicity is real:
  if two effects both grant `&"lifeline"` to the same node and one is
  revoked, the tag must stay present for the other. `SkillNode` gets
  `_tags: Dictionary[StringName, int]` (parallel to how `node_board` is a
  sparse, lazily-allocated per-node structure) with `add_tag` / `remove_tag`
  (refcount ±1) / `has_tag` (count > 0). `Entity` gets the same shape for
  entity-wide tags.
- **Consumers read `has_tag(&"lifeline")`**, not a stat value — no
  `StatRegistry` entry, no board slot. `get_active_tags()` gives tooltips /
  `DebugClipboard` a generic "what's currently active" listing for free —
  which is also the actual answer to "hide unless true": a tag either exists
  on that carrier or it doesn't, there's nothing to hide.
- **Authoring stays effect-composed.** `AuraEffect` keeps radiating numeric
  modifiers; a sibling (`TagAuraEffect`, or a flag on `AuraEffect` selecting
  which channel `recompute` grants through) radiates a tag over the same
  `reach`/`metric`/`distance_scale` knobs instead. Both can sit side by side
  in one carrier's `Array[Effect]` — same pattern as Serpent's two
  `AuraEffect`s composing without a `CompositeEffect`.

## LifeLine radiates from the addon node, NOT from core

An earlier draft said "grant `&"lifeline"` to nodes within N hops **of core**."
That is wrong for LifeLine and would never fire: the mechanic triggers exactly
when a component is **islanded** — cut off from core — so at the decision point
those nodes are at infinite core-hop-distance and a core-sourced `HopRangeFinder`
can't reach them. Worse, the deallocation that islands them fires
`_on_node_deallocated → recompute → revoke_all`, stripping a core-sourced tag at
the very moment the cascade needs to read it.

LifeLine must radiate from its **carrier node** (the node holding the lifeline
addon), i.e. `EffectContext.source_node`, not `core_location`. This is the
general "origin" question for auras, resolved without a new knob: an aura's
source is `ctx.source_node if ctx.source_node != null else ctx.core_location`
— a node-carried effect radiates from its own node; an entity-wide (core-class)
effect falls back to the core. `AuraEffect.recompute` currently hardcodes
`ctx.core_location`; the tag-aura sibling (and `AuraEffect` itself) should adopt
the fallback rule so a node-carried aura sources from where it lives.

## LifeLine specifically: the tag is necessary, not sufficient

Granting `&"lifeline"` to nodes within N hops of the carrier node is the easy
80% and fits the shape above exactly. The actual "survive disconnection for one
turn" behavior needs new work **outside** the tag system, because it changes
*when* death happens, not just *what data* a node carries.

> **Superseded — see `mvp_decisions.md` D-28/D-29 for the current design.**
> Two claims this section originally made are now known wrong, and are kept
> here only so the reasoning that replaced them is legible:
>
> - *"snapshot `has_tag` before the dealloc loop."* Wrong, not merely
>   inelegant. A lifeline node hanging off the cut vertex carries the tag
>   **before** the cut and loses it **after**; a pre-cut snapshot spares a node
>   that must die (config C4 in D-28). Protection is `has_tag` recomputed on the
>   **post-cut** subgraph.
> - *"grace bookkeeping belongs to `BattleSystem`."* Dropped, along with the
>   later proposal to relocate the cascade into `AllocationSystem`. Both the
>   speculative resolvers (spell propagation, melee blade sim) and real playback
>   must reach the same verdict, so the decision lives in one shared
>   `apply_depletions(entity, D) -> { died, graced }` owned by neither system.
>
> What survives unchanged: **reconnection cancels the reprieve** — if a graced
> node is reachable from core again before its counter expires, drop the entry
> rather than let a stale countdown sweep a node that is actually safe.
>
> The generalization that replaced all of it: a node survives iff it is inside
> some **surviving life source's reach** — core with infinite reach, a lifeline
> carrier with 2 hops. "Connected to core" is core's case of one rule, not a
> separate rule.

## Touch points (once this gets scheduled)

- `SkillNode` / `Entity`: `_tags` dict + `add_tag`/`remove_tag`/`has_tag`/`get_active_tags`.
- `EffectContext` / `EffectInstance`: `grant_tag`, ledger row extension, `revoke_all` coverage.
- New `LifelineEffect` (or `TagAuraEffect` base + concrete resource): recomputes on
  `_on_granted`/`_on_node_allocated`/`_on_node_deallocated`/`_on_core_moved`, same
  shape as `AuraEffect.recompute`, granting/revoking the tag instead of a modifier.
- `AuraEffect` origin rule: resolve the radiation source as
  `ctx.source_node if ctx.source_node != null else ctx.core_location` (replacing
  the current hardcoded `ctx.core_location`). Node-carried auras (lifeline addon)
  then radiate from their own node; core-class auras are unchanged. No new
  `@export` — a resolution rule, not a knob.
- `BattleSystem`: grace-period dictionary, cascade-loop consult, turn-boundary tick,
  reconnection cancel.
- Tests: tag ledger revocation (two sources, one revoked, tag persists), the
  cascade skip, the countdown expiry, and the reconnection-cancels-grace case —
  each is its own failure mode and none is exercised by the others.

## Recommendation

Don't model `has_lifeline` (or any future status flag) as a `ScalarStat`. Build
the tag-set channel described above sized for "a few now, more later" — it's
cheap (one refcounted dict per carrier) and reuses the grant/ledger/revoke
discipline `Effect` already has, so it's additive rather than a second mental
model. Keep the LifeLine grace mechanic itself out of the tag system: the tag
is only the "is this node currently protected" primitive; the cascade query
hook and the countdown are `BattleSystem`'s own state, same as every other
piece of forced-dealloc bookkeeping it already owns.
