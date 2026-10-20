@tool
@abstract
class_name PayloadExtension
extends Resource

## A template for one piece of spell-specific state a [CastSpell] carries down
## its walk, authored on [member PropagationConfig.extensions]. Each payload
## holds one [PayloadState] per extension in [member CastSpell.extras], built
## by the three constructors: the resolver's seed loop calls [method seed],
## [method PropagationConfig.mint] calls [method mint] after advancing the walk,
## and [method IncidentReducer._merge_payload_defaults] calls [method merge].
##
## A [method merge] must be order-independent (MAX/SUM) or sort its states
## first: the incident order is not a gameplay fact, and the result must be
## deterministic.

## The key readers look the state up by: [code]payload.extra(id)[/code]. Two
## extensions on one config must not share it.
@export var id: StringName = &""


## The seed payload's state, at the cast's start.
@abstract func seed(ctx: PropagationContext) -> PayloadState


## The child's state for one [param pick], from the landing payload's
## [param parent] state (null when the parent carried none). [param lctx] is
## the landing the parent just made — this wave has LANDED. [param hop_index]
## is the parent's, the same index [member PropagationConfig.hop_damage] sees.
## Set [member PayloadState.terminal] to end the walk at the child.
@abstract func mint(parent: PayloadState, pick: PropagationPick, lctx: LandingContext,
		hop_index: int) -> PayloadState


## One state from the converging incidents' [param states] (≥1, same id).
@abstract func merge(states: Array[PayloadState]) -> PayloadState
