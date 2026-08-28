@tool
class_name LobbyOption
extends Resource

## One NAMED choice in a lobby run-section picker (#643 decision 3, "presets
## first") — a label a player reads, plus the leaf patches picking it writes
## onto the run.
##
## [b]A named option is a BUNDLE of patches, not one.[/b] "Heavy blockers" is
## three writes (`blocker_per_small` / `_medium` / `_large`), so the plural is
## load-bearing rather than speculative: a single-patch shape would have forced
## the blocker ladder to become three separate pickers offering the player a
## combination they have no way to reason about.
##
## [b]Why this is not a module `.tres`.[/b] #642 decision 1 read "an override is
## a module resource of that module's own type", but the merge path #642 actually
## shipped is [ScenarioOverride] — a `{target, value}` scalar leaf patch, hardened
## by D15 to reject anything that is not a scalar. So an option carries leaf
## patches, which is also what keeps the 7 x 6 x 3 = 126-authored-`.tres`
## explosion #642 opens with from reappearing here one level down: XS..XXL is six
## small resources, not six copies of a whole Topology module.

## What the dropdown shows. Never parsed — the patches carry the meaning.
@export var label: String = ""

## The leaf patches picking this option contributes to [member RunConfig.overrides].
## Empty is legal and means "this option is the authored preset" — which is how
## a ladder offers a no-op entry without special-casing it in the picker.
@export var patches: Array[ScenarioOverride] = []
