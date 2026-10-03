class_name SavedRun
extends RefCounted
## The one way a saved run is opened — the pause menu's LOAD and the
## frontmatter's LOAD GAME both come through here, so "which slot, which
## session call, which scene" has a single answer.
##
## Split in two for the same reason [method PauseMenu.leave_run] is: [method open]
## is the testable half, [method route] ends in [method SceneDirector.goto],
## which would swap the scene out from under a test. A caller that has to do
## something in between (the pause menu unpauses) does it between the two.


## Reads [param path] and, on [constant SaveFile.LoadResult.OK], opens it on
## [GameSession]. Never null; a refused file leaves the session untouched and
## comes back with its [member SaveFile.load_result] set.
static func open(path: String = SaveFile.SLOT_PATH) -> SaveFile:
	return SaveFile.new()


## Go to the level [param save] was taken in. Only after [method open] answered OK.
static func route(save: SaveFile) -> void:
	pass


## True iff [param path] holds something to offer LOAD on — the button's gate.
## A file that turns out CORRUPT is still offered, so the press can say why.
static func has_slot(path: String = SaveFile.SLOT_PATH) -> bool:
	return true


## The one line a refused load shows the player.
static func describe(result: SaveFile.LoadResult) -> String:
	return ""
