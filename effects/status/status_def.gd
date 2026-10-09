@tool
class_name StatusDef
extends Resource

## The shared definition of a node status — poison, blindness, armor break
## (#868 hub, #872 plumbing). Authored once as a `.tres`, referenced by every
## node carrying that status; it holds NO runtime state. The per-node state
## (current power) lives on [NodeCombat]'s status slice as a [NodeStatus] row.
##
## A status is a bounded, decaying power: [method NodeCombat.apply_status] adds
## or refreshes it (per [member reapply]), [method NodeCombat.tick_statuses]
## fires [method _on_tick] and then decays it per its [member decay] slot.
## Behaviour hooks are overridable on a subclass script; the base does nothing on any of them.
##
## Display identity is the concept's [Identity] ([member identity]): [member tint]
## and [member icon] read it, so the status, its aspect, resistance and stacks
## stats share one hue and glyph and a consumer never picks one of its own
## (docs/adr/0046-identity-is-the-one-display-atom.md). [member display_name]
## stays here — the status noun and the concept noun may differ.

## Reapplication policy when the status is already on the node.
enum Reapply {
	## Keep the larger of the current and the incoming power — a re-cast
	## resets the timer, it never stacks and never shortens.
	REFRESH,
	## Add the incoming power to the current one, clamped at [member power_max].
	ACCUMULATE,
}

## What happens to the status when its node is deallocated (#879 wires it).
enum OnDealloc {
	## The row is released on any ownership loss, and never lands on an
	## unallocated node — nothing owns it, nothing would tick it.
	CLEAR,
	## The row survives deallocation — a voluntary dealloc or a bare
	## [method AllocationSystem.force_deallocate] — and is never handed to
	## spill (`release_statuses(true)` keeps it out of the returned rows); it
	## may land on an unallocated node. While its node is unowned it ticks once per ANY
	## entity's [method Entity.resolve_turn_end] (the lingering-host registry
	## on [method CombatWorld.live]), so it decays N× faster in an N-entity
	## game; re-allocated, it ticks on its new owner's turn end like every
	## owned row. A death strip — a node stripped by combat or by its owner's
	## death ([method EntityCombat.apply_cascade]) — releases every row:
	## LINGER survives deallocation only.
	LINGER,
}

## Unique key — the status slice is a dictionary on this.
@export var id: StringName = &""
@export var display_name: String = ""
## The concept this status expresses (`identity/defs/<id>.tres`).
@export var identity: Identity = null
## Prose for tooltips. Blank → [method get_description] derives one.
@export_multiline var description: String = ""
## The concept's glyph, read from [member identity]. Consumers fall back to a
## letter glyph when null, as [SpellPickerButton] does.
var icon: Texture2D:
	get:
		return identity.icon if identity != null else null
## The canonical colour of this status wherever UI mentions it (poison = green),
## read from [member identity]; white when none is set.
var tint: Color:
	get:
		return identity.tint if identity != null else Color.WHITE
## Classification tags a consumer may filter on (`&"debuff"`, `&"dot"`, …).
## Metadata only — NOT granted to the node as [method NodeCombat.add_tag] tags.
@export var tags: Array[StringName] = []
## The defender-side resistance stat (e.g. `&"poison_resistance"`): a
## fraction read on the HOST at effect time, filtering how many stacks each
## apply and tick counts, round half-down, while the row decays raw; at
## `>= 1` stacks do not land ([method StatusHost.effective_power], ADR 0031).
## Blank → unresisted.
@export var resistance_stat_id: StringName = &""
## The attacker-side stacks stat this status folds its per-hit power through
## ([method stacks_per_hit]): `<family>_stacks_per_hit` for a DoT, whose
## `dot_stacks_per_hit` parent folds in the same read, or blindness's own
## parentless stat. Blank → the authored power lands as-is.
@export var stacks_stat_id: StringName = &""
## What an attacker reads differently against this status's host: each entry
## says "an attacker's read of `stat_id` against my host gets `operation` with
## `value × power`", power being the host's EFFECTIVE power summed over the
## node's and its owner's rows ([method NodeCombat.incoming_overlays]). Sum ops
## only (ADD_BASE / INCREASE / ADD_BONUS): `value × power` means nothing for a
## SET or a MULTIPLY, so one is refused here with a `push_error` and ignored.
## Planted on no board: the door folds it into a [ModifierBins] per read.
@export var incoming_modifiers: Array[StatModifier] = []:
	set(v):
		incoming_modifiers = _sum_ops_only(v)
