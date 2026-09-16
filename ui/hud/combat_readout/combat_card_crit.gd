@tool
class_name CombatCardCrit
extends CombatReadoutCard
## Crit readout: chance to crit + crit damage multiplier.
##
## Never mode-highlighted (not tied to an AttackMode, same as Defense) — crit
## applies equally whether the plan is melee/ranged/magic or manage mode has
## no plan selected at all, so there's no "select Crit" input channel.
##
## Both rows are plain scene-authored [CombatValueRow]s (#913): chance reads
## `crit_chance` (a 0..1 fraction) through [member CombatValueRow.scale] to
## show a whole percent; multiplier just carries an "x" [member
## CombatValueRow.suffix]. Neither needs subclass wiring.
