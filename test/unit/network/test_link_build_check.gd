extends GutTest

## #546's link-time build gate. Two peers on different commits must REFUSE to
## link, and both ends must print which build the other was on.
##
## [b]Why this is worth a file of its own.[/b] The failure it prevents is the
## only one that corrupts the harness's output while looking like a clean run:
## a client that reaches the wrong host applies its commands, tallies its probe
## results, and prints a table in which every number is measured against the
## wrong process. There is no in-band signal — the banner says connected.
##
## The other half of #546 (a `--role=host` that cannot bind exits non-zero) is
## not testable here: it ends in `get_tree().quit(1)`, which would take GUT
## with it. What IS covered is the message, through
## `mp_dev_sandbox.bind_failure_lines` — extracted pure for exactly that reason.

const _SANDBOX := preload("res://scenes/dev/mp_dev_sandbox.gd")

var _host: CommandLink
var _client: CommandLink
var _host_lines: PackedStringArray
var _client_lines: PackedStringArray


func before_each() -> void:
	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])
	_host_lines = PackedStringArray()
	_client_lines = PackedStringArray()
	_host = _make_link(pair[0], CommandLink.Mode.BROADCAST, _host_lines)
	_client = _make_link(pair[1], CommandLink.Mode.MIRROR, _client_lines)


## No [CommandApplier] and no [Graph]: every assertion here is about the
## handshake, and [method CommandLink.send_hello] tolerates a null graph
## ([method WorldFingerprint.compute] folds nothing).
func _make_link(transport: NetworkTransport, mode: CommandLink.Mode,
		sink: PackedStringArray) -> CommandLink:
	var link := CommandLink.new()
	link.transport = transport
	link.mode = mode
	add_child_autofree(link)
	link.logged.connect(func(line: String) -> void: sink.append(line))
	return link


func _stamp(sha: String, branch: String = "master", worktree: String = "") -> Dictionary:
	return {
		CommandLink.BUILD_SHA: sha,
		CommandLink.BUILD_BRANCH: branch,
		CommandLink.BUILD_WORKTREE: worktree,
	}


func _joined(lines: PackedStringArray) -> String:
	return "\n".join(lines)


func test_matching_builds_link_normally() -> void:
	_host.build_stamp = _stamp("4174f36")
	_client.build_stamp = _stamp("4174f36")
	var refusals := 0
	_client.link_refused.connect(func(_r: String) -> void: refusals += 1)

	_host.send_hello()

	assert_eq(refusals, 0, "same sha must not refuse")
	assert_true(_client.transport.is_linked(), "the link must survive a matching build")
	assert_string_contains(_joined(_client_lines), "in sync at link-up")


## The [BuildInfo] autoload fills both stamps in a single process, so the
## existing hello tests (and the harness's own same-machine runs) keep working
## without staging anything.
func test_a_real_process_stamps_itself_and_agrees_with_itself() -> void:
	assert_eq(_host.build_stamp, _client.build_stamp,
			"one process's two links must announce the same build")
	assert_eq(_host.build_stamp.get(CommandLink.BUILD_SHA), BuildInfo.short_sha)


func test_mismatched_sha_refuses_and_both_ends_name_the_other_build() -> void:
	_host.build_stamp = _stamp("4174f36")
	_client.build_stamp = _stamp("54cfcd7", "master", "issue-546")

	_host.send_hello()

	var client_log := _joined(_client_lines)
	assert_string_contains(client_log, "link REFUSED")
	assert_string_contains(client_log, "4174f36 (master)")
	assert_string_contains(client_log, "54cfcd7 (master @ issue-546)")

	var host_log := _joined(_host_lines)
	assert_string_contains(host_log, "link REFUSED")
	assert_string_contains(host_log, "54cfcd7 (master @ issue-546)")
	assert_string_contains(host_log, "4174f36 (master)")


## The refusing side hangs up; the side merely TOLD stays listening. A host that
## closed its socket over one bad client would leave the operator relaunching a
## fixed client into nothing — and on a LAN it would drop every other peer too.
func test_the_refusing_peer_hangs_up_and_the_host_keeps_listening() -> void:
	_host.build_stamp = _stamp("4174f36")
	_client.build_stamp = _stamp("54cfcd7")

	_host.send_hello()

	assert_false(_client.transport.is_linked(), "the refusing peer must hang up")
	assert_true(_host.transport.is_linked(), "the host must stay reachable")


