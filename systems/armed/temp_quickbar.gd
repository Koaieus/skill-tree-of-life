class_name TempQuickbar
extends RefCounted

## The Z–B quickbar: the player's temp-upgrade favourites, one per arming key
## ([constant PlayerInputController.TEMP_UPGRADE_HOTKEYS] — the slot count, no
## second number). Held on [MeleeMemory], so it is seat memory: kept for the
## run, never synced, never saved here.
##
## Fills ([method autofill], [method on_aspect_gained]) only ever take OPEN
## slots — empty and not [member pinned] — in the order given, and never put a
## kind on the bar twice. [method swap] is the manual pick and pins its slot,
## so no later fill overwrites it (an emptied pinned slot stays empty too).
## Pure logic: no scene, no catalog; the controller decides what is offered.

## Emitted once per call that moved any slot or pin.
signal changed

## The scene each slot arms, or null for an empty slot.
var slots: Array[PackedScene] = []
## Per slot: set by [method swap], never cleared — fills skip a pinned slot.
var pinned: Array[bool] = []
## Whether the run-start [method autofill] has run.
var autofilled := false


func _init() -> void:
	var n := PlayerInputController.TEMP_UPGRADE_HOTKEYS.size()
	slots.resize(n)
	pinned.resize(n)


## The run-start fill: every open slot takes the next of
## [param placeable_in_order] not already on the bar.
func autofill(placeable_in_order: Array[PackedScene]) -> void:
	autofilled = true
	_fill(placeable_in_order)


## An aspect went from 0 to above 0: each of [param kinds_of_that_aspect]
## takes the next open slot until the bar is full.
func on_aspect_gained(kinds_of_that_aspect: Array[PackedScene]) -> void:
	_fill(kinds_of_that_aspect)


## The manual pick: slot [param i] holds [param scene] (null empties it) and is
## pinned. A [param scene] already in another slot trades places with what
## [param i] held, so the bar never doubles a kind.
func swap(i: int, scene: PackedScene) -> void:
	if i < 0 or i >= slots.size():
		return
	var j := slots.find(scene) if scene != null else -1
	if j != -1 and j != i:
		slots[j] = slots[i]
	slots[i] = scene
	pinned[i] = true
	changed.emit()


## Slot [param i]'s scene, or null when it is empty or out of range.
func scene_at(i: int) -> PackedScene:
	if i < 0 or i >= slots.size():
		return null
	return slots[i]


func _fill(order: Array[PackedScene]) -> void:
	var moved := false
	var i := 0
	for scene in order:
		if scene == null or slots.has(scene):
			continue
		while i < slots.size() and (slots[i] != null or pinned[i]):
			i += 1
		if i >= slots.size():
			break
		slots[i] = scene
		moved = true
	if moved:
		changed.emit()
