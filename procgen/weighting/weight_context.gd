class_name WeightContext
extends RefCounted

## Per-node bag of inputs that [WeightProfile]s read from. Built once per
## node's modifier draw and read unchanged by every pick in it — nothing here
## reports what earlier picks rolled. v4 fuses duplicate (stat, op) picks, so
## a profile reacting to "what's on the node" must read the fused result, not
## a raw per-pick list.
##
## Not all fields are populated by every caller; profiles read only what they
## need and treat absent fields permissively.

var archetype: StringName = &""
var position: Vector2 = Vector2.ZERO
## Reserved for a future positional [WeightProfile] to write & read; no
## current profile sets it.
var radial_band: StringName = &""
var theme: StringName = &""
var degree: int = 0
## Counts of archetype tag → number of neighbours within k hops. Populated by
## [NeighborhoodProfile] (not in step 3).
var neighborhood_archetypes: Dictionary = {}
var node_index: int = -1
## Per-run state — level number, difficulty, etc. Empty in v2 step 3.
var run_state: Dictionary = {}
## Hard-exclusion tags pulled from the active [ArchetypePolicy.forbid_tags].
## Picker zeroes weight on any entry whose tags overlap this set BEFORE
## weight profiles run, so designers' explicit exclusions are uncrossable.
var forbid_tags: Array[StringName] = []
