extends Resource
class_name StatMetaData

## Full name of a stat
@export var name: String = 'Unnamed stat'

## Abbreviation of a stat
@export var abbreviation: String = '---'

## Description of a stat
@export_multiline var description: String = ''

## Order in panel display amongst other stats
@export_range(1, 999, 1, "or_greater") var order: int = 100

## UI display style of this stat
enum DisplayType {
	BASIC,
	BAR,
	PROGRESS_WITH_LABEL,
	INLINE
}
@export var display_type: DisplayType = DisplayType.BASIC

## Widget override per DisplayType
@export var widget_overrides: Dictionary[DisplayType, PackedScene] = {}
	
## Format for numeric value display (e.g. %d, %d/%d)
@export var value_format: String = "%s"

## Optional mid-label format for PROGRESS widgets
@export var mid_label_format: String = ""

## Tooltip text format string
@export var tooltip_format: String = "%s"

## Color tint for this stat in UI
@export var tint_color: Color = Color(1, 1, 1, 1)

## Dot-paths to value fields, e.g. ["value", "_max.value"]
@export var value_fields: Array[String] = ["value"]

func _get_widget_or_stat_ui_default(prop: StringName):
	var widget = get(prop)
	if widget:
		return widget
	return StatUIConfig.get(prop)
