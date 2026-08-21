class_name NodeCommand
extends Command

## A [Command] whose whole payload is one target node — `(entity_id, node_id)`.
## Five of the ten share that shape (allocate, deallocate, stake, extract,
## toggle temp upgrade), so the id plumbing lives here once. Abstract in
## practice: it has no `TAG` of its own and [CommandCodec] never builds one.

## The target node, as [member SkillNode.stable_id].
var node_id: int = 0


func _init(entity_id_: int = 0, node_id_: int = 0) -> void:
	super(entity_id_)
	node_id = node_id_


func to_dict() -> Dictionary:
	var d := super()
	d["node_id"] = node_id
	return d
