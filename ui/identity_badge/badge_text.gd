class_name BadgeText
extends RefCounted

## Authored text with `{id}` or `{id:amount}` tokens, rendered into a
## [RichTextLabel]: each token becomes the optional amount (pre-formatted by the
## composer) + a non-breaking space, the identity's badge
## ([method IdentityBadge.composite], hued by [method Emissive.at]) + a
## non-breaking space + its noun, all in the identity's hue. When the identity
## has a [ConceptCard] the whole unit sits in one `push_hint` keyed
## [method hint_of] (the badge image carries the same tooltip), so amount, badge
## and noun are one hover target — [BadgeLabel] turns that key into the card.
## Plain runs go through `append_text`, so BBCode around a token still applies
## (`[b]{poison}[/b]` is a bold badge+noun). A token resolves against
## [IdentityRoster] first, then as a stat id via its [member StatDef.identity];
## an unknown token renders verbatim and warns once per id per process.
## [method strip] is the plain-text twin for `Label`s.

const _TOKEN := "\\{([a-z_]+)(?::([^}]*))?\\}"
const _NBSP := "\u00A0"

const HINT_PREFIX := "concept:"

static var _regex: RegEx
static var _warned := {}


## Clears [param label] and fills it from [param text]. [param size_px] is the
## badge side; 0 means the label's `normal_font_size`.
static func render(label: RichTextLabel, text: String, tier := Emissive.LABEL, size_px := 0) -> void:
	label.clear()
	var size := size_px if size_px > 0 else label.get_theme_font_size(&"normal_font_size")
	var cursor := 0
	for m in _token_regex().search_all(text):
		var identity := _resolve(m.get_string(1))
		if identity == null:
			continue
		if m.get_start() > cursor:
			label.append_text(text.substr(cursor, m.get_start() - cursor))
		var hue := Emissive.at(identity.tint, tier)
		var hint := hint_of(identity)
		if not hint.is_empty():
			label.push_hint(hint)
		label.push_color(hue)
		var amount := m.get_string(2)
		if not amount.is_empty():
			label.add_text(amount + _NBSP)
		label.add_image(IdentityBadge.composite(identity, size), size, size, hue,
				INLINE_ALIGNMENT_CENTER, Rect2(), null, false, hint)
		label.add_text(_NBSP + identity.noun)
		label.pop()
		if not hint.is_empty():
			label.pop()
		cursor = m.get_end()
	if cursor < text.length():
		label.append_text(text.substr(cursor))


## [param text] with every resolvable token replaced by its noun, its amount
## (if any) and a space in front.
static func strip(text: String) -> String:
	var out := ""
	var cursor := 0
	for m in _token_regex().search_all(text):
		var identity := _resolve(m.get_string(1))
		if identity == null:
			continue
		var amount := m.get_string(2)
		out += text.substr(cursor, m.get_start() - cursor)
		out += (amount + " " if not amount.is_empty() else "") + identity.noun
		cursor = m.get_end()
	return out + text.substr(cursor)


## The hover key of [param identity]'s token — [constant HINT_PREFIX] + its id
## when it has a [ConceptCard], "" (no hint) otherwise.
static func hint_of(identity: Identity) -> String:
	return HINT_PREFIX + String(identity.id) if ConceptCard.supports(identity) else ""


## The identity a [method hint_of] key names, or null for any other text.
static func concept_of(hint: String) -> Identity:
	if not hint.begins_with(HINT_PREFIX):
		return null
	return IdentityRoster.shared().by_id(StringName(hint.trim_prefix(HINT_PREFIX)))


## Forgets which unknown ids already warned — test isolation.
static func clear_warnings() -> void:
	_warned.clear()


static func _resolve(id: String) -> Identity:
	var identity := IdentityRoster.shared().by_id(StringName(id))
	if identity == null:
		var def := StatRegistry.get_def(StringName(id))
		if def != null:
			identity = def.identity
	if identity == null and not _warned.has(id):
		_warned[id] = true
		push_warning("BadgeText: unknown token {%s}" % id)
	return identity


static func _token_regex() -> RegEx:
	if _regex == null:
		_regex = RegEx.create_from_string(_TOKEN)
	return _regex
