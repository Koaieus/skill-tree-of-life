@tool
class_name SpellBook
extends Resource

## A character's known spells, plus the gating logic that turns
## "knows spell X" into "can cast X from node N right now". Centralising those
## rules here keeps [MagicAttackPlan] and the spell-picker UI in agreement —
## both ask the same question, both get the same answer.
##
## Authored as a .tres per character archetype (apprentice spellbook, archmage
## spellbook…) and assigned to [member Entity.spellbook]; runtime sandboxes
## that don't bother with a .tres can build one with [code]SpellBook.new()[/code]
## + push spells into [member spells].
##
## [b]Dynamic spellbook.[/b] Spells can be granted and revoked at runtime via
## [SpellGrant] effects on allocated nodes. Each spell tracks its sources; a
## spell is only removed from [member spells] when the last source drops. The
## [signal changed] signal (inherited from [Resource]) is emitted on every
## membership change so UI can react.
##
## [b]#198 invariant.[/b] SpellGrants are granted/revoked only as whole-node
## batches ([code]_grant_node_effects[/code] <-> [code]revoke_effects_from[/code]),
## so keying [member _sources] by [code]source_node[/code] can't collide. If a
## mid-life single-effect revoke is ever added, rekey [member _sources] by
## [EffectInstance] instead.

## Emitted whenever [member spells] changes — a spell is added or removed.
## Distinct from the inherited [signal Resource.changed] only so consumers give
## it a descriptive name.
signal membership_changed()

@export var spells: Array[SpellDef] = []

var _sources: Dictionary[SpellDef, Array] = {}


## Add [param spell] from [param source]. When [param source] is a node, the
## same source re-granting the same spell is a no-op — refcount stays at 1.
## A null [param source] means "innate / permanent" — it's stored as a
## pseudo-source in [member _sources] just like a node, EXCEPT
## [method remove_spell] refuses to remove a null source (below), so once
## added it can never be ref-counted away. That single asymmetry is what
## makes "granting an already-innate spell from a node, then losing that
## node" a no-op rather than an accidental un-learn — see [method permanent_spells].
func add_spell(spell: SpellDef, source: Variant) -> void:
	if spell == null:
		return
	if not _sources.has(spell):
		_sources[spell] = []
		spells.append(spell)
	var source_list: Array = _sources[spell]
	if source in source_list:
		return
	source_list.append(source)
	_notify_changed()


## Remove [param spell] from [param source]. When the last source is gone the
## spell leaves [member spells]. A null [param source] is a no-op (permanent
## spells are revoked when the granting core class is dismantled, not here).
## A source that never granted the spell is a safe no-op.
func remove_spell(spell: SpellDef, source: Variant) -> void:
	if spell == null or source == null:
		return
	if not _sources.has(spell):
		return
	var source_list: Array = _sources[spell]
	source_list.erase(source)
	if source_list.is_empty():
		_sources.erase(spell)
		spells.erase(spell)
	_notify_changed()


## Number of active grants for [param spell]. Mainly for tests.
func source_count(spell: SpellDef) -> int:
	if not _sources.has(spell):
		return 0
	return _sources[spell].size()


## Spells whose source-side constraints are satisfied at [param source] for
## [param attacker]. Mana check is NOT included here — that's per-cast and the
## caller (MagicAttackPlan.validate / spell-picker enable state) layers it on.
func castable_from(source: SkillNode, attacker: Entity) -> Array[SpellDef]:
	var result: Array[SpellDef] = []
	for spell in spells:
		if spell != null and _node_meets_source_requirements(spell, source, attacker):
			result.append(spell)
	return result


## Every owned node of [param attacker] that may cast [param spell] right now
## — the inverse of [method castable_from], and the source set the pick-spell-
## first targeting union is built over (#728).
##
## The one home for "can this node cast it": [SpellTargetUnion] and the
## spell-picker's no-caster gate both call THIS, rather than each re-deriving
## min_degree against the owned subgraph. Mana is still not part of it, for the
## same reason [method castable_from] leaves it out — it is per-cast, and the
## picker layers it on as its own separate gate.
func eligible_sources(spell: SpellDef, attacker: Entity) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if spell == null or attacker == null or attacker.navigator == null:
		return out
	for n in attacker.navigator.get_mirrored_nodes():
		if _node_meets_source_requirements(spell, n, attacker):
			out.append(n)
	return out


