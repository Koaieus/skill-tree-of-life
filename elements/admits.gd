@tool
class_name Admits
extends Resource

## Abstract: which landing copies a node in a band lets through. #1807 owns the
## answer; #1798 gives it its seams. A null [Admits] admits every arrival.


## The admit read (ADR 0083 §2, ADR 0087 §1): asked about each copy arriving at
## [param node], against [param before], the node's terrain before this
## generation's element riders land. True lands it; false absorbs it: the copy
## makes no entry (no damage, no aspect rider), but its element riders land all
## the same. [param arrival] carries its damage facts ([member Arrival.amount],
## its head's crit). Never asked about a head or a centre copy. Base: lands
## everything.
## [method admit] on [param world], the world the gather runs on (a cast's
## shadow included): the call [HitGather] makes. Read the node's holder through
## [code]world.combat_for(node)[/code], never [member SkillNode.owned_by]. Base:
## [method admit].
func admit_in(_world: CombatWorld, node: SkillNode, before: TerrainRead, arrival: Arrival) -> bool:
	return admit(node, before, arrival)


func admit(_node: SkillNode, _before: TerrainRead, _arrival: Arrival) -> bool:
	return true


## The second read (ADR 0083 §2, ADR 0091 §1, §4): asked once per node per
## generation, after every arrival's element riders landed and before the
## node's go-offs, against [param after] (the post-land terrain) and
## [param arrivals], every arrival of the generation at the node, each with its
## own facts ([member Arrival.amount], its head's crit). Null, or the base
## answer, breaks nothing and ends nothing.
## [method read] on [param world], as [method admit_in]: the call [HitGather]
## makes. Base: [method read].
func read_in(_world: CombatWorld, node: SkillNode, after: TerrainRead,
		arrivals: Array[Arrival]) -> AdmitsAnswer:
	return read(node, after, arrivals)


func read(_node: SkillNode, _after: TerrainRead, _arrivals: Array[Arrival]) -> AdmitsAnswer:
	return AdmitsAnswer.new()
