@tool
class_name LinkChannel
extends Node
## One protocol riding a [NetworkLink]: the wire kinds it owns and what to do
## with each. A three-method contract, not a second dispatcher — channels differ
## in [method kinds], never in how a payload reaches them. The core owns
## everything that gates every kind (role, build stamp, the refused latch, the
## pre-world latch); a channel owns only its own kinds' send and receive.

## The core this channel rides. Set by [method NetworkLink.register], never
## exported — a channel belongs to exactly the link that composed it.
var link: NetworkLink = null

## "Drop my kinds while [member NetworkLink.defer_until_world] is set" — a
## channel whose payloads mutate a world has nothing to apply them to before one
## exists. See [method is_deferred] for a channel whose kinds split.
var deferred_until_world := false


## The wire kinds this channel owns. A kind is owned by at most one channel on a
## link.
func kinds() -> Array[String]:
	return []


## Is [param kind] dropped before a world exists? Per-kind so a channel whose
## kinds split ([CommandChannel]: a command waits, a refusal must not) can say
## which; a single-purpose channel only sets [member deferred_until_world].
func is_deferred(_kind: String) -> bool:
	return deferred_until_world


## Called once by [method NetworkLink.register] after [member link] is set —
## where a channel subscribes to the core's signals. Default: nothing.
func _on_attached() -> void:
	pass


## The core's [member NetworkLink.role] or its transport-assigned peer id
## ([method NetworkLink.local_peer_id]) changed — also called once right after
## [method _on_attached], so a role set before registration still lands.
## Default: nothing.
func _on_identity_changed() -> void:
	pass


## One payload of a kind this channel owns, already past the core's gates.
func receive(_kind: String, _payload: Dictionary) -> void:
	pass
