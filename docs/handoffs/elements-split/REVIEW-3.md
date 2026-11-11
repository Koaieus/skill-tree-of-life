# Re-review 3 — elements split (#1716), the 19 issues of the fix round

Reviewer: one fresh subagent, 2026-11-11, read-only over the bodies as posted (pulled once with `gh issue view`). Bar: `FIX-BRIEF.md` (rules, shared arithmetic, the 02:43 NOTE), ADRs 0081-0091, `docs/design/elements.md` (cited sections only), `ORDER.md` / `NUMBERS.md`, `REVIEW-rulings.md`. Line numbers (`:NN`) point into the bodies as pulled; find each passage by its quoted text. Not reported: `elements.md` line ranges, drift stamps, tentative readings correctly marked tentative.

Findings T1, T2, … run across the file. Kinds: A contradiction / ownership / Blocked-by, B stale citation or quote, C untestable acceptance, D the fork NOTE, E arithmetic.

## Cross-cutting checks (mechanical)
- **Owner quotes:** every `*"…"*` quote in the 19 bodies (196 in all) was matched against `elements.md` + `docs/adr/00*.md`, whitespace- and markup-normalised: none missing. Other double-quoted strings are labels or doc phrases, not owner quotes.
- **D, the 02:43 NOTE:** present, verbatim, at the top of #1798, #1804, #1807, #1808, #1812, #1813, #1816. Each of them cites the raw amount, the threshold or the flat breaker, so none is unneeded. No body without the NOTE cites the damage breaker or the break threshold: #1795:40 ("a shatter's") and #1806:24 ("the arrival that breaks the ice sets the arc off") name only the break, not the damage breaker. **D is clean.**
- **Blocked-by / Blocks** match `ORDER.md` everywhere except #1814 (T10). #1807 does not list #1444 on its Blocks line, but its NOTES name it ("Frostbite #1444 (blocked by this)"), and the relation is a board edge: not reported.
- **"Closes" / save items:** none. (#1801:57 says "No save version moves", which is a statement, not an item.)
- **Superseded ADR §§:** every citation of 0084 §5, 0086 §6, 0083 §5, 0082 §3, 0083 §2, 0085 §4 and 0081 §7 is paired with the ADR that supersedes it, or cites only the half that still stands. No body cites 0087 for a thawing absorbed copy walking on.

## #1793 — defs
No findings. Writer point 3 resolves here: acceptance 2 now reads "Burning has `light`; no Ice or Lightning band does. (Fire's overflow band's `light` is #1805's, so this test does not pin it.)" (see T6).

## #1795 — flow
No findings. Its commit shape (:40, two commits per generation: a land batch, then a spend batch, with transferred Charge in the spend batch) is the bar for T5.

## #1796 — terrain-ui
No findings. Writer point 5: #1796:27 ("This unit adds the signal unless it already exists. … #1805 is not behind this unit") and #1805:28 ("if it is not on master at dispatch, this unit adds that one signal exactly as #1796 specifies it") are a matched contingency. #1796 owns the spec; ORDER gives no edge between them, so no blocker is owed.

## #1798 — resolver
**T1 (A, cross-body with #1806; writer point 2).** #1798:91: "This unit ships no hop seat: a `GoOff`'s reached nodes all land in the next generation. If #1806 finds no seat for later rings, the seat is the gather's; stop and report." #1806:44: "The seat that carries the depth, and the stagger itself, are #1798's; if its contract at dispatch takes the reached set without a depth, stop and say so." Each body defers to the other, so the seam ships in neither, and #1806 acceptance 3a ("Y and W one above the hit, Z two above") cannot pass. Source: one decision, one owner (FIX-BRIEF § Rules). The reading itself is ADR 0091 §1's pass reading, tentative. **Fix (#1798):** the gather owns generations and the entry's `generation` field, so ship the seat there. A `GoOff`'s reached nodes carry a depth (default 1). The gather appends a depth-d entry at generation g + d, and admits and reads it against the terrain that generation starts from. The spend and the transfer still commit at g. One test uses a test-local `GoOff` returning a depth-2 node. #1806 then only fills the depth from `nodes_within`.

**T2 (C/E; writer point 6).** #1798:42 hands the second read "its raw amount (the stamped amount with the crit already in, × its share; armor and the damage floor play no part, ADR 0091 §3)". #1798:41 lands every go-off entry at "damage × s + own damage", and #1807 acceptance 3b reads a copy's raw amount as D + d ("D < τ ≤ D + d … A's copy breaks"). #1807 agrees with #1798:41 and with ADR 0086 §2 (the centre copy carries the own damage, "as a reached node's copy does"). #1798:42's definition leaves the own damage out, and says nothing on whether the crit multiplies it. **Fix (#1798):** define a copy's raw amount as its landing's own number, stamped × crit × share + own damage, and say whether the crit multiplies the own damage. The NOTE covers the eventual value.

**T3 (A, with #1799; writer point 10).** #1798:41 puts the law in the base: "The base default is the element law: spend 1 per node reached, 0 reached means no go-off". The same line has it judged by the gather: "'0 reached, no go-off' is judged on that reach". Acceptance 2 says "a go-off reaching no other node spends nothing, makes no entry and lands no centre copy" without saying which `GoOff`. #1799:64 needs it to be the base's overridable default: "if #1798's gather enforces it at the read for every go-off, stop and report, since a lone charged node would stop spending". Both bodies agree the law is the owner's (ADR 0081 §1, ADR 0086 §1) and that go-off zero keeps today's lone-node spend as a lead interim (tentative, #1799). #1798 does not pin which side enforces it. **Fix (#1798):** say the gather commits whatever spend a `GoOff` returns, even when it reaches no node, and adds entries and the centre copy only when it reaches at least one. Acceptance 2 should test the base default (0 reached → spend 0) apart from a test-local `GoOff` that returns spend 1 with 0 reached (store −1, no entry, no centre copy).

## #1799 — go-off zero
No findings of its own. Its :27 and :64 carry the lone-node spend as a tentative lead interim with a stop clause. That clause is correct, and T3 makes #1798 meet it.

## #1800 — burning
No findings in the passages checked: the whole-hit counts at :21-22 and :73, and the 0084 §5 supersession at :22.

## #1801 — catalyst
**T4 (A; writer point 4).** #1801:18: "Arrows as ammo are #1810's (the element arrows beside the goo, and the volley order with the goo at 2)." #1810 states only the element types' orders: :18, "`order` = 3 / 4 / 6 (Heat / Charge / Cold arrows …)". The goo's 2 is today's `attack/ammo/types/explosive.tres` (`order = 2`), which #1810 never mentions. **Fix (#1801):** say the goo keeps today's `order = 2` through the retag (its own `.tres`, which this unit renames), and that only the element types' orders are #1810's.

**T5 (A, with #1795; writer point 9).** #1801:38: "The seat #1795's settle routine exposes (per beat and per world turn) reads the node's Catalyst row whenever a band crosses from inert to primed". #1795:40 commits twice in each generation of a beat: a land batch, then a spend batch. The spend batch carries an arc's transferred Charge, which can prime a reached node, and #1795's stub `SettleReader` "is called once per node in the batch". A per-beat seat would miss a crossing in a later generation, or in a spend batch. **Fix (#1801):** the seat runs at every commit of #1795's routine: both batches of every generation, and each world-turn step.

## #1804 — blade-elements
**T6 (C, cross-body with #1807 and #1798).** #1804:55: "No doc or ADR says which of those numbers is the contact's raw amount as thrown, which ADR 0091 §3's damage breaker reads in stage one. #1798 hands the damage fact to #1807's break check, and neither names the blade's. Not decided here." #1807 acceptance 8 and 8b test blade contacts with "raw damage under τ", and the body never says which number that is. Today a contact's `amount` is the `vertex_damage` coefficient, scaled by the speed curve and this unit's factor only in stage two. So 8 and 8b cannot be built as written, and the seam has no owner. The NOTE covers it: the lead's lean, crit and blade only, would remove the question. **Fix:** under ADR 0091 as it stands, #1804 (it stamps the contact) names the number it hands the gather as the contact's raw amount, for example coefficient × speed curve × factor at contact time; or the lead files the question beside the 02:43 fork. Listed under F.

## #1805 — fire
**T7 (A; writer point 3).** #1805 acceptance 3c: "#1793's roster pin "only Burning has `light`" in `test/unit/elements/test_element_roster.gd` is re-pointed to "only Fire's bands have `light`"". #1793 acceptance 2 no longer pins "only Burning": "Burning has `light`; no Ice or Lightning band does. (Fire's overflow band's `light` is #1805's, so this test does not pin it.)". The overflow band lighting (acceptance 3c, a lead call marked tentative) does not contradict #1793; only the re-point clause is stale. **Fix (#1805):** drop the re-point, and assert the overflow band's `light` in its own test, or add it to #1793's roster file as a new assertion.

## #1806 — lightning
T1 is shared with #1798; the fix is #1798's. The landing counts in acceptance 1b and 5 check out: a Burning + Shocked node hit once takes 3 (1 + 2); a node in the disc and an arc takes 2 entries with terrain once. Writer point 2's part here: #1806:44 is specified well enough once #1798 ships the seat (depth from `nodes_within`, entry generation g + d). The open fork at :80 is listed under F.

## #1807 — ice
No findings. Arithmetic verified against ADR 0086 §1 / §3, 0090 §1 and 0091:
- A plain break: 1 + `break_channels` = 3 (acceptance 3, 6, 7, 8, 8b).
- Acceptance 3b: H takes 3. Two breaking copies: F takes 2 × (1 + 2) = 6, with one shatter and a burst of 3 × fraction × M (the Cold is T + 3 after the Heat lands). The non-breaking sibling B stays absorbed.
- Acceptance 3c: P takes 3, Q takes 1, one shatter.

Writer point 1 is settled under the writer points below.

## #1808 — pairs
**T8 (A, with #1798).** #1808:27: "With several breakers in one generation the node is read once and releases once (tentative, not the owner's; asked of the owner)". Its NOTES name the alternative: one release per breaker, each spending the arc's Charge and adding a centre landing and copies. #1798 acceptance 6 already fixes how often an unmuted go-off fires for two same-beat arrivals at one node: "both have their go-off handed S + 2; both go off. Their spends are summed and clamped at 0". That is the owner's "a node's own go-off fires once per hit" (`elements.md` § Landing resolution; #1816's 0081 §1 item). Under #1798's rule a released arc fires once per breaking hit, so #1808's tentative "releases once" departs from the resolver's own count without saying so. The "read once" half is settled: ADR 0091 §1. **Fix:** #1808 cites ADR 0091 §1 for the one read, and says its "releases once" departs from #1798 acceptance 6's per-hit go-off count. The owner's answer goes to #1798, which owns the go-off count, and #1808 follows it. Listed under F, together with which breaker's payload the release's copies carry.

Arithmetic verified. A Frozen + Shocked breaking hit takes 2 + b = 4: its own landing, b = 2 break landings, and the released arc's centre landing (ADR 0086 §1, 0090 §1, 0081 §4). Each neighbour takes 1. Two breakers take 2 + 2b = 6 beyond the centre landing, with one shatter.

## #1809 — forge
**T9 (B; writer point 8).** #1809:15: "It keeps its name for now (owner picked keeping it, 2026-11-10)." Neither `elements.md` nor an ADR carries this call. The doc's v1 spell bullet (§ Open) reads "`lightning_bolt` carries Charge (renamed, not reshaped, …)". The pick is recorded only in the handoff `BRIEF.md` item H ("(a) Keep the name lightning_bolt for now"). Quote marks were rightly dropped, but the dated call has no quotable home, and the doc says the opposite. **Fix:** the lead corrects the doc's v1 bullet to "keeps its name for now (owner, 2026-11-10)", and #1809 then cites § Open. Until then #1809 cites `BRIEF.md` H and notes that the doc's word is stale.

Not a finding: the trim order is honestly left open. #1809:38 says "this unit picks none", acceptance 9 says "Which field gives way is not asserted", and NOTES :71 says "Open, asked of the owner". It is listed under F. A drone still has to give `clamp_infusion` some order when a shared element's shape + ride exceed its count, and no tentative default is named, so the fork does block Ready.

## #1810 — quiver
No findings. T4 is the pointer into this body.

## #1811 — forge-ui
No findings in the passages checked.

## #1812 — cast-shapes
No findings. The seed counts are verified:
- An unprimed shaped cast lands 1 (ADR 0086 §4).
- A same-element primed node lands 2 (0086 §5; :16, :61, :63, :64).
- A shape plus another element's go-off lands 1 + 1 (:18, :20).
- A Fire shape on a Shocked node lands 2 (:24: "the disc adds none").
- :37: 1 + one centre copy per band of another element that goes off.

## #1813 — ice-cast
No findings in the passages checked. The NOTE is present, and the raw amount ×m × share at :16, :33 and :58 is consistent with ADR 0091 §3 and #1807.

## #1814 — overqualified-casting
**T10 (A; Blocked-by).** #1814:3: "Blocked by: #1811 (same HUD files, and this unit re-points its cap read), which is behind #1809". `ORDER.md`: "{overqualified-casting} … blocked by {forge} and {forge-ui}". **Fix (#1814):** "Blocked by: #1809, #1811", with the parenthetical kept.

**T11 (A, with #1809; writer point 7).** #1814:77: "Facts, not picks: today `socket_points` walks front to back, so the front sockets fill first; #1809's `clamp_infusion` adds the ride after the aspects (tentative there)." #1809:38 says the opposite: "Which of the aspects, the ride and the shape gives way first is the forge's trim order (open; asked of the owner; ADR 0089 §4): this unit picks none". So does #1809 acceptance 9. The clause states as fact an order #1809 no longer has. **Fix (#1814):** replace it with "#1809's `clamp_infusion` picks no order; the order is this unit's `trim_to`, once the owner answers".

## #1816 — adr-fixes
No findings. The NOTE is needed: the closing line cites "The number the flat damage breaker reads is ADR 0091 §3, reopened".

## Open forks per issue (F)
Here a fork means a design call the body leaves open with no default. Every body that carries the NOTE also carries **the 02:43 damage-breaker fork**: #1798, #1804, #1807, #1808, #1812, #1813, #1816. They stay out of Ready until the owner rules on it.

| Issue | Open forks besides the 02:43 one |
|---|---|
| #1793 | none |
| #1795 | none |
| #1796 | none |
| #1798 | none of its own (T1 and T3 are spec gaps, not owner forks) |
| #1799 | none |
| #1800 | none |
| #1801 | none |
| #1804 | the blade contact's raw amount: which stamped number the damage breaker reads (:55, "Not decided here"; T6) |
| #1805 | none |
| #1806 | :80, a level-2+ arc stopping at a ring node whose path ends: does the source still pay and transfer for the nodes behind it? ("Open, not decided anywhere"; acceptance 3a asserts no spend in that run) |
| #1807 | none beyond the 02:43 one |
| #1808 | (a) several breakers in one generation: one release or one per breaker (:27, "asked of the owner"; T8); (b) which breaker's payload the release's copies carry when the breakers differ (:27, NOTES) |
| #1809 | the forge's trim order, which `clamp_infusion` needs today (:17, :38, :71; acceptance 9) |
| #1810 | none |
| #1811 | none |
| #1812 | none beyond the 02:43 one |
| #1813 | none beyond the 02:43 one |
| #1814 | the forge's trim order (:14, :36, :77) |
| #1816 | none (Backlog, docs only; its NOTE is informational) |

**Counted as tentative with a default, not forks:**
- #1793 :28, the overflow multiple of 2.
- #1798, the centre copy not asked of `Admits`; the larger `ceil(r × s)` for two shares; the burst queued after the generation's entries; the dedupe merging within a generation; the mark's id form.
- #1799, the lone-node spend, `lands_on_own_node` false, and the disc share 0.5.
- #1801, the split-then-prime reading.
- #1805 acceptance 3c, the overflow band's `light` and burn.
- #1806 and #1807, one hop per generation and the shatter as a 0D go-off.
- #1807, an absorbed copy whose Heat thaws the node walks on; a dedupe-merged arrival tested at its sum; the blade gate read before the riders.
- #1812, `shape_power_per_point` 5; shape points off the capacity; the solo-cost floor of 1.
- #1813, `shatter_excess_per_hop_cut` 1.0.

## Writer points 1-10
1. **Landings of a breaking hit.** Both bodies are right. #1807's 1 + `break_channels` = 3 is a plain Frozen node. #1808's 2 + b = 4 is a Frozen + Shocked node, where the break releases the muted arc (ADR 0081 §4) and that go-off is a channel landing one centre payload (ADR 0086 §1). #1807 points the release and its centre copy at #1808 ("A Frozen + Shocked node's mute and release, and the released go-off's centre copy, are #1808's"). No finding.
2. **The hop seat.** Neither body ships it (T1). #1798 must carry it: it owns generations and the entry's `generation` field. #1806's description (depth 1 to L from `nodes_within`, a copy d generations after the arrival) is enough to build once #1798 states the entry rule: generation g + d, admitted against that generation's start, spend and transfer at g.
3. **The `light` flag.** Resolved in #1793, whose acceptance 2 no longer pins "only Burning". The stale piece is #1805 acceptance 3c's re-point clause (T7).
4. **The goo order.** Confirmed: #1810 states no goo order. The goo's 2 is today's `explosive.tres` value, and #1801 should say so (T4).
5. **`terrain_changed`.** No finding. #1796 and #1805 carry a matched add-if-absent clause, #1796 owns the spec, and ORDER gives no edge between them.
6. **D + d.** #1807 is consistent with ADR 0086 §2 and #1798:41 (every go-off entry lands damage × s + own damage). #1798:42's raw-amount definition is the body that omits the own damage (T2).
7. **The clamp order.** Confirmed stale in #1814:77 (T11). #1809 leaves the order open throughout.
8. **The name.** "Keeps its name (owner, 2026-11-10)" is sourced only in `BRIEF.md` H. The doc's "renamed, not reshaped" contradicts it and is the stale side. A doc fix is needed (T9).
9. **"Per beat".** Confirmed stale in #1801:38 (T5). The seat runs at every commit, twice per generation.
10. **The lone node.** Both bodies agree the law is the owner's (ADR 0081 §1) and that go-off zero keeps today's lone-node spend as a tentative interim. #1798 is ambiguous about whether the base `GoOff` or the gather enforces "0 reached, no go-off" (T3). Fix in #1798, so that #1799's stop clause never fires.