## …and staying open costs it nothing: BROADCAST never applies what it receives.
func test_a_host_told_of_a_refusal_still_applies_nothing_from_that_peer() -> void:
	var applier := CommandApplier.new()
	add_child_autofree(applier)
	_host.command_applier = applier
	_host.build_stamp = _stamp("4174f36")
	_client.build_stamp = _stamp("54cfcd7")
	_host.send_hello()
	_host_lines.clear()

	_host.transport.message_received.emit({
		CommandLink.KEY_KIND: CommandLink.KIND_COMMAND,
		CommandLink.KEY_COMMAND: {},
		CommandLink.KEY_FINGERPRINT: 0,
	})

	assert_eq(_joined(_host_lines), "", "a BROADCAST link must not mirror")


func test_refusal_emits_link_refused_on_both_ends() -> void:
	_host.build_stamp = _stamp("4174f36")
	_client.build_stamp = _stamp("54cfcd7")
	var seen: Array[String] = []
	_client.link_refused.connect(func(r: String) -> void: seen.append("client:" + r))
	_host.link_refused.connect(func(r: String) -> void: seen.append("host:" + r))

	_host.send_hello()

	# Order is not a contract — the loopback delivers the reject synchronously
	# from inside `_refuse`, so the host announces first — but both must fire.
	assert_has(seen, "client:build mismatch")
	# The REASON travels since #716: a lobby puts this string in front of a
	# human, and "refused by peer" alone says a mismatch happened without
	# saying what mismatched.
	assert_has(seen, "host:refused by peer — build mismatch")


## The incident itself: the orphan was running code from before this check, so
## its hello carries no build key at all. Absent must NOT read as agreement, or
## the fix sails past the one run it was written for.
func test_a_hello_with_no_build_stamp_is_refused() -> void:
	_client.build_stamp = _stamp("4174f36")

	# What a pre-#546 host puts on the wire, verbatim.
	_client.transport.message_received.emit({
		CommandLink.KEY_KIND: CommandLink.KIND_HELLO,
		CommandLink.KEY_FINGERPRINT: 0,
		CommandLink.KEY_SUMMARY: "0 nodes",
	})

	var client_log := _joined(_client_lines)
	assert_string_contains(client_log, "link REFUSED")
	assert_string_contains(client_log, "predates this check")
	assert_string_contains(client_log, "unknown — no build stamp")


## Present-but-empty is a match, unlike absent. Since `mise run build` writes a
## build stamp this is no longer the ordinary shape of an exported build — but
## a build produced any other way still reaches here, and an empty-vs-empty
## comparison must stay a pass rather than falling into the "predates this
## check" refusal, which would be a lie about what the peer is running.
func test_two_stampless_exported_builds_still_link() -> void:
	_host.build_stamp = _stamp("", "", "")
	_client.build_stamp = _stamp("", "", "")

	_host.send_hello()

	assert_true(_client.transport.is_linked())
	assert_false(_joined(_client_lines).contains("REFUSED"))


## The gate is one check for every kind, so a refused link goes quiet — it does
## not stay half-open, mirroring commands from a peer it just rejected.
func test_a_refused_client_applies_nothing_afterwards() -> void:
	_host.build_stamp = _stamp("4174f36")
	_client.build_stamp = _stamp("54cfcd7")
	_host.send_hello()
	_client_lines.clear()

	# Straight at the receive side: the transport is already down, so a real
	# send would be dropped by the transport rather than by the gate, and this
	# test would pass for the wrong reason.
	_client.transport.message_received.emit({
		CommandLink.KEY_KIND: CommandLink.KIND_COMMAND,
		CommandLink.KEY_COMMAND: {},
		CommandLink.KEY_FINGERPRINT: 0,
	})

	assert_eq(_joined(_client_lines), "", "a refused link must not log an apply")


## [b]The refusal must not park a client at `Mode.OFF`.[/b] That is the
## tempting one-liner and it is a trap: the `mode` setter writes
## `is_authority = value != Mode.MIRROR`, so OFF would hand a refused CLIENT
## authority — and a client with authority is the silent-divergence hole
## `mp_dev_sandbox._ready` documents at length.
func test_refusal_does_not_promote_the_client_to_authority() -> void:
	var applier := CommandApplier.new()
	add_child_autofree(applier)
	_client.command_applier = applier
	_client.mode = CommandLink.Mode.MIRROR
	_host.build_stamp = _stamp("4174f36")
	_client.build_stamp = _stamp("54cfcd7")

	_host.send_hello()

	assert_false(applier.is_authority, "a refused client must go quiet, not take over")


## The other half of #546: the operator must be told which port is taken and
## how to find what is holding it. The exit code is verified by hand; the
## message is what the owner called the deliverable.
func test_bind_failure_message_names_the_port_and_the_check() -> void:
	var text := "\n".join(_SANDBOX.bind_failure_lines(9099, ERR_CANT_CREATE))

	assert_string_contains(text, "9099")
	assert_string_contains(text, "already in use")
	assert_string_contains(text, "ps aux | grep mp_dev_sandbox")
