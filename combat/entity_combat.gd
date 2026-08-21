class_name EntityCombat
extends RefCounted

## The live combat-state slice for an [Entity] (#498 — see
## docs/domain/attack-timeline.md). Step 1 moved exactly one thing here: the
## revoke sweep + navigator-mirror removal that [AllocationSystem.force_deallocate]
## runs on the node's *previous owner* ([method revoke_node]). Step 2 adds
## [method snapshot] — a detached SHADOW that can resolve a whole attack,
## including the forced-dealloc cascade and entity death, without touching
## [Events], [AllocationSystem], or any real [SkillNode]/[Entity].
##
## [member host] is assigned once, at construction, and is never reassigned —
## no public setter. [method snapshot] is the only hostless-slice factory and
## it takes no host argument.
##
## Ownership storage does NOT move onto this class. [member owned] / [member core]
## / [member board] are ACCESSORS: live reads through [member host] (never
## cached — [AllocationSystem] writes `node.owned_by` / mirrors the navigator
## and knows nothing of this slice, so a cached read would go stale silently);
## a shadow falls back to its own [member _owned] / [member _core] / [member _board],
## populated once at [method snapshot] and kept current by
## [method force_deallocate_owned] — the ONLY place that mutates a shadow's
## ownership, and it updates the [NodeCombat] backpointer and the shadow
## [GraphMirror] together (never one without the other, or islanding would
## answer a set the slice itself disagrees with).
##
## Effect-hook placement rule (docs/domain/attack-timeline.md's "one boundary
## that can rot"): an [Effect] hook that changes a number belongs on
## [EntityCombat]; a hook that only tells someone belongs on the host. Step 1's
## scope was the revoke sweep's own bookkeeping, not a dispatched hook.
## Step 2 does not extend this to `_on_node_deallocated` itself, or to
## [AuraEffect] recompute: a shadow's forced-dealloc cascade
## ([method force_deallocate_owned] / [method simulate_entity_death]) strips
## OWNERSHIP AND TOPOLOGY ONLY — no [Effect]/[AuraEffect] revocation or
## recompute runs against a shadow's board, and no SP-wound / `dealloc_damage`
## HP-chip bookkeeping happens either (both stay real [AllocationSystem] /
## [BattleSystem] concerns, out of this unit's owned files). This is a real,
## deliberate scope line, not an oversight — see the #498 step 2 report for
## why, and the follow-up it names.
##
## A caller done with a SHADOW must call [method free_shadow] on it — see
## that method for why ordinary refcounting can't do it (a reference cycle
## between this instance and its owned [NodeCombat]s).
var host: Entity

## Shadow-only backing (meaningful only when [member host] == null).
var _board: StatBoard
var _owned: Array[NodeCombat] = []
var _core: NodeCombat
## Manual-mode [GraphMirror] over the REAL [Graph] (topology never changes
## mid-attack — see docs/domain/attack-timeline.md's melee physics note), used
## only for [method nodes_islanded_by_removing] on a shadow. `wire_to` is
## never called, so [method GraphMirror._should_mirror] (the only thing that
## reads REAL ownership) is never consulted — precedent:
## `attack/plan/melee_attack_plan.gd`'s `_blade_mirror`. [GraphMirror] `extends
## Node`, so it needs an explicit free — [method free_shadow] does that (the
## primary path; see its doc for why [constant NOTIFICATION_PREDELETE] alone
## can't be relied on here, unlike the `_blade_mirror` precedent).
var _mirror: GraphMirror
## Real [SkillNode] <-> shadow [NodeCombat], both directions — needed because
## [member _mirror] is keyed by the real node (topology lives there) while
## every other shadow accessor is keyed by [NodeCombat] (ownership lives
## here). Built once at [method snapshot]; membership only ever shrinks
## (nodes leave via [method force_deallocate_owned], nothing re-enters).
var _shadow_by_real: Dictionary[SkillNode, NodeCombat] = {}
var _real_by_shadow: Dictionary[NodeCombat, SkillNode] = {}


func _init(p_host: Entity = null) -> void:
	host = p_host


