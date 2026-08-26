class_name MenuGraph
extends RefCounted

## The frontmatter's menu tree, as menu-local data (#567 / #568).
##
## [b]This is deliberately NOT a [Graph].[/b] Owner call 2026-08-24: [i]"special
## menu local model for sure, if we did our composibility right we could steal
## just the *visuals* of the real elements involved iff not using the real ones
## directly"[/i]. Nothing here touches [Graph], [SkillNode], [Entity],
## [StatBoard], [AllocationSystem] or [TurnManager] — the menu borrows the
## node VISUALS (`skill_node/visuals/node_visuals_composite.tscn`, #569) and
## none of the machinery that normally drives them.
##
## [b]It carries topology and routing, and no look at all[/b] (#589 D5). Every
## display string, tint and radius is authored on a [MenuSlot] in
## `ui/frontmatter/layout/`, where it can be seen at full-screen scale; ask
## [method FrontmatterLayout.look_of] for one. What stays here is the half that
## is not visual and already has a net under it — `test_meta_routing_parity.gd`
## pins [member Item.panel] and [member Item.route] against the live
## `meta_root.gd`.
##
## [b]It is a tree, not a graph[/b], despite the name: every item has exactly
## one parent, the root has none, and there are no cycles. The name says what it
## LOOKS like on screen. [FrontmatterLayout] turns it into world positions once,
## at build time; navigation moves the camera, never a node (#567 constraint 1,
## "no detaching, ever").
##
## [b]The tree mirrors the routing `scenes/meta/meta_root.gd` ships today[/b],
## including #531's host/join/hot-seat intermediary. The routing is not being
## redesigned, only its presentation — [member Item.route] records, per leaf,
## the [RunConfig.Mode] and [NetworkTransport.Role] that leaf has always
## produced, and `test/unit/ui/test_meta_routing_parity.gd` pins that
## correspondence against the live `meta_root.gd` so the deletion of the old
## `MenuStack` breadcrumb (#579) could not quietly change it.


## What a leaf asks the panel layer for, once the player commits to it.
##
## Split into "which panel opens" ([member Item.panel]) and "what run shape does
## it eventually author" (this) because those differ: JOIN opens the code-entry
## panel and only reaches the lobby afterwards, while HOST opens the lobby
## directly. Both end up with a CLIENT/HOST [NetworkConfig].
##
## The address and port are NOT here. They are typed by a human into the panel,
## which is the whole reason [NetworkConfig] exists as a per-machine thing (see
## its class docs) — a route describes the shape, the panel fills in the digits.
class Route extends RefCounted:
	## The mode this ROUTE asks for — not the mode the run gets. #554 D3 derives
	## that from the roster when START is pressed
	## ([method LobbyScreen.resolve_mode]), because "more than one non-AI camp"
	## is not knowable at the moment a button is pressed. Host and Join both ask
	## for COOP_HOTSEAT here and both come out VERSUS.
	var requested_mode: RunConfig.Mode = RunConfig.Mode.SINGLE
	## Which [NetworkConfig] constructor the panel layer must call:
	## OFFLINE -> `offline()`, HOST -> `host(port)`, CLIENT -> `join(addr, port)`.
	##
	## Every route states this, including the offline ones. That is deliberate
	## and load-bearing — see [method MetaRoot._push_lobby]'s comment: a player
	## who hosted, backed out, and then started a solo run must not silently
	## open a socket.
	var network_role: NetworkTransport.Role = NetworkTransport.Role.OFFLINE
	## What this route's lobby lets its slots choose (#615 D2) — null on a route
	## that opens no lobby, and null is also the legal "today's behaviour" answer
	## ([LobbyPolicy]'s class docs).
	##
	## [b]It hangs here, and not on a [enum RunConfig.Mode] table[/b], because
	## [member requested_mode] is explicitly NOT authoritative — it is what this
	## leaf ASKED for, and the run's real mode is derived from the roster at
	## START. A policy is needed at lobby-OPEN, when the only thing that exists
	## is this route. Plain `var`, not `@export`: [Route] is a [RefCounted]
	## authored in [method build], not a [Resource] edited in the inspector.
	var lobby_policy: LobbyPolicy = null

	func _init(
		mode: RunConfig.Mode = RunConfig.Mode.SINGLE,
		role: NetworkTransport.Role = NetworkTransport.Role.OFFLINE,
		policy: LobbyPolicy = null
	) -> void:
		requested_mode = mode
		network_role = role
		lobby_policy = policy


