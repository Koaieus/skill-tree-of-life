extends GutTest

## The "off is a per-system flag" convention (#1006, ADR 0026). There is no
## shared `System` base: a system that HAS an off state declares
## `@export var enabled := true` and guards its own public entry points with
## its own semantics. This file is the convention's test — one case per
## system in the audit's bucket (b), asserting the property exists and that a
## disabled instance's public entry is a no-op in that system's own terms.
##
## Audit (2026-09-21): no inherited scene omits a system — Godot inherited
## scenes cannot delete an instanced node — so the only "omitters" were the
## three root flags (`enable_fog` / `show_ui` / `auto_start_turn`), which
## moved onto the systems they toggle: [member VisionSystem.enabled],
## [member HudRoot.enabled], [member TurnManager.opens_first_turn].

const _HUD := preload("res://ui/hud/hud_root.tscn")


func _assert_has_enabled(sys: Object) -> bool:
	var has := "enabled" in sys
	assert_true(has, "%s declares `enabled`" % sys.get_class())
	if has:
		assert_true(sys.get("enabled"), "%s: enabled defaults to true" % sys.get_class())
	return has


## Disabled VisionSystem: everything is visible, nothing is fogged, and no
## circles are offered to the renderers — the "no fog" showcase reading.
func test_vision_system_disabled_sees_everything() -> void:
	var vs := VisionSystem.new()
	autofree(vs)
	if not _assert_has_enabled(vs):
		return
	vs.empty_mode = VisionSystem.EmptyMode.DARKNESS
	vs.set("enabled", false)
	var node := SkillNode.new()
	autofree(node)
	assert_true(vs.is_visible(node), "disabled: every node is visible")
	assert_true(vs.is_sensed(node), "disabled: every node is sensed")
	assert_false(vs.should_render_fog(), "disabled: fog overlay is not drawn")
	assert_eq(vs.get_vision_sources(), [], "disabled: no vision circles")


## Disabled HudRoot: `bind_systems` binds nothing and the layer hides itself.
func test_hud_root_disabled_compose_is_a_noop() -> void:
	var hud: HudRoot = _HUD.instantiate()
	add_child_autofree(hud)
	if not _assert_has_enabled(hud):
		return
	hud.set("enabled", false)
	hud.bind_systems(null, null, null, null, null, null)
	assert_false(hud.visible, "disabled: the HUD layer is hidden")
	assert_false(hud.is_bound(), "disabled: nothing was bound")


## `TurnManager.opens_first_turn` is the moved `auto_start_turn` — not an off
## state (the manager stays live for the turns a showcase drives itself), so
## a plain export rather than `enabled`. [method GameRoot._open_first_turn]
## reads it; `test_initiative_stagger.gd` covers that read.
func test_turn_manager_declares_opens_first_turn() -> void:
	var tm := TurnManager.new()
	autofree(tm)
	assert_true("opens_first_turn" in tm, "TurnManager declares `opens_first_turn`")
	if "opens_first_turn" in tm:
		assert_true(tm.get("opens_first_turn"), "defaults to true")
