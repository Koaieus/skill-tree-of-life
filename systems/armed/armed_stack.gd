class_name ArmedStack
extends Node

## The seat-local armed-input stack (#1222): the active branch of a statechart,
## root first. The root ([ManageMode]) is unpoppable; every other level is an
## [ArmedMode] pushed on top. Never synced — only the Commands a level submits
## cross the wire.
##
## Every public mutation emits [signal changed] exactly once (or not at all when
## nothing moved), however many levels it pushed or popped. [method ArmedMode.on_popped]
## runs top-down, AFTER the level has left the branch.

signal changed

var _branch: Array[ArmedMode] = []


## Install [param mode] as the unpoppable root, dropping any branch silently
## (no [method ArmedMode.on_popped], no [signal changed]) — construction, not play.
func set_root(mode: ArmedMode) -> void:
	_branch = [mode]
	mode.stack = self


func root() -> ArmedMode:
	return _branch[0] if not _branch.is_empty() else null


func top() -> ArmedMode:
	return _branch.back() if not _branch.is_empty() else null


## Root first. A copy — mutate through the stack's own operations.
func branch() -> Array[ArmedMode]:
	return _branch.duplicate()


func has(mode: ArmedMode) -> bool:
	return mode in _branch


## The top-most level that is an instance of [param type] (a level class), or null.
func find(type: Variant) -> ArmedMode:
	for i in range(_branch.size() - 1, 0, -1):
		if is_instance_of(_branch[i], type):
			return _branch[i]
	return null


## Push [param mode] on top. False when the level refused ([method ArmedMode.on_pushed]).
func push(mode: ArmedMode) -> bool:
	if _branch.is_empty() or not _enter(mode):
		return false
	changed.emit()
	return true


## Pop the top level. False at the root.
func pop_top() -> bool:
	if _branch.size() <= 1:
		return false
	_pop_above(_branch.size() - 2)
	changed.emit()
	return true


## "Pop me": remove [param mode] and everything above it. False when it is
## not on the branch, or is the root.
func pop(mode: ArmedMode) -> bool:
	var i := _branch.find(mode)
	if i <= 0:
		return false
	_pop_above(i - 1)
	changed.emit()
	return true


## Pop back to [param anchor] (the root by default), then push [param mode] —
## one operation, one [signal changed]. Returns whether [param mode] landed; the
## pops stand either way.
func switch_to(mode: ArmedMode, anchor: ArmedMode = null) -> bool:
	var i := _branch.find(anchor if anchor != null else root())
	if i < 0:
		return false
	var popped := _pop_above(i)
	var pushed := _enter(mode)
	if popped or pushed:
		changed.emit()
	return pushed


func clear_to_root() -> void:
	if _pop_above(0):
		changed.emit()


func _enter(mode: ArmedMode) -> bool:
	mode.stack = self
	if not mode.on_pushed():
		return false
	_branch.append(mode)
	return true


func _pop_above(index: int) -> bool:
	var any := false
	while _branch.size() - 1 > index:
		var mode: ArmedMode = _branch.pop_back()
		mode.on_popped()
		any = true
	return any
