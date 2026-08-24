@tool
class_name StandardPoolStatDef
extends PoolStatDef

## A fixed-cap pool (HP, mana, action points, deallocation points, …) — one
## whose cap moves only via the modifier pipeline and which has no behaviour of
## its own when it fills.
##
## [b]Deliberately empty.[/b] It used to carry `heal_on_max_increase` plus the
## `on_max_increased` / `grant_max_increase_delta` pair; #555 moved that policy
## up to [PoolStatDef] as the authored [enum PoolStatDef.CapRise] /
## [enum PoolStatDef.CapFall] pair, because the same question was being answered
## in three vocabularies on three classes. What is left is the concrete
## "ordinary pool" choice: [PoolStatDef] is abstract, so every pool def still
## picks a subclass, and this is the one that adds nothing.
##
## The D-21 ratchet did not disappear with the method — it is
## `on_cap_rise = FOLLOW` on `health.tres`, and the named seam D-26 asks for is
## [method PoolStat._follow_cap_delta].
