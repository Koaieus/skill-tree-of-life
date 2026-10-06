---
status: exploring
---

# LifeLine grace — surviving disconnection (design, unbuilt: #240)

> The marker half of LifeLine has shipped: the refcounted tag channel
> (`EffectContext.grant_tag`, `TagAuraEffect`, an aura radiating from its
> carrier node) is `docs/domain/effect-system.md` § "Known limits". What
> follows is the unbuilt half — the grace mechanic. Its design home is #240;
> the rationale is D-28/D-29 in `docs/adr/legacy-mvp-decisions.md`.

## The tag is necessary, not sufficient

Granting `&"lifeline"` to nodes within N hops of the carrier node is the easy
80%. The actual "survive disconnection for one turn" behaviour needs new work
**outside** the tag system, because it changes *when* death happens, not just
*what data* a node carries. Keep the grace mechanic itself out of the tag
system: the tag is only the "is this node currently protected" primitive.

LifeLine radiates from its **carrier node**, never from core: at the decision
point the islanded nodes are cut off from core, so a core-sourced reach could
not see them, and the deallocation that islands them would revoke a
core-sourced tag at the moment the cascade reads it.

- **A node survives iff it is inside some surviving life source's reach** —
  core with infinite reach, a lifeline carrier with 2 hops. "Connected to core"
  is core's case of one rule, not a separate rule.
- **Protection is `has_tag` recomputed on the post-cut subgraph**, never a
  pre-cut snapshot: a lifeline node hanging off the cut vertex carries the tag
  before the cut and loses it after.
- **One shared resolver decides deaths** — `apply_depletions(entity, D) ->
  { died, graced }`, owned by neither `BattleSystem` nor `AllocationSystem`, so
  the speculative resolvers (spell propagation, melee blade sim) and real
  playback reach the same verdict.
- **Reconnection cancels the reprieve** — if a graced node is reachable from a
  life source again before its counter expires, drop the entry rather than let
  a stale countdown sweep a node that is actually safe.

## Touch points (once this gets scheduled)

- A `LifelineEffect` (a concrete `TagAuraEffect` resource) granting the tag
  from its carrier node.
- The shared depletion resolver: the grace-period bookkeeping, the cascade
  consult, the turn-boundary tick, the reconnection cancel.
- Tests: the cascade skip, the countdown expiry, and the
  reconnection-cancels-grace case — each is its own failure mode and none is
  exercised by the others.
