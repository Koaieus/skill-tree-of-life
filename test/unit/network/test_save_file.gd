extends GutTest

## [SaveFile] — the disk codec around a [WorldImage]. The halves are opaque to
## it (it nests the image's own envelope, never decodes a snapshot), so most
## cases need no scene: a hand-made image with non-empty halves is a world as
## far as the codec can tell.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _TEST_SLOT := "user://test_save_file.bin"

## [member SaveFile.FORMAT_VERSION] → [method SaveFile.row_layout_hash] at that
## version. Red when a `_R_*` row layout (or the WorldImage envelope) changes
## without a version bump, and when a bump lands without its pin: bump the
## version, then add the new hash here.
const _ROW_LAYOUT_PINS := {
	1: "8d2ad82f2df3252642749fab0700d38b3b7f3a4340a3344272186ebf0bc1bcb7",
	# 2: an `_R_STATUSES` entry grew `[def_idx, power]` → `[def_idx, power,
	# key, camp_id, applier_id]` (status rows keyed by group_by). The indices
	# did not move, so the hash is 1's; the bump is the entry shape.
	2: "8d2ad82f2df3252642749fab0700d38b3b7f3a4340a3344272186ebf0bc1bcb7",
	# 3: the xp stat's dict gained `banked` (lifetime XP). No row moved, so the
	# hash is 2's; the bump is the stat dict's shape.
	3: "8d2ad82f2df3252642749fab0700d38b3b7f3a4340a3344272186ebf0bc1bcb7",
	# 4: GraphSnapshot gained `_R_LAST_OWNED_VISION` (a node's remembered sight).
	4: "2f2af3cc83555396e3dd69b5864bec2d12f52dbcb125bbd81661ae3f353dbfa2",
	# 5: the board lost two stat ids (ADR 0045). No row moved, so the hash is
	# 4's; the bump is the stat set's shape.
	5: "2f2af3cc83555396e3dd69b5864bec2d12f52dbcb125bbd81661ae3f353dbfa2",
	# 6: an `_R_STATUSES` entry grew `decay_step`. No row moved, so the hash
	# is 5's; the bump is the entry shape.
	6: "2f2af3cc83555396e3dd69b5864bec2d12f52dbcb125bbd81661ae3f353dbfa2",
	# 7: EntitySnapshot gained `_R_CORE_MOVED` (the core-move exert latch).
	7: "a947145a33c12afa7ccdfedb81a1605126696059aefda1a137a470768664152a",
}


