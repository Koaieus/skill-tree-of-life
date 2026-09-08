extends GutTest

## #765: a spell tooltip that renders BEHIND a modal or another full-screen
## overlay is worse than no tooltip — the player asked for information and
## got a glitch instead. Sibling order under [HudRoot] IS z-order (no
## [CanvasLayer], no per-node z_index), so this pins the one property the fix
## depends on: [SpellTooltip] must be the last child, drawn on top of every
## modal-queue member (#204/#486) and every other full-screen overlay.

const _HUD_ROOT := preload("res://ui/hud/hud_root.tscn")

const _OTHER_OVERLAY_NAMES := [
	"StatBoardOverlay", "PauseMenu", "LootPicker", "SpellLootPicker",
	"MassActionConfirmPanel", "RunEndOverlay",
]


func test_spell_tooltip_draws_above_every_modal_and_overlay() -> void:
	# Not added to the tree — inspecting sibling order needs no _ready() from
	# HudRoot or any of its children (godot-scene-authoring.md); queue_free(),
	# never free(), since this is a level-sized instance (testing.md).
	var hud: HudRoot = _HUD_ROOT.instantiate()

	var tooltip := hud.get_node("SpellTooltip")
	assert_not_null(tooltip, "HudRoot should have a SpellTooltip child")
	var tooltip_index: int = tooltip.get_index()

	for other_name in _OTHER_OVERLAY_NAMES:
		var other := hud.get_node(other_name as String)
		assert_not_null(other, "HudRoot should have a %s child" % other_name)
		assert_gt(
			tooltip_index, other.get_index(),
			"SpellTooltip must sit after (draw above) %s" % other_name
		)

	hud.queue_free()
