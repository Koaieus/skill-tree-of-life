@tool
class_name SandboxTab
extends MarginContainer
## Base for one tab in the unified sandbox host (#77 phase 1).
##
## Declares the tab's execution MODE — the load-bearing live-edit vs played
## distinction from docs/domain/sandbox-framework.md:
##   • LIVE_EDIT — an @tool panel that reacts to the Inspector in-editor
##     (spell / VFX / stat-board). Embedded directly; runs live.
##   • PLAYED    — a non-@tool gameplay scene that only executes on play
##     (allocation / loot showcases). Surfaced as a launch card, NOT embedded,
##     because @tool-ing the gameplay systems to run them in-editor is the
##     explicitly-rejected branch (see the design doc).
##
## Concrete reusable subclasses configure themselves via setup():
## SandboxLiveTab, SandboxPlayedTab. The `class_name` is also the Phase-4
## auto-discovery scan target (get_global_class_list base scan) — declared now
## so that phase is a pure addition.

enum Mode { LIVE_EDIT, PLAYED }


func get_tab_title() -> String:
	return "Tab"


func get_mode() -> Mode:
	return Mode.LIVE_EDIT
