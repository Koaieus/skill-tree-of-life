extends GutTest
## Every pack texture under the library folder has a user: its res:// path
## appears in at least one scene, resource, shader or script. Only those four
## file kinds count — a `.import` sidecar or a doc table would make the check
## pass vacuously. See docs/domain/abstract-textures.md.

const LIBRARY_DIR := "res://assets/textures/abstract/"
const USER_EXTENSIONS: Array[String] = [".tres", ".tscn", ".gdshader", ".gd"]


func test_every_library_texture_has_a_user() -> void:
	var textures := _files_under(LIBRARY_DIR, [".png"])
	var sources := _files_under("res://", USER_EXTENSIONS)
	var self_path: String = get_script().resource_path
	var corpus := PackedStringArray()
	for path in sources:
		if path == self_path:
			continue
		corpus.append(FileAccess.get_file_as_string(path))
	var haystack := "\n".join(corpus)
	for tex in textures:
		assert_true(haystack.contains(tex),
				"%s is in the texture library but nothing references it" % tex)


func _files_under(dir_path: String, extensions: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		out.append_array(_files_under(dir_path.path_join(sub), extensions))
	for file in dir.get_files():
		for ext in extensions:
			if file.ends_with(ext):
				out.append(dir_path.path_join(file))
				break
	return out
