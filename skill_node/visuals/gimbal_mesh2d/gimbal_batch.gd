@tool
class_name GimbalBatch
extends Node2D
## Shape-B spike (#1075): every gimbal on a canvas drawn from ONE shared
## `MultiMesh`, referenced by two `MultiMeshInstance2D`s (back half below the
## node disks, front half above), rotated + projected in
## `gimbal_mesh2d.gdshader`. Hands out stable slot indices; the CPU writes an
## instance only when a gimbal appears, moves or changes params.

## Stable slot index for the owner, growing the buffer when needed.
func acquire(owner: Object) -> int:
	return -1


## Frees the owner's slot; the index is reused by the next `acquire`.
func release(owner: Object) -> void:
	pass


func slot_of(owner: Object) -> int:
	return -1


## Live (acquired) slot count.
func live_count() -> int:
	return 0


## Allocated GPU buffer capacity (`MultiMesh.instance_count`).
func capacity() -> int:
	return 0
