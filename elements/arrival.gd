class_name Arrival
extends RefCounted

## One arrival of a hit at a node in one generation of [HitGather]'s stage one:
## the head itself (generation 0), or a copy a go-off sent. What
## [method Admits.admit] is asked about.

var node: SkillNode = null
## The hit this arrival belongs to: its head ([member HitInstance.is_head]).
var head: HitInstance = null
var generation: int = 0
## A go-off's copy; false for the head itself. Only a copy can be absorbed.
var is_copy: bool = false
## A go-off's centre copy (the node it went off from): never asked, never
## lands terrain.
var centre: bool = false
## The share the copy lands at, and the go-off's own damage it carries.
var share: float = 1.0
var own_damage: float = 0.0
## Its own landing's damage, before mitigation, as the second read is handed it
## ([method Admits.read]): (stamped damage × [member share] + [member own_damage])
## × the head's crit multiplier. Set at the read.
var amount: float = 0.0