## One node of the menu tree. A pure record: it holds no scene, no [Control], no
## position and — since #591 — no LOOK either. #569 gives it a view,
## [FrontmatterLayout] gives it a place, and [MenuSlot] gives it a caption.
class Item extends RefCounted:
	## Stable identifier. Used as the layout key, the focus token, the id every
	## other child of #567 addresses this node by, and the key its
	## [MenuSlot.Look] is authored under.
	var id: StringName = &""
	## Parent id, `&""` on the root.
	var parent: StringName = &""
	## Child ids, in the order they are drawn top to bottom.
	var children: Array[StringName] = []
	## Which panel this leaf raises on the `%PanelLayer`
	## ([method FrontmatterPanels.show_panel]). Empty on a non-leaf: a node with
	## children navigates, it does not open anything.
	var panel: StringName = &""
	## Set on leaves that eventually author a run. Null on leaves that only open
	## a panel (settings, exit confirm, the parked load screen).
	var route: Route = null
	## Reachable but not selectable — LOAD GAME, because #23 save/load is parked
	## (#567's "LOAD GAME stays disabled/empty").
	var disabled: bool = false

	func is_leaf() -> bool:
		return children.is_empty()


## Panel ids, so no caller spells one by hand. #573 registers the real panels
## on [FrontmatterPanels] under exactly these names.
const PANEL_LOBBY := &"lobby"
const PANEL_LOAD := &"load"
const PANEL_JOIN := &"join"
const PANEL_SETTINGS := &"settings"
const PANEL_EXIT_CONFIRM := &"exit_confirm"

## Item ids. Same reason as the panel ids, plus these are the focus tokens the
## camera (#570) and the input map (#576) address.
const ID_ROOT := &"root"
const ID_SINGLE_PLAYER := &"single_player"
const ID_NEW_GAME := &"new_game"
const ID_LOAD_GAME := &"load_game"
const ID_MULTIPLAYER := &"multiplayer"
const ID_LOCAL := &"local"
const ID_HOST := &"host"
const ID_JOIN := &"join"
const ID_OPTIONS := &"options"
const ID_EXIT := &"exit"

## The three lobby shapes (#615). One authored resource per shape, not per leaf:
## HOST and JOIN open the same versus lobby and must agree about it, which is
## the whole reason the policy is data rather than a branch in the lobby.
const POLICY_SINGLE := preload("res://ui/frontmatter/policies/lobby_policy_single.tres")
const POLICY_HOTSEAT := preload("res://ui/frontmatter/policies/lobby_policy_hotseat.tres")
const POLICY_VERSUS := preload("res://ui/frontmatter/policies/lobby_policy_versus.tres")

## The root's id. Set by [method add] for the first parentless item.
var root: StringName = &""

var _items: Dictionary = {}
## Insertion order, which is also a pre-order walk for [method build] — the
## layout's leaf stacking reads it, so it must stay deterministic.
var _order: Array[StringName] = []


