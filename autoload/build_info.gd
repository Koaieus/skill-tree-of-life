extends Node

## Which checkout + branch + commit this running window is. Read ONCE at
## startup via plain FileAccess (no `git` subprocess — unavailable in an
## exported build, too slow to shell out per frame).
##
## [b]Two sources, tried in that order.[/b] `res://.git` is the dev one and is
## never exported. An exported build instead carries [constant STAMP_PATH], a
## ConfigFile that `mise run build` writes from the exporting checkout's HEAD
## and the presets' `include_filter` packs — so a shipped build knows its own
## sha even though it has no repository.
##
## That second source is not cosmetic: [CommandLink] builds its #546 hello
## stamp straight off this autoload, and that gate compares shas. With no
## stamp, two DIFFERENT exported builds both announce an empty sha, compare
## equal, and go on to desync — the exact silent failure #546 exists to kill.
## Stamping at export time is what makes the gate fire between builds.
##
## [member is_dev] stays false in a stamped build: it means "running from a
## checkout", which a build is not, and nothing about having a sha changes
## that.

## Where `mise run build` writes the exporting checkout's identity. Absent in a
## checkout (it is gitignored and only generated at export time), which is why
## the git path is tried first and this is a fallback rather than a replacement.
const STAMP_PATH := "res://build_stamp.cfg"


var branch: String = ""
var short_sha: String = ""
## Worktree name, e.g. "issue-377-refactor-formulas". Empty on the main
## checkout.
var worktree: String = ""
var is_dev: bool = false


func _ready() -> void:
	_resolve(ProjectSettings.globalize_path("res://"))
	if short_sha.is_empty():
		_adopt_stamp(read_stamp(STAMP_PATH))


func _resolve(project_root: String) -> void:
	var result := parse_git_dir(project_root.path_join(".git"))
	branch = result.get("branch", "")
	short_sha = result.get("short_sha", "")
	worktree = result.get("worktree", "")
	is_dev = result.get("is_dev", false)


func _adopt_stamp(stamp: Dictionary) -> void:
	branch = stamp.get("branch", "")
	short_sha = stamp.get("short_sha", "")
	worktree = stamp.get("worktree", "")


## Pure reader for the export-time stamp — same shape as [method parse_git_dir]
## minus `is_dev`, and likewise takes its path so a test can point it at a
## fixture. A missing or unparseable file yields empty fields, which is the
## pre-stamp behaviour and the correct answer for a build that never got one.
static func read_stamp(path: String) -> Dictionary:
	var out := {"branch": "", "short_sha": "", "worktree": ""}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	out.branch = String(cfg.get_value("build", "branch", ""))
	out.short_sha = String(cfg.get_value("build", "short_sha", ""))
	out.worktree = String(cfg.get_value("build", "worktree", ""))
	return out


## Pure parsing entrypoint (also used by tests against fixture directories) —
## takes the absolute path to a `.git` entry, directory or file, and returns
## {branch, short_sha, worktree, is_dev}.
static func parse_git_dir(git_path: String) -> Dictionary:
	var out := {"branch": "", "short_sha": "", "worktree": "", "is_dev": false}

	var per_worktree_dir := ""
	var common_git_dir := ""

	if DirAccess.dir_exists_absolute(git_path):
		per_worktree_dir = git_path
		common_git_dir = git_path
	elif FileAccess.file_exists(git_path):
		var content := FileAccess.get_file_as_string(git_path).strip_edges()
		if not content.begins_with("gitdir: "):
			return out
		per_worktree_dir = content.trim_prefix("gitdir: ").strip_edges()
		# .git/worktrees/<name> -> common is the parent of "worktrees".
		common_git_dir = per_worktree_dir.get_base_dir().get_base_dir()
		out.worktree = per_worktree_dir.get_file()
	else:
		return out

	var head_path := per_worktree_dir.path_join("HEAD")
	if not FileAccess.file_exists(head_path):
		return out
	var head_content := FileAccess.get_file_as_string(head_path).strip_edges()

	if not head_content.begins_with("ref: "):
		# Detached HEAD: the content IS the sha.
		out.short_sha = head_content.substr(0, 7)
		out.is_dev = true
		return out

	var ref := head_content.trim_prefix("ref: ").strip_edges()
	out.branch = ref.get_file()

	var sha := _resolve_ref(common_git_dir, ref)
	out.short_sha = sha.substr(0, 7)
	out.is_dev = true
	return out


## Loose ref first, falling back to packed-refs (a freshly-cloned or gc'd
## repo has no loose ref for a branch).
static func _resolve_ref(common_git_dir: String, ref: String) -> String:
	var loose_path := common_git_dir.path_join(ref)
	if FileAccess.file_exists(loose_path):
		return FileAccess.get_file_as_string(loose_path).strip_edges()

	var packed_path := common_git_dir.path_join("packed-refs")
	if not FileAccess.file_exists(packed_path):
		return ""
	for line in FileAccess.get_file_as_string(packed_path).split("\n"):
		if line.ends_with(" " + ref):
			return line.split(" ")[0]
	return ""
