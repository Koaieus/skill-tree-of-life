class_name PayloadState
extends RefCounted

## One [PayloadExtension]'s carried state on one [CastSpell], in
## [member CastSpell.extras]. A subclass adds the typed fields; readers find it
## by id through [method CastSpell.extra].

## The extension that built this state — its [member PayloadExtension.id] is
## this state's id, and [method IncidentReducer._merge_payload_defaults] merges
## through it.
var template: PayloadExtension = null

## Set by a [method PayloadExtension.mint]: the walk ends at the payload that
## carries this state ([method PropagationConfig.mint] zeroes its
## [member CastSpell.hops_remaining]). The payload still lands.
var terminal: bool = false


func get_id() -> StringName:
	return template.id if template != null else &""
