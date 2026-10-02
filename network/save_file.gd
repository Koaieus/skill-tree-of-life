class_name SaveFile
extends RefCounted
## Stub — implementation follows.

enum LoadResult { OK, MISSING, CORRUPT, VERSION_MISMATCH }

const FORMAT_VERSION := 1
const SLOT_PATH := "user://save.bin"
const MAGIC := "XXXX"
const VERSION_OFFSET := 0
const HEADER_SIZE := 0

var format_version: int = FORMAT_VERSION
var build_sha: String = ""
var level_scene_path: String = ""
var config: Dictionary = {}
var roster: Dictionary = {}
var world: WorldImage = WorldImage.new()
var load_result: LoadResult = LoadResult.OK


static func capture(_graph: Graph) -> SaveFile:
	return SaveFile.new()


static func row_layout_hash() -> String:
	return ""


func to_bytes() -> PackedByteArray:
	return PackedByteArray()


static func from_bytes(_bytes: PackedByteArray) -> SaveFile:
	return SaveFile.new()


static func read_slot(_path: String = SLOT_PATH) -> SaveFile:
	return SaveFile.new()


func write_slot(_path: String = SLOT_PATH) -> Error:
	return OK