## Power is clamped to this on apply and on accumulate. `<= 0` → uncapped
## (#962): [method NodeCombat.apply_status] skips the clamp entirely.
@export var power_max: float = 1.0
## How power falls on every [method NodeCombat.tick_statuses], after
## [method _on_tick] has fired — a [FlatDecay], a [FractionDecay], or any
## sibling [StatusDecay] (#1258). Shared and stateless like this def. Defaults
## to a flat `1` per tick; `null` means the status never decays.
@export var decay: StatusDecay = FlatDecay.new()
## How stacks move between hosts — a [StatusSpread] signature, shared and
## stateless like this def. `null` → the status never spreads.
@export var spread: StatusSpread = null
## Display anchor for [method NodeStatus.normalised] (bar fill, node tint):
## `0` → use [member power_max]. An uncapped def authors one so the 0..1 scale
## survives (poison: 10).
@export var display_max: float = 0.0
@export var reapply: Reapply = Reapply.REFRESH
## What deallocation does to this def's rows — see [enum OnDealloc].
@export var on_dealloc: OnDealloc = OnDealloc.CLEAR

## The grouping key a landing's row is filed under (#1343): a GDScript
## [Expression], parsed once against [constant GROUP_BY_INPUTS] and run per
## apply ([method group_key]). Empty means `true` — every applier shares ONE
## row, the shipped behaviour. `false` is refused (independent rows need a
## deterministic application id, not built). The key must be a bool, int or
## StringName — a row replays identically on every peer. Inputs:
##   [b]camp_id[/b]    — StringName, the applier's [member Faction.id] (`&""` none)
##   [b]applier_id[/b] — int, the applier's [member Entity.entity_id] (`0` none)
## e.g. `camp_id` (one row per camp), `applier_id` (one per entity).
@export_multiline var group_by: String = "":
	set(v):
		group_by = v
		_warn_on_parse_error(v, GROUP_BY_INPUTS, "group_by")
## Whether a viewer reads a row's count ([method count_visible]): a boolean
## [Expression] over [constant VISIBLE_IF_INPUTS]. Empty means every viewer
## reads it. Inputs: the row's [b]camp_id[/b] / [b]applier_id[/b] (as
## [member group_by]'s), plus [b]viewer_camp_id[/b] (StringName) and
## [b]viewer_id[/b] (int) — e.g. `camp_id == viewer_camp_id`.
@export_multiline var visible_if: String = "":
	set(v):
		visible_if = v
		_warn_on_parse_error(v, VISIBLE_IF_INPUTS, "visible_if")

const GROUP_BY_INPUTS: PackedStringArray = ["camp_id", "applier_id"]
const VISIBLE_IF_INPUTS: PackedStringArray = ["camp_id", "applier_id", "viewer_camp_id", "viewer_id"]

var _group_expr: Expression = null
var _group_text: String = ""
var _visible_expr: Expression = null
var _visible_text: String = ""


## The key a landing by [param camp_id] / [param applier_id] files its row
## under ([member group_by]). `true` for an empty expression. `null` means
## REFUSED — a parse or run error, `false`, or a non-bool/int/StringName
## result — after a `push_error`; the caller's apply is then a no-op.
func group_key(camp_id: StringName, applier_id: int) -> Variant:
	if group_by.strip_edges().is_empty():
		return true
	if _group_expr == null or _group_text != group_by:
		_group_expr = _compile(group_by, GROUP_BY_INPUTS)
		_group_text = group_by
	if _group_expr == null:
		push_error("StatusDef %s: group_by '%s' does not parse" % [id, group_by])
		return null
	var key: Variant = _group_expr.execute([camp_id, applier_id], null, false)
	if _group_expr.has_execute_failed():
		push_error("StatusDef %s: group_by '%s' failed: %s" % [id, group_by, _group_expr.get_error_text()])
		return null
	if typeof(key) == TYPE_STRING:
		key = StringName(key)
	if key is bool and key == false:
		push_error("StatusDef %s: group_by evaluated to false — independent rows are not built" % id)
		return null
	if not (key is bool or key is int or key is StringName):
		push_error("StatusDef %s: group_by key %s is not a bool/int/StringName" % [id, key])
		return null
	return key


## Whether a viewer of camp [param viewer_camp_id] / entity [param viewer_id]
## reads [param row]'s count ([member visible_if]). Empty → always; a parse or
## run error → hidden, after a `push_error`.
func count_visible(row: NodeStatus, viewer_camp_id: StringName, viewer_id: int) -> bool:
	if visible_if.strip_edges().is_empty():
		return true
	if row == null:
		return false
	if _visible_expr == null or _visible_text != visible_if:
		_visible_expr = _compile(visible_if, VISIBLE_IF_INPUTS)
		_visible_text = visible_if
	if _visible_expr == null:
		push_error("StatusDef %s: visible_if '%s' does not parse" % [id, visible_if])
		return false
	var seen: Variant = _visible_expr.execute(
			[row.camp_id, row.applier_id, viewer_camp_id, viewer_id], null, false)
	if _visible_expr.has_execute_failed():
		push_error("StatusDef %s: visible_if '%s' failed: %s" % [id, visible_if, _visible_expr.get_error_text()])
		return false
	return bool(seen)


