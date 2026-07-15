class_name HighlightProvider
extends RefCounted

## Base contract for anything that drives the highlight overlays — attack plans,
## core-move targeting, future hover/inspect modes. Only ONE provider is active
## at a time (see [HighlightController]); the overlays paint whatever the active
## provider describes. A provider tags nodes with a [enum HighlightRole] and
## optionally hands back a [RangeVisual] of rings + edges.
##
## [AttackPlan] extends this (its plan state IS its highlight state). Lighter
## providers (core-move) are pure view-state snapshots the controller rebuilds.

## Semantic roles for visualizing graph elements participating in the active
## provider. Overlays read these per node/edge and render accordingly — they
## don't care whether a role came from a melee right-click, a derived ranged
## firing position, or a core-move reachability sweep.
enum HighlightRole {
	NONE,
	ORIGIN,           ## Melee pivot / magic source / ranged firing position / core start.
	MEMBER,           ## Secondary participant (melee blade member).
	HOSTILE_TARGET,   ## Committed enemy target / active core-move landing.
	FRIENDLY_TARGET,  ## Committed allied target (heals / buffs).
	IN_RANGE,         ## Valid candidate the provider would accept.
	INVALID,          ## Hovered-but-rejected (range / ownership / etc.).
	REACHABLE,        ## Core-move: an owned node reachable within the MP budget.
	PATH,             ## Edge role: a reachable / on-route edge (core-move).
	PROPAGATION,      ## RESERVED: spell propagation preview (red). Not yet driven — see issue.
	ALLOCATABLE,      ## Manage mode: unowned node the player can allocate (adjacent + SP gated).
}

## Fires whenever the provider's internal state shifts (pivot picked, blade
## toggled, target set, drag preview moved, …). [HighlightController] rebinds
## this across provider swaps and re-emits as [signal HighlightController.provider_state_changed]
## so the overlays subscribe once to the controller, not to every provider.
signal state_changed


## Visualization role for [param node] under this provider's current state.
## Default NONE; concrete providers override for the nodes they care about.
func get_node_role(_node: SkillNode) -> HighlightRole:
	return HighlightRole.NONE


## Optional plain range circle radius around [param node] (e.g. ranged
## firing-position reach). Default 0 = no circle.
func get_node_range(_node: SkillNode) -> float:
	return 0.0


## Optional richer reach description — rings + edges. Returned [code]null[/code]
## (or empty) = nothing to paint. Magic plans hand back the active spell's
## range_finder visual; core-move hands back its reachable/route edges.
func get_range_visual() -> RangeVisual:
	return null
