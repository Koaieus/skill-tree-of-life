class_name AnnouncementRequest
extends RefCounted

## A single announcement display request routed to one of AnnouncementLayer's
## variant bands. Submit via [method AnnouncementLayer.enqueue] or
## [method AnnouncementLayer.enqueue_now].
##
## Styles are intentionally semantic, not visual ("LEVEL_UP" vs. "gold-tinted")
## so the look can evolve without touching call sites.
##
## Named [enum Kind] (not "Variant") to avoid shadowing GDScript's built-in
## [Variant] type within this class's own type hints.

enum Kind {
	TITLE,   ## Center-screen main+sub banner (turn/level/kill toasts).
	CALLOUT, ## Top-anchored single-line combat callout (melee/ranged/spell).
}

enum Style {
	DEFAULT,
	PHASE,
	LEVEL_UP,
	KILL,
	DEATH,
	MELEE,
	RANGED,
	MAGIC,
}

var kind: Kind = Kind.TITLE
var main_text: String = ""
var sub_text: String = ""
var style: Style = Style.DEFAULT
## Optional text tint overriding [member style]'s own colour. For announcements
## whose colour is DATA rather than a semantic register — the run-end winner
## banner is tinted [member Faction.color], and a camp's colour is authored per
## camp, so it can't be one more [enum Style] (#517).
##
## Fully transparent means "no override", which is the only reading a zero-alpha
## tint could have anyway. Check with [method has_tint], never `tint != ...`.
var tint: Color = Color(0, 0, 0, 0)
var stack_count: int = 1
## Optional staleness context. Key: `entity: Entity`. AnnouncementLayer drops
## the request on dequeue if a different entity is now acting.
var context: Dictionary = {}


static func make(main: String, sub: String = "", s: Style = Style.DEFAULT,
		k: Kind = Kind.TITLE) -> AnnouncementRequest:
	var r := AnnouncementRequest.new()
	r.main_text = main
	r.sub_text = sub
	r.style = s
	r.kind = k
	return r


## Same as [method make] but with an explicit text colour (see [member tint]).
## Deliberately NOT [method make_for_entity]: a camp-authored line has no acting
## entity to go stale against, and stamping one would let a turn change drop the
## banner that says the run is over.
static func make_tinted(main: String, sub: String, t: Color,
		s: Style = Style.DEFAULT, k: Kind = Kind.TITLE) -> AnnouncementRequest:
	var r := make(main, sub, s, k)
	r.tint = t
	return r


## Is [member tint] an actual override, or the transparent "unset" default?
func has_tint() -> bool:
	return tint.a > 0.0


## Same as [method make] but stamps `{entity}` into [member context] so
## AnnouncementLayer can drop the request if a different entity is acting by
## the time it dequeues.
static func make_for_entity(main: String, sub: String, s: Style, entity: Entity,
		k: Kind = Kind.TITLE) -> AnnouncementRequest:
	var r := make(main, sub, s, k)
	r.context = {&"entity": entity}
	return r


## Grouping identity for coalescing. If a newly enqueued request's key equals
## the queue tail's key, AnnouncementLayer merges it via [method absorb]
## instead of appending a second entry. Return `null` to opt out of
## coalescing entirely. Default mirrors the pre-coalescing dedup-by-drop
## behavior: identical kind/style/text never needs to display twice anyway.
func coalesce_key() -> Variant:
	return [kind, style, main_text, sub_text, tint]


## Merge `other` (a newer request that matched [method coalesce_key]) into
## `self` in place. Default just bumps the display count; override to fold
## `other`'s data into the displayed text (see [LevelUpAnnouncementRequest]).
func absorb(other: AnnouncementRequest) -> void:
	stack_count += other.stack_count
