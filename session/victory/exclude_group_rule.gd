class_name ExcludeGroupRule
extends ContestantRule

## Everyone is in the contest except members of one Godot group (#517). The
## first — and, for now, only — [ContestantRule], carrying the case that used to
## be `Faction.counts_for_victory`: dormant-core blockers are inert scenery, not
## a camp that can win or lose.
##
## **The polarity is load-bearing: the group means OUT, never IN.**
## [VictorySystem] is mounted in `scenes/game_root.tscn`, so a GUT fixture or a
## sandbox tab has no GameRoot to stamp anyone. Under an "in" polarity nobody
## would ever be a contestant and every evaluation would be an instant DRAW.
## Out-of-contest is the exception, so only the exception has to author itself —
## today that is `entity/blocker/blocker_entity.tscn` alone.
##
## The group is authored in the inspector on the entity's scene, which is the
## per-entity handle the whole issue exists for: two entities of the same
## faction can differ, and a blocker taken out of the group at runtime rejoins
## the contest immediately, because membership is re-read on every evaluation.

## The group whose members are OUT of the contest. Note the literal exists twice
## with no compile-time link — here and as a `groups=` entry in
## `blocker_entity.tscn` — which is why a test pins the shipped blocker against
## this default rather than against a hand-wired one.
@export var group: StringName = &"scenery"


func includes(ent: Entity) -> bool:
	if ent == null:
		return false
	return not ent.is_in_group(group)
