@tool
class_name GraphProcgenShape
extends Resource

## Shape module (#349). The region procgen samples inside. Save as its own
## top-level `.tres` under `procgen/modules/<preset>/` and reference it by
## path from [GraphProcgenConfig.shape] — never embed it as a SubResource
## (#349 D3).

@export var shape_mask: ShapeMask
