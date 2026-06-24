class_name WeightContext
extends RefCounted

## Per-node bag of inputs that [WeightProfile]s read from. Built fresh on each
## modifier draw — the `already_rolled` field grows across draws within the
## same node so [CollisionProfile] (and future soft-bias profiles) can react
## to what's already on the node.
##
## Not all fields are populated by every caller; profiles read only what they
## need and treat absent fields permissively.

var archetype: StringName = &""
var position: Vector2 = Vector2.ZERO
## Set by the procgen pass once band boundaries are known. v2 step 3 ignores
## this; [RadialBandProfile] (step 6) writes & reads it.
var radial_band: StringName = &""
var theme: StringName = &""
var degree: int = 0
## Counts of archetype tag → number of neighbours within k hops. Populated by
## [NeighborhoodProfile] (not in step 3).
var neighborhood_archetypes: Dictionary = {}
## Modifiers already minted on THIS node by prior draws. CollisionProfile
## walks this to zero (stat_id, operation) duplicates.
var already_rolled: Array[StatModifier] = []
var node_index: int = -1
## Per-run state — level number, difficulty, etc. Empty in v2 step 3.
var run_state: Dictionary = {}
## Hard-exclusion tags pulled from the active [ArchetypePolicy.forbid_tags].
## Picker zeroes weight on any entry whose tags overlap this set BEFORE
## weight profiles run, so designers' explicit exclusions are uncrossable.
var forbid_tags: Array[StringName] = []
