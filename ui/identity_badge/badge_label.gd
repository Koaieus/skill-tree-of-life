class_name BadgeLabel
extends RichTextLabel

@export_multiline var badge_text: String = ""


func plain_text() -> String:
	return ""


func _make_custom_tooltip(_for_text: String) -> Object:
	return null
