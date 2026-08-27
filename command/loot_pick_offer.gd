class_name LootPickOffer
extends RefCounted

## "Show this collector a pick screen; here is the draw." — the downward
## offer message #646 split out of [LootRoundCommand].
##
## [b]NOT a [Command].[/b] It carries an OFFER, not a decided outcome, and it
## mutates nothing on arrival — so unlike [LootRoundCommand] it never enters
## [method CommandApplier._drain]. [CommandLink] sends it directly
## ([constant CommandLink.KIND_LOOT_OFFER]), outside the
## validate/confirm/apply pipeline, the same additive-and-opt-in shape as
## [constant CommandLink.KIND_SNAPSHOT] / `KIND_SETUP` / `KIND_ENTITIES`.
##
## Raised when [LootPickRegistry] parks a request for a REMOTE collector
## ([enum LootPickRequest.Claim.REMOTE]) — see [signal LootPickRegistry.offer_parked].
## A peer that receives one knows to open its OWN picker locally and answer
## with a [PickLootCommand], which is unchanged by #646 and still travels
## upward as the intent.
##
## Candidates travel BY VALUE, never an index into a board a peer holds only
## partially or staler than the draw — see `.claude/rules/multiplayer-sync.md`.
## Stat candidates are full [StatModifier] wire dicts
## ([method StatModifierCodec.to_dicts]); spell candidates are [SpellDef] ids,
## resolved through the shared [SpellCatalog] the same way
## [method LootRoundCommand.granted_spell] does — an authored spell has a real
## identity, unlike a runtime-minted [StatModifier].

## Which candidate list this offer carries. GDScript has no generics and
## [LootPickRequest] / [SpellLootRequest] are deliberately not folded together
## (see [SpellLootRequest]'s own note) — this is the wire-side discriminator.
const KIND_STAT: StringName = &"stat"
const KIND_SPELL: StringName = &"spell"

## Correlates a [PickLootCommand] back to this offer — the same id
## [LootPickRegistry.park] minted for it.
var request_id: int = 0

## [member Entity.entity_id] of the collector being asked to pick.
var collector_id: int = 0

var kind: StringName = KIND_STAT
var stat_candidates: Array[StatModifier] = []
var spell_ids: Array[StringName] = []


static func for_stat_request(request: LootPickRequest) -> LootPickOffer:
	var offer := LootPickOffer.new()
	offer.kind = KIND_STAT
	offer.request_id = request.request_id
	offer.collector_id = request.collector.entity_id if request.collector != null else 0
	offer.stat_candidates = request.candidates
	return offer


static func for_spell_request(request: SpellLootRequest) -> LootPickOffer:
	var offer := LootPickOffer.new()
	offer.kind = KIND_SPELL
	offer.request_id = request.request_id
	offer.collector_id = request.collector.entity_id if request.collector != null else 0
	for s in request.candidates:
		offer.spell_ids.append((s as SpellDef).id)
	return offer


func to_dict() -> Dictionary:
	var d := {
		"request_id": request_id,
		"collector_id": collector_id,
		"kind": kind,
	}
	if kind == KIND_SPELL:
		var ids: Array = []
		for id in spell_ids:
			ids.append(String(id))
		d["spell_ids"] = ids
	else:
		d["stat_candidates"] = StatModifierCodec.to_dicts(stat_candidates)
	return d


static func from_dict(d: Dictionary) -> LootPickOffer:
	var offer := LootPickOffer.new()
	offer.request_id = int(d.get("request_id", 0))
	offer.collector_id = int(d.get("collector_id", 0))
	offer.kind = StringName(d.get("kind", KIND_STAT))
	if offer.kind == KIND_SPELL:
		for id in d.get("spell_ids", []):
			offer.spell_ids.append(StringName(id))
	else:
		offer.stat_candidates = StatModifierCodec.array_from_dicts(d.get("stat_candidates", []))
	return offer
