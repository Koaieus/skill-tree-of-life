@tool
class_name AddonVisual
extends Node2D

## The drawing half of an addon: a plain child [Node2D] of a
## [SkillNodeAddon] scene that owns the draw code and its look knobs, so an
## addon subclass exists only for behaviour. Subclasses override [method _draw],
## plus a throttled [method _process] when the look animates, sizing everything
## off [member radius]; their knobs redraw from their setters so they tune live
## in the editor.
##
## The radius arrives from the parent addon — seeded once in
## [method SkillNodeAddon._ready], then forwarded by
## [method SkillNodeAddon.configure_visual]. Keep this node's transform
## identity: it draws concentric with the carrier, as the addon root does.
## A fact beyond the radius (the carrier's owner colour, say) is read through
## [code]get_parent()[/code], never pushed in.

## The carrier radius this visual draws at.
var radius: float = 32.0:
	set(value):
		radius = value
		queue_redraw()
