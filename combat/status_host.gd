class_name StatusHost
extends RefCounted

## The status machinery (#872) as ONE implementation over two hosts (#995,
## hub #994): [NodeCombat] composes it today, [EntityCombat] in C1. Owns the
## rows — every [StatusDef] currently on the host, keyed by
## [member StatusDef.id] — and the apply / tick / cure / remove lifecycle;
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

var _statuses: Dictionary[StringName, NodeStatus] = {}
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
## row via [method NodeStatus.clone] (same shared def, own power). Fires no
## hook and no notify: a shadow tick must never move the live row.
func clone_into(other: StatusHost) -> void:
	for id in _statuses:
		other._statuses[id] = _statuses[id].clone()


## Put [param def] on the host at [param power], or re-apply it per
## [member StatusDef.reapply]; the result is clamped to
## [member StatusDef.power_max] (unless that is `<= 0`: uncapped, #962) and
## handed to [method StatusDef._on_applied].
## No-op on an unallocated host for a `CLEAR` def (owner, 2026-09-14: nothing
## owns it, nothing would tick it), on a null def, and on a non-positive power.
func apply_status(def: StatusDef, power: float) -> void:
	if def == null or power <= 0.0:
		return
	if def.on_dealloc == StatusDef.OnDealloc.CLEAR and not owner.is_allocated():
		return
	var had_status := not _statuses.is_empty()
	var row: NodeStatus = _statuses.get(def.id)
	var next: float
	if row == null:
		row = NodeStatus.new(def, 0.0)
		_statuses[def.id] = row
		next = power
	else:
		match def.reapply:
			StatusDef.Reapply.ACCUMULATE:
				next = row.power + power
			_:
				next = maxf(row.power, power)
	# `power_max <= 0` is uncapped (#962: poison stacks without limit).
	row.power = next if def.power_max <= 0.0 else minf(next, def.power_max)
	def._on_applied(owner, row.power)
	# Sparse tick subscription (#879): the FIRST status landing is the owner's
	# cue to subscribe to the turn.
	if not had_status:
		owner._on_first_status()
	# #880: the tint reads the strongest status; refresh on every apply.
	owner._on_statuses_changed()


## One tick for every status on the host: [method StatusDef._on_tick] first
## (damage, effects), then decay per [method StatusDef.decayed] — flat by
## [member StatusDef.decay_per_tick], or halving with the tail cut below 1
## for a FRACTION def (#962) — then removal at `<= 0`. Iterates a COPY and re-checks each row is still the
## one on the host before touching it — a tick can `take_damage` into a kill
## cascade that `clear_statuses()` this very host, or a hook can remove a
## sibling; either way a vanished status is skipped, never resurrected.
func tick_statuses() -> void:
	var rows: Array[NodeStatus] = []
	rows.assign(_statuses.values())
	for row in rows:
		var id := row.def.id
		if _statuses.get(id) != row:
			continue  # vanished mid-tick
		var before := row.power
		var after := row.def.decayed(before)  # by decay_mode; 0 means removed
		row.def._on_tick(owner, before, after)
		if _statuses.get(id) != row:
			continue  # the hook removed it (or the host was cleared under us)
		row.power = after
		if after <= 0.0:
			remove_status(id)
	# #880: decay changes the blend even on rows that survive (no removal, so
	# no notify from inside the loop above) — one refresh per tick pass.
	owner._on_statuses_changed()


## Damage the statuses on the host still have in them (#962): the sum of
## [method StatusDef.projected_damage] over every row — poison's remaining
## halving series; a damageless def contributes 0. Drawn by #953.
func projected_status_damage() -> float:
	var total := 0.0
	for row: NodeStatus in _statuses.values():
		total += row.def.projected_damage(owner, row.power)
	return total


## Cure by [param heal_amount] (#875, hub #868 D7): every `&"debuff"`-tagged
## status on the host loses `heal_amount * def.cure_per_hp` power — a def that
## authors no [member StatusDef.cure_per_hp] (`0.0`, the default) is never
## touched. A status cured to `<= 0` goes through [method remove_status] so
## [method StatusDef._on_removed] fires normally; one that survives gets
## [method StatusDef._on_applied] re-run at its new power so a planted
## modifier (Blindness's factor) follows it down — there is no separate
## "on cured" hook, `_on_applied` is already idempotent for that shape (#873).
## Iterates a COPY and re-checks the row is still live, same as
## [method tick_statuses] — a hook can remove a sibling or the host itself.
func cure_debuffs(heal_amount: float) -> void:
	if heal_amount <= 0.0:
		return
	var rows: Array[NodeStatus] = []
	rows.assign(_statuses.values())
	for row in rows:
		if row.def.cure_per_hp <= 0.0 or not row.def.tags.has(&"debuff"):
			continue
		var id := row.def.id
		if _statuses.get(id) != row:
			continue  # vanished from an earlier row's hook this same call
		var after := maxf(row.power - heal_amount * row.def.cure_per_hp, 0.0)
		if after <= 0.0:
			remove_status(id)
		else:
			row.power = after
			row.def._on_applied(owner, after)
	# #880: a cure changes power on rows that survive too (same reasoning as
	# tick_statuses' trailing refresh) — the zeroed-out ones already notified
	# via remove_status.
	owner._on_statuses_changed()


## Drop the status [param id]; [method StatusDef._on_removed] fires exactly once.
## Unknown ids are ignored.
func remove_status(id: StringName) -> void:
	var row: NodeStatus = _statuses.get(id)
	if row == null:
		return
	_statuses.erase(id)
	row.def._on_removed(owner)
	# Sparse tick subscription (#879): the LAST status leaving is the owner's
	# cue to unsubscribe. Fires from every step of [method clear_statuses]
	# too — the one that empties the store is the one that unsubscribes.
	if _statuses.is_empty():
		owner._on_last_status_removed()
	# #880: refresh on every remove.
	owner._on_statuses_changed()


## Drop every status, each through [method remove_status].
func clear_statuses() -> void:
	for id in _statuses.keys():
		remove_status(id)


## Current power of status [param id], `0.0` when absent.
func get_status_power(id: StringName) -> float:
	var row: NodeStatus = _statuses.get(id)
	return row.power if row != null else 0.0


## The rows a UI reads, in application order — the live rows, not copies:
## read `def` / `power` / `normalised()`, never write.
func get_statuses() -> Array[NodeStatus]:
	var rows: Array[NodeStatus] = []
	rows.assign(_statuses.values())
	return rows
