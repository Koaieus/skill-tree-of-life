# Review 2: the 17 bodies changed in the review round (#1716)

Scope: the bodies in `git diff --name-only 041ea86a HEAD -- docs/handoffs/elements-split/`, minus `ROUND-REPORTS.md` and `STATE.md`. Line ranges into `elements.md` and drift stamps are not reviewed. Line numbers are in the current files. "Doc" means `docs/design/elements.md` § Landing resolution unless another section is named.

Checked and clean, so not listed below:
- In the nine arithmetic bodies (resolver, go-off-zero, burning, lightning, pairs, cast-shapes, ice-cast, ice, catalyst), every Blocked-by and Blocks line names the units ORDER.md gives (ice.md's wording is R16).
- No acceptance item reaches past its unit's blockers: pairs 5 now uses a direct terrain write (F7), cast-shapes 7 is behind forge, lightning 9 is behind terrain-ui, and ice-cast 4b is behind ice.
- None of those bodies says "Closes" for #1660, #1695, #1696 or #1765.

## Whole-hit arithmetic, diffed across the bodies

The rule agrees across all nine bodies, with two departures: go-off zero's tentative exemption (R19) and burning's "every rider" on a node both reaches hit (R3).

The counts I checked:

| body | items | counts |
|---|---|---|
| resolver.md | acc 8 | H takes 2 with one band, 3 with both; N2 takes 2; terrain riders once |
| burning.md | acc 3b | C takes 2, N takes 1; Heat moves by h − 1 |
| lightning.md | acc 1b and 5 | X takes 2, each leaf 1; a Burning-and-Shocked node takes 3 |
| pairs.md | acc 2, 2b, 3, 4, 6 | 2, 3, 2 and 1 as the rule gives; terrain riders once |
| cast-shapes.md | acc 2-9 | an unprimed seed takes 1; another element's go-off makes it 2; a same-element add-up makes it 2 (tentative); a node both reach takes 2 |
| ice-cast.md | acc 4b | seed 8D with one channel, 12D with two; each neighbour 4D; X 8D |
| ice.md | acc 3b | H takes 3; F takes 2 or 0; Heat once |
| catalyst.md | acc 3 | the hit node takes 2; a centre landing converts nothing |

Every body marks the A39 same-element reading as tentative and quotes "a shape alone is not a channel" as the owner's.

## resolver.md

R1. resolver.md:77 (and the contract at :35) reads: "#{ice} adds the burst to the second `Admits` answer and the gather lands it in stage two. This unit ships no burst field." ice.md:34 sends that seat back ("is #{resolver}'s; if none exists at dispatch, stop"), and F1 gives ice no gather code, so no unit writes it. Fix: per F1, resolver.md's second `Admits` answer returns a burst amount beside the break spend, which the gather lands in stage two through `DotTick.mint`, with an acceptance item to match.

## go-off-zero.md

R2. go-off-zero.md:28 and :35 read "If #{resolver} left no such seat, this unit adds one `@export var lands_on_own_node`" and "`elements/go_off.gd` only if #{resolver} left no centre-copy switch". resolver.md:26 and acc 2 now own the knob. Fix: point at resolver's `GoOff.lands_on_own_node`, author it `false` on the Explosive disc, and drop the fallback and its Files-touched clause.

## burning.md

R3. burning.md:19 reads "each landing everything at its share", and burning.md:53 (acc 5) reads "each with every rider and its damage". Stage one's once-per-node-per-hit cap and the whole-hit paragraph ("Terrain riders still land once per node per hit") forbid this. resolver acc 8, lightning acc 5 and pairs acc 6 all follow the cap; the doc's older "Dual reach" sentence is where "every rider" came from. Fix: in both lines, the second entry carries damage and aspect riders only, and its Heat / Cold / Charge land once.

R4. burning.md:53 (acc 5) reads "the hit node's total is 1 + 1 per channel …, with go-off zero's disc counted as #{go-off-zero} answers for its own centre (1 + 2 if it lands there too)". That is a conditional, not an assertable number. Fix: assert 2 under go-off zero's carried reading (`lands_on_own_node` false on the Explosive disc) and move the 1 + 2 alternative to NOTES.

R5. burning.md:51 (acc 3b) reads "lands 2 landings on C (each with damage D and Poison p)", then asks for a separate test that "C's centre landing also carries the own damage". At the default `damage_per_power` of 2.0 the first clause is false under resolver.md:34 and acc 2. Fix: zero `damage_per_power` in the main 3b fixture (as pairs.md:34 and ice-cast 4b do) and keep the own-damage assertion in the separate test only.

R6. burning.md:14, :19, :21, :32, :54, :64, :67 use bare placeholders ("({fire})", "{cast-shapes}'s"), which substitution turns into plain numbers instead of issue links. Fix: write `#{fire}` and `#{cast-shapes}`.

R7. burning.md:9 quotes *"option 1 but spare no drones, split if needed"*. That quote is in `docs/handoffs/elements.md`, not the design doc (WRITER-BRIEF:16). Fix: drop the quote marks and state it as the owner's dated split call.

## lightning.md

R8. lightning.md:40 reads "has no seat among #{resolver}'s four returns … `EdgeGoOff` answers it as one more fact beside the four". This is stale: resolver.md:34 now says "The spend return also says where the spent stacks go … the seat for Lightning's Charge transfer". Fix: point at resolver's spend-return seat and drop the fifth answer.

R9. lightning.md:20 says a visited node "still gains the stack though it takes no new entry", and lightning.md:54 says "C included though #{resolver}'s once-per-node set gives it no new entry". resolver.md:30, :34 and acc 7 say the opposite ("The returning copy on H is one more entry, carrying damage and aspect riders only"). Fix: say a visited node takes a payload entry per arc that reaches it, and no land or read. (This follows resolver, which owns the gather and reads the doc's "concatenated, not deduplicated" that way. The doc never says it in so many words, so if resolver is overruled this becomes a gap.)

R10. lightning.md:25 quotes *"i forgot i designed that as a feature …"* and *"i agree with that lean."*. Both are in `docs/handoffs/elements.md`, not the design doc. Fix: drop the quote marks and state them as the owner's dated calls.

## pairs.md

R11. pairs.md:42 (acc 6b) reads "places it so its own disc reaches only one fresh enemy node … spends Heat once, for the one node its disc reaches". Under resolver.md:34 and acc 7 a disc's spend and entries count visited nodes too. A 4R-minimum disc on a node inside the hit node's disc normally reaches the hit node back, which makes the spend 2 and adds an entry there. Fix: require the neighbour's disc to reach exactly one node in all, with the hit node outside it (the hit node's excess above the neighbour's, the distance between their radii).

R12. pairs.md:8 quotes *"option 1. or whichever fits a DAG."*, which is in `docs/handoffs/elements.md`, not the design doc. Fix: drop the quote marks and state it as the owner's dated split call.

## ice.md

R13. ice.md:80 reads "keeps the shatter's excess an input that can be added to (one number the burst and the spend read)". The doc (§ Ice on a cast) has only "the burst reads excess + hops removed × a knob", and ice-cast.md:30 says "It adds nothing to the Cold removed". Fix: make the burst's excess the addable input, and let the spend read the node's own excess only.

R14. ice.md:3 reads "Blocked by: #{blade-elements} (and through it #{refresh}, #{defs}, … #{catalyst-blade})". ORDER.md:17 names one blocker, and a clerk reading this line can set ten. Fix: keep only `#{blade-elements}` on the Blocked-by line and move the transitive list to prose.

R15. ice.md:83 quotes *"option 1 seems best"*, which is in `BRIEF.md`, not the design doc. Fix: drop the quote marks and state it as the owner's dated pick.

## ice-cast.md

R16. ice-cast.md:30 says "The seed landing carries hops removed as a fact into #{resolver}'s gather". But resolver.md:35 hands `Admits` only "crit and damage facts", resolver.md:38 ships "No shape argument, field or test", and Files touched (:37-:41) names neither the gather nor `hit_landing.gd`. Fix: name the seat (the head's `HitLanding`, handed to `Admits`' second read) and list the gather class and `hit_landing.gd` under Files touched, as cast-shapes.md:44 does.

R17. ice-cast.md:65 quotes *"thinking of breaking spells down by their 4~5 identity fields …"*, which is in `docs/design/spells.md`, not `elements.md`. Fix: cite `docs/design/spells.md` as the source.

## catalyst.md

R18. catalyst.md:17 (*"… spare no drones …"*) and :98 (*"btw infusing Firecracker with Catalyst naturally makes it more effective!"*) quote `docs/handoffs/elements.md`, not the design doc. Fix: drop the quote marks and state them as the owner's dated calls.

## owner (the doc does not decide)

R19. GAP (owner): does go-off zero follow "Every landing is a whole hit"? go-off-zero.md:13 and :62 and resolver.md:26 carry an exemption until the retag: share 0.5, no centre copy. Under it a node with Explosive charges and Burning sends out two channels but its hit node takes 2, the one exception to the shared rule. burning.md (R4) and catalyst.md:35 wait on the answer.

R20. GAP (owner): is a centre copy asked at the admit step? pairs.md:54 reads "`admits` is not asked of it", ice.md:13 and :36 read "a centre copy … is a copy too", and resolver.md:35 is silent. It matters only below share 1 or on a release by a blade's weight touch. Once ruled, resolver.md states it.

R21. GAP (owner): what happens to transferred Charge sent to a Frozen node that absorbs the copy? pairs.md:24 and acc 4 (:39) void it with "no new code". resolver.md:34 and acc 7, and lightning.md:20, commit it with the source's spend, as spend rather than rider, before the next generation's admit, so pairs acc 4 fails against resolver as specified. The doc's pass reading ("treated exactly like the Charge rider an arc copy lands") leans toward pairs. Whichever reading stands, resolver.md writes the line.

R22. GAP (owner): does `dedupe_dual_reach = true` merge the hit node's centre copies (3 → 2)? resolver.md acc 8 asserts 2 (tentative), and pairs.md:53 leaves it unasserted.

R23. GAP (owner): does a centre copy carry the go-off's own damage? resolver.md:34 and burning.md:33 carry yes (tentative); the doc says only "one more payload".

## Round-report contradictions: do they still hold?

- Resolver's contract vs the Charge transfer seat: resolver.md is fixed, but lightning.md:40 is stale. Still holds (R8).
- Burning or lightning landing terrain riders twice on a node both reach: lightning is fixed (acc 5); burning still does. Still holds (R3).
- Resolver acc "seed once": fixed (resolver.md:22, acc 8).
- Go-off zero's exemption vs burning's hit node (1 + 1 vs 1 + 2): burning now defers, but untestably (R4). The underlying question is R19.
- Go-off zero's exemption vs catalyst's centre-test re-point: fixed (catalyst.md:35 is conditional on R19).
- Pairs says the centre landing is not asked of `admits`; ice answers it as a copy. Still holds (R20).
- Resolver has the shatter burst land in stage two, but no unit writes that line. Still holds (R1).
- ice.md's "one number the burst and the spend read" vs ice-cast adding the hops cut to the burst only. Still holds (R13).
- ice.md's "cold arrow" pointer: fixed (ice.md:83, "#{quiver}").

## The eight smaller bodies (sub-reviewer, merged by the lead; S-numbers)
- applier.md: none.
- defs.md — S1 :15 "rekeying the forge budget belongs to #{forge}": forge.md:19 and burning.md:23 keep the budget keyed by concept; drop the pointer. S2 :24-25 "Knobs: none." then "Keep it a knob.": pick one. S3 :32 `Element.decay_per_world_turn` (below-band rate) has no authored value or test; author 1 (owner settled it, batch 3) and assert it in acceptance 2.
- blade-elements.md — S4 :11 *"option 1 seems best"* and :50 *"also maybe easiest: tune the PBD weight?"* are not in `docs/design/elements.md` (only `docs/handoffs/elements.md:330-331`, which is deleted at the end): drop the quote marks, keep the rule.
- fire.md — S5 :15, :40 restate the radius formula and worked numbers and never name `disc_radius`: call #{burning}'s `disc_radius(power, node_radius)`, keep only the ratio test. S6 :15, :18 *"butn 1 per stack"* is not in the design doc (handoff :433): drop the quote marks. S7 :25 vision recomputes only on `terrain_band_changed`, so the light goes stale while the excess changes inside Burning: name a refresh trigger on a lit node's excess change. S8 :35 "The elements domain doc gets the burn and the light": say "appends to the doc #{defs} opens" (F12). S9 :42 acceptance 5 names no test file.
- flow.md — S10 :10 *"Same rule, linear default"*, :13 *"In the world-turn pass, with Heat/Cold"* are not in the design doc: drop the quote marks (the second as "picked …"). S11 :40 "#{resolver} calls it once per beat generation": resolver.md:30 commits through the settle routine twice per generation (rider land, then spends); state both.
- forge.md — S12 :36 "Both are ungated here … #{overqualified-casting} adds the caster gate": overqualified-casting gates only `set_ride`; say only `set_ride` is gated later. S13 units written as `` `quiver` ``, `` `forge-ui` `` (no braces): write the issue numbers. S14 :64 acceptance 11 passes with `default_value` 0: assert each count's `default_value` > 0 (starter 1).
- forge-ui.md — S15 :42 acceptance 3 tests refusal in the shape socket, which is #{cast-shapes}'s (after forge-ui): limit to the ride socket. S16 :25 stray comma after "#{overqualified-casting}'s".
- quiver.md — S17 :1, :24, :31, :38, :43 units written as `` `forge` ``, `` `forge-ui` ``, `` `blade-elements` ``: write the issue numbers. S18 :11 "mints `fire` fire arrows": the count is `fire_element`.
- terrain-ui.md — S19 :1, :3 say it blocks only #{forge-ui}; ORDER also puts #{lightning} and #{pairs} behind it (F8).
- (S20, bare `{name}` placeholders in burning.md: fixed by the lead before the re-post.)
