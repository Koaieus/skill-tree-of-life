class_name LootRoundCommand
extends Command

## "Run one round of this relic's claim flow" — the verb that carries loot
## across the wire (#522).
##
## [b]Two states, one type[/b], deliberately copying [LaunchAttackCommand]:
##   * [member resolved] EMPTY — an INITIATE. The authority filters the relic's
##     remaining pool by `would_cycle` against the collector's LIVE board,
##     weighted-samples an offer, raises a [LootPickRequest] (or auto-resolves
##     when nobody claims it), grants the pick, and stamps what it did into this
##     same object — which is what [CommandLink] broadcasts.
##   * [member resolved] POPULATED — a REPLAY. A peer grants exactly what is
##     recorded. It does not roll, does not filter, does not raise a request and
##     does not advance the chain.
##
## [b]Why the round and not the pick is the wire unit.[/b] The obvious design —
## "the player's pick becomes a command" — mirrors only the path with a human
## on it. Two of [SkillDustAddon]'s grant paths never raise a request at all:
## the single-cycle-safe-survivor auto-grant, and the NPC / headless
## auto-resolve. A vocabulary built around [PickLootCommand] alone would leave
## every NPC relic claim diverging a peer while the human-pick test passed.
## Recording the ROUND covers all three uniformly; the human path is just the
## one with latency in the middle.
##
## [PickLootCommand] still exists and is still the right shape — it is the
## INTENT travelling the other way, from a remote human's client back to the
## host. See its own doc.
##
## [b]One command per round[/b], including the terminal one. A relic that
## grants K things produces K rounds plus a final `finished` round that frees
## it. Folding the terminal state into the last grant would need lookahead, and
## the five distinct ways [SkillDustAddon] can reach its end (collector dead,
## rounds exhausted, pool dry, no cycle-safe survivor, empty sample) all have to
## free the peer's relic too — a round that grants nothing and says `finished`
## covers every one of them, including "nothing was ever granted".

const TAG: StringName = &"loot_round"

## [member SkillNode.stable_id] of the relic node carrying the
## [SkillDustAddon]. Never a node reference — see
## `.claude/rules/multiplayer-sync.md`.
var carrier_id: int = 0

## The round's outcome record. Empty means "not applied yet"; see the class
## note. Populated it always carries all three keys:
##   * `granted` — the [StatModifier] wire form ([method StatModifier.to_dict]),
##     or null when this round granted no stat. BY VALUE, per the #522 owner
##     call: two of the three loot buckets read the VICTIM'S own board, which a
##     peer holds only partially and possibly stale, so an index into it would
##     be a silent mis-grant.
##   * `spell_id` — [member SpellDef.id], or `""`. Spells ARE authored, so an id
##     genuinely works there ([method SpellCatalog.by_id] resolves it).
##   * `finished` — this round ends the chain; free the relic.
var resolved: Dictionary = {}


func _init(entity_id_: int = 0, carrier_id_: int = 0, resolved_: Dictionary = {}) -> void:
	super(entity_id_)
	carrier_id = carrier_id_
	resolved = resolved_


func type_tag() -> StringName:
	return TAG


## True once the authority has stamped an outcome — i.e. this is a replay.
func is_replay() -> bool:
	return not resolved.is_empty()


## Stamp the outcome. Called by [SkillDustAddon] the instant its round has
## settled, so the record rides out on [signal CommandApplier.command_confirmed]
## without waiting for anything after it.
func record(granted: StatModifier, spell_id: StringName, finished: bool) -> void:
	resolved = {
		"granted": granted.to_dict() if granted != null else null,
		"spell_id": String(spell_id),
		"finished": finished,
	}


## The granted modifier this round recorded, rebuilt locally, or null.
func granted_modifier() -> StatModifier:
	return StatModifierCodec.from_dict(resolved.get("granted"))


## The granted spell this round recorded, or null. Resolves through the
## authored catalog rather than reconstructing a [SpellDef] — a spell has a real
## identity, unlike a runtime-minted [StatModifier].
func granted_spell() -> SpellDef:
	return SpellCatalog.by_id(StringName(resolved.get("spell_id", "")))


## Whether this round frees the relic.
func is_final() -> bool:
	return bool(resolved.get("finished", false))


func to_dict() -> Dictionary:
	var d := super()
	d["carrier_id"] = carrier_id
	d["resolved"] = resolved
	return d


static func from_dict(d: Dictionary) -> LootRoundCommand:
	return LootRoundCommand.new(
		int(d.get("entity_id", 0)),
		int(d.get("carrier_id", 0)),
		d.get("resolved", {}),
	)
