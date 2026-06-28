@tool
class_name GlowStyle
extends Resource

## Tunable profile for a SkillNode hover glow (#73). Bundled as a Resource so a
## consuming node carries ONE `@export` instead of a redraw-triggering setter per
## knob: editing any field in the inspector auto-emits [signal Resource.changed],
## which the consumer rebinds to its rebuild/redraw. Drop a `.tres` and share it
## across node types for a consistent hover look. (See the DRY discussion in #73 —
## this is the idiomatic Godot answer to "N exports that all do the same thing".)
##
## NOTE: the auto-`changed` is an inspector behaviour. Mutating a field from code
## at runtime won't fire it — call [method Resource.emit_changed] at the call
## site if you animate a value live.
##
## All radii are RELATIVE to the node boundary (`radius`) so they track node
## size: the glow fades in `inner_feather` px inside the peak, peaks
## `peak_outset` px past the boundary, and reaches 0 by `outset` px past it.
## See `.claude/rules/skill-node-visuals.md`.

## Glow tint. The alpha channel scales overall brightness.
@export var color: Color = Color.YELLOW_GREEN
## Outer reach: the glow has fully faded to 0 this many px past the boundary.
@export var outset: float = 14.0
## Peak (brightest) position, in px past the boundary. Small positive = a halo
## hugging just outside the rim without eating into the colored archetype ring.
@export var peak_outset: float = 2.0
## How far INSIDE the peak the glow fades in (px). Larger = softer inner edge
## that bleeds further toward the node center (and starts tinting the ring).
@export var inner_feather: float = 2.0
