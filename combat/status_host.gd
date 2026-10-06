class_name StatusHost
extends RefCounted

## The status machinery (#872) as ONE implementation over two hosts (#995,
## hub #994): [NodeCombat] composes it today, [EntityCombat] in C1. Owns the
## rows — every [StatusDef] currently on the host, keyed by
## `(def.id, key)` (#1343) — and the apply / tick / cure / remove lifecycle;
## never a second `apply_status`.
##
## The host contract is DUCK-TYPED on [member owner], the composing slice —
## an explicit interface would either be a second file or move the slices
## off `RefCounted`. Every def hook receives [member owner] (never this
## object), so what the six defs + [DotTick] + [StatusInstance] call on it is
## the contract:
##   `board()`, `get_local_value(id)`, `get_max_hp()`, `heal_damage()`,
##   `add_local_modifier(m)` / `remove_local_modifier(m)`, `host` (for
##   `DamageInstance.target`), `DamageInstance.land_on(owner)`;
## plus what this class itself calls back:
##   `is_allocated()` — the `CLEAR` gate on apply;
##   `_on_first_status()` — the FIRST row landing (sparse tick subscription, #879);
##   `_on_last_status_removed()` — the LAST row leaving;
##   `_on_statuses_changed()` — after every apply / tick / cure / remove (#880).
## The live-only gating of those three (`host != null`) is the owner's, not
## this class's: a shadow owner implements them as no-ops.

## The rows, `def.id -> {key: NodeStatus}` (#1343): a row's identity is
## `(def.id, key)`, the key computed by [method StatusDef.group_key]; a shared
## def has the one key `true`. An emptied inner dictionary is erased, so
## `_statuses.is_empty()` means "no row at all".
var _statuses: Dictionary[StringName, Dictionary] = {}
## Weak, never strong: the composing slice holds this host by value, so a
## strong back-reference would be a RefCounted cycle — a shadow slice would
## never free (`test_snapshot_and_free_shadow_leaks_nothing`).
var _owner_ref: WeakRef
## The composing slice — the `host` every def hook sees. Untyped on purpose:
## the contract above is duck-typed. Null once the slice is gone.
var owner:
	get:
		return _owner_ref.get_ref() if _owner_ref != null else null


func _init(p_owner = null) -> void:
	_owner_ref = weakref(p_owner) if p_owner != null else null


## Copy every row into [param other] — the shadow snapshot's clone, row by
## row via [method NodeStatus.clone] (same shared def, own power, same key).
## Fires no hook and no notify: a shadow tick must never move the live row.
func clone_into(other: StatusHost) -> void:
	for id in _statuses:
		var rows := {}
		for key in _statuses[id]:
			rows[key] = (_statuses[id][key] as NodeStatus).clone()
		other._statuses[id] = rows


## Put [param def] on the host at [param power] — on the row
## [method StatusDef.group_key] files a landing by [param camp_id] /
## [param applier_id] under, which then records them as its latest applier
## (#1343) — or re-apply it per
## [member StatusDef.reapply]; the result is clamped to
## [member StatusDef.power_max] (unless that is `<= 0`: uncapped, #962) and
## handed to [method StatusDef._on_applied].
## No-op on an unallocated host for a `CLEAR` def (owner, 2026-09-14: nothing
## owns it, nothing would tick it), on a null def, on a non-positive power,
## and on a key the def refuses (`null`, after its `push_error`).
func apply_status(def: StatusDef, power: float, camp_id: StringName = &"", applier_id: int = 0) -> void:
	if def == null or power <= 0.0:
		return
	if not _may_host(def):
		return
	var key: Variant = def.group_key(camp_id, applier_id)
	if key == null:
		return
	var current := get_status_power(def.id, key)
	var next := power
	if _row(def.id, key) != null:
		match def.reapply:
			StatusDef.Reapply.ACCUMULATE:
				next = current + power
			_:
				next = maxf(current, power)
	_settle(def, next, key, true, [camp_id, applier_id])


## Put the row `(def.id, [param key])` back at exactly [param power] with its
## applier fields and ramp position ([member NodeStatus.decay_step]) — the
## snapshot restore's writer. Never recomputes the key
## through the def (a decoded row keeps the key it was saved under); keeps
## [method apply_status]'s `CLEAR` gate and [method _settle]'s clamp.
func restore_row(def: StatusDef, power: float, key: Variant, camp_id: StringName = &"",
		applier_id: int = 0, decay_step: int = 0) -> void:
	if def == null or power <= 0.0 or key == null or not _may_host(def):
		return
	_settle(def, power, key, true, [camp_id, applier_id])
	var row := _row(def.id, key)
	if row != null:
		row.decay_step = decay_step


