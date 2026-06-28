@tool
class_name GlowStyle
extends Resource

## Tunable profile for a SkillNode hover glow (#73). Bundled as a Resource so the
## redraw-triggering side effect lives in ONE place and the consuming node
## connects ONCE (to [signal Resource.changed]) instead of carrying a bespoke
## rebuild setter per knob. Drop a `.tres` and share it across node types for a
## consistent hover look.
##
## IMPORTANT: a custom resource does NOT auto-emit `changed` when a property is
## assigned — verified, and the engine docs say so explicitly. So every field
## below has a trivial `set(v): field = v; emit_changed()` (the canonical Godot
## pattern). That's the honest cost of this approach: N uniform one-line setters
## in the *data* object — but they're trivial and decoupled from the consumer's
## redraw logic, and the node side drops to a single `changed` connection.
##
## All radii are RELATIVE to the node boundary (`radius`) so they track node
## size: the glow fades in `inner_feather` px inside the peak, peaks
## `peak_outset` px past the boundary, and reaches 0 by `outset` px past it.
## See `.claude/rules/skill-node-visuals.md`.

## Glow tint. The alpha channel scales overall brightness.
@export var color: Color = Color.YELLOW_GREEN:
	set(value):
		color = value
		emit_changed()
## Outer reach: the glow has fully faded to 0 this many px past the boundary.
@export var outset: float = 14.0:
	set(value):
		outset = value
		emit_changed()
## Peak (brightest) position, in px past the boundary. Small positive = a halo
## hugging just outside the rim without eating into the colored archetype ring.
@export var peak_outset: float = 2.0:
	set(value):
		peak_outset = value
		emit_changed()
## How far INSIDE the peak the glow fades in (px). Larger = softer inner edge
## that bleeds further toward the node center (and starts tinting the ring).
@export var inner_feather: float = 2.0:
	set(value):
		inner_feather = value
		emit_changed()
