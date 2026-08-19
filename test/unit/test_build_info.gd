extends GutTest

## The autoload's script type — reaching the static `parse_git_dir` through
## the `BuildInfo` singleton instance trips the analyzer's static-called-on-
## instance warning, so tests call it on the script itself.
const BuildInfoScript := preload("res://autoload/build_info.gd")

var _fixture_root: String


func before_each() -> void:
	_fixture_root = OS.get_user_data_dir().path_join("test_build_info_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_fixture_root)


func after_each() -> void:
	_rm_recursive(_fixture_root)


func _write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f.close()


func _rm_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if entry in [".", ".."]:
			pass
		elif dir.current_is_dir():
			_rm_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func test_parses_main_checkout_directory_shaped_git() -> void:
	var git_dir := _fixture_root.path_join("main/.git")
	_write(git_dir.path_join("HEAD"), "ref: refs/heads/master\n")
	_write(git_dir.path_join("refs/heads/master"), "d8e0a06d8e0a06d8e0a06d8e0a06d8e0a06d8e0a\n")

	var result := BuildInfoScript.parse_git_dir(git_dir)

	assert_true(result.is_dev)
	assert_eq(result.branch, "master")
	assert_eq(result.short_sha, "d8e0a06")
	assert_eq(result.worktree, "")


func test_parses_worktree_file_shaped_git_with_packed_refs_fallback() -> void:
	var common_git_dir := _fixture_root.path_join("main/.git")
	var per_worktree_dir := common_git_dir.path_join("worktrees/wt-test")
	_write(per_worktree_dir.path_join("HEAD"), "ref: refs/heads/feature-x\n")
	# No loose ref for feature-x — only packed-refs, exercising the fallback.
	_write(common_git_dir.path_join("packed-refs"),
			"# pack-refs with: peeled fully-peeled sorted\n" +
			"3f19ab23f19ab23f19ab23f19ab23f19ab23f19 refs/heads/feature-x\n")

	var worktree_git_file := _fixture_root.path_join("checkout/.git")
	_write(worktree_git_file, "gitdir: %s\n" % per_worktree_dir)

	var result := BuildInfoScript.parse_git_dir(worktree_git_file)

	assert_true(result.is_dev)
	assert_eq(result.branch, "feature-x")
	assert_eq(result.short_sha, "3f19ab2")
	assert_eq(result.worktree, "wt-test")


func test_missing_git_dir_yields_empty_non_dev_result() -> void:
	var result := BuildInfoScript.parse_git_dir(_fixture_root.path_join("nonexistent/.git"))

	assert_false(result.is_dev)
	assert_eq(result.branch, "")
	assert_eq(result.short_sha, "")
