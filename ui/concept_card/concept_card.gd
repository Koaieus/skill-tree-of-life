@tool
class_name ConceptCard
extends PanelContainer


static func supports(_identity: Identity) -> bool:
	return false


func bind(_identity: Identity) -> void:
	pass


func summary_text() -> String:
	return ""
