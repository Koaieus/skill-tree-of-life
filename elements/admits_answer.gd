class_name AdmitsAnswer
extends RefCounted

## A node's second [Admits] answer ([method Admits.read]; ADR 0083 §2, ADR 0090
## §1, ADR 0091 §1, §4): given once per node per generation of [HitGather]'s
## stage one, over every arrival of that generation at the node, after their
## element riders landed and before the node's go-offs fire.

## The arrivals that break the node (indices into the arrivals the read was
## handed), each tested alone. Any breaker shatters the node once: one
## [member spend], one [member burst], and every path through it walks on.
var breakers: Array[int] = []
## Paths through the node end here (Frozen holds). Read only when no arrival
## breaks: a shatter walks every path on.
var paths_end: bool = false
## Stacks the break spends off the answering band's element, committed with the
## generation's go-off spends (summed, clamped at 0). Read only on a break.
var spend: int = 0
## HP the break bursts onto the node's holder as TRUE damage, in stage two,
## through [method DotTick.mint]. None on an unallocated node. Read only on a
## break.
var burst: float = 0.0
## The HP amount #1807 computes for the break. Declared for #1807; the gather
## does not read it.
var hp: float = 0.0
## The extra landings each breaker takes on the node, on top of its own: copies
## of its own landing, damage and aspect riders only. A break counts as 2
## channels (owner, 2026-11-11; ADR 0090 §1): #1807 owns the knob, tentative.
var extra_landings: int = 2
