@tool
class_name FrontmatterPanels
extends Control

## Container for the frontmatter's non-graph screens (lobby, settings, join,
## load, exit confirm). Lives inside `frontmatter_root.tscn`'s `%PanelLayer`
## `CanvasLayer`, so it is immune to the graph camera's pan and zoom (#567).
##
## This is the **seam** between the graph layer and the panel layer: the
## navigation state machine calls `show_panel()` / `hide_all()` and knows
## nothing else about what a panel is.
##
## [b]Registration is by existing, not by table.[/b] Every [FrontmatterPanel]
## child is registered under its own [member FrontmatterPanel.panel_id] at
## `_ready`, so adding a panel means instancing its scene here and nothing else
## — there is no list to keep in sync, and no id spelled by hand: the panels
## carry `MenuGraph.PANEL_*` values, set in the inspector on each inherited
## scene. A panel whose id is empty, or which duplicates one already claimed, is
## a programming error and asserts.
##
## [b]Exactly one panel is up at a time, or none.[/b] There is no stack —
## [MenuStack]'s breadcrumb-of-shrinking-panels is what #567 replaced with the
## graph itself, and re-growing one here would resurrect it. "Back" is the
## graph's business: a panel emits [signal FrontmatterPanel.dismissed], this
## re-emits [signal panel_dismissed], and the navigation state machine decides
## where that lands.

## Emitted when the shown panel wants the frontmatter to return to the graph.
signal panel_dismissed(id: StringName)

## Emitted when the exit-confirm panel is answered "yes". Relayed rather than
## acted on for the same reason `meta_root.gd` relays `MainMenuScreen`'s
## `quit_pressed`: a [method SceneTree.quit] down here would end a test run the
## moment the button was pressed. The shell connects it; see [ExitConfirmPanel].
signal quit_requested

## Id of the panel currently shown, or `&""` when the graph layer has the stage.
var shown_panel: StringName = &"":
	get:
		return shown_panel

var _panels: Dictionary = {}


func _ready() -> void:
	_register_panels()
	hide_all()


## Raise the panel registered under `id`, hiding any other. Unknown ids are a
## no-op so the graph layer can route a leaf whose panel has not landed yet.
##
## [member shown_panel] records what the graph ASKED for, registered or not —
## `test/unit/ui/test_frontmatter_layout.gd` pins that against a container with
## no panels in it at all, which is what makes an unlanded leaf a no-op rather
## than a crash. Whether a body actually exists is [method has_panel]'s
## question, and it is the one that decides whether this layer takes the stage.
func show_panel(id: StringName) -> void:
	shown_panel = id
	for panel_id in _panels:
		(_panels[panel_id] as FrontmatterPanel).visible = panel_id == id
	visible = has_panel(id)


## Return the stage to the graph layer.
func hide_all() -> void:
	shown_panel = &""
	for panel_id in _panels:
		(_panels[panel_id] as FrontmatterPanel).visible = false
	visible = false


## Whether `id` names a panel this container can actually raise.
func has_panel(id: StringName) -> bool:
	return _panels.has(id)


## The panel registered under `id`, or null. For tests and for a caller that
## needs to configure a panel before raising it — the lobby's route, say.
func get_panel(id: StringName) -> FrontmatterPanel:
	return _panels.get(id) as FrontmatterPanel


## Every registered id, in scene order.
func panel_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _panels:
		ids.append(id)
	return ids


func _register_panels() -> void:
	_panels.clear()
	for child in get_children():
		var panel := child as FrontmatterPanel
		if panel == null:
			continue
		assert(panel.panel_id != &"", "panel '%s' declares no panel_id" % panel.name)
		assert(not _panels.has(panel.panel_id),
				"two panels claim the id '%s'" % panel.panel_id)
		_panels[panel.panel_id] = panel
		panel.dismissed.connect(_on_panel_dismissed.bind(panel.panel_id))
		var exit_confirm := panel as ExitConfirmPanel
		if exit_confirm != null:
			exit_confirm.quit_requested.connect(_on_quit_requested)


func _on_panel_dismissed(id: StringName) -> void:
	if shown_panel == id:
		hide_all()
	panel_dismissed.emit(id)


func _on_quit_requested() -> void:
	quit_requested.emit()
