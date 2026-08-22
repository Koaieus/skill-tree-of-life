class_name PickLootCommand
extends Command

## "Of the relic mods you offered me, I keep this one."
##
## [b]Owner call 2026-08-21:[/b] [i]"loot picks are just 'hey i picked <this
## statmodifier>', users cannot distinguish a same-seed roll from a random roll
## given that looting is done by 1 player and invisible to others -- the
## resulting pick however needs to be communicated back to host so they can
## broadcast or whatever if needed"[/i]
##
## So the ROLL stays host-only and needs no determinism guarantee; only the
## PICK travels. An index, not a modifier: whoever received the request already
## holds the candidate list. [member request_id] correlates the answer with the
## [LootPickRequest] that asked, since several can be queued
## (`ui/hud/hud_root.gd` `_enqueue_pick`).
##
## [b]Singular, per the owner call 2026-08-22[/b] — [i]"for the longest time i
## said 'pick 1 out of N, M times' and agents wrote up 'pick M from N'"[/i]. A
## draw is always a pick-ONE; the M is [member SkillDustAddon.rounds], and each
## round sends its own command. This carried an `chosen_indices: Array[int]`
## until then. Do not re-pluralise it.
##
## [member chosen_index] is -1 for a forfeited round — the resolver's documented
## empty-`chosen` branch, which must survive the wire.

const TAG: StringName = &"pick_loot"

## The [member LootPickRequest.request_id] being answered.
var request_id: int = 0

## Index into that request's `candidates`, or -1 to forfeit the round.
var chosen_index: int = -1


func _init(entity_id_: int = 0, request_id_: int = 0, chosen_index_: int = -1) -> void:
	super(entity_id_)
	request_id = request_id_
	chosen_index = chosen_index_


func type_tag() -> StringName:
	return TAG


func to_dict() -> Dictionary:
	var d := super()
	d["request_id"] = request_id
	d["chosen_index"] = chosen_index
	return d


static func from_dict(d: Dictionary) -> PickLootCommand:
	return PickLootCommand.new(
		int(d.get("entity_id", 0)),
		int(d.get("request_id", 0)),
		int(d.get("chosen_index", -1)),
	)
