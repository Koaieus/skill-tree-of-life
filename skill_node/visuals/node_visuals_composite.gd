@tool
extends SkillNodeVisual
## Orchestration scene composing all SkillNode-visual components (#126,
## milestone #16). Children are scene-composed in
## node_visuals_composite.tscn (not instantiated in code) — this script only
## forwards the shared radius. Z-order in the .tscn already matches the
## final draw order: disk -> weld -> wall -> rim bonuses -> halos -> rune ring.
##
## STUB coordination until #123-#125/#127-#129 land; the stake/cap-depth
## composition (#126's ring-stacking / segmented-dial / well-groove modes)
## is not implemented yet.

@onready var _children: Array[SkillNodeVisual] = [
	%InnerDisk, %WeldSymbol, %RingWall, %RimBonuses, %CoreHalos, %RuneRing,
]


func configure(new_radius: float) -> void:
	super.configure(new_radius)
	for child in _children:
		if child != null:
			child.configure(new_radius)
