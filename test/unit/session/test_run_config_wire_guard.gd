extends GutTest

## #641 acceptance 7 — the PERMANENT fix for #597's named trap: "a new
## `@export var preset` that `to_dict` never learned about crosses as nothing,
## and the client silently generates from a null preset. It does not show up
## in a single-process suite." Acceptance 3 catches that for `scenario`, this
## one time; this walks EVERY script variable [RunConfig] declares and fails
## if any of them is neither a `to_dict()` key nor on the deny-list below — so
## the guard cannot go stale the next time a field is added (#642's
## `overrides`, #638's third slot).
##
## [b]A guard, not a reflection-generated codec.[/b] A hand-written `to_dict`
## keeps the freedom to deliberately exclude a field, and this repo relies on
## that: `command/command.gd` keeps `pre_fingerprint` and `intent_id`
## deliberately off the wire in some states. A reflection encoder would start
## transmitting exactly those. This test only checks that every field made a
## DECISION — wire or deny-listed — never which decision.
##
## [b]STORAGE && SCRIPT_VARIABLE, not STORAGE alone.[/b] STORAGE alone drags in
## `resource_name`, `resource_local_to_scene` and `script` from base
## [Resource]. `autoload/settings.gd`'s `exported_keys()` already applies
## exactly this pair of checks; copied here as the precedent.

## Starts EMPTY. Every future entry must carry a comment saying why that field
## must not cross the wire — same discipline `command/command.gd` documents
## for `pre_fingerprint` / `intent_id`.
const _DENY_LIST: Dictionary = {}


func test_every_script_variable_is_on_the_wire_or_explicitly_denied() -> void:
	var cfg := RunConfig.new()
	var wire_keys: Array = cfg.to_dict().keys()

	for prop in cfg.get_property_list():
		if (prop.usage as int) & PROPERTY_USAGE_STORAGE == 0:
			continue
		if (prop.usage as int) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var field_name: String = prop.name
		assert_true(wire_keys.has(field_name) or _DENY_LIST.has(field_name),
				("'%s' is a RunConfig script variable that is neither a to_dict() "
				+ "key nor on the deny-list — #597's silent-null trap: decide "
				+ "whether it should cross the wire and add it to "
				+ "to_dict()/from_dict(), or add it to the deny-list with a "
				+ "comment saying why not") % field_name)
