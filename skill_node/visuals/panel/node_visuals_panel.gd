@tool
extends Control
## Live-preview panel for the SkillNode-visuals-v2 component family (#122).
## Every slot is scene-composed in node_visuals_panel.tscn (composite +
## the 6 leaf components), so selecting a child in the scene tree dock and
## tweaking its @export vars gives instant `queue_redraw()` feedback — no
## code in this script builds or wires anything.
