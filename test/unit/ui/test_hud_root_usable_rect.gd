extends GutTest

## [method HudRoot.usable_rect] — the screen the HUD leaves free for world
## overlays (the tooltip fan's keep-in). It is the HUD's own rect minus the
## docked chrome on each side, so it must sit strictly inside on every side
## that carries chrome.

const _HUD_ROOT := preload("res://ui/hud/hud_root.tscn")

var _hud: HudRoot


func before_each() -> void:
	_hud = _HUD_ROOT.instantiate()
	add_child_autofree(_hud)
	# Two frames: containers sort their children on the first.
	await get_tree().process_frame
	await get_tree().process_frame


func test_usable_rect_excludes_the_docked_chrome() -> void:
	var whole := _hud.get_global_rect()
	var usable := _hud.usable_rect()
	assert_true(usable.has_area(), "the chrome leaves some screen free: %s" % usable)
	assert_gt(usable.position.x, _hud.left_column_slot.get_global_rect().end.x - 0.5,
			"left edge clears the left column")
	assert_gt(usable.position.y, _hud.xp_track.get_global_rect().end.y - 0.5,
			"top edge clears the top strip")
	assert_lt(usable.end.x, _hud.combat_readout.get_global_rect().position.x + 0.5,
			"right edge clears the combat readout")
	assert_lt(usable.end.y, _hud.command_tray.get_global_rect().position.y + 0.5,
			"bottom edge clears the command tray")
	assert_lt(usable.end.y, _hud.minimap_panel.get_global_rect().position.y + 0.5,
			"bottom edge clears the minimap")
	assert_true(whole.encloses(usable), "and never reaches past the HUD itself")
