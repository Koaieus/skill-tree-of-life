@tool
class_name CarriedScalar
extends PayloadExtension

## The stock [PayloadExtension]: one float carried down the walk. It starts at
## [member seed_value], each mint optionally [member reseed]s it from the landed
## world and then shapes it by [member progression], and converging incidents
## fold it by [member fold]. Read it as
## [code](payload.extra(id) as CarriedScalar.State).value[/code].

## The state on each payload.
class State extends PayloadState:
	var value: float = 0.0


## The value at the seed.
@export var seed_value: float = 0.0

## How the value evolves per hop, applied as
## [code]apply(value, seed_value, hop_index)[/code]. Null = carried verbatim.
@export var progression: HopDamageProgression = null

## How converging incidents fold their values: MAX or SUM (MIN and FIRST
## also work; FIRST depends on incident order).
@export var fold: IncidentReducer.StackFold = IncidentReducer.StackFold.MAX

## Optional: replaces the value from the landed world before [member progression].
@export var reseed: ScalarReseed = null

## Optional: a concept id whose cast load ([member PropagationContext.load])
## seeds the value instead of [member seed_value] — a status rider reading this
## scalar ([member ApplyStatusEffect.power_from]) then lands exactly the load at
## the seed. Empty = [member seed_value].
@export var seed_from_load: StringName = &""

## A minted value below this marks the child terminal — it still lands, the
## walk ends there. [code]-INF[/code] = off.
@export var min_value: float = -INF


func seed(_ctx: PropagationContext) -> PayloadState:
	return _state(seed_value)


func mint(parent: PayloadState, _pick: PropagationPick, lctx: LandingContext,
		hop_index: int) -> PayloadState:
	var value := (parent as State).value if parent is State else seed_value
	if reseed != null:
		value = reseed.reseed(value, lctx, self)
	if progression != null:
		value = progression.apply(value, seed_value, hop_index)
	var out := _state(value)
	out.terminal = value < min_value
	return out


func merge(states: Array[PayloadState]) -> PayloadState:
	var out: float = (states[0] as State).value
	if fold != IncidentReducer.StackFold.FIRST:
		for i in range(1, states.size()):
			var v: float = (states[i] as State).value
			match fold:
				IncidentReducer.StackFold.SUM:
					out += v
				IncidentReducer.StackFold.MIN:
					out = minf(out, v)
				_:
					out = maxf(out, v)
	return _state(out)


func _state(value: float) -> State:
	var s := State.new()
	s.template = self
	s.value = value
	return s
