class_name DeallocEntry
extends RefCounted

## One node's share of a forced-deallocation cascade — what leaving cost its
## owner (#518, see docs/domain/attack-timeline.md).
##
## Produced by [method EntityCombat.apply_cascade], recorded onto the
## [HitInstance] that caused it, and carried across the wire by [AttackRecord]
## so a peer [b]replays[/b] the set instead of re-deriving it. Re-derivation is
## what the old peer path did, and it cannot survive fog: walking the
## defender's navigator means walking nodes a filtered-delta client may not
## hold at all (docs/domain/multiplayer-sync-model.md).
##
## [b]Two purposes, kept apart on purpose.[/b] Everything above the divider is
## what the world BECOMES — model state a peer must apply to end in the same
## world. [member revoked_labels] is what to DRAW, and a peer that drops it
## entirely still lands in the identical world. Do not let a reader that needs
## one reach for the other.
##
## Owner call 2026-08-21, on why a deallocation is recorded at all rather than
## being left to fall out of the HP numbers:
##
## > [i]a node reduced to 1 HP is still 100% alive and granted no XP, a killed
## > node is one step closer to eliminating an entity entirely[/i]
##
## An entity's `health` pool only ever moves through core-node overflow or the
## [member chip] below, so damage that leaves a non-core node at 1 HP moves it
## by exactly zero — an outcome exposing damage totals but not deallocations
## does not expose the attrition vector at all.

# ── Model: a peer applies these ────────────────────────────────────────────

## The node that left its owner. Null only on a slice whose shadow has no real
## counterpart; every shadow built by [method EntityCombat.snapshot] does have
## one (topology is the real graph — see that method), so this is populated on
## live and shadow alike.
var node: SkillNode = null
## [member SkillNode.stable_id] of [member node], captured BEFORE the strip.
## The wire form carries this, never the reference (`.claude/rules/multiplayer-sync.md`).
var node_id: int = 0
## [member SkillNode.allocation_level] read BEFORE the strip, floored at 1.
##
## Pre-strip is load-bearing and has bitten before (#337): `force_deallocate`
## drives `owner_changed` -> `_refresh_alloc_count`, which zeroes the level, so
## any read AFTER the call returns 0 and both numbers below silently collapse
## to nothing. Same shape as [LootSystem]'s pre-cleanup snapshot.
var allocation_level: int = 0
## SP wounded by this node's departure — `maxi(allocation_level, 1)`. A 2/2
## node costs 2 wounds; the floor keeps pre-staking 1/1 costs exactly as they
## were.
var wound: int = 0
## HP chipped off the owner's `health` pool — `dealloc_damage * wound`.
var chip: float = 0.0
## True if this node was its owner's core. Never set by an attack cascade (a
## core node's depletion overflows into `health` instead of deallocating — see
## [method NodeCombat.take_damage]), but a whole-entity strip
## ([method EntityCombat.simulate_entity_death]) does reach the core, and a
## consumer counting "did this attack eliminate them" needs to tell the two
## apart.
var was_core: bool = false

# ── Presentation: a peer may ignore all of this ────────────────────────────

## Display names of the stat modifiers this node was granting its owner, for
## the client-side "modifier lost" toast. Owner call 2026-08-21: *"could attach
## whatever stat grants were revoked so the clients can draw them if they so
## want (stat modifier loss is sometimes toasted)"*.
##
## [b]Labels, not handles, and deliberately not a revocation.[/b] #518 does not
## revoke a shadow's granted modifiers at all — that is #520, and the reason is
## that the helpers which would do it ([method SkillNode.remove_entity_modifiers_from],
## [method SkillNode.clear_scaled_effect_sets]) MUTATE the real node, so a
## shadow cannot borrow them. Reading names off `node.modifiers` mutates
## nothing, which is exactly why the presentation half could ship here and the
## model half could not.
var revoked_labels: PackedStringArray = PackedStringArray()


func _to_string() -> String:
	return "<DeallocEntry #%d lvl=%d wound=%d chip=%.1f>" % [
		node_id, allocation_level, wound, chip]
