extends GutTest
## The core's one job: route a payload to the channel whose [method
## LinkChannel.kinds] names it, behind the gates every kind shares.


class StubChannel extends LinkChannel:
	var owned: Array[String] = []
	var seen: Array[String] = []

	func kinds() -> Array[String]:
		return owned

	func receive(kind: String, _payload: Dictionary) -> void:
		seen.append(kind)


var _link: NetworkLink
var _transport: LoopbackTransport
var _alpha: StubChannel
var _beta: StubChannel
var _log: Array[String] = []


func before_each() -> void:
	_log = []
	_transport = LoopbackTransport.pair()[0]
	add_child_autofree(_transport)
	_alpha = _channel(["alpha"])
	_beta = _channel(["beta"])
	_beta.deferred_until_world = true
	_link = NetworkLink.new()
	_link.transport = _transport
	_link.channels = [_alpha, _beta] as Array[LinkChannel]
	_link.add_child(_alpha)
	_link.add_child(_beta)
	_link.logged.connect(func(line: String) -> void: _log.append(line))
	add_child_autofree(_link)
	_link.role = NetworkConfig.Role.CLIENT


func _channel(owned: Array[String]) -> StubChannel:
	var c := StubChannel.new()
	c.owned = owned
	return c


func _deliver(kind: String) -> void:
	_transport.message_received.emit({"kind": kind})


func test_a_kind_reaches_only_the_channel_that_owns_it() -> void:
	_deliver("alpha")
	_deliver("beta")

	assert_eq(_alpha.seen, ["alpha"] as Array[String])
	assert_eq(_beta.seen, ["beta"] as Array[String])
	assert_eq(_alpha.link, _link, "the core stamps itself on every channel it composes")


func test_a_kind_nobody_owns_is_logged_as_ignored() -> void:
	_deliver("gamma")

	assert_true(_alpha.seen.is_empty() and _beta.seen.is_empty())
	assert_true(_log.any(func(l: String) -> bool: return l.contains("ignored") and l.contains("gamma")),
			"the drop is on the trace: %s" % [_log])


func test_a_refused_link_drops_every_kind() -> void:
	_transport.message_received.emit({"kind": NetworkLink.KIND_REFUSED, "summary": "build mismatch"})
	_deliver("alpha")
	_deliver("beta")

	assert_true(_alpha.seen.is_empty(), "a refused client is deaf")
	assert_true(_beta.seen.is_empty())


func test_before_a_world_only_the_deferred_channel_is_dropped() -> void:
	_link.defer_until_world = true

	_deliver("alpha")
	_deliver("beta")

	assert_eq(_alpha.seen, ["alpha"] as Array[String], "a channel that needs no world still hears")
	assert_true(_beta.seen.is_empty(), "a deferred channel's kind waits for the world")
	assert_true(_log.any(func(l: String) -> bool: return l.contains("beta") and l.contains("dropped")),
			"the drop is on the trace: %s" % [_log])
