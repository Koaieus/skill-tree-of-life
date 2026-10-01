class_name GateCutHighlightProvider
extends HighlightProvider

## Lights the nodes a gate flip would strand. Two sources feed it: a pending
## gate toggle's one-warning confirm, and a melee plan's armed fuses (the
## fused swing's predicted stranded union). Its input is a plain settable set.
##
## [member base] is the provider it overlays — the melee plan while a fuse
## warning is up, so the blade keeps its own roles and only the stranded nodes
## repaint. Null (the toggle confirm) paints the stranded set alone.

var stranded: Array[SkillNode] = []:
	set(v):
		if v == stranded:
			return
		stranded = v
		state_changed.emit()

var base: HighlightProvider = null:
	set(v):
		if v == base:
			return
		if base != null and base.state_changed.is_connected(state_changed.emit):
			base.state_changed.disconnect(state_changed.emit)
		base = v
		if base != null:
			base.state_changed.connect(state_changed.emit)
		state_changed.emit()


func get_node_role(node: SkillNode) -> HighlightRole:
	if node != null and stranded.has(node):
		return HighlightRole.FORFEIT
	return base.get_node_role(node) if base != null else HighlightRole.NONE


func get_node_range(node: SkillNode) -> float:
	return base.get_node_range(node) if base != null else 0.0


func get_node_range_fill(node: SkillNode) -> float:
	return base.get_node_range_fill(node) if base != null else 1.0


func get_range_visual() -> RangeVisual:
	return base.get_range_visual() if base != null else null