## Move [param def]'s RAW row `(def.id, [param key])` on this host by [param delta] stacks — the one
## primitive [method apply_status] and [SpreadApplier]
## land through ([method _settle]). `+n` on an absent row creates it; a
## result `<= 0` removes it; `-n` on an absent row is a no-op. Not a landing:
## no attacker fold, no reapply policy — moving stacks is not landing them.
## Creation keeps [method apply_status]'s gate: a `CLEAR` def is never put on
## an unallocated host, so a spread credit onto one is VOIDED, not banked.
## A row it creates carries no applier (`&""` / `0`): moving is not landing.
func adjust_power(def: StatusDef, delta: float, key: Variant = true) -> void:
	if def == null or delta == 0.0 or key == null:
		return
	if _row(def.id, key) == null and (delta < 0.0 or not _may_host(def)):
		return
	_settle(def, get_status_power(def.id, key) + delta, key)


## The shared tail: set [param def]'s row to [param target], clamped to
## [member StatusDef.power_max] (`<= 0` uncapped, #962). `<= 0` goes through
## [method remove_status]; otherwise the row is created if absent (the FIRST
## row is the owner's [code]_on_first_status[/code] cue, #879), set, and
## handed to [method StatusDef._on_applied] at its resisted count (ADR 0031).
## [param notify] off lets a batch caller refresh once at its end (#880).
## [param applier] `[camp_id, applier_id]`, when given, is recorded on the row.
## [method tick_statuses] is NOT a caller: tick keeps its own tail, because
## its survivor path is [method StatusDef._on_tick]'s, not `_on_applied`'s.
func _settle(def: StatusDef, target: float, key: Variant = true, notify: bool = true,
		applier: Array = []) -> void:
	# ADR 0032: the row is whole. A fraction here is a minting site's bug
	# (the fold, a decay, a spill) — never rounded silently at the store.
	assert(is_equal_approx(target, roundf(target)),
			"StatusHost: non-integer stack count %s for %s" % [target, def.id])
	var whole := roundf(target)
	var next := whole if def.power_max <= 0.0 else minf(whole, floorf(def.power_max))
	if next <= 0.0:
		remove_row(def.id, key)
		return
	var had_status := not _statuses.is_empty()
	var row := _row(def.id, key)
	if row == null:
		row = NodeStatus.new(def, 0, key)
		(_statuses.get_or_add(def.id, {}) as Dictionary)[key] = row
	row.power = int(next)
	if applier.size() == 2:
		row.camp_id = applier[0]
		row.applier_id = applier[1]
	def._on_applied(owner, effective_power(def, row.power))
	if not had_status:
		owner._on_first_status()
	if notify:
		owner._on_statuses_changed()


## No `CLEAR` def on an unallocated host (owner, 2026-09-14: nothing owns it,
## nothing would tick it). A `LINGER` def is hostable there: the lingering
## registry ticks it ([method CombatWorld.tick_lingering]).
func _may_host(def: StatusDef) -> bool:
	return def.on_dealloc != StatusDef.OnDealloc.CLEAR or owner.is_allocated()


## One tick for every status on the host: [method StatusDef._on_tick] first
## (damage, effects) — handed [method effective_power] of both `before` and
## `after` — then decay of the RAW row per [method StatusDef.decayed] (its
## [member StatusDef.decay] slot) — then removal at `<= 0`. Iterates a COPY and re-checks each row is still the
## one on the host before touching it — a tick can `take_damage` into a kill
## cascade that `release_statuses()` this very host, or a hook can remove a
## sibling; either way a vanished status is skipped, never resurrected.
func tick_statuses() -> void:
	for row in get_statuses():
		var id := row.def.id
		if _row(id, row.key) != row:
			continue  # vanished mid-tick
		var before := float(row.power)
		var after := row.def.decayed(before, row)  # per its decay slot; 0 means removed
		assert(is_equal_approx(after, roundf(after)),
				"StatusHost: %s decayed to a non-integer %s" % [id, after])
		# ADR 0031: the hook sees both ends resisted; decay stays raw below.
		row.def._on_tick(owner, effective_power(row.def, before), effective_power(row.def, after))
		if _row(id, row.key) != row:
			continue  # the hook removed it (or the host was cleared under us)
		row.power = int(roundf(after))
		row.decay_step += 1
		if row.power <= 0:
			remove_row(id, row.key)
	# #880: decay changes the blend even on rows that survive (no removal, so
	# no notify from inside the loop above) — one refresh per tick pass.
	owner._on_statuses_changed()


## The host exerted: [method StatusDef._on_exerted] for every row on it.
## Iterates a COPY and re-checks presence like [method tick_statuses] — a hook
## may remove its own row or a sibling's, and a vanished row is skipped.
func exert() -> void:
	for row in get_statuses():
		if _row(row.def.id, row.key) != row:
			continue
		row.decay_step = 0
		row.def._on_exerted(owner)