func after_each() -> void:
	for path in [_TEST_SLOT, _TEST_SLOT + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameSession.end()


func _sample() -> SaveFile:
	var save := SaveFile.new()
	save.build_sha = "abc1234"
	save.level_scene_path = "res://scenes/level.tscn"
	save.config = {"seed": 42, "participants": [{"name": "Red"}]}
	save.roster = {"participants": [{"name": "Red", "kind": 1}]}
	save.world = WorldImage.new(PackedByteArray([1, 2, 3]), PackedByteArray([4, 5, 6, 7]))
	return save


func test_round_trip_carries_every_field() -> void:
	var src := _sample()
	var got := SaveFile.from_bytes(src.to_bytes())
	assert_eq(got.load_result, SaveFile.LoadResult.OK)
	assert_eq(got.format_version, SaveFile.FORMAT_VERSION)
	assert_eq(got.build_sha, src.build_sha)
	assert_eq(got.level_scene_path, src.level_scene_path)
	assert_eq(got.config, src.config)
	assert_eq(got.roster, src.roster)
	assert_eq(got.world.entity_bytes, src.world.entity_bytes)
	assert_eq(got.world.graph_bytes, src.world.graph_bytes)


func test_flipped_body_byte_is_corrupt() -> void:
	var bytes := _sample().to_bytes()
	assert_gt(bytes.size(), SaveFile.HEADER_SIZE, "a body follows the header")
	var i := SaveFile.HEADER_SIZE + (bytes.size() - SaveFile.HEADER_SIZE) / 2
	bytes[i] = bytes[i] ^ 0xFF
	var got := SaveFile.from_bytes(bytes)
	assert_eq(got.load_result, SaveFile.LoadResult.CORRUPT)
	assert_true(got.world.is_empty(), "a corrupt load carries no world to apply")


func test_flipped_magic_and_truncation_are_corrupt() -> void:
	var bytes := _sample().to_bytes()
	var bad_magic := bytes.duplicate()
	bad_magic[0] = bad_magic[0] ^ 0xFF
	assert_eq(SaveFile.from_bytes(bad_magic).load_result, SaveFile.LoadResult.CORRUPT)
	assert_eq(SaveFile.from_bytes(bytes.slice(0, 6)).load_result, SaveFile.LoadResult.CORRUPT)
	assert_eq(SaveFile.from_bytes(bytes.slice(0, bytes.size() - 3)).load_result,
			SaveFile.LoadResult.CORRUPT)
	assert_eq(SaveFile.from_bytes(PackedByteArray()).load_result, SaveFile.LoadResult.CORRUPT)


func test_other_version_is_a_version_mismatch() -> void:
	var bytes := _sample().to_bytes()
	bytes.encode_u32(SaveFile.VERSION_OFFSET, SaveFile.FORMAT_VERSION + 1)
	var got := SaveFile.from_bytes(bytes)
	assert_eq(got.load_result, SaveFile.LoadResult.VERSION_MISMATCH)
	assert_eq(got.format_version, SaveFile.FORMAT_VERSION + 1, "the file's version, for the message")
	assert_true(got.world.is_empty())


## A v7 file differs from v8 only by rows ending earlier, which
## [GraphSnapshot] decodes with defaults — so it loads rather than refusing.
func test_the_previous_version_still_loads() -> void:
	var bytes := _sample().to_bytes()
	bytes.encode_u32(SaveFile.VERSION_OFFSET, 7)
	var got := SaveFile.from_bytes(bytes)
	assert_eq(got.load_result, SaveFile.LoadResult.OK)
	assert_eq(got.format_version, 7, "the file's own version")
	assert_false(got.world.is_empty())


func test_missing_slot_is_missing() -> void:
	var got := SaveFile.read_slot("user://no_such_save_file.bin")
	assert_eq(got.load_result, SaveFile.LoadResult.MISSING)


func test_slot_round_trip_is_atomic() -> void:
	var src := _sample()
	assert_eq(src.write_slot(_TEST_SLOT), OK)
	assert_true(FileAccess.file_exists(_TEST_SLOT))
	assert_false(FileAccess.file_exists(_TEST_SLOT + ".tmp"), "the tmp is renamed over the slot")
	src.build_sha = "def5678"
	assert_eq(src.write_slot(_TEST_SLOT), OK, "a second write replaces the slot")
	var got := SaveFile.read_slot(_TEST_SLOT)
	assert_eq(got.load_result, SaveFile.LoadResult.OK)
	assert_eq(got.build_sha, "def5678")
	assert_eq(got.world.graph_bytes, src.world.graph_bytes)


func test_row_layout_hash_is_pinned_to_format_version() -> void:
	assert_true(_ROW_LAYOUT_PINS.has(SaveFile.FORMAT_VERSION),
			"bumped FORMAT_VERSION needs its pin: %s" % SaveFile.row_layout_hash())
	assert_eq(SaveFile.row_layout_hash(), _ROW_LAYOUT_PINS.get(SaveFile.FORMAT_VERSION),
			"a _R_* row layout changed: bump SaveFile.FORMAT_VERSION and pin the new hash")


func test_capture_reads_the_session_and_the_level() -> void:
	var cfg := RunConfig.new()
	cfg.seed = 777
	GameSession.start(cfg)
	var level := Node.new()
	level.scene_file_path = "res://scenes/level.tscn"
	add_child_autofree(level)
	var graph: Graph = _GRAPH_SCENE.instantiate()
	level.add_child(graph)
	graph.owner = level
	await get_tree().process_frame
	var save := SaveFile.capture(graph)
	assert_eq(save.level_scene_path, "res://scenes/level.tscn")
	assert_eq(save.config, GameSession.config.to_dict())
	assert_eq(save.roster, GameSession.roster.to_dict())
	assert_eq(save.build_sha, BuildInfo.short_sha)
	assert_eq(save.world.graph_bytes, GraphSnapshot.encode(graph))
	assert_eq(SaveFile.from_bytes(save.to_bytes()).load_result, SaveFile.LoadResult.OK)