## The error of [param text] against [param inputs], `""` when it is clean
## (or empty) — what the setters warn with and the disk sweep asserts. An
## [Expression] parses an unknown identifier fine (it reads it off the base
## instance at run time), so this also DRY-RUNS it on neutral inputs
## (`&""` for a `*camp_id`, `0` otherwise) to catch a typo'd input.
static func parse_error(text: String, inputs: PackedStringArray) -> String:
	if text.strip_edges().is_empty():
		return ""
	var e := Expression.new()
	if e.parse(text, inputs) != OK:
		return e.get_error_text()
	var dummy: Array = []
	for n in inputs:
		dummy.append(&"" if n.ends_with("camp_id") else 0)
	e.execute(dummy, null, false)
	return e.get_error_text() if e.has_execute_failed() else ""


static func _compile(text: String, inputs: PackedStringArray) -> Expression:
	var e := Expression.new()
	return e if e.parse(text, inputs) == OK else null


func _warn_on_parse_error(text: String, inputs: PackedStringArray, field: String) -> void:
	var err := parse_error(text, inputs)
	if not err.is_empty():
		push_warning("StatusDef %s: %s '%s' does not parse against %s: %s"
				% [resource_path, field, text, inputs, err])


func get_description() -> String:
	if not description.is_empty():
		return description
	var name := display_name if not display_name.is_empty() else String(id)
	if decay == null:
		return "%s (max %s)" % [name, NumFmt.num(power_max)]
	return "%s (max %s, %s)" % [name, NumFmt.num(power_max), decay.describe()]


## The stacks one hit of [param authored] power lands from an attacker with
## [param board] (the defender's resistance filters later, on the host):
## ONE read of
## [member stacks_stat_id] with [param authored] as a `base_add` overlay, so
## the stat's flats add to it and its INCREASE / MORE scale it (ADR 0029).
## Rounded HALF-UP, once, here — the row is a whole count (ADR 0032) and a tie
## goes to the attacker; the `*_stacks_per_hit` stats stay FLOAT so their read
## never truncates first. A null board, a blank id or an unknown stat answers
## [param authored], rounded the same way. The landing and the on-hit readout
## both call this, so they cannot disagree.
func stacks_per_hit(board: StatBoard, authored: float) -> float:
	if board == null or stacks_stat_id.is_empty():
		return round_half_up(authored)
	var stat: Stat = board.get_stat(stacks_stat_id)
	if stat == null:
		return round_half_up(authored)
	var bins := ModifierBins.new()
	bins.base_add = authored
	var overlays: Array[ModifierBins] = [bins]
	return round_half_up(float(stat.get_value_with(overlays)))


## The one on-hit readout line every status describer returns:
## `Applies <name> (<n> per hit<ingest>).` — [member display_name], falling back
## to [member id]; `<n>` is [method stacks_per_hit] of [param authored] on
## [param board], the fold the landing uses; [param ingest] is appended inside
## the parentheses verbatim (a [SpellAffinity] passes `"; <its ingest clause>"`).
## A [param slice] (the hit's read node) folds through [method stacks_per_hit_at]
## instead — the branch [method StatusInstance.land_on] takes — and then
## [param board] is moot: the slice reads its owner's entity bins itself.
func applies_line(board: StatBoard, authored: float, ingest: String = "",
		slice: NodeCombat = null) -> String:
	var name := display_name if not display_name.is_empty() else String(id)
	var stacks := stacks_per_hit_at(slice, authored) if slice != null \
			else stacks_per_hit(board, authored)
	return "Applies %s (%s per hit%s)." % [name, NumFmt.num(stacks), ingest]


## [method stacks_per_hit] read through the attacking node's [param slice]:
## [method NodeCombat.get_local_value_with] folds the owner's entity bins, then
## the node's local bins, then [param authored] as the `base_add` overlay, then
## [param extra] (a swing's temp overlays, [member HitLanding.read_overlays]) —
## so a modifier local to that node scales only the hits it reads for. Rounded
## HALF-UP like the board form. A null slice, a blank id or a stat on neither
## board answers [param authored], rounded the same way.
func stacks_per_hit_at(slice: NodeCombat, authored: float,
		extra: Array[ModifierBins] = []) -> float:
	if slice == null or stacks_stat_id.is_empty():
		return round_half_up(authored)
	var bins := ModifierBins.new()
	bins.base_add = authored
	var overlays: Array[ModifierBins] = [bins]
	overlays.append_array(extra)
	var v: Variant = slice.get_local_value_with(stacks_stat_id, overlays)
	if v == null:
		return round_half_up(authored)
	return round_half_up(float(v))


