@tool
class_name Identity
extends Resource

## The one display atom of a concept (poison, strength, a spell, an addon):
## its noun, kind, hue and glyph. Every facet of the concept — its stats, its
## [StatusDef], its spells and addons — references the same `.tres` under
## `identity/defs/`, so a hue or icon changes in one place. Owns nothing else.

enum Kind { ASPECT, ATTRIBUTE, VITAL, SPELL, ADDON }

@export var id: StringName = &""
## The concept's noun as shown to the player ("Poison").
@export var noun: String = ""
@export var kind: Kind = Kind.ASPECT
## The concept hue, unlifted (≤ 1.0, never a tier) — presenters lift it
## through [code]Emissive.at[/code].
@export var tint: Color = Color.WHITE
## The concept glyph; null → consumers show the noun's first letter.
@export var icon: Texture2D = null
