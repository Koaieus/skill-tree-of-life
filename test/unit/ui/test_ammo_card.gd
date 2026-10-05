extends GutTest

## An ammo card wears its type's first status as one [IdentityBadge], so the
## cards read apart at a glance. Everything derives from the [AmmoType]; a
## status-less type shows no badge.

const _CARD_SCENE := preload("res://ui/hud/command_tray/bodies/ammo_card.tscn")
const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")
const _POISON: AmmoType = preload("res://attack/ammo/types/poison.tres")


func _card(type: AmmoType) -> AmmoCard:
	var card: AmmoCard = _CARD_SCENE.instantiate()
	add_child_autofree(card)
	card.setup(type)
	return card


func _visible_badges(card: AmmoCard) -> Array[IdentityBadge]:
	var out: Array[IdentityBadge] = []
	for n in card.find_children("*", "IdentityBadge", true, false):
		if (n as IdentityBadge).is_visible_in_tree():
			out.append(n)
	return out


func test_a_poison_card_shows_exactly_one_badge_bound_to_poisons_identity() -> void:
	var card := _card(_POISON)
	var badges := _visible_badges(card)
	assert_eq(badges.size(), 1, "exactly one visible identity badge")
	if badges.is_empty():
		return
	assert_not_null(badges[0].identity, "the badge is bound")
	if badges[0].identity == null:
		return
	assert_eq(badges[0].identity.id, _POISON.first_status_def().identity.id, "bound to the status identity")
	assert_eq(badges[0].size_px, card.badge_px, "sized by the card's knob")


func test_the_base_arrow_card_shows_no_badge() -> void:
	var card := _card(_ROSTER.base_type())
	assert_eq(_visible_badges(card).size(), 0, "a status-less type shows no badge")


func test_the_letter_fallback_is_gone() -> void:
	var card := _card(_POISON)
	assert_null(card.find_child("StatusLetter", true, false), "no StatusLetter node remains")
