@tool
extends SkillNodeVisual
## STUB (red commit): the entity look for a core slot.

@export var style: Gimbal3D.Style = Gimbal3D.Style.HOLO_GLASS
@export_range(1.0, 3.0, 0.01) var halo_scale: float = 1.8
var ring_count: int = 2
var phase: float = 0.0
var revealed: bool = true
var _rig: Gimbal3D
var _holder: Node3D