## The frontmatter tree as shipped. Mirrors `scenes/meta/meta_root.gd`'s routing
## one-for-one; see `test_meta_routing_parity.gd` for the machine-checked half
## of that claim.
##
## There is no display string anywhere below, and that is the acceptance of
## #591: what each of these ids LOOKS like is authored in its fan scene.
static func build() -> MenuGraph:
	var tree := MenuGraph.new()
	tree.add(_item(ID_ROOT, &""))

	tree.add(_item(ID_SINGLE_PLAYER, ID_ROOT))
	# `_on_new_game_pressed` -> `_push_lobby(SINGLE, NetworkConfig.offline())`.
	tree.add(_leaf(ID_NEW_GAME, ID_SINGLE_PLAYER, PANEL_LOBBY,
			Route.new(RunConfig.Mode.SINGLE, NetworkTransport.Role.OFFLINE,
					POLICY_SINGLE)))
	var load_game := _leaf(ID_LOAD_GAME, ID_SINGLE_PLAYER, PANEL_LOAD)
	load_game.disabled = true  # #23 save/load is parked.
	tree.add(load_game)

	tree.add(_item(ID_MULTIPLAYER, ID_ROOT))
	# The three answers #531 put between "Multiplayer" and the lobby. All three
	# land on the SAME lobby; only the NetworkConfig differs.
	tree.add(_leaf(ID_LOCAL, ID_MULTIPLAYER, PANEL_LOBBY,
			Route.new(RunConfig.Mode.COOP_HOTSEAT, NetworkTransport.Role.OFFLINE,
					POLICY_HOTSEAT)))
	tree.add(_leaf(ID_HOST, ID_MULTIPLAYER, PANEL_LOBBY,
			Route.new(RunConfig.Mode.COOP_HOTSEAT, NetworkTransport.Role.HOST,
					POLICY_VERSUS)))
	# JOIN's panel is the address screen, so its policy is not read on arrival —
	# it is read when that screen reports an address and `_on_join_requested`
	# pushes the lobby. Authored anyway, and identical to HOST's, because both
	# ends of one link must show the same lobby.
	tree.add(_leaf(ID_JOIN, ID_MULTIPLAYER, PANEL_JOIN,
			Route.new(RunConfig.Mode.COOP_HOTSEAT, NetworkTransport.Role.CLIENT,
					POLICY_VERSUS)))

	tree.add(_leaf(ID_OPTIONS, ID_ROOT, PANEL_SETTINGS))
	tree.add(_leaf(ID_EXIT, ID_ROOT, PANEL_EXIT_CONFIRM))
	return tree


## Registers [param item] and links it under its parent. The first parentless
## item becomes [member root]; a second one is a programming error, since the
## whole design (one camera over one persistent tree) assumes a single root.
func add(item: Item) -> Item:
	assert(not _items.has(item.id), "duplicate menu item id '%s'" % item.id)
	_items[item.id] = item
	_order.append(item.id)
	if item.parent == &"":
		assert(root == &"", "a MenuGraph has exactly one root")
		root = item.id
	else:
		var parent := get_item(item.parent)
		assert(parent != null, "menu item '%s' has unknown parent '%s'" % [item.id, item.parent])
		parent.children.append(item.id)
	return item


func has(id: StringName) -> bool:
	return _items.has(id)


func get_item(id: StringName) -> Item:
	return _items.get(id) as Item


## Every id, in insertion order. [method build] inserts pre-order, and
## [FrontmatterLayout] relies on that for a stable leaf stacking.
func ids() -> Array[StringName]:
	return _order.duplicate()


func size() -> int:
	return _order.size()


func children_of(id: StringName) -> Array[StringName]:
	var item := get_item(id)
	if item == null:
		var none: Array[StringName] = []
		return none
	return item.children.duplicate()


func parent_of(id: StringName) -> StringName:
	var item := get_item(id)
	return &"" if item == null else item.parent


func is_leaf(id: StringName) -> bool:
	var item := get_item(id)
	return item != null and item.is_leaf()


## Siblings of [param id] INCLUDING itself, in draw order — what up/down
## navigation (#576) steps through.
func siblings_of(id: StringName) -> Array[StringName]:
	var parent := parent_of(id)
	if parent != &"":
		return children_of(parent)
	var only: Array[StringName] = []
	if has(id):
		only.append(id)
	return only


## Root-first chain down to [param id], `[root, …, id]`. Empty for an unknown
## id. This is the whole of "where am I" — back navigation is just dropping the
## last element, which under a moving camera is symmetric with going forward by
## construction (#567).
func path_to(id: StringName) -> Array[StringName]:
	var chain: Array[StringName] = []
	var cursor := id
	while cursor != &"":
		var item := get_item(cursor)
		if item == null:
			return []
		chain.push_front(cursor)
		cursor = item.parent
	return chain


## Distance from the root; 0 for the root itself, -1 for an unknown id.
func depth_of(id: StringName) -> int:
	return path_to(id).size() - 1


static func _item(id: StringName, parent: StringName) -> Item:
	var item := Item.new()
	item.id = id
	item.parent = parent
	return item


static func _leaf(
	id: StringName, parent: StringName, panel: StringName, route: Route = null
) -> Item:
	var item := _item(id, parent)
	item.panel = panel
	item.route = route
	return item
