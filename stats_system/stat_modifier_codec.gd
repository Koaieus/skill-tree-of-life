class_name StatModifierCodec
extends RefCounted

## Tag -> concrete type dispatch for [StatModifier] and [StatFormula]
## deserialization (#522). The mirror image of [CommandCodec], for the same
## reason it exists: `CompositeStatModifier extends StatModifier` while
## `StatModifier` names `CompositeStatModifier` is a parse-time cycle in
## GDScript, and so is `LinearFormula extends StatFormula` while `StatFormula`
## names `LinearFormula`. A codec outside both inheritance chains has no cycle,
## and the per-type `to_dict` / `read_dict` pair stays on each type where it
## belongs. If you see "Could not find type CompositeStatModifier" here, that is
## the cycle talking, not a stale class cache — do not reach for
## `mise run refresh`.
##
## Encoding is the other direction and needs no dispatch at all:
## `modifier.to_dict()`.
##
## [b]The tags live here, not on the types[/b], unlike [Command]'s — because
## unlike `Command`, the base [StatModifier] and base [StatFormula] are
## themselves instantiable and so need a tag of their own, and GDScript refuses
## a subclass const that shadows its parent's. One file owning the whole wire
## vocabulary for these types is the better shape anyway.
##
## [b]Why loot needs this at all[/b] — see the wire-form note on
## [StatModifier]: the #522 owner call sends loot candidates BY VALUE rather
## than as locators into state a peer holds only partially.

const TAG_MOD: StringName = &"mod"
const TAG_COMPOSITE: StringName = &"composite"

const TAG_LINEAR: StringName = &"linear"
const TAG_RATIO: StringName = &"ratio"
const TAG_EXPRESSION: StringName = &"expression"
const TAG_THRESHOLD: StringName = &"threshold"
const TAG_SQRT: StringName = &"sqrt"


## Rebuild one modifier from its wire form. Returns null for a null/empty dict
## (a round that granted nothing is a legal payload) and warns on an unknown
## tag rather than half-building something a board would then bind.
static func from_dict(d: Variant) -> StatModifier:
	if d == null or not (d is Dictionary) or (d as Dictionary).is_empty():
		return null
	var dict: Dictionary = d
	var tag := StringName(dict.get("type", TAG_MOD))
	var m: StatModifier = null
	match tag:
		TAG_MOD:
			m = StatModifier.new()
		TAG_COMPOSITE:
			m = CompositeStatModifier.new()
		_:
			push_warning("StatModifierCodec: unknown modifier type tag '%s'" % tag)
			return null
	m.read_dict(dict)
	return m


## Rebuild a formula from its wire form, or null when there is none. Separate
## entry point rather than folded into [method from_dict] because a formula is
## a FIELD of a modifier, not a kind of one.
static func formula_from_dict(d: Variant) -> StatFormula:
	if d == null or not (d is Dictionary) or (d as Dictionary).is_empty():
		return null
	var dict: Dictionary = d
	# No default: [StatFormula] is abstract, so an untagged payload is a decode
	# error, not a bare base formula.
	var tag := StringName(dict.get("type", &""))
	var f: StatFormula = null
	match tag:
		TAG_LINEAR:
			f = LinearFormula.new()
		TAG_RATIO:
			f = RatioFormula.new()
		TAG_EXPRESSION:
			f = ExpressionFormula.new()
		TAG_THRESHOLD:
			f = ThresholdFormula.new()
		TAG_SQRT:
			f = SqrtFormula.new()
		_:
			push_warning("StatModifierCodec: unknown formula type tag '%s'" % tag)
			return null
	f.read_dict(dict)
	return f


## Encode a whole candidate list — the shape an offer travels in.
static func to_dicts(mods: Array) -> Array:
	var out: Array = []
	for m in mods:
		if m != null:
			out.append((m as StatModifier).to_dict())
	return out


## Decode a whole candidate list, dropping any entry that failed to decode.
## Typed on the way out so it can be assigned straight to an
## `Array[StatModifier]` field.
static func array_from_dicts(dicts: Variant) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	if not (dicts is Array):
		return out
	for d in (dicts as Array):
		var m := from_dict(d)
		if m != null:
			out.append(m)
	return out


## The merge key (#775): a modifier's wire form with [code]"value"[/code]
## erased — "same stat, same op, same formula" without caring how much of it.
## Shared by [method Entity.absorb_core_modifier] (does an incoming grant
## match an existing one?) and [method StatBoard.sync_register_from_wire]
## (does a register entry's key match what the wire says this stat carries?),
## so neither can drift on what "equivalent" means. The codec already defines
## the wire form this key is derived from, so it lives here rather than on
## [StatModifier] itself (out of this drone's fence — see the #775/#774
## swarm brief) or on [Stat] (same fence).
##
## Works on the ENCODED form on purpose — [method merge_key_of_dict] is the
## same erasure applied directly to a wire dict, without minting a
## [StatModifier] first, which is what a late-join reconcile needs (it is
## comparing against payload dicts, not live objects). A [CompositeStatModifier]
## candidate never merges (see [method Entity.absorb_core_modifier]) — this is
## only ever compared between plain modifiers, so no dispatch is needed here:
## a composite's `to_dict()` carries a `"children"` block and a `"composite"`
## type tag, which already fails to match a plain modifier's key with no
## special-casing.
static func merge_key(m: StatModifier) -> Dictionary:
	return merge_key_of_dict(m.to_dict())


## See [method merge_key] — the same erasure, applied to an already-encoded
## wire dict instead of a live [StatModifier].
static func merge_key_of_dict(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	out.erase("value")
	return out
