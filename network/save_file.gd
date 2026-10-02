class_name SaveFile
extends RefCounted
## One in-progress run on disk: the run's setup (config + roster), the level it
## plays on, and its world as a [WorldImage]. A save is the join world written
## to disk — the image's own versioned envelope rides inside untouched, so a
## piece of state reaches the save by riding its snapshot row, never by a
## second serializer here. See docs/adr/0042-*.md.
##
## Disk layout: [constant MAGIC] | u32 [member format_version] | SHA-256 of the
## body | body, the body being [method GraphSnapshot._pack]'s size-prefixed
## ZSTD of a plain Dictionary. Everything is validated before a caller can touch
## the world — magic, version, checksum, then field types — and the body is
## decoded with `bytes_to_var` only, so a save file cannot carry code.

enum LoadResult { OK, MISSING, CORRUPT, VERSION_MISMATCH }

## Bumped whenever the body's shape, a snapshot's `_R_*` row layout or the
## [WorldImage] envelope changes; a file of another version is refused, never
## migrated. `test_save_file.gd` pins [method row_layout_hash] per version.
const FORMAT_VERSION := 1
## The single slot — mirrors [constant Settings.SAVE_PATH]'s `user://` home.
const SLOT_PATH := "user://save.bin"
const MAGIC := "STLS"
const VERSION_OFFSET := 4
const _CHECKSUM_OFFSET := 8
const _CHECKSUM_SIZE := 32
const HEADER_SIZE := _CHECKSUM_OFFSET + _CHECKSUM_SIZE

var format_version: int = FORMAT_VERSION
## The build that wrote the file — diagnostics only, never refused on: a dev
## save must survive a commit.
var build_sha: String = ""
var level_scene_path: String = ""
var config: Dictionary = {}  ## [method RunConfig.to_dict]
var roster: Dictionary = {}  ## [method ParticipantRoster.to_dict]
var world: WorldImage = WorldImage.new()
## Anything but OK leaves every other field at its default — an empty
## [member world] — so a refused load has nothing to half-apply.
var load_result: LoadResult = LoadResult.OK


## The running run: [GameSession]'s config and roster, [param graph]'s world,
## and the level scene that owns [param graph] (what a load reopens).
static func capture(graph: Graph) -> SaveFile:
	var save := SaveFile.new()
	save.build_sha = BuildInfo.short_sha
	save.level_scene_path = graph.owner.scene_file_path if graph.owner != null else ""
	save.config = GameSession.config.to_dict() if GameSession.config != null else {}
	save.roster = GameSession.roster.to_dict() if GameSession.roster != null else {}
	save.world = WorldImage.capture(graph)
	return save


## A digest of every `_R_*` row index in [GraphSnapshot] and [EntitySnapshot],
## plus the [WorldImage] envelope version — the layouts a save's bytes depend
## on beyond this file's own.
static func row_layout_hash() -> String:
	var parts := PackedStringArray(["WorldImage=%d" % WorldImage.FORMAT_VERSION])
	for script: Script in [GraphSnapshot, EntitySnapshot]:
		var consts := script.get_script_constant_map()
		# Keys are StringNames, which sort by pointer — sort them as Strings.
		var names := PackedStringArray()
		for k in consts:
			if String(k).begins_with("_R_"):
				names.append(String(k))
		names.sort()
		for n in names:
			parts.append("%s.%s=%d" % [script.resource_path.get_file(), n, consts[n]])
	return ";".join(parts).sha256_text()


func to_bytes() -> PackedByteArray:
	var body := GraphSnapshot._pack({
		"build_sha": build_sha,
		"level_scene_path": level_scene_path,
		"config": config,
		"roster": roster,
		"world": world.to_bytes(),
	})
	var header := MAGIC.to_ascii_buffer()
	header.resize(_CHECKSUM_OFFSET)
	header.encode_u32(VERSION_OFFSET, format_version)
	return header + _checksum(body) + body


## Never null: a refused file comes back with its [member load_result] set and
## nothing else filled in (a VERSION_MISMATCH also reports the file's version).
static func from_bytes(bytes: PackedByteArray) -> SaveFile:
	var save := SaveFile.new()
	save.load_result = LoadResult.CORRUPT
	if bytes.size() < HEADER_SIZE + 4 or bytes.slice(0, VERSION_OFFSET) != MAGIC.to_ascii_buffer():
		return save
	var version := bytes.decode_u32(VERSION_OFFSET)
	if version != FORMAT_VERSION:
		save.format_version = version
		save.load_result = LoadResult.VERSION_MISMATCH
		return save
	var body := bytes.slice(HEADER_SIZE)
	if bytes.slice(_CHECKSUM_OFFSET, HEADER_SIZE) != _checksum(body):
		return save
	var payload: Variant = GraphSnapshot._unpack(body)
	if not payload is Dictionary or not _has_typed(payload, {
		"build_sha": TYPE_STRING, "level_scene_path": TYPE_STRING,
		"config": TYPE_DICTIONARY, "roster": TYPE_DICTIONARY, "world": TYPE_PACKED_BYTE_ARRAY,
	}):
		return save
	var image := WorldImage.from_bytes(payload["world"])
	if image == null or image.is_empty():
		return save
	save.build_sha = payload["build_sha"]
	save.level_scene_path = payload["level_scene_path"]
	save.config = payload["config"]
	save.roster = payload["roster"]
	save.world = image
	save.load_result = LoadResult.OK
	return save


static func read_slot(path: String = SLOT_PATH) -> SaveFile:
	if not FileAccess.file_exists(path):
		var missing := SaveFile.new()
		missing.load_result = LoadResult.MISSING
		return missing
	return from_bytes(FileAccess.get_file_as_bytes(path))


## Atomic: writes `<path>.tmp`, then renames it over [param path], so a crash
## mid-write leaves the previous save whole.
func write_slot(path: String = SLOT_PATH) -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(to_bytes())
	var err := file.get_error()
	file.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return err
	return DirAccess.rename_absolute(tmp, path)


static func _checksum(body: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	return ctx.finish()


static func _has_typed(payload: Dictionary, types: Dictionary) -> bool:
	for key: String in types:
		if typeof(payload.get(key)) != types[key]:
			return false
	return true
