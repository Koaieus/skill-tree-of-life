@tool
class_name VfxEditorScene
extends RefCounted

## Is this node part of the scene the editor is currently EDITING?
##
## The distinction this answers is the one `Engine.is_editor_hint()` cannot.
## That flag is process-wide: it is true for every node in the editor process,
## including ones a live sandbox tab instantiates at runtime. A `@tool` visual
## that guards its whole `_ready` on it therefore skips spawning its body in
## the VFX playground too — which is how eight authored spells shipped
## rendering impact rings and no projectiles at all (#663, found by eye
## 2026-08-31; the tests could not see it, since GUT is headless and the flag
## is false there).
##
## The thing a visual actually wants to avoid is leaving a phantom child in a
## scene someone has open for editing. That is this check, and it is false for
## a throwaway runtime instance in a live tab.
##
## See `.claude/rules/sandbox-host.md` and docs/domain/sandbox-framework.md —
## "never guard a whole `_ready` on the editor hint".
static func is_edited(node: Node) -> bool:
	if not Engine.is_editor_hint():
		return false
	var tree := node.get_tree()
	if tree == null:
		return false
	var root := tree.edited_scene_root
	if root == null:
		return false
	return node == root or root.is_ancestor_of(node)