## Does the entity's owned-subgraph degree at [param source] satisfy
## [param spell]'s [member SpellDef.min_degree]? Returns true for null source
## (the UI uses this to decide "can EVER be cast" before a source is picked).
func is_castable(spell: SpellDef, source: SkillNode, attacker: Entity) -> bool:
	if spell == null:
		return false
	if source == null:
		# Pre-source state: don't grey-out spells, just enable them — the
		# real gate fires once a source is selected.
		return true
	return _node_meets_source_requirements(spell, source, attacker)


func _node_meets_source_requirements(spell: SpellDef, source: SkillNode,
		attacker: Entity) -> bool:
	if attacker == null or attacker.navigator == null:
		# Conservative default: without a navigator we can't measure degree;
		# assume gating fails so we don't promise an invalid cast.
		return false
	if source.owned_by != attacker:
		return false
	var deg := attacker.navigator.get_degree(source)
	return deg >= spell.min_degree


## Convenience for tests / scripted setup — appends a spell if absent.
## Editor-safe (no scene-tree access).
func learn(spell: SpellDef) -> void:
	if spell == null or spell in spells:
		return
	spells.append(spell)
	_notify_changed()


## Spells that persist across topology changes for the owner of `core`:
## innate (null-sourced — a permanent pseudo-source that [method remove_spell]
## refuses to remove, see [method add_spell] — or added via [method learn],
## which never touches [member _sources] at all) + spells granted by the core
## node. `core in _sources[spell]` keeps a spell sourced by core AND a
## territory node (acceptance #5). At `entity_dying` the strip hasn't run, so
## core grants are still present in `_sources`. See #204.
func permanent_spells(core: SkillNode) -> Array[SpellDef]:
	var out: Array[SpellDef] = []
	for spell in spells:
		if spell == null:
			continue
		var sources: Array = _sources.get(spell, [])
		if sources.is_empty() or null in sources or core in sources:
			out.append(spell)          # innate (incl. `learn`) or core-node-sourced
	return out


func _notify_changed() -> void:
	emit_changed()
	membership_changed.emit()


## A fresh book holding a random subset of [member spells], drawn by the
## #586 prune chain. Used at blocker spawn so a Dormant Core offers a varying
## slice of its authored loot rather than the same book every run.
##
## [b]The chain.[/b] With `n` spells left, pop a uniformly-random one with
## probability `n / (n + m)`; on the first failed roll, stop and keep what's
## left. It can run all the way to empty — that is the point, since the
## claimant of a relic picks exactly ONE spell from whatever is offered, so
## the only lever on how fast spells spread is how often a kill offers none.
##
## [b]What `m` means.[/b] It picks the shape of the outcome distribution over
## `k` kept spells, and both closed forms are exact:
## [codeblock]
## E[kept]      = n * m / (m + 1)
## P(kept == 0) = 1 / C(n + m, n)      # integer m
## [/codeblock]
## `m == 1` is the special case where every outcome in `{0..n}` is EQUALLY
## likely — maximum variance, and `P(kept == 0) == 1 / (n + 1)`.
## [b]Raising `m` above 1 makes spells spread FASTER, not slower[/b]: at
## `n == 4` the chance of offering nothing falls from 20% (m=1) to 2.9% (m=3).
## Turn `m` DOWN, not up, to make loot stingier (m=0.5 → 41% at `n == 4`).
##
## A null [param rng] or a non-positive [param m] prunes nothing — that is the
## "feature off" path a hand-authored level or a fixture takes by not opting in.
##
## [member _sources] is deliberately not carried over: the copy is a loot pool,
## so every spell in it reads as innate, which is what [SkillDustAddon] wants.
func duplicate_pruned(rng: RandomNumberGenerator, m: float) -> SpellBook:
	var out := SpellBook.new()
	out.spells = spells.duplicate()
	if rng == null or m <= 0.0:
		return out
	while not out.spells.is_empty():
		var n := float(out.spells.size())
		if rng.randf() >= n / (n + m):
			break
		out.spells.remove_at(rng.randi_range(0, out.spells.size() - 1))
	return out
