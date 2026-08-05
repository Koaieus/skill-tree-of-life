class_name FanAnimation
extends Resource

## Tooltip V2 (#234) — the self-contained idle-loop settings for one fan
## element. A plain knob bag: [FanTrace] reads [member period] +
## [member pulse_scale], [FanPanel] reads [member period] +
## [member float_amplitude] + [member glow_amplitude]; whichever of the two is
## not yours is simply ignored. It is a settings object, not an animator — the
## tween choreography stays in the components, which is what lets them keep the
## constant-brightness rule structural (idle only ever adds above the settled
## floor, and [method FanTrace.play_out] / [method FanPanel.play_out] kill the
## loop before the fade reads from it).
##
## The RESOURCE is the unit of swap and of removal: assign a different `.tres`
## to change the idle style, set the export to `null` to turn idle off — the
## "way to turn it off" #234's reopen asked for. Nothing in the shipped fan
## assigns one (off by default, opt-in per unit); two ready-made examples ship
## alongside this class for that.
##
## Name is deliberately general — `FanAnimation` rather than `IdleAnimation` —
## because traces and panels share one fan lifecycle (animate in → idle →
## animate out), so the same resource type should be able to carry whatever
## phase knobs surface later without a rename or a second class.

## Full period (seconds) of one up-and-back idle cycle. Shared meaning across
## both elements; the components floor it (>= ~0.05s) so a stray 0 can never
## spin a looped tween per-frame.
@export_range(0.05, 8.0, 0.05) var period := 1.6

## [FanTrace] only: the peak scale the settled tip pulses to, as a multiplier
## on [member FanTrace.tip_scale]. Only ever scales UP from the settled tip,
## never below — the trace's constant-brightness rule.
@export_range(1.0, 2.0, 0.01) var pulse_scale := 1.35

## [FanPanel] only: vertical bob amplitude in pixels around the panel's settled
## position.
@export_range(0.0, 12.0, 0.5) var float_amplitude := 4.0

## [FanPanel] only: how far ABOVE the settled [member FanPanel.glow] the idle
## pulse peaks — added, never subtracted, so the loop never dips below the
## steady-lit settled value.
@export_range(0.0, 0.6, 0.01) var glow_amplitude := 0.15
