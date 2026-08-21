class_name PickLootCommand
extends Command

## "Of the relic mods you offered me, I keep these."
##
## [b]Owner call 2026-08-21:[/b] [i]"loot picks are just 'hey i picked <this
## statmodifier>', users cannot distinguish a same-seed roll from a random roll
## given that looting is done by 1 player and invisible to others -- the
## resulting pick however needs to be communicated back to host so they can
## broadcast or whatever if needed"[/i]
##
## So the ROLL stays host-only and needs no determinism guarantee; only the
## PICK travels. Indices, not modifiers: whoever received the request already
## holds the candidate list, and
## `ui/loot_picker/loot_picker_body.gd:80 resolve()` already yields exactly
## these positions. [member request_id] correlates the answer with the
## [LootPickRequest] that asked, since several can be queued
## (`ui/hud/hud_root.gd:135 _enqueue_pick`).

const TAG: StringName = &"pick_loot"

## The [member LootPickRequest.request_id] being answered.
var request_id: int = 0

## Indices into that request's `candidates`.
var chosen_indices: Array[int] = []


func _init(entity_id_: int = 0, request_id_: int = 0, chosen_indices_: Array[int] = []) -> void:
	super(entity_id_)
	request_id = request_id_
	chosen_indices = chosen_indices_


func type_tag() -> StringName:
	return TAG


func to_dict() -> Dictionary:
	var d := super()
	d["request_id"] = request_id
	d["chosen_indices"] = chosen_indices.duplicate()
	return d


static func from_dict(d: Dictionary) -> PickLootCommand:
	var idx: Array[int] = []
	idx.assign(d.get("chosen_indices", []))
	return PickLootCommand.new(
		int(d.get("entity_id", 0)), int(d.get("request_id", 0)), idx
	)
