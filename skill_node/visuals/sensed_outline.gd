@tool
extends SkillNodeVisual
## The composite's sensed-fog representation (#141): a faint archetype-tinted
## outline drawn while the node is sensed-but-not-visible. Replaces the legacy
## BaseCircle sensed draw — the sensed look is now a real member of the
## NodeVisualsComposite family, hidden when the node is visible and shown by the
## composite's `sensed` state (which hides the shader stack in the same breath).
##
## Structurally archetype-only: this component reads ONLY `archetype_tint`
## ("what I AM"), never `entity_tint` ("this is MINE"). So a sensed node cannot
## leak its owner by construction — the info gate is enforced by which identity
## the component is *able* to draw, not by a `visible = false` on everything
## else. Non-shader (plain `_draw`), so a sensed node claims zero slots in the
## shared instance-uniform buffer (#172) exactly as a fog-hidden one does.

# Thinner than the live rim and partially transparent: "I know it's there, can't
# see detail" against the fog. Matches the retired BaseCircle sensed draw.
const OUTLINE_WIDTH: float = 1.5
# Low fixed floor: sensed nodes z-promote above the fog overlay, so this is what
# they render at regardless of local darkness. Below what a barely-visible
# (fade-zone) node renders at, so sensed → visible-but-faded doesn't jump darker.
const OUTLINE_ALPHA: float = 0.30


func _draw() -> void:
	var c := Color(archetype_tint.r, archetype_tint.g, archetype_tint.b, OUTLINE_ALPHA)
	# Straddles the boundary: inner_offset = -width/2 → centerline at radius.
	var centerline := SkillNode.ring_centerline(radius, -OUTLINE_WIDTH / 2.0, OUTLINE_WIDTH)
	draw_circle(Vector2.ZERO, centerline, c, false, OUTLINE_WIDTH, true)


## Redraw when the provided archetype tint or radius changes (base class calls
## this on identity change; the radius setter already redraws).
func _on_identity_changed() -> void:
	queue_redraw()
