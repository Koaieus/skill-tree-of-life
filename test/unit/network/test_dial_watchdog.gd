extends GutTest

## #752 — a dial nobody answers is reported, not left hanging.
##
## `create_client` returns OK the instant a socket exists, and ENet's own
## `connection_failed` only fires once its connect retries are exhausted (15–30s).
## On a LAN every common failure — wrong IP, host not up yet, a firewall eating
## UDP — looks exactly like "still dialling" until then, so [Wire] arms a
## watchdog on every dial and gives up out loud through the same
## [signal Wire.link_lost] a dropped link uses; the lobby already renders that.
##
## Same fixture rules as `test_wire_outlives_the_level.gd`: [Wire] is a
## process-global autoload, so every test here opens with a `stop()` and closes
## with one, and the watchdog's interval is put back to the production value so
## no later file inherits a 50ms dial budget.
##
## [b]The watchdog is driven by hand for the bookkeeping tests[/b], the way that
## file calls [method Wire._on_server_disconnected] — what is pinned is what a
## timeout DOES, with the timer itself reduced to "is it armed". The one real-
## time test at the bottom is the acceptance itself: the dial is over, one way
## or another, inside the budget.

const _NOBODY_HOME := "127.0.0.1"
## A port no server in this suite listens on.
const _DEAD_PORT := 1

var _lost: Array[String] = []


func before_each() -> void:
	Wire.stop()
	_lost = []
	Wire.link_lost.connect(_on_lost)


func after_each() -> void:
	Wire.link_lost.disconnect(_on_lost)
	Wire.stop()
	Wire.dial_timeout_sec = Wire.DIAL_TIMEOUT_SEC


func _on_lost(reason: String) -> void:
	_lost.append(reason)


func test_a_dial_arms_the_watchdog() -> void:
	assert_true(Wire._dial_watchdog.is_stopped(), "idle before any dial")
	Wire.start_client(_NOBODY_HOME, _DEAD_PORT)
	assert_false(Wire._dial_watchdog.is_stopped(), "armed by the dial")
	assert_almost_eq(Wire._dial_watchdog.wait_time, Wire.DIAL_TIMEOUT_SEC, 0.001)


func test_hanging_up_disarms_it() -> void:
	Wire.start_client(_NOBODY_HOME, _DEAD_PORT)
	Wire.stop()
	assert_true(Wire._dial_watchdog.is_stopped(),
			"a dial the player backed out of must not report a loss later")


func test_an_unanswered_dial_is_given_up_with_the_endpoint_named() -> void:
	Wire.start_client(_NOBODY_HOME, _DEAD_PORT)

	Wire._on_dial_watchdog_timeout()

	assert_eq(_lost, ["no answer from 127.0.0.1:1"],
			"the reason names what was dialled, so a typo is visible in the message")
	assert_false(Wire.is_open(), "the dead dial is torn down, not left polling")
	assert_eq(Wire.role, NetworkTransport.Role.OFFLINE)
	assert_string_contains(Wire.last_status, "no answer from 127.0.0.1:1",
			"and a lobby that mounts late still finds the account in last_status")


func test_the_timeout_is_a_no_op_once_the_server_answered() -> void:
	Wire.start_client(_NOBODY_HOME, _DEAD_PORT)
	# The server's arrival, as ENet reports it client-side.
	Wire._on_peer_connected(NetworkTransport.HOST_PEER_ID)

	Wire._on_dial_watchdog_timeout()

	assert_eq(_lost, [], "a link that is up is not lost by a stale timer")
	assert_true(Wire.is_linked())


func test_the_timeout_is_a_no_op_with_no_dial_at_all() -> void:
	Wire._on_dial_watchdog_timeout()
	assert_eq(_lost, [])

	Wire.start_host(0)
	Wire._on_dial_watchdog_timeout()
	assert_eq(_lost, [], "a host is not dialling anybody")
	assert_true(Wire.is_open())


func test_a_redial_rearms_for_the_new_endpoint() -> void:
	Wire.start_client("10.0.0.4", 7777)
	Wire.start_client(_NOBODY_HOME, _DEAD_PORT)

	Wire._on_dial_watchdog_timeout()

	assert_eq(_lost, ["no answer from 127.0.0.1:1"], "the second dial, not the first")


## The acceptance, in real time. Whichever of the two endings the OS hands a
## dial at a closed loopback port — an ICMP refusal ENet turns into
## `connection_failed` at once, or silence the watchdog ends — the joiner is
## told within the budget and the socket is gone.
func test_a_dial_nobody_answers_is_over_within_the_budget() -> void:
	Wire.dial_timeout_sec = 0.1
	Wire.start_client(_NOBODY_HOME, _DEAD_PORT)

	await wait_for_signal(Wire.link_lost, 1.0)

	assert_eq(_lost.size(), 1, "exactly one loss reported, not one per ending")
	assert_false(Wire.is_open())
	assert_string_contains(Wire.last_status, "client: ")
	gut.p("dial ended with: %s" % Wire.last_status)
