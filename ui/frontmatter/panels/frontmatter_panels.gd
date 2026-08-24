@tool
class_name FrontmatterPanels
extends Control

## Container for the frontmatter's non-graph screens (lobby, settings, join,
## load, exit confirm). Lives inside `frontmatter_root.tscn`'s `%PanelLayer`
## `CanvasLayer`, so it is immune to the graph camera's pan and zoom (#567).
##
## This is the **seam** between the graph layer and the panel layer: the
## navigation state machine calls `show_panel()` / `hide_all()` and knows
## nothing else about what a panel is. The panels themselves are filled in by
## #573 (C6), which re-homes them off the deleted `MenuStack`.

## Emitted when the shown panel wants the frontmatter to return to the graph.
signal panel_dismissed(id: StringName)

## Id of the panel currently shown, or `&""` when the graph layer has the stage.
var shown_panel: StringName = &"":
	get:
		return shown_panel


## Raise the panel registered under `id`, hiding any other. Unknown ids are a
## no-op so the graph layer can route a leaf whose panel has not landed yet.
func show_panel(id: StringName) -> void:
	shown_panel = id


## Return the stage to the graph layer.
func hide_all() -> void:
	shown_panel = &""


## Whether `id` names a panel this container can actually raise.
func has_panel(id: StringName) -> bool:
	return false
