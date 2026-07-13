@tool
class_name PacifistCore
extends CoreClass

## A gambit class built entirely on unspent action points (#39, falls out of
## #152 + #156). Its innate movement and deallocation budgets are SET to 0 —
## every point of motion or reshape is *purchased* by an action point it
## declined to spend, converted to DP/MP surplus at a steep `ap_transfer_rate`.
## Attack once and you've bought that swing with a chunk of your mobility;
## attack out your whole AP bar and you're anchored.
##
## Only implementable because the #152 boost lives in `SurplusPoolStat`'s bin
## *outside* the modifier pipeline: a `SET cap = 0` pool with nonzero surplus is
## a coherent state. Had the boost been a cap modifier, the SET would eat it and
## this class would be a rock that can never move. Modifier set lives in
## pacifist_core.tres.
##
## The two cap SETs use `priority = SET_PRIORITY` so the anchor is inviolable —
## above anything a keystone or addon would plausibly author (those default to
## priority 0). Keep class-identity SETs at this tier; leave node content below it.
const SET_PRIORITY := 100