## Damage the statuses on the host still have in them (#962): the sum of
## [method StatusDef.projected_damage] over every row — each remaining tick
## as it would land (resisted, floored), so the bar equals reality; a
## damageless def contributes 0. Drawn by #953.
func projected_status_damage() -> float:
	var total := 0.0
	for row in get_statuses():
		total += row.def.projected_damage(owner, row.power)
	return total


## Drop EVERY row of the status [param id], each through [method remove_row].
## Unknown ids are ignored.
func remove_status(id: StringName) -> void:
	var rows: Dictionary = _statuses.get(id, {})
	for key in rows.keys():
		remove_row(id, key)


## Drop the one row `([param id], [param key])`; [method StatusDef._on_removed]
## fires exactly once. An unknown row is ignored.
func remove_row(id: StringName, key: Variant) -> void:
	var row := _row(id, key)
	if row == null:
		return
	var rows: Dictionary = _statuses[id]
	rows.erase(key)
	if rows.is_empty():
		_statuses.erase(id)
	row.def._on_removed(owner)
	# Sparse tick subscription (#879): the LAST status leaving is the owner's
	# cue to unsubscribe. Fires from every step of [method release_statuses]
	# too — the one that empties the store is the one that unsubscribes.
	if _statuses.is_empty():
		owner._on_last_status_removed()
	# #880: refresh on every remove.
	owner._on_statuses_changed()


## Drop every status, each through [method remove_status], and hand back the
## rows as they stood — the caller that is stripping the node feeds them to
## [method CombatWorld.note_removed] so a spreading def can spill them.
## [param keep_lingering] is the DEALLOC flavour: `LINGER` rows stay on the
## host and are not handed back (so never spilled); a death strip and a
## restore wipe pass false and release everything.
func release_statuses(keep_lingering: bool = false) -> Array[NodeStatus]:
	var out: Array[NodeStatus] = []
	for row in get_statuses():
		if _row(row.def.id, row.key) != row:
			continue  # an earlier row's _on_removed took it
		if keep_lingering and row.def.on_dealloc == StatusDef.OnDealloc.LINGER:
			continue
		out.append(row)
		remove_row(row.def.id, row.key)
	return out


## True iff any row on the host is a `LINGER` def's.
func has_lingering() -> bool:
	for id in _statuses:
		var rows: Dictionary = _statuses[id]
		for key in rows:
			if (rows[key] as NodeStatus).def.on_dealloc == StatusDef.OnDealloc.LINGER:
				return true
	return false


## The count [param power] stacks of [param def] act as on this host — what
## every apply and every tick hands the def (ADR 0031). Resistance is read
## node-locally on [member owner] (`get_local_value`: a node slice, or the
## entity board for a fallen-through row); a blank or unknown id reads 0.
## Round half-down: `cancelled = ⌈power × res − ½⌉`, clamped to
## `[0, power]`, so 1% never curbs a small row to 0 and 1·50% keeps its
## stack. At [method blocks] the answer is 0 outright — the formula alone
## would leave a fractional row's `< ½` standing. The row itself is never
## touched: this is a live filter, so shedding resistance restores the full
## count on the very next tick.
func effective_power(def: StatusDef, power: float) -> float:
	if power <= 0.0:
		return 0.0
	var res := _resistance(def)
	if res >= 1.0:
		return 0.0
	var cancelled := clampf(ceilf(power * res - 0.5), 0.0, power)
	return power - cancelled


## True when this host's resistance to [param def] is 100% or more: a
## landing resolves to 0 stacks (the gate lives in [StatusInstance]'s
## authority resolve, so a replay lands the recorded 0), and a row already
## standing deals 0 while it still decays.
func blocks(def: StatusDef) -> bool:
	return _resistance(def) >= 1.0


func _resistance(def: StatusDef) -> float:
	var o = owner
	if def == null or def.resistance_stat_id.is_empty() or o == null:
		return 0.0
	var v: Variant = o.get_local_value(def.resistance_stat_id)
	return float(v) if v != null else 0.0


## Current power of the row `([param id], [param key])`, `0.0` when absent.
func get_status_power(id: StringName, key: Variant = true) -> float:
	var row := _row(id, key)
	return float(row.power) if row != null else 0.0


## The rows a UI reads — every row of every def, defs in first-application
## order, each def's rows in theirs; each carries its `key`. The live rows,
## not copies: read `def` / `power` / `key` / `normalised()`, never write.
func get_statuses() -> Array[NodeStatus]:
	var out: Array[NodeStatus] = []
	for id in _statuses:
		for row: NodeStatus in (_statuses[id] as Dictionary).values():
			out.append(row)
	return out


func _row(id: StringName, key: Variant) -> NodeStatus:
	var rows: Dictionary = _statuses.get(id, {})
	return rows.get(key)
