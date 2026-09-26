extends GutTest

## End Turn is click-is-click by default: the unspent-AP warning still shows,
## but it no longer gates the press behind a confirm bubble unless the cluster
## opts back in via `confirm_unspent_ap`.

const _CLUSTER := preload("res://ui/hud/action_cluster/action_cluster.tscn")

var _cluster: ActionCluster


func before_each() -> void:
	_cluster = _CLUSTER.instantiate()
	add_child_autofree(_cluster)
	await get_tree().process_frame
	(_cluster.get_node(^"%WarningLabel") as Label).modulate.a = 1.0


func test_warning_does_not_gate_by_default() -> void:
	assert_false(_cluster.call(&"_needs_confirm"), "click is click: no confirm even with the warning up")


func test_opt_in_reinstates_the_confirm() -> void:
	_cluster.confirm_unspent_ap = true
	assert_true(_cluster.call(&"_needs_confirm"), "opted in + warning showing → confirm")