func _notification(what: int) -> void:
	# Defensive backstop only — see [method free_shadow] for why this rarely
	# fires. A shadow with an EMPTY owned set (no [NodeCombat] holding a
	# backpointer into it) has no cycle and DOES reach NOTIFICATION_PREDELETE
	# normally; anything with owned nodes needs the explicit call.
	if what == NOTIFICATION_PREDELETE and _mirror != null:
		_mirror.free()
		_mirror = null


## Tear down a SHADOW explicitly — the caller's job once it's done with one
## (an AI rollout between iterations, a test in `after_each`). Ordinary
## refcounting cannot do this for us: every owned [NodeCombat]'s
## [member NodeCombat._owner] backpoints at THIS instance, so a shadow entity
## and its shadow nodes form a reference CYCLE, and GDScript's [RefCounted]
## has no cycle collector — [method _notification]'s [constant NOTIFICATION_PREDELETE]
## would never fire on its own. This method breaks the cycle (clears every
## backpointer) and frees [member _mirror] (a [Node] — also never freed by
## refcounting), after which ordinary refcounting finishes the job once the
## caller drops its own reference. No-op on a LIVE slice — nothing to tear
## down; [member host] != null never entered a cycle in the first place.
##
## [b]The cloned stat boards are a SECOND cycle of the same shape[/b] (#514):
## every [Stat] backpoints at the [StatBoard] holding it, so a board dropped
## without [method StatBoard.release] is never collected either — 122 objects
## per entity board, measured, plus one node board per owned node. Releasing
## them is therefore part of this teardown, not a separate call a caller could
## forget. Done BEFORE `_owned` is cleared, which is the only order that can
## still reach each owned node's board.
func free_shadow() -> void:
	if host != null:
		return
	for n in _owned:
		if n._board != null:
			n._board.release()
			n._board = null
	if _board != null:
		_board.release()
		_board = null
	for n in _owned:
		n._owner = null
	_owned.clear()
	_shadow_by_real.clear()
	_real_by_shadow.clear()
	_core = null
	if _mirror != null:
		_mirror.free()
		_mirror = null


## This entity's [StatBoard]. Live: [member Entity.stat_board], read fresh
## every call. Shadow: the deep clone made at [method snapshot].
func board() -> StatBoard:
	return host.stat_board if host != null else _board


## Every [NodeCombat] this entity owns. Live: derived from
## [member Entity.navigator] on every call (never cached, same rule as
## [method board]). Shadow: the slice's own ledger.
func owned() -> Array[NodeCombat]:
	if host != null:
		var out: Array[NodeCombat] = []
		if host.navigator != null:
			for n in host.navigator.get_mirrored_nodes():
				out.append(n.get_combat())
		return out
	return _owned.duplicate()


## This entity's core [NodeCombat]. Live: [member Entity.core_location]'s
## slice. Shadow: the slice snapshotted at [member Entity.core_location].
func core() -> NodeCombat:
	if host != null:
		# Null-guarded — GDScript has no safe-navigation operator, and
		# `core_location` genuinely is null before an entity's first
		# placement.
		return host.core_location.get_combat() if host.core_location != null else null
	return _core


## Build a detached SHADOW of this LIVE slice (only ever call on a slice with
## [member host] != null). `host` on the result is null FOREVER — see the
## class doc. Deep-clones [member Entity.stat_board] exactly like
## [method Entity._ready] does, snapshots every currently-owned [NodeCombat]
## via [method NodeCombat.snapshot], and builds the manual-mode [member _mirror]
## from the real owned set — see the class doc for why a real [SkillNode] is
## still needed for that one piece.
func snapshot() -> EntityCombat:
	var shadow := EntityCombat.new()
	if host == null:
		return shadow
	if host.stat_board != null:
		# clone_live, not duplicate(true) — see its doc: a bare duplicate
		# silently drops every already-applied modifier's bins and every
		# dynamically-minted stat.
		shadow._board = host.stat_board.clone_live()
	shadow._mirror = GraphMirror.new()
	shadow._mirror.graph = host.navigator.graph if host.navigator != null else null
	var real_nodes: Array[SkillNode] = host.navigator.get_mirrored_nodes() if host.navigator != null else []
	for real_node in real_nodes:
		var node_shadow: NodeCombat = real_node.get_combat().snapshot(shadow)
		shadow._owned.append(node_shadow)
		shadow._shadow_by_real[real_node] = node_shadow
		shadow._real_by_shadow[node_shadow] = real_node
		shadow._mirror.mirror_add(real_node)
	if host.core_location != null:
		shadow._core = shadow._shadow_by_real.get(host.core_location)
	return shadow


