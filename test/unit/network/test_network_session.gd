extends GutTest
## [NetworkSession] with no link: the single-player shape (#1004). The same
## node `game_root.tscn` composes for every level, with nothing to adopt, open
## or wait for — so its predicates answer "offline", and `join_or_host`
## completes synchronously: the caller's lambda has landed its value before
## the test's next line runs, with no frame in between.


func _offline_session() -> NetworkSession:
	var session := NetworkSession.new()
	add_child_autofree(session)
	return session


func test_no_link_is_neither_client_nor_host_and_is_its_own_authority() -> void:
	var session := _offline_session()
	assert_false(session.is_client(), "no network config: not a joining client")
	assert_false(session.is_host(), "no network config: not a host either")
	assert_true(session.is_authority(),
			"an offline run decides for itself — the turn loop opens on this")


func test_join_or_host_with_no_link_completes_without_awaiting() -> void:
	var session := _offline_session()
	var landed: Array = []
	var run := func() -> void: landed.append(await session.join_or_host())
	run.call()
	assert_eq(landed, [true],
			"no link: nothing to open or wait for — true, before any frame passes")
