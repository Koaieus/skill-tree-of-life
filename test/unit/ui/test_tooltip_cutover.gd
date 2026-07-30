extends GutTest

## Tooltip V2 (#235) — the cutover: `ui/skill_node_tooltip.{gd,tscn}` is gone and
## `TooltipFan` is the HUD's only hover-driven node tooltip.
##
## Worth its own file rather than a line in `test_tooltip_fan.gd`, because what it
## guards is a DELETION. The failure mode being locked out is re-adding a second
## tooltip: for the whole of Phase 2 both V1 and the fan were mounted in
## `hud_root.tscn` and both self-subscribed to `Events.skill_node_hovered`, so
## every hover fired two tooltips. Nothing in the suite noticed, because each one
## was individually correct.

const _HUD_SCENE := preload("res://ui/hud/hud_root.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

const _V1_SCRIPT := "res://ui/skill_node_tooltip.gd"
const _V1_SCENE := "res://ui/skill_node_tooltip.tscn"


func _hud() -> HudRoot:
	var hud := _HUD_SCENE.instantiate() as HudRoot
	add_child(hud)
	autofree(hud)
	return hud


# --- the deletion --------------------------------------------------------------

func test_the_v1_tooltip_files_are_gone() -> void:
	assert_false(ResourceLoader.exists(_V1_SCRIPT), "%s must be deleted" % _V1_SCRIPT)
	assert_false(ResourceLoader.exists(_V1_SCENE), "%s must be deleted" % _V1_SCENE)


func test_the_hud_scene_still_loads_after_the_removal() -> void:
	# A `.tscn` that drops a node block but keeps its `ext_resource` (or the
	# reverse) fails to load outright. Instantiating is the assertion.
	var hud := _hud()
	assert_not_null(hud, "hud_root.tscn must still instantiate")
	assert_not_null(hud.tooltip_fan, "%TooltipFan must still resolve")


func test_the_hud_mounts_no_second_node_tooltip() -> void:
	var hud := _hud()
	assert_null(hud.get_node_or_null("SkillNodeTooltip"),
		"the V1 tooltip must not be mounted")
	var fans := hud.find_children("*", "TooltipFan", true, false)
	assert_eq(fans.size(), 1, "exactly one TooltipFan, no more and no fewer")


## The real acceptance criterion, stated against the mechanism rather than the
## node list: exactly one HUD node may raise a *tooltip* on a node hover. Counted
## by bus subscription, since that is how both tooltips wired themselves and how a
## third would.
##
## Scope, precisely: this counts subscribers wired at `_ready`, which is what a
## self-driving tooltip does (V1 and the fan both did). It deliberately does NOT
## catch compose-time subscribers, and one of those is legitimate —
## `CombatReadout` subscribes inside its own `bind()` to preview an attack against
## the hovered node. That is a readout, not a tooltip, and it is *supposed* to
## respond. So the fixture skips `compose()` and the assertion stays about
## tooltips rather than about hover-awareness in general.
func test_exactly_one_hud_node_answers_a_node_hover_at_ready() -> void:
	var hud := _hud()
	await get_tree().process_frame
	var subscribers: Array[String] = []
	for conn in Events.skill_node_hovered.get_connections():
		var target: Variant = (conn["callable"] as Callable).get_object()
		if target is Node and hud.is_ancestor_of(target as Node):
			subscribers.append((target as Node).name)
	assert_eq(subscribers, ["TooltipFan"] as Array[String],
		"the fan must be the HUD's only _ready-time hover subscriber (found %s)" % [subscribers])


# --- and the fan still works through the HUD ----------------------------------

func test_hovering_mounts_the_fan_under_the_hud() -> void:
	var hud := _hud()
	await get_tree().process_frame
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child(node)
	autofree(node)

	Events.skill_node_hovered.emit(node)
	await get_tree().process_frame

	assert_true(hud.tooltip_fan.visible, "the fan should be showing")
	assert_not_null(hud.tooltip_fan._current_fan, "and should have mounted its scene")


func test_unhovering_hides_it_again() -> void:
	var hud := _hud()
	await get_tree().process_frame
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child(node)
	autofree(node)

	Events.skill_node_hovered.emit(node)
	await get_tree().process_frame
	Events.skill_node_unhovered.emit()
	var frames := 0
	while hud.tooltip_fan._current_fan != null and frames < 240:
		await get_tree().process_frame
		frames += 1
	assert_null(hud.tooltip_fan._current_fan, "the fan should retire cleanly through the HUD too")


# --- no second modifier formatter survives (#305) ------------------------------

## V1 carried a hand-mirrored `_format_modifier` whose own docstring said "keep
## the two in sync by hand". #305 made `StatModifier.format()` the single home and
## deliberately left V1's copy alone, to die here. Asserted by inspection so a
## future panel doesn't quietly grow a third one.
func test_no_second_modifier_formatter_exists_under_ui() -> void:
	var offenders: Array[String] = []
	for path in _gd_files_under("res://ui"):
		var src := FileAccess.get_file_as_string(path)
		if src.contains("func _format_modifier("):
			offenders.append(path)
	assert_eq(offenders, [] as Array[String],
		"StatModifier.format() is the only modifier formatter; found copies in %s" % [offenders])


func _gd_files_under(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := root.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_gd_files_under(path))
		elif entry.ends_with(".gd"):
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
