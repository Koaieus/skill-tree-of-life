@tool
class_name CombatCardDefense
extends CombatReadoutCard
## Defense readout: armor, damage floor ([Mitigation]'s `min_damage_taken`),
## node health, and spike regen — four plain scene-authored [CombatValueRow]s
## (#913), each self-binding to its board stat and previewing its own
## node-local override. No subclass wiring needed.
##
## Never mode-highlighted (not tied to an AttackMode) — the shell still
## flashes it via [method flash_unmute] on any relevant stat change.
