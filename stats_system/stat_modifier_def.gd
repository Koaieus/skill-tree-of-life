@tool
class_name StatModifierDef
extends Resource

## The designer-loop atom: pick a stat (by id), pick an op, enter a value.
## Sits on a SkillNode's `modifiers: Array[StatModifierDef]`. Stat applies it
## via the pipeline below.
##
## Pipeline (see Stat.get_value):
##   SET (if present) returns immediately — highest `priority` wins,
##   ties broken by insertion order (last-in wins).
##   Otherwise:
##     result = (base + Σ ADD_BASE)
##           × (1 + Σ INCREASE / 100)
##           × Π MULTIPLY
##           + Σ ADD_BONUS
##   Then coerced to definition.value_type (INT rounds once, here).
##
## Value scales:
##   ADD_BASE / ADD_BONUS : raw amount       (value =  4   →  +4)
##   INCREASE             : percent points   (value = 20   →  +20%; 5× gives ×2)
##   MULTIPLY             : raw multiplier   (value =  1.5 →  ×1.5; 0.5 acts as ÷2)
##   SET                  : the result       (value = 13   →  =13, pipeline bypassed)

enum Operation {
	## +X to base, before multipliers. Scales with INCREASE and MULTIPLY.
	## The default — most permanent build sources (passives, allocated nodes) want this.
	ADD_BASE,
	## +X% additive percent (PoE "increased"). All INCREASE mods sum into one
	## (1 + Σ/100) multiplier — five +20% give +100% (×2), not (1.2)⁵ (≈×2.49).
	INCREASE,
	## ×X multiplicative (PoE "more"). Each MULTIPLY stacks independently with
	## every other MULTIPLY. value < 1 acts as a divide.
	MULTIPLY,
	## +X to result, after all multipliers. Use for flat sources that should
	## NOT scale with the build's % increases (loot trinkets, leech caps, etc.).
	ADD_BONUS,
	## =X override. Bypasses the pipeline entirely. Highest `priority` wins
	## among multiple SETs; ties broken by insertion order (last-in wins).
	SET,
}

@export var stat_id: StringName = &""
@export var operation: Operation = Operation.ADD_BASE
@export var value: float = 0.0
## Tie-breaker — currently only consulted for SET (the only op where
## composition order matters). Higher wins.
@export var priority: int = 0
