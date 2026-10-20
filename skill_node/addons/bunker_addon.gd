@tool
class_name BunkerAddon
extends SkillNodeAddon

## Casemate plating. On the defender it is a plate (its `deflection` grant —
## see [BladeObstacleField]); on the attacker's blade it is a heavy member: a
## bunker vertex weighs [member blade_mass] plain members and recoils off a
## plate with [member blade_restitution] of its approach speed. Every other
## contact stays position-based and inelastic. Design: issue #1634.

## A bunker member's mass in plain members; its `inv_mass` is divided by it.
## Tentative, easy to change.
@export_range(0.1, 10.0, 0.1, "or_greater") var blade_mass: float = 2.0
## Share of the approach speed along a plate's normal a bunker member leaves
## a plate with (0 = the inelastic default, 1 = a perfect bounce).
## Tentative, easy to change.
@export_range(0.0, 1.0, 0.05) var blade_restitution: float = 0.5


func apply_to_blade(state: BladeState, particle_idx: int) -> void:
	super.apply_to_blade(state, particle_idx)
	if blade_mass > 0.0:
		state.inv_masses[particle_idx] /= blade_mass  # the pivot's 0 stays 0
	state.vertex_restitution[particle_idx] = blade_restitution
