@tool
class_name StatDef
extends Resource

## Per-stat blueprint. Each .tres file in stats_system/list/ IS one stat's
## identity (id, display, type). The runtime instance is created from this.
## See docs/design/stat_system.md.

enum ValueType { INT, FLOAT, BOOL }
## Picks the widget the stats panel renders for this stat.
## BASIC   — single Label. Default for scalars.
## BAR     — scalar as a bar against an implicit ceiling. Reserved; not authored yet.
## PROGRESS— pool with current/max as a ProgressBar. Default for pool stats.
## INLINE  — reserved (compact one-line bar+label).
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
