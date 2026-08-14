@tool
class_name SandboxTab
extends MarginContainer
## Base for one tab in the unified sandbox host (#77 phase 1).
##
## Declares the tab's execution MODE — the load-bearing live vs played
## distinction from docs/domain/sandbox-framework.md is **auto-tick = played;
## explicit-step = live**, not @tool-ness (every shipped tab is @tool since
## #260):
##   • LIVE_EDIT — embedded directly, runs in-editor. Either reacts to the
##     Inspector (spell / VFX / stat-board) or hosts a gameplay world driven
##     by explicit button-triggered beats (allocation / loot) — it never
##     auto-runs its own scenario.
##   • PLAYED    — surfaced as a launch card, NOT embedded; auto-drives its
##     scenario once launched. No shipped tab uses this mode since #260 — kept
##     for a future surface that genuinely needs continuous auto-tick loops.
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
