extends GutTest

## #554 decision 1 — the transport is where a peer id lives, and the seam is
## what hands it up. `EnetTransport` gets its ids from a real socket, so what is
## pinned headlessly here is the CONTRACT: the base class's defaults, and
## `LoopbackTransport` honouring it so a versus fixture can run in one process.

func test_the_base_seam_answers_offline() -> void:
	var t := NetworkTransport.new()
	autofree(t)
	assert_eq(t.local_peer_id(), 0,
			"offline, this machine is peer 0 — the same value a lobby-authored "
			+ "offline seat carries, so an offline run stays a couch")
	assert_false(t.is_linked())


func test_a_paired_loopback_mints_two_different_ids() -> void:
	var pair := LoopbackTransport.pair()
	var host := pair[0]
	var client := pair[1]
	assert_eq(host.local_peer_id(), NetworkTransport.HOST_PEER_ID)
	assert_true(client.local_peer_id() != host.local_peer_id(),
			"a versus fixture is exactly two peers that disagree about who they are")


func test_announce_joined_hands_up_the_other_end_s_id() -> void:
	var pair := LoopbackTransport.pair()
	var host := pair[0]
	var client := pair[1]
	var seen: Array[int] = []
	host.peer_joined.connect(func(id: int): seen.append(id))
	host.announce_joined()
	assert_eq(seen.size(), 1)
	assert_eq(seen[0], client.local_peer_id(), "the host learns WHICH peer arrived")


func test_starting_a_host_claims_the_server_id() -> void:
	var t := LoopbackTransport.new()
	autofree(t)
	assert_eq(t.local_peer_id(), 0, "not linked yet")
	t.start_host(0)
	assert_eq(t.local_peer_id(), NetworkTransport.HOST_PEER_ID)
	t.stop()
	assert_eq(t.local_peer_id(), 0, "a closed link is nobody")
