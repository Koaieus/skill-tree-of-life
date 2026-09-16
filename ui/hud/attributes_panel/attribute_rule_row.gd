@tool
class_name AttributeRuleRow
extends HBoxContainer
## One row of the Attributes Panel's hover tooltip (#791): the rule sentence
## on the left ("+1 Blade Size per 20 STR", [method StatModifier.format]) and
## this rule's OWN live contribution right-aligned on the right ("+2",
## [method StatModifier.effective_value_text]). Two Labels in an HBox so the
## contribution column lines up across rows — the old single joined Label
## could only fuse the two with an ASCII "->".
##
## Its own scene rather than a [ModSlabRow]: that slab carries exactly one
## Label (`slab_row.tscn`, #588) and adding a trailing value column would be
## scene surgery on the tooltip-fan base every SlabRow inherits.

## The target stat this row describes — what the panel filters on when it
## rebuilds an open tooltip; not rendered.
var stat_id: StringName = &""

var rule: String = "":
	set(v):
		rule = v
		if _rule_label != null:
			_rule_label.text = v

var contribution: String = "":
	set(v):
		contribution = v
		if _contribution_label != null:
			_contribution_label.text = v

@onready var _rule_label: Label = %RuleLabel
@onready var _contribution_label: Label = %ContributionLabel


func _ready() -> void:
	_rule_label.text = rule
	_contribution_label.text = contribution


## Fills the row from one [method AttributeRules.describe] entry.
func bind_entry(entry: Dictionary) -> void:
	stat_id = entry.get("stat_id", &"")
	rule = entry.get("rule", "")
	contribution = entry.get("contribution", "")
