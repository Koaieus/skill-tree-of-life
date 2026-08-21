class_name LastCampStandingCondition
extends VictoryCondition

## The first win condition, and the default (#460).
##
## **Owner call 2026-08-21:** "be the only camp that survives — no living
## hostile entities remain. **Blocker NPCs do not count**; they are inert
## scenery, not a camp that can win or lose."
##
## Inertness is authored on the faction ([member Faction.counts_for_victory]),
## resolved inside [method VictoryContext.living_camps] — so a board holding
## nothing but dormant cores is already won by whoever is left, and this class
## never mentions a faction id.
##
## Degradation is automatic, not special-cased: in single-player the player is
## the only counting camp besides the AI, so the player dying leaves the AI
## standing (a LOSS) and clearing the board leaves the player standing (a WIN).
## Zero counting camps left is a mutual wipe — a DRAW.

func evaluate(ctx: VictoryContext) -> RunOutcome:
	var alive := ctx.living_camps()
	if alive.size() > 1:
		return null
	if alive.size() == 1:
		return _outcome(ctx, alive[0])
	return _outcome(ctx, null)
