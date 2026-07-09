@tool
class_name Keystone
extends Resource

## Named, landmark content authored onto a [SkillNode] — a [b]blueprint[/b], not
## a behaviour. It carries identity (name, prose, icon) and a payload of
## [Effect]s; allocating the carrier node grants the payload to the owner,
## deallocating revokes it.
##
## [b]The payload is plain [Effect]s.[/b] A hand-crafted stat bundle is one
## [StatEffect] in [member effects]; anything behavioural (auras, per-turn
## rules) is an [Effect] subclass alongside it. Keystone deliberately carries no
## `modifiers` array of its own — it was field-for-field [Effect]'s, and the
## duplication meant two homes for the same content (#149).
##
## Runtime wiring lives in [AllocationSystem] (`allocate` → `entity.grant_effect`,
## `deallocate` → revoke), keyed by the source node, and the grant ledger on each
## [EffectInstance] is what makes revocation exact. Procgen-side placement is
## [KeystonePlacement].
##
## [b]Shared resource.[/b] One `.tres` may sit on many nodes and many entities.
## Keep runtime state on the [EffectInstance], never here.

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
## Everything this keystone grants while its carrier node is allocated.
## [AllocationSystem] grants each against the carrier, so deallocating the node
## revokes exactly these.
@export var effects: Array[Effect] = []

@export_group("Presentation")
## Overrides the carrier's [member SkillNode.base_type_color] at stamp time, so
## a landmark reads as one on the board. Fully transparent (the default) means
## "leave the archetype colour alone".
@export var color: Color = Color(0, 0, 0, 0)
## Overrides the carrier's [member SkillNode.radius] at stamp time. `0.0` means
## "leave it alone".
@export var radius: float = 0.0
## [SkillNodeAddon] scenes minted onto the carrier at stamp time — a keystone
## that wants a visual gizmo or a node-local stat bundle brings its own.
@export var addon_scenes: Array[PackedScene] = []


## Author this keystone onto [param node] — the blueprint half (#149).
##
## [b]Presentation is baked, the payload stays live.[/b] Colour, radius and
## addons are copied onto the node and the keystone is not consulted for them
## again; [member effects] are left as a reference, read at every allocation. So
## editing a keystone `.tres` still propagates its mechanics to every node
## already carrying it, while its looks are a generation-time decision like any
## other archetype stamp.
##
## Call this [b]after[/b] the node is in the tree: [SkillNode] connects its
## addon-anchor signals in `_ready`, so an addon parented earlier would never
## hand its modifiers over. [GraphProcgen] calls it right after `add_skill_node`.
func stamp(node: SkillNode) -> void:
	if node == null:
		return
	node.keystone = self
	if color.a > 0.0:
		node.base_type_color = color
	if radius > 0.0:
		node.radius = radius
	if addon_scenes.is_empty():
		return
	if not node.is_inside_tree():
		# The anchor's child_entered_tree hookup happens in SkillNode._ready, so
		# an addon parented before then attaches visibly and stays mechanically
		# inert — no error, just a silently missing modifier. Verified.
		push_warning("Keystone '%s': stamp() called before %s entered the tree; "
			% [display_name, node.name] + "addons would be inert. Skipping them.")
		return
	var anchor := node.get_node_or_null("Visuals/AddonAnchor")
	if anchor == null:
		push_warning("Keystone '%s': no AddonAnchor on %s; addons dropped." % [display_name, node.name])
		return
	for scene in addon_scenes:
		if scene != null:
			anchor.add_child(scene.instantiate())