## All [NodeCombat]s that would lose reachability to [param anchor] if
## [param node] were removed — the slice-scoped twin of
## [method GraphMirror.nodes_islanded_by_removing]. Live delegates straight to
## [member Entity.navigator] (already exact); a shadow answers off
## [member _mirror], translating through [member _shadow_by_real] /
## [member _real_by_shadow] at the boundary since the mirror itself is keyed
## by the real [SkillNode].
func nodes_islanded_by_removing(node: NodeCombat, anchor: NodeCombat) -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	if node == null or anchor == null:
		return out
	if host != null:
		if host.navigator == null or node.host == null or anchor.host == null:
			return out
		for n in host.navigator.nodes_islanded_by_removing(node.host, anchor.host):
			out.append(n.get_combat())
		return out
	if _mirror == null:
		return out
	var real_node: SkillNode = _real_by_shadow.get(node)
	var real_anchor: SkillNode = _real_by_shadow.get(anchor)
	if real_node == null or real_anchor == null:
		return out
	for rn in _mirror.nodes_islanded_by_removing(real_node, real_anchor):
		var shadow_n: NodeCombat = _shadow_by_real.get(rn)
		if shadow_n != null:
			out.append(shadow_n)
	return out


## Cascade a non-core node's depletion on a SHADOW: [param node] plus every
## node [method nodes_islanded_by_removing] reports off it, each stripped via
## [method _strip_one]. The live twin of this (BattleSystem._on_node_depleted
## reacting to `Events.skill_node_depleted`) never runs for a shadow — a
## shadow's `notify_depleted` is never reached (see [NodeCombat.take_damage]),
## so nothing would drive the cascade without this. Ownership + topology only
## — see the class doc for what this deliberately does NOT replicate (SP
## wound / `dealloc_damage` chip, effect revocation).
func force_deallocate_owned(node: NodeCombat) -> void:
	if node == null or not _owned.has(node):
		return
	var cascade: Array[NodeCombat] = [node]
	cascade.append_array(nodes_islanded_by_removing(node, _core))
	for n in cascade:
		_strip_one(n)


## Strip every node this shadow owns — the shadow twin of
## [method AllocationSystem.deallocate_all_owned], run when the shadow's core
## `health` pool crosses 0 (see [NodeCombat.take_damage]'s overflow branch).
## "Recursive" in the sense the acceptance criteria mean it: a core hit can
## chip `health` to 0, which strips the whole owned set in one sweep — there
## is nothing left to recurse into after that.
func simulate_entity_death() -> void:
	for n in _owned.duplicate():
		_strip_one(n)
	_core = null


func _strip_one(node: NodeCombat) -> void:
	if node == null or not _owned.has(node):
		return
	_owned.erase(node)
	node._owner = null
	var real: SkillNode = _real_by_shadow.get(node)
	if real != null and _mirror != null:
		_mirror.mirror_remove(real)


## Strip [param node]'s footprint from [member host]: swapped effect-sets,
## granted effects, entity-scoped modifiers, and the navigator mirror. Called
## by [method AllocationSystem.force_deallocate] on the node's previous owner,
## before ownership clears. LIVE-only (reaches [member host] directly) — a
## shadow's forced-dealloc cascade goes through [method force_deallocate_owned]
## instead, which deliberately does not replicate this (see the class doc).
func revoke_node(node: SkillNode) -> void:
	var board := host.stat_board
	# Strip swapped effect-sets BEFORE the revoke sweep — the set leaves were
	# applied outside the effect ledger and would strand otherwise (#376).
	node.clear_scaled_effect_sets(board)
	host.revoke_effects_from(node)
	node.remove_entity_modifiers_from(board)
	if host.navigator != null:
		host.navigator.mirror_remove(node)
