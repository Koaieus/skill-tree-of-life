class_name HealAura
extends CoreAura

## The healing channel for [CoreAura] (D-10): heals through combat (ignores
## the D-9 damage gate) and grants no ramp — it's applied as a flat top-up
## alongside, never through, [method SkillNode.apply_turn_regen]'s
## `node_healing` / `regen_stacks` term.


func apply(node: SkillNode, value: float) -> void:
	if node == null or value <= 0.0:
		return
	node.heal_damage(value, self)
