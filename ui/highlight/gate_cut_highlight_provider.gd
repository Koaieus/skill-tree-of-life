class_name GateCutHighlightProvider
extends HighlightProvider

## Lights the nodes a pending gate flip would strand, while its one-warning
## confirm is armed. Its input is a plain settable set so a second source (the
## fuse scrubber) can feed it the same way.

var stranded: Array[SkillNode] = []


func get_node_role(node: SkillNode) -> HighlightRole:
	return HighlightRole.HOSTILE_TARGET if node != null and stranded.has(node) else HighlightRole.NONE
