@tool
class_name ActionPalette
extends Resource

## The identity colour of each non-attack player ACTION — the Manage verbs, core
## movement, and the temp-upgrade addon kinds (#664). Authored once as
## `ui/theme/action_palette.tres`.
##
## [b]An extraction, not a new palette.[/b] Every value here was already
## authored, in two different homes: five inline `title_color`s on
## `manage_body.tscn`'s cards and `MeleeBody._UPGRADE_BLIP_COLORS`. #664 added a
## third consumer — the armed-mode cursor badge — and an [ArmedMode] is a
## `RefCounted` in `systems/` that must not reach into `ui/` to read a `.tscn`
## export. So the values moved HERE and the tray reads them back. Carried over
## unchanged: this was a move, not a retune. The tray card a player just clicked
## and the badge now on their cursor match for free, from one source.
##
## [b]Distinct from the stat palette, and it does NOT restate it.[/b]
## `.claude/rules/ui-palette.md` makes [member StatDef.tint_color] the single
## source of truth for attribute colours and forbids a second resource repeating
## them. Melee/Ranged/Magic are therefore deliberately ABSENT — they are
## attribute colours (STR/DEX/INT) and [AttackPlanArmedMode] reads them off
## `StatRegistry` exactly as it already did. What lives here is the set of
## actions that have no attribute behind them at all.
##
## Colours are UNLIFTED — no [Emissive] tier is applied. "Which hue" is a rule
## of the game; "how loud it burns" belongs to whatever presents it (see
## [ArmedModeIcon.glow_stops] and [ArmedModeGlow]).

## Plain allocate — the idle default click. Tray-card only: allocate is
## deliberately not an [ArmedMode], so it has no badge (see
## [ManageArmedMode]'s docs and #664's "badge ⇔ your click is modal" rule).
@export var allocate: Color = Color(0.2606, 0.6387, 0.9922, 1)

## Core movement (#21). WIS gold.
@export var move_core: Color = Color(0.9039, 0.7331, 0.2746, 1)

## Deallocate. PER purple.
@export var deallocate: Color = Color(0.6935, 0.4045, 0.9676, 1)

## Stake a node.
@export var stake: Color = Color(0.35, 0.85, 0.55, 1)

## Extract from a staked node.
@export var extract: Color = Color(0.95, 0.55, 0.35, 1)

## Clamp temp-upgrade addon — cool metal-brace blue.
@export var clamp_addon: Color = Color(0.4, 0.7, 0.95, 1)

## Spike-ring temp-upgrade addon — warm damage amber.
@export var spike_ring: Color = Color(0.95, 0.6, 0.25, 1)

## The ONE accessor. Every consumer — the tray cards, the melee blip strip, and
## the armed-mode badge — goes through this, so there is a single contract to
## keep rather than one shape per caller.
##
## Keys for the two addon entries are the [constant
## MeleeAttackPlan.TEMP_UPGRADE_CATALOG] `id`s verbatim, so a caller holding a
## catalog entry never needs a second lookup table to get from it to a colour.
## Verb keys are the lower-cased [enum PlayerInputController.ManageVerb] names,
## plus `&"move_core"` for core-move targeting, which is a mode rather than a
## verb.
##
## An unmapped key returns [constant Color.TRANSPARENT] — same fall-through
## contract as [method ArmedMode.icon_tint]: "nothing to say here", never
## "paint this blank".
func color_for(key: StringName) -> Color:
	match key:
		&"allocate": return allocate
		&"move_core": return move_core
		&"deallocate": return deallocate
		&"stake": return stake
		&"extract": return extract
		&"clamp": return clamp_addon
		&"spike_ring": return spike_ring
	return Color.TRANSPARENT
