class_name BindScope
extends RefCounted

## One `bind()`'s worth of signal connections, released as a unit.
##
## HUD clusters bind to whoever the current hero is, and hot-seat coop (#459)
## re-points them mid-run — so every binder needs to let go of the previous
## hero's stats before it takes the next one's, or player 1's pools keep
## driving player 2's gauges.
##
## Most of those connections are anonymous lambdas capturing the gauge they
## drive (`hero_sigil_card._bind_pool`, `turn_resources_panel._bind_cells`,
## ...), which rules out both obvious alternatives:
##   - there is no named method to `disconnect`, and
##   - you cannot identify the owner from the outside either — a GDScript
##     lambda's `Callable.get_object()` is the **GDScript resource**, not the
##     node that made it, so sweeping a stat's connection list for "callables
##     belonging to the HUD" finds nothing. (Verified empirically; don't
##     re-derive it.)
##
## Recording the connection at the moment it is made is therefore the only
## reliable release. This exists so there is exactly ONE such bookkeeping
## implementation rather than one per cluster.
##
## Usage: hold one per binder, `release()` at the top of `bind()`, and route
## every connection whose lifetime is the binding — not the node — through
## [method link].

var _links: Array[Array] = []


## Connect [param target] to [param sig] and remember it, so [method release]
## can undo exactly this connection later.
##
## Pass the Callable you actually want connected — `foo.unbind(1)` mints a NEW
## Callable on every call, so a later `sig.disconnect(foo.unbind(1))` would not
## match. Storing the instance that was connected is what makes those releasable.
func link(sig: Signal, target: Callable) -> void:
	sig.connect(target)
	_links.append([sig, target])


## Drop every connection made through [method link] since the last release.
##
## Tolerates an emitter that has been freed in the meantime (a hero dying
## during handover): the Signal still holds a dangling object pointer, so the
## validity check has to come before `is_connected`.
func release() -> void:
	for entry in _links:
		var sig: Signal = entry[0]
		var target: Callable = entry[1]
		if not is_instance_valid(sig.get_object()):
			continue
		if sig.is_connected(target):
			sig.disconnect(target)
	_links.clear()


## How many live connections this scope is holding. For tests and debugging.
func size() -> int:
	return _links.size()
