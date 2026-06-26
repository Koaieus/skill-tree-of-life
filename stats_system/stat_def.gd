@tool
class_name StatDef
extends Resource

## Per-stat blueprint. Each .tres file in stats_system/defs/ IS one stat's
## identity (id, display, type). The runtime instance is created from this.
## See docs/design/stat_system.md.

enum ValueType { INT, FLOAT, BOOL }
## Picks the widget the stats panel renders for this stat.
## BASIC   — single Label. Default for scalars.
## BAR     — scalar as a bar against an implicit ceiling. Reserved; not authored yet.
## PROGRESS— pool with current/max as a ProgressBar. Default for pool stats.
## INLINE  — sub-row rendered immediately under parent_stat_id, dimmed. Use for
##            per-turn stats and other derivatives that belong visually with a parent.
## HIDDEN  — omitted from the panel entirely. Use for internal scratch stats.
enum DisplayType { BASIC, BAR, PROGRESS, INLINE, HIDDEN }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var value_type: ValueType = ValueType.INT
@export var default_value: float = 0.0
@export var display_order: int = 0
@export var display_type: DisplayType = DisplayType.BASIC
@export var tint_color: Color = Color.WHITE
## Tab the StatsPanel routes this stat into. Empty defaults to the catch-all
## tab. Convention: keep to a small fixed set so the panel stays scannable.
## Ignored for INLINE stats — those inherit their parent's tab.
@export var display_group: StringName = &""
## For INLINE display_type: the id of the stat this renders under as a sub-row.
## The panel inserts the inline row immediately after the named parent's row.
@export var parent_stat_id: StringName = &""
