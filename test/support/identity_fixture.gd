class_name IdentityFixture
extends RefCounted

## A throwaway [Identity] for a test def: [member StatusDef.tint],
## [member StatusDef.icon] and an identity-backed [member StatDef.tint_color]
## are read through the def's identity and never written, so a fixture that
## needs a hue hands the def one of these.
static func of(tint: Color, id := &"fixture", kind := Identity.Kind.ASPECT) -> Identity:
	var identity := Identity.new()
	identity.id = id
	identity.tint = tint
	identity.kind = kind
	return identity
