@tool
class_name IdChipPanel
extends FanPanel

## Tooltip V2 (#226/#232) — the identity chip: node degree, with its OWN
## trace ("it belongs to the sprout rather than floating free" — the only
## reason it gets a full [FanUnit] pair instead of hanging directly off the
## node like the old single-card tooltip did). Two modes, one scene (#232
## spec v3, predicate flipped by #179):
##
## - normal (`node.get_node_effects().is_empty()`): degree only, no name. A
##   plain node has no [method SkillNode.get_display_name] either — that's
##   `""` until #288's name composer lands — so this mode renders NOTHING but
##   the degree line and collapses to that line's height.
## - wide (`not node.get_node_effects().is_empty()`): [member
##   SkillNode.display_name] (when authored), an effect count, then degree.
##   Effects are the honest signal for the wide layout — a name alone (#288's
##   generated names arrive later) must never trigger it.
##
## Degree itself is always graph degree; entity degree is appended — and
## labelled distinctly — only when the node is owned (#232 Decision 2):
## `deg 5` unowned, `deg 5 · yours 2` owned. `entity_degree <= graph_degree`
## by definition and is meaningless on a node the hovering entity doesn't own,
## so it is never shown there.
##
## The chip's background hugs its content structurally (#344): the Rows column
## is a [PanelContent] inside the [PanelLayout] skin, so the skin sizes itself
## to whatever rows [method bind] left visible. Safe because
## [FanAnchorDriver] re-derives the trace terminus from the panel's LIVE skin
## rect every frame (see `fan_anchor_driver.gd::_reroute`), so a resize here
## is never stale for the trace that arrives at it.

@onready var _name_label: Label = %NameLabel
@onready var _effects_label: Label = %EffectsLabel


func _ready() -> void:
	super._ready()
	# See owner_panel.gd's _ready — Label.text/visible are real serializable
	# properties, so skip writing them during an editor load; the authored
	# .tscn defaults are what's previewed while placing the panel.
	if Engine.is_editor_hint():
		return
	_name_label.visible = false
	_effects_label.visible = false


func bind(node: SkillNode, graph: Graph) -> void:
	var display_name := node.get_display_name()
	_name_label.visible = not display_name.is_empty()
	if _name_label.visible:
		_name_label.text = display_name

	var effect_count := node.get_node_effects().size()
	_effects_label.visible = effect_count > 0
	if _effects_label.visible:
		_effects_label.text = "%d effect%s" % [effect_count, "" if effect_count == 1 else "s"]

	if _header:
		_header.header = "Degree %d" % node.get_entity_degree(graph, node.owned_by)
		_header.subheader = "Graph Degree: %d" % node.get_graph_degree(graph)
