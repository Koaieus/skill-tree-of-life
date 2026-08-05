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
## The chip's background hugs its content structurally (#344): the Rows column
## is a [PanelContent] inside the [PanelLayout] skin, so the skin sizes itself
## to whatever rows [method bind] left visible (width included — the degree
## line's own text width, or the keystone's widened description column, drives
## it; there is no fixed normal-mode envelope anymore). Safe because
## [FanAnchorDriver] re-derives the trace terminus from the panel's LIVE skin
## rect every frame (see `fan_anchor_driver.gd::_reroute`), so a resize here
## is never stale for the trace that arrives at it.

## Keystone mode widens the chip at RUNTIME only. A keystone description is
## prose, not a label — `xp_anchor_keystone.tres`'s is 95 characters, which
## autowraps into a ~12-line noodle inside the 68px normal-mode envelope. The
## authored (pre-bind) width stays the narrow chip (68px, the scene's
## [PanelLayout] `min_size`) so the structural overlap test still measures the
## narrow chip; only a node that actually carries a keystone ever pays the
## extra width, and there are two such resources in the game.
const _KEYSTONE_HALF_WIDTH := 84.0

## Horizontal padding between the widened envelope and the wrapped description
## text — must match the [PanelContent] padding X so the wrap column equals the
## skin's inner width exactly and the content hugs the authored keystone
## envelope rather than one text-pixel narrower.
const _H_PADDING := 6.0

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
	if keystone != null:
		_set_description_wrap_column()

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


## The keystone description's wrap column, driven from the same widened
## envelope the [PanelLayout] skin hugs — the prose must wrap to the WIDE
## column or the chip would widen to the full unwrapped text width. In normal
## (non-keystone) mode the description is invisible and contributes nothing to
## the layout; the chip then hugs the degree line alone.
func _set_description_wrap_column() -> void:
	if _description_label == null:
		return
	_description_label.custom_minimum_size.x = _KEYSTONE_HALF_WIDTH * 2.0 - _H_PADDING * 2.0
