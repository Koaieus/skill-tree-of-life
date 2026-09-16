@tool
class_name CombatCardRanged
extends CombatReadoutCard
## Ranged readout: damage/leaf + firing range (px).
##
## Reads `ranged_damage` and `range` from the entity's StatBoard — both are
## formula-driven StatDefs, so both rows are plain scene-authored
## [CombatValueRow]s (#913; the range row's " px" suffix is authored via
## [member CombatValueRow.suffix]) and need no subclass wiring at all.
