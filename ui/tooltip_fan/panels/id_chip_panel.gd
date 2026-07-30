@tool
class_name IdChipPanel
extends FanPanel

## Tooltip V2 (#226/#232) — the identity chip: node degree, with its OWN
## trace ("it belongs to the sprout rather than floating free" — the only
## reason it gets a full [FanUnit] pair instead of hanging directly off the
## node like the old single-card tooltip did). Two modes, one scene (#232
## spec v3 — absorbs the Keystone regression noted on #159):
##
## - normal (`node.keystone == null`): degree only, no name. A plain node has
##   no [method SkillNode.get_display_name] — that's `""` until #288's name
##   composer lands — so this mode renders NOTHING but the degree line and
##   collapses to that line's height.
## - keystone (`node.keystone != null`): the keystone's gold [member
##   Keystone.display_name], an optional description block (collapses when
##   empty, same convention as [PanelHeader]'s subheader), an effect count,
##   then degree. Parity with V1's `skill_node_tooltip.gd::_populate_keystone`
##   so #235's cutover drops nothing.
##
## Degree itself is always graph degree; entity degree is appended — and
## labelled distinctly — only when the node is owned (#232 Decision 2):
## `deg 5` unowned, `deg 5 · yours 2` owned. `entity_degree <= graph_degree`
## by definition and is meaningless on a node the hovering entity doesn't own,
## so it is never shown there.
##
## The chip's background resizes to its content every [method bind] (width
## stays fixed; height shrinks/grows with which rows are visible) — safe
## because [FanAnchorDriver] re-derives the trace terminus from the panel's
## LIVE skin rect every frame (see `fan_anchor_driver.gd::_reroute`), so a
## resize here is never stale for the trace that arrives at it.

## Matches the original stub's authored footprint (68x26) exactly — the
## variant scenes place NodeStats/Addons/Owner close enough that this is the
## whole safe envelope in the STATIC (pre-[method bind]) state
## `test_tooltip_fan_variants.gd::test_no_two_panels_overlap_in_any_variant`
## checks. Growth beyond it only ever happens at runtime, after [method bind],
## which that structural test never exercises (it never binds a node).
const _HALF_WIDTH := 34.0
const _V_PADDING := 10.0

## Keystone mode widens the chip at RUNTIME only. A keystone description is
## prose, not a label — `xp_anchor_keystone.tres`'s is 95 characters, which
## autowraps into a ~12-line noodle inside the 68px normal-mode envelope. The
## authored (pre-bind) width stays [constant _HALF_WIDTH] so the structural
## overlap test still measures the narrow chip; only a node that actually
## carries a keystone ever pays the extra width, and there are two such
## resources in the game.
const _KEYSTONE_HALF_WIDTH := 84.0

## Horizontal padding between the widened envelope and the wrapped description
## text, so autowrap has a real column to work with rather than the label's
## authored `custom_minimum_size`.
const _H_PADDING := 8.0

@onready var _holo: Control = %HoloPanel
@onready var _rows: VBoxContainer = %Rows
@onready var _name_label: Label = %NameLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _effects_label: Label = %EffectsLabel
@onready var _degree_label: Label = %DegreeLabel


func _ready() -> void:
	super._ready()
	# See owner_panel.gd's _ready — Label.text/visible are real serializable
	# properties, so skip writing them during an editor load; the authored
	# .tscn defaults are what's previewed while placing the panel.
	if Engine.is_editor_hint():
		return
	_name_label.visible = false
	_description_label.visible = false
	_effects_label.visible = false
	_degree_label.text = "deg –"


func bind(node: SkillNode, graph: Graph) -> void:
	var keystone: Keystone = node.keystone

	var display_name := node.get_display_name()
	_name_label.visible = not display_name.is_empty()
	if _name_label.visible:
		_name_label.text = display_name

	var description := keystone.description if keystone != null else ""
	_description_label.visible = not description.is_empty()
	_description_label.text = description

	var effect_count := node.get_node_effects().size() if keystone != null else 0
	_effects_label.visible = effect_count > 0
	if _effects_label.visible:
		_effects_label.text = "%d effect%s" % [effect_count, "" if effect_count == 1 else "s"]

	var graph_degree := node.get_graph_degree(graph)
	var degree_text := "deg %d" % graph_degree
	if node.is_allocated():
		var entity_degree := node.get_entity_degree(graph, node.owned_by)
		degree_text += " · yours %d" % entity_degree
	_degree_label.text = degree_text

	_resize_to_content(keystone != null)


## Height fits whichever rows [method bind] left visible — [VBoxContainer]
## skips invisible children when computing its combined minimum size (same
## mechanism [PanelHeader]'s empty-subheader collapse relies on), so this just
## reads that off and applies it to the HoloPanel background. Width is one of
## two envelopes, [param keystone_mode] picking the wide one; see
## [constant _KEYSTONE_HALF_WIDTH]. Both are centred, so neither shifts the
## panel's authored anchor position.
##
## The description label's wrap column is driven from the same half-width
## rather than left at its authored `custom_minimum_size` — otherwise widening
## the background alone would leave the prose still wrapped to the narrow
## column, which is the bug this exists to fix.
func _resize_to_content(keystone_mode: bool) -> void:
	if _rows == null or _holo == null:
		return
	var half_width: float = _KEYSTONE_HALF_WIDTH if keystone_mode else _HALF_WIDTH
	if _description_label != null:
		_description_label.custom_minimum_size.x = half_width * 2.0 - _H_PADDING * 2.0
	var content_height: float = _rows.get_combined_minimum_size().y
	var half_height: float = maxf(content_height, _degree_label.get_minimum_size().y) * 0.5 + _V_PADDING
	_holo.offset_left = -half_width
	_holo.offset_right = half_width
	_holo.offset_top = -half_height
	_holo.offset_bottom = half_height
