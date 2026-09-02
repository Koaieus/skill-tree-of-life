extends GutTest

## #716 item 1: refusing a PEER is not refusing the socket.
##
## [b]Why this needs a file of its own beside `test_link_build_check.gd`.[/b]
## That one pins the #546 gate, which is a property of a PAIR — one host, one
## client, and "the refusing side hangs up" is the whole story. The defect #716
## is about only exists with SEVERAL clients: `_refuse` called
## [method NetworkTransport.stop], so the first joiner on a stale commit took the
## listener down for every player already seated. Nothing with two ends can state
## that, so the fixture here is one host facing two clients
## ([method LoopbackTransport.attach]).
##
## The gate also MOVED: it used to ride the host's hello, which a lobby cannot
## send because it has no world. A client now announces its own stamp the instant
## its dial completes, and the host clears or refuses that peer before offering
## it anything — which is what makes acceptance 2 ("a refused peer never appears
## in anyone's roster") a property of the wiring.

## The ids the two loopback clients answer to. [method LoopbackTransport.pair]
## mints the first; the second is minted here, and only has to DIFFER.
const _CLIENT_A := 2
const _CLIENT_B := 3

var _host_transport: LoopbackTransport
var _a_transport: LoopbackTransport
var _b_transport: LoopbackTransport

var _host: CommandLink
var _a: CommandLink
var _b: CommandLink

## Counted into arrays rather than into ints: a lambda captures an outer local BY
## VALUE, so a `var n := 0` incremented inside a handler never moves and the test
## fails reading exactly like "the signal never fired".
var _cleared: Array[int] = []
var _refused: Array[String] = []
var _a_refusals: Array[String] = []
var _b_refusals: Array[String] = []
var _b_lost: Array[String] = []


func before_each() -> void:
	var pair := LoopbackTransport.pair()
	_host_transport = pair[0]
	_a_transport = pair[1]
	_b_transport = LoopbackTransport.attach(_host_transport, _CLIENT_B)
	for t in [_host_transport, _a_transport, _b_transport]:
		add_child_autofree(t)

	_cleared = []
	_refused = []
	_a_refusals = []
	_b_refusals = []
	_b_lost = []

	_host = _link(_host_transport, CommandLink.Mode.BROADCAST)
	_a = _link(_a_transport, CommandLink.Mode.MIRROR)
	_b = _link(_b_transport, CommandLink.Mode.MIRROR)

	_host.peer_cleared.connect(func(id: int) -> void: _cleared.append(id))
	_host.peer_refused.connect(
			func(id: int, reason: String) -> void: _refused.append("%d:%s" % [id, reason]))
	_a.link_refused.connect(func(r: String) -> void: _a_refusals.append(r))
	_b.link_refused.connect(func(r: String) -> void: _b_refusals.append(r))
	_b_transport.link_lost.connect(func(r: String) -> void: _b_lost.append(r))


## No [CommandApplier] and no [Graph] — every assertion here is about the
## handshake, same as `test_link_build_check.gd`.
func _link(transport: NetworkTransport, mode: CommandLink.Mode) -> CommandLink:
	var link := CommandLink.new()
	link.transport = transport
	link.mode = mode
	add_child_autofree(link)
	return link


func _stamp(sha: String) -> Dictionary:
	return {
		CommandLink.BUILD_SHA: sha,
		CommandLink.BUILD_BRANCH: "master",
		CommandLink.BUILD_WORKTREE: "",
	}


## Everybody on the same commit, unless a test says otherwise.
func _agree() -> void:
	for link in [_host, _a, _b]:
		link.build_stamp = _stamp("4174f36")


# --- acceptance 1: one peer is refused, everybody else is untouched -----------

func test_a_mismatched_joiner_is_dropped_alone_and_the_other_client_survives() -> void:
	_agree()
	_b.build_stamp = _stamp("54cfcd7")

	_a_transport.announce_joined()
	_b_transport.announce_joined()

	assert_eq(_cleared, [_CLIENT_A], "only the matching joiner cleared the gate")
	assert_eq(_refused, ["%d:build mismatch" % _CLIENT_B], "and only the other one was refused")

	# The refused end knows why, and knows it is offline.
	assert_eq(_b_refusals, ["refused by peer — build mismatch"],
			"the reason travels, so a lobby has something to put on screen")
	assert_eq(_b_lost, ["dropped by host"], "and the link went away without B asking")
	assert_eq(_b_transport.role, NetworkTransport.Role.OFFLINE)
	assert_false(_b_transport.is_linked())

	# …and nothing happened to anybody else. This is the defect, stated.
	assert_true(_a_transport.is_linked(), "the innocent client is still on the link")
	assert_true(_host_transport.is_linked(), "and the host is still listening")
	assert_eq(_a_refusals, [], "which it was never told about")


## The same claim at the level that actually matters: a message the host sends
## AFTER the refusal reaches the surviving client and not the refused one. A
## `stop()` on the host would have made this arrive nowhere.
func test_the_host_still_broadcasts_to_the_client_it_kept() -> void:
	_agree()
	_b.build_stamp = _stamp("54cfcd7")
	_a_transport.announce_joined()
	_b_transport.announce_joined()

	var to_a: Array[Dictionary] = []
	var to_b: Array[Dictionary] = []
	_a_transport.message_received.connect(func(p: Dictionary) -> void: to_a.append(p))
	_b_transport.message_received.connect(func(p: Dictionary) -> void: to_b.append(p))

	_host.send_lobby_roster(ParticipantRoster.of([]))

	assert_eq(to_a.size(), 1, "the roster reached the client that cleared")
	assert_eq(String(to_a[0].get(CommandLink.KEY_KIND)), CommandLink.KIND_LOBBY)
	assert_eq(to_b, [], "and nothing reached the peer that was hung up on")


