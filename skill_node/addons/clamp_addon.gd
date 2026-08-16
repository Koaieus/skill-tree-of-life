@tool
class_name ClampAddon
extends SkillNodeAddon

## When the carrier is used as a joint in a phantom blade, weld it —
## the joint becomes rigid instead of free-pin. Design intent:
## docs/design/skill_node_addons.md#clamp.
##
## Phantom-brace trick: a weld at joint J between two arms is
## mathematically equivalent to a distance constraint between the two
## arm-tip particles. We just add such a constraint per neighbor pair.
## Reuses the existing PBD solver; no new constraint class needed.
##
## Crucially, this does NOT create a face: future area-damage code
## traverses `state.edges` (the explicit edge list), not `state.constraints`.
## Phantom braces stay invisible to it — matching the design doc's
## "rigidity only, no face" contract.
##
## Degree-2 (the typical hinge case) → 1 brace; over-constraining at
## higher degree is tolerable, PBD converges. Already-triangulated
## joints get redundant constraints; redundant ≈ no-op for PBD.
##
## Visual (#455): no sprite on the carrier itself — `SkillNode.has_addon`
## lets `Edge` read a carrier's Clamp state directly, so a clamped node's
## incident edges render thicker near that node instead. See
## `graph/edge.gd`'s `_clamp_code` and `graph/edge_mesh.gdshader`.


func apply_to_blade(state: BladeState, particle_idx: int) -> void:
	append_weld_braces(state, particle_idx)


## Static so ClampAddon.apply_to_blade and any other caller building the same
## brace geometry share one implementation — extracted for testability, not
## for a separate dispatcher (a temp Clamp is a real ClampAddon, #406, so it
## reaches this through apply_to_blade like any other instance).
static func append_weld_braces(state: BladeState, particle_idx: int) -> void:
	var neighbors: Array[int] = []
	for e in state.edges:
		if e.x == particle_idx:
			neighbors.append(e.y)
		elif e.y == particle_idx:
			neighbors.append(e.x)
	for i in neighbors.size():
		for j in range(i + 1, neighbors.size()):
			var a := neighbors[i]
			var b := neighbors[j]
			var rest := state.positions[a].distance_to(state.positions[b])
			state.constraints.append(BladeDistanceConstraint.new(a, b, rest))
