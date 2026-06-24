@tool
class_name NodeTypeDef
extends Resource

## Procgen base type. Drives both clustering (nodes of the same type cluster
## together via [member GraphProcgenConfig.cluster_count] seeds) and modifier
## flavour (each type points at its own [ModifierPool]).
##
## Content-coherence note: cluster geometry comes from the type assignment,
## but content coherence rides on the modifier pool — give a type a pool
## skewed toward a specific stat family and that family will naturally
## concentrate in that type's clusters. To bias *within* a type (rare-stat
## sub-clusters), use multiple types with overlapping colour but distinct
## pools — that's the lever before we add an explicit content-cluster pass.

@export var id: StringName = &""
## Visual tint applied to unallocated nodes of this type. Owned nodes still
## show the owning entity's colour.
@export var color: Color = Color.DIM_GRAY
## Relative likelihood this type wins a cluster seed. Sums normalised at use.
@export var weight: float = 1.0
@export var modifier_pool: ModifierPool
## Inclusive budget range rolled per node before draws begin.
@export var budget_min: int = 2
@export var budget_max: int = 5
