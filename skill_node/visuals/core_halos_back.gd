@tool
extends Node2D
## Back layer for CoreHalos' GIMBAL preset (#138): draws whatever portion of
## each gimbal ring has rotated Z < 0 — behind the SkillNode's own disk. See
## core_halos.tscn: this sits as a child of CoreHalos with `z_index = -1`
## (relative, so it rides the SkillNode's own graph-level z-index rather than
## fighting it), which is what actually puts it behind InnerDisk/RimRing
## (both default z_index = 0) within this node's own stacking.
##
## Owns no geometry/rotation math of its own — it borrows CoreHalos'
## _gimbal_runs()/_gimbal_batch()/_draw_batch() (untyped access; this class stays duck-typed
## against its parent rather than declaring `class_name CoreHalos`, matching
## every other leaf component in this family) so the front and back halves
## can never drift into disagreeing geometry.
##
## Must redraw every tick CoreHalos does (see CoreHalos._process /
## _redraw_all) — otherwise this half freezes mid-spin while the front half
## keeps animating.

@onready var _halos = get_parent()


func _draw() -> void:
	if not is_instance_valid(_halos) or not _halos.is_gimbal_active():
		return
	var halo_color: Color = _halos._halo_color
	var base_r: float = _halos.radius * _halos.halo_scale
	var runs: Dictionary = _halos._gimbal_runs(base_r, halo_color)
	_halos._draw_batch(self, _halos._gimbal_batch(runs["back"]))
