class_name LootRoundCommand
extends Command

## "This round of this relic's claim flow granted THIS." — the verb that
## carries a settled loot outcome across the wire (#522, split from the
## pick-offer by #646).
##
## [b]Always a replay, on every peer INCLUDING the authority.[/b] Unlike
## [LaunchAttackCommand] this is not a two-states-one-type command — #646 gave
## up that symmetry on purpose. The offer / pick / roll sequence that used to
## live inside this command's own `_apply` now runs entirely OUTSIDE the
## command pipeline, host-side, driven by [SkillDustAddon]. Only once the
## outcome is fully known does the authority construct one of these — the
## constructor takes the outcome — and submit it. So by the time a
## `LootRoundCommand` exists at all, [member resolved] is already stamped, and
## `validate -> confirm -> apply` (#540, #545) needs no opt-out for it:
## confirming broadcasts a complete record with nothing left to wait for.
##
## The old shape stamped the outcome from DEEP INSIDE `_apply`
## ([SkillDustAddon]'s `_run_round` chain calling `record()`), so
## [CommandLink]'s confirm-before-apply ordering broadcast an EMPTY `resolved`
## — a peer read that as an unstamped INITIATE and rolled its own divergent
## loot instead of replaying the authority's. That is the #646 defect, and the
## fix is this class no longer having an INITIATE state to be caught
## mid-stamp: see `docs/domain/multiplayer-sync-model.md` for why the loot
## round is the deliberate exception to "one type, two states".
##
## [b]Why the round and not the pick is the wire unit.[/b] The obvious design —
## "the player's pick becomes a command" — mirrors only the path with a human
## on it. Two of [SkillDustAddon]'s grant paths never raise a pick at all: the
## single-cycle-safe-survivor auto-grant, and the NPC / headless auto-resolve.
## A vocabulary built around [PickLootCommand] alone would leave every NPC
## relic claim diverging a peer while the human-pick test passed. Recording
## the ROUND covers all three uniformly; the human path is just the one with
## latency in the middle — latency that now happens entirely BEFORE this
## command is minted, never inside its application.
##
## [PickLootCommand] still exists and is still the right shape — it is the
## INTENT travelling the other way, from a remote human's client back to the
## host, answering the downward [LootPickOffer] (also #646, NOT a [Command] —
## see that class). See [PickLootCommand]'s own doc.
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

## The round's settled outcome, stamped at construction — see the class note.
## Always carries all three keys:
##   * `granted` — the [StatModifier] wire form ([method StatModifier.to_dict]),
##     or null when this round granted no stat. BY VALUE, per the #522 owner
##     call: two of the three loot buckets read the VICTIM'S own board, which a
##     peer holds only partially and possibly stale, so an index into it would
##     be a silent mis-grant.
##   * `spell_id` — [member SpellDef.id], or `""`. Spells ARE authored, so an id
##     genuinely works there ([method SpellCatalog.by_id] resolves it).
##   * `finished` — this round ends the chain; free the relic.
var resolved: Dictionary = {}


## The constructor takes the outcome (#646) — by the time a caller can name
## [param granted] / [param spell_id] / [param finished] the round has already
## been decided, so there is no legal way to construct one of these
## mid-decision. [method from_dict] is the one exception, rebuilding straight
## from a wire [member resolved] rather than re-deriving it from parts.
func _init(entity_id_: int = 0, carrier_id_: int = 0, granted: StatModifier = null,
		spell_id: StringName = &"", finished: bool = false) -> void:
	super(entity_id_)
	carrier_id = carrier_id_
	resolved = {
		"granted": granted.to_dict() if granted != null else null,
		"spell_id": String(spell_id),
		"finished": finished,
	}


func type_tag() -> StringName:
	return TAG


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
	var command := LootRoundCommand.new(int(d.get("entity_id", 0)), int(d.get("carrier_id", 0)))
	command.resolved = d.get("resolved", {})
	return command
