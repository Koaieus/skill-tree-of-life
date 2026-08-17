extends Node

## Which checkout + branch + commit this running window is. Read ONCE at
## startup via plain FileAccess (no `git` subprocess — unavailable in an
## exported build, too slow to shell out per frame). res://.git is not
## exported, so in a shipped build every field stays empty and consumers
## hide themselves — that's correct, this is a dev-only feature.

var branch: String = ""
var short_sha: String = ""
## Worktree name, e.g. "issue-377-refactor-formulas". Empty on the main
## checkout.
var worktree: String = ""
var is_dev: bool = false


func _ready() -> void:
	_resolve(ProjectSettings.globalize_path("res://"))


func _resolve(project_root: String) -> void:
	var result := parse_git_dir(project_root.path_join(".git"))
	branch = result.get("branch", "")
	short_sha = result.get("short_sha", "")
	worktree = result.get("worktree", "")
	is_dev = result.get("is_dev", false)


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