## The host must not latch either. A latch would make it deaf to the very client
## the operator is about to fix and relaunch — which is the workflow the whole
## build gate exists to serve.
func test_a_refusal_leaves_the_host_able_to_clear_the_next_joiner() -> void:
	_agree()
	_b.build_stamp = _stamp("54cfcd7")
	_b_transport.announce_joined()
	assert_eq(_cleared, [], "sanity: the mismatched peer cleared nothing")

	_a_transport.announce_joined()

	assert_eq(_cleared, [_CLIENT_A], "a later, matching joiner is still heard")


# --- the gate itself, on the new upward leg ----------------------------------

func test_a_matching_announce_clears_the_peer_and_refuses_nobody() -> void:
	_agree()

	_a_transport.announce_joined()

	assert_eq(_cleared, [_CLIENT_A])
	assert_eq(_refused, [])
	assert_true(_a_transport.is_linked())
	assert_eq(_a_refusals, [])


## Absent is a mismatch, not a pass — the #546 incident, arriving through the
## new leg. A peer running code from before this check announces nothing at all,
## so what the host sees is a hello with no build key.
func test_an_announce_with_no_build_stamp_is_refused() -> void:
	_agree()

	_host_transport.message_received.emit({
		CommandLink.KEY_KIND: CommandLink.KIND_HELLO,
		CommandLink.KEY_PEER: _CLIENT_B,
	})

	assert_eq(_cleared, [])
	assert_eq(_refused, ["%d:the peer sent no build stamp — it predates this check" % _CLIENT_B])


## Present-but-empty still compares equal, exactly as it does on the downward
## leg: an exported build has no `res://.git` and so no sha.
func test_two_stampless_builds_still_clear() -> void:
	_host.build_stamp = _stamp("")
	_a.build_stamp = _stamp("")

	_a_transport.announce_joined()

	assert_eq(_cleared, [_CLIENT_A])
	assert_eq(_refused, [])


## The announce carries the sender's own id, because nothing under
## [method NetworkTransport.send] carries a return address — and the host aims
## its reject at that id.
func test_the_announce_names_the_sender() -> void:
	_agree()
	var seen: Array[Dictionary] = []
	_host_transport.message_received.connect(func(p: Dictionary) -> void: seen.append(p))

	_b_transport.announce_joined()

	assert_eq(seen.size(), 1)
	assert_eq(String(seen[0].get(CommandLink.KEY_KIND)), CommandLink.KIND_HELLO)
	assert_eq(int(seen[0].get(CommandLink.KEY_PEER)), _CLIENT_B)


## [b]The announce names its sender, and the host does not take its word for
## it.[/b] `KEY_PEER` is a claim; the transport's own
## [method NetworkTransport.last_sender_id] is not. A client that announced its
## NEIGHBOUR's id would otherwise have the host disconnect an innocent peer that
## had already cleared and been seated — one buggy joiner evicting a player, by
## exactly the mechanism this issue exists to stop happening to the socket.
##
## The liar is the one refused, and the refusal says what it did.
func test_a_peer_announcing_someone_else_s_id_is_refused_itself() -> void:
	_agree()
	_a_transport.announce_joined()
	assert_eq(_cleared, [_CLIENT_A], "sanity: A is on the link and cleared")

	# B announces, correctly stamped, but claiming to be A.
	_b_transport.send({
		CommandLink.KEY_KIND: CommandLink.KIND_HELLO,
		CommandLink.KEY_BUILD: _b.build_stamp,
		CommandLink.KEY_PEER: _CLIENT_A,
	})

	assert_eq(_refused.size(), 1, "one refusal, and it is not A's")
	assert_string_contains(_refused[0], "%d:" % _CLIENT_B)
	assert_string_contains(_refused[0], "announced as peer %d" % _CLIENT_A)
	assert_eq(_cleared, [_CLIENT_A], "the claim cleared nobody a second time")

	assert_false(_b_transport.is_linked(), "the peer that lied is gone")
	assert_true(_a_transport.is_linked(), "and the peer it named is still on the link")
	assert_eq(_a_refusals, [], "and was never even told about it")


## The verified id also wins when the claim is merely ABSENT, which is what a
## peer that predates this key sends. Nothing is inferred from the payload.
func test_the_gate_keys_off_the_transport_s_id_not_the_payload_s() -> void:
	_agree()

	_b_transport.send({
		CommandLink.KEY_KIND: CommandLink.KIND_HELLO,
		CommandLink.KEY_BUILD: _b.build_stamp,
	})

	assert_eq(_cleared, [_CLIENT_B], "the host cleared whoever actually sent it")
	assert_eq(_refused, [])


## A refused CLIENT goes quiet (#716): it has already been disconnected, so
## anything still in flight must not be acted on. The HOST's behaviour on being
## told is unchanged — see `test_link_build_check.gd`.
func test_a_refused_client_latches_and_the_host_does_not() -> void:
	_agree()
	_b.build_stamp = _stamp("54cfcd7")

	_b_transport.announce_joined()

	assert_true(_b._refused, "the client that was hung up on is deaf now")
	assert_false(_host._refused, "the host that did the hanging up is not")
