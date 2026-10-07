extends GutTest

## Headless smoke for the arrow gallery sandbox tab (visual tool: no look test,
## `.claude/rules/red-green.md`). The panel instantiates, its picker holds every
## roster type, and every type fires through `BattleSystem.launch_attack` under
## every verdict preset, each preset producing the verdict it exists to show.
##
## Instant mutation: the beat clock is the game's, not what this asserts, and
## 12 types x 5 presets on the reveal clock would blow the 15 s budget.

const _PANEL_PATH := "res://addons/arrow_gallery/arrow_gallery_panel.tscn"
const _ROSTER_PATH := "res://attack/ammo/ammo_type_roster.tres"
const _BUDGET_SECONDS := 10.0

var _panel: Node


func before_each() -> void:
	var scene := load(_PANEL_PATH) as PackedScene
	assert_not_null(scene, "the gallery panel scene loads")
	if scene == null:
		return
	_panel = scene.instantiate()
	_panel.instant = true
	add_child_autofree(_panel)
	await wait_physics_frames(1)


func test_picker_holds_every_roster_type() -> void:
	var roster := load(_ROSTER_PATH) as AmmoTypeRoster
	assert_not_null(_panel, "panel instantiated")
	if _panel == null:
		return
	assert_eq(_panel.type_count(), roster.types.size(), "one picker entry per roster type")


func test_every_type_fires_under_every_preset() -> void:
	assert_not_null(_panel, "panel instantiated")
	if _panel == null:
		return
	var started := Time.get_ticks_msec()
	for preset in _panel.Preset.values():
		for i in _panel.type_count():
			var outcome: AttackOutcome = await _panel.fire(i, preset, 4)
			var ammo: AmmoType = _panel.type_at(i)
			var label := "%s / %s" % [ammo.id, _panel.Preset.keys()[preset]]
			assert_not_null(outcome, "%s fired" % label)
			if outcome != null:
				_assert_preset_beat(outcome, preset, ammo, label)
	assert_lt((Time.get_ticks_msec() - started) / 1000.0, _BUDGET_SECONDS,
			"60 instant volleys inside the budget")


## A 0-damage type (blindness) never reaches mitigation or the crit
## multiplier, so the damage presets read nothing off it.
func _assert_preset_beat(outcome: AttackOutcome, preset: int, ammo: AmmoType, label: String) -> void:
	var deals := not is_zero_approx(ammo.damage_scale)
	var arrows: Array[HitInstance] = _panel.arrows_of(outcome)
	assert_eq(arrows.size(), 4, "%s: four arrows" % label)
	var gated := 0
	var healed := 0
	var held := 0
	var crits := 0
	for a in arrows:
		if a.gated:
			gated += 1
		elif a.kind == HitInstance.Kind.HEAL:
			healed += 1
		elif is_zero_approx(a.effective_amount):
			held += 1
		if a.is_crit:
			crits += 1
	if preset == _panel.Preset.DUD:
		if deals:
			assert_gt(gated, 0, "%s: a later arrow duds on the depleted target" % label)
	elif preset == _panel.Preset.HELD:
		assert_eq(held, arrows.size(), "%s: armour holds every arrow" % label)
	elif preset == _panel.Preset.GAINED:
		if deals:
			assert_eq(healed, arrows.size(), "%s: every arrow feeds the defender" % label)
	elif preset == _panel.Preset.CRIT:
		if deals:
			assert_eq(crits, arrows.size(), "%s: every arrow crits" % label)
