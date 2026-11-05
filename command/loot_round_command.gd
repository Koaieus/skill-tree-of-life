class_name LootRoundCommand
extends Command

## "This round of this relic's claim flow granted THIS": carries a settled loot
## outcome across the wire. Always a replay on every peer including the authority
## (`resolved` is stamped before construction). The round, not the pick, is the
## wire unit; one command per round, including the terminal `finished` round.
## See docs/domain/loot-system.md

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
	@warning_ignore("incompatible_ternary")
	resolved = {
		"granted": granted.to_dict() if granted != null else null,
		"spell_id": String(spell_id),
		"finished": finished,
	}


func type_tag() -> StringName:
	return TAG


## The wire form, declared once (#1000); see [WireFields].
static func wire_fields() -> Array[WireFields.Field]:
	var fields := Command.wire_fields()
	fields.append(WireFields.Field.new(&"carrier_id", TYPE_INT))
	fields.append(WireFields.Field.new(&"resolved", TYPE_DICTIONARY))
	return fields


## The granted modifier this round recorded, rebuilt locally, or null.
func granted_modifier() -> StatModifier:
	return StatModifierCodec.from_dict(resolved.get("granted"))


## The granted spell this round recorded, or null. Resolves through the
## authored catalog rather than reconstructing a [SpellDef] — a spell has a real
## identity, unlike a runtime-minted [StatModifier]. [param catalog] is the
## applier's ([member CommandContext.spell_catalog]); null resolves nothing.
func granted_spell(catalog: SpellCatalog) -> SpellDef:
	if catalog == null:
		return null
	return catalog.by_id(StringName(resolved.get("spell_id", "")))


## Whether this round frees the relic.
func is_final() -> bool:
	return bool(resolved.get("finished", false))


static func from_dict(d: Dictionary) -> LootRoundCommand:
	return WireFields.from_dict(LootRoundCommand, d)
