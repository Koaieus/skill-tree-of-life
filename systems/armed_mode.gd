class_name ArmedMode
extends RefCounted

## One level of the seat-local [ArmedStack] (#1222): the active branch of a
## statechart, root ([ManageMode]) first. Levels live in `systems/armed/`.
## Duck-typed, not a true interface — GDScript has none; subclasses override
## the methods they need. The base constructor takes nothing, so a bare level
## can stand on a stack with no controller.

## The stack this level stands on, set on push — what [method pop_self] pops.
var stack: ArmedStack
## The controller whose player this level acts for. Null on a bare level.
var ctl: PlayerInputController


## Called before the level lands; `false` refuses the push (nothing lands).
func on_pushed() -> bool:
	return true


## Called AFTER the level has left the branch — undo this level's own writes.
func on_popped() -> void:
	pass


## A left-click walked down from the top of the branch. `true` consumes it;
## `false` falls through to the level below. A level may pop itself and still
## return `false`.
func handle_left_click(_node: SkillNode) -> bool:
	return false


## Right-click / Esc on the TOP level, before the level itself pops: retreat
## one step inside the level. `true` means it did, and the level stays.
func pop_within() -> bool:
	return false


## One of this player's own commands resolved — the level's pop policy lives
## here (Stake pops on success). Feedback stays with the controller.
func on_command_resolved(_command: Command, _success: bool) -> void:
	pass


## "Pop me": this level and everything above it.
func pop_self() -> bool:
	return stack != null and stack.pop(self)


## Handle the `ui_reload` action — "re-arm the weapon in hand". Returns true
## when this level CONSUMED the key, whether or not the re-arm succeeded: the
## armed level owns the verb, so a refusal (empty quiver, no AP) is still its
## answer and never falls through to a lower level's meaning of the same key.
## `false` means "not mine, keep walking", the same fall-through rule as
## [method icon]. Only [AttackPlanMode] answers today — ranged reloads
## the quiver, melee re-forms the last blade.
func reload() -> bool:
	return false


## The identity colour this level lends to the viewport armed-mode glow
## (#412), or a transparent colour for "this level shows no glow".
##
## Only [AttackPlanMode] overrides this today — **owner call 2026-08-21:**
## "in Manage mode: no outline". Every other level (Manage verbs, core-move,
## temp-upgrade, mass-action) deliberately contributes nothing, so the
## highlight-ring language doesn't gain colours ahead of a design pass.
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
## click is modal.** Plain allocate is the root [ManageMode] and
## contributes nothing, so it has no badge — never add one, or a rule the
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