## True when an [member incoming_modifiers] entry names [param stat_id].
func has_incoming(stat_id: StringName) -> bool:
	for m in incoming_modifiers:
		if m != null and m.stat_id == stat_id:
			return true
	return false


## [param mods] without its SET / MULTIPLY entries, each refused with a
## `push_error` — the [member incoming_modifiers] load check. A null entry (an
## inspector slot not yet filled) is kept and skipped by every reader.
func _sum_ops_only(mods: Array[StatModifier]) -> Array[StatModifier]:
	var kept: Array[StatModifier] = []
	for m in mods:
		if m != null and (m.operation == StatModifier.Operation.SET
				or m.operation == StatModifier.Operation.MULTIPLY):
			push_error("StatusDef %s: incoming modifier on %s is %s — only ADD_BASE / INCREASE / ADD_BONUS scale by power; entry ignored"
					% [id, m.stat_id, StatModifier.Operation.keys()[m.operation]])
			continue
		kept.append(m)
	return kept


## [param v] to the nearest whole, a half going UP. Float noise is snapped
## first: a value within `is_equal_approx` of a whole or of a half counts as
## it, so a true 2.5 computed as `2.4999…` still lands 3.
static func round_half_up(v: float) -> float:
	if is_equal_approx(v, roundf(v)):
		return roundf(v)
	var half := floorf(v) + 0.5
	if is_equal_approx(v, half):
		return floorf(v) + 1.0
	return floorf(v + 0.5)


## The power this status would carry after one tick's decay, per its
## [member decay] slot; [method NodeCombat.tick_statuses] and
## [method projected_damage] both read it. `0` means "removed". A null slot
## answers [param power] unchanged.
func decayed(power: float, row: NodeStatus = null) -> float:
	return power if decay == null else decay.decayed(power, row)


## Total damage this status still has in it on [param host] at [param power],
## summed over its remaining ticks under its own decay (#962, drawn by #953's
## projected-damage overlay). The base deals none, so `0`.
func projected_damage(_host, _power: float) -> float:
	return 0.0


## The damage the NEXT tick lands on [param host] from a row of [param power]
## raw stacks — the first term of [method projected_damage], resisted and
## floored exactly as it lands. The base deals none, so `0`.
func next_tick_damage(_host, _power: float) -> float:
	return 0.0


# ── Behaviour hooks — override on a subclass; the base does nothing ─────────
#
# `host` is the composing slice a [StatusHost] serves — a [NodeCombat] today,
# an [EntityCombat] once C1 of #994 lands — duck-typed to the contract listed
# on [StatusHost]: `board()`, `get_local_value`, `get_max_hp`, `heal_damage`,
# `add_local_modifier` / `remove_local_modifier`, `host`. Untyped on purpose;
# an override keeps it untyped too.

## The status was just applied (or re-applied, or cured) on [param host];
## [param power] is the resulting post-clamp power AS RESISTED by the host
## ([method StatusHost.effective_power]) — the row keeps the raw count.
func _on_applied(_host, _power: float) -> void:
	pass


## One turn tick on [param host], BEFORE decay lands: [param before] is the
## current power, [param after] what it will be once this hook returns —
## both AS RESISTED by the host ([method StatusHost.effective_power]); the
## raw row decays after this returns. Damage
## and other effects go here (poison: [method DotTick.mint]). The host may
## vanish under you (a kill cascades into `clear_statuses`); the slice tolerates
## it, so don't assume the status still exists when you return.
func _on_tick(_host, _before: float, _after: float) -> void:
	pass


## [param host] exerted: it is in a launching attack's origin set (one call per
## attack, at its first beat), or it is the entity host of a core that moved
## this turn (once per turn). Called for every row on the host; a row the hook
## removes is not resurrected, a sibling it removes is skipped.
func _on_exerted(_host) -> void:
	pass


## [param host] took a critical DAMAGE hit (any crit path; a heal never
## calls this): return the power the row KEEPS. [param power] is the RAW row
## count, not the resisted one the sibling hooks see — the caller moves the raw
## row by `kept − power` through [method StatusHost.adjust_power] (moving
## stacks, not landing them). The default keeps everything.
func _on_crit_taken(_host, power: float) -> float:
	return power


## The status left [param host] — decayed out, cured, cleared or removed.
## Fires exactly once per removal.
func _on_removed(_host) -> void:
	pass
