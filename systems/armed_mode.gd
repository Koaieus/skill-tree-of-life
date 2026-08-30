class_name ArmedMode
extends RefCounted

## One level of PlayerInputController's pop stack (#404's shared arm/pop
## primitive, generalized #406). Priority is array order in
## PlayerInputController._armed_modes — earlier entries pop before later
## ones, which is how nesting is expressed (e.g. a temp-upgrade arm sits on
## top of an attack plan and must pop first). Duck-typed, not a true
## interface — GDScript has none; subclasses override the methods they need.

func is_armed() -> bool:
	return false


## Pop one level. Returns true if anything changed.
func pop() -> bool:
	return false


## The identity colour this level lends to the viewport armed-mode glow
## (#412), or a transparent colour for "this level shows no glow".
##
## Only [AttackPlanArmedMode] overrides this today — **owner call 2026-08-21:**
## "in Manage mode: no outline". Every other level (Manage verbs, core-move,
## temp-upgrade, mass-action) deliberately contributes nothing, so the
## highlight-ring language doesn't gain colours ahead of the design pass
## `docs/FOCUS.md` already reserves for it.
##
## Read by [method PlayerInputController.get_armed_tint], which walks the stack
## **base-first** — see its docstring for why that isn't the pop order.
func tint() -> Color:
	return Color.TRANSPARENT


## The badge this level puts on the cursor (#664), or `null` for "this level
## contributes nothing".
##
## The SECOND presentation channel, and deliberately not a duplicate of
## [method tint]. The two answer different questions in different parts of the
## visual field: the border glow is peripheral and says *what am I wielding*,
## the cursor badge is foveal and says *what does my next click do*. That is
## why [method PlayerInputController.get_armed_icon] walks the stack from the
## TOP while [method PlayerInputController.get_armed_tint] walks it from the
## BASE — see that method's docstring. Do not "fix" them into agreement.
##
## `null` means *keep walking*, never *blank the badge* — the same fall-through
## rule [method tint] documents above, so a level with no icon can never mask
## one beneath it.
##
## The implicit rule the whole channel rests on: **a badge is present iff your
## click is modal.** Plain allocate is deliberately not an [ArmedMode]
## (see [ManageArmedMode]), so it has no badge — never add one, or a rule the
## player learns for free is lost.
func icon() -> Texture2D:
	return null


## The colour [method icon] is modulated with, or a transparent colour for
## "no opinion, draw it white".
##
## Read off the SAME level [method icon] came from — never a second independent
## walk of the stack. One level supplies both halves, so a badge can never show
## one mode's glyph in another mode's colour.
##
## Returned UNLIFTED, exactly as [method tint] is: "which hue" is a rule of the
## game, "how loud it burns" belongs to [ArmedModeIcon].
func icon_tint() -> Color:
	return Color.TRANSPARENT
