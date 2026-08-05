@tool
extends Control
## Live-preview panel for the SkillNode-visuals-v2 component family (#122).
## Every slot is scene-composed in node_visuals_panel.tscn (composite +
## the 6 leaf components), so selecting a child in the scene tree dock and
## tweaking its @export vars gives instant `queue_redraw()` feedback — no
## code in this script builds or wires anything.


const CarveShape = preload("res://skill_node/visuals/emblem/carve_shape.gd")

@onready var _composite := $ViewportContainer/World/CompositeSlot/Composite
## A whole `SkillNode` — an inherited scene of the real `skill_node.tscn`, so
## the Inspector you get on it is the REAL one, on the real exports
## (`base_radius`, `stake_level`, `archetype`), with the composite selectable
## underneath. No knob surface is reimplemented here.
##
## The point of it being INHERITED: overrides you make while tweaking land in
## `skill_node_lab.tscn`, so `skill_node.tscn` ships pristine. Tweak leaf
## components through this panel or the lab — never by opening and saving a
## leaf component's own scene, which is how baked `instance_shader_parameters`
## end up committed (see test_node_visuals_contract).
@onready var _lab: SkillNode = $ViewportContainer/World/LabSlot/SkillNodeLab
# The lab is authored to be tweakable, but two things are missing before that
# pays off, and both are filed rather than open questions:
# 1) opening the source scene's inspector from the sandbox tab — #249 (live-tab
#    scaffolding: scenic base + back-refs) is the vehicle.
# 2) an inspector edit reflecting in the running tab without an editor restart —
#    #139 confirmed it does NOT; #251 is the fix.
# Until those land the lab is a static single-drawn preview, so don't write
# acceptance criteria against it (see #238).


## The [SandboxLiveTab] loader hook: select a [CarveShape] `.tres` in the
## FileSystem dock and the composite slot carves it immediately. This is the
## one-click shape preview the panel was missing — until this existed the tab
## was wired to a `noop` loader, so previewing a shape meant drilling into a
## leaf [InnerDisk]'s scalar carve knobs (retired in #285), which any resync
## silently overwrote.
##
## Non-CarveShape selections are ignored rather than clearing the preview —
## clicking a `.png` in the dock shouldn't wipe the shape you're looking at.
func load_carve_shape(obj: Object) -> void:
	if obj is CarveShape:
		_composite.carve_shape = obj
		# The lab is a real SkillNode, so it resolves the shape through the
		# actual emblem pipeline rather than taking it pre-resolved — that
		# difference is worth seeing side by side. SkillNode carries an
		# [Archetype] now (#312), not a bare CarveShape, so wrap the loaded
		# shape in a throwaway one just to carry it through the pipeline.
		var arch := Archetype.new()
		arch.carve_shape = obj
		_lab.archetype = arch
