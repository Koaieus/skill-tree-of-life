extends GutTest

## Guards the `.tscn` root-node ordering gotcha (`.claude/rules/godot-workflow.md`):
## Godot deserializes root-node properties in file order, so a
## `script = ExtResource(...)` line placed AFTER an `@export` override silently
## reinitialises that export to its GDScript default, discarding the override.
## An editor pass that reorders the root node reintroduces it, with no error.
##
## The contract is therefore "the authored override SURVIVED instantiation",
## not "melee is exactly this red" — the swatches are a palette decision whose
## home is the `.tscn`. Pinning exact RGB here broke all four tests on any
## retune, for a change that was never a regression.

const _MELEE := preload("res://ui/hud/combat_readout/combat_card_melee.tscn")
const _RANGED := preload("res://ui/hud/combat_readout/combat_card_ranged.tscn")
const _MAGIC := preload("res://ui/hud/combat_readout/combat_card_magic.tscn")
const _DEFENSE := preload("res://ui/hud/combat_readout/combat_card_defense.tscn")

## `CombatReadoutCard.mode_color`'s GDScript default — the gold every card
## reverts to when the ordering bug bites. See combat_readout_card.gd.
const _CLASS_DEFAULT := Color(0.9, 0.75, 0.4, 1.0)


func test_authored_mode_colors_survive_instantiation() -> void:
	var scenes: Array[PackedScene] = [_MELEE, _RANGED, _MAGIC, _DEFENSE]
	var seen: Array[Color] = []
	for scene in scenes:
		var card := scene.instantiate()
		add_child_autofree(card)
		assert_ne(card.mode_color, _CLASS_DEFAULT,
			"%s reverted to the class default — is `script =` listed after `mode_color` on its root node?"
				% scene.resource_path)
		assert_false(card.mode_color in seen,
			"%s shares a mode_color with an earlier card; each mode needs its own swatch"
				% scene.resource_path)
		seen.append(card.mode_color)
	assert_eq(seen.size(), 4, "all four cards should have been checked")
