# Re-review 3 — elements split (#1716), the 19 issues of the fix round

Reviewer: one fresh subagent, 2026-11-11, read-only over the bodies as posted (pulled once with `gh issue view`). Bar: `FIX-BRIEF.md` (rules, shared arithmetic, the 02:43 NOTE), ADRs 0081-0091, `docs/design/elements.md` (cited sections only), `ORDER.md` / `NUMBERS.md`, `REVIEW-rulings.md`. Line numbers (`:NN`) point into the bodies as pulled; find each passage by its quoted text. Not reported: `elements.md` line ranges, drift stamps, tentative readings correctly marked tentative.

Findings T1, T2, … run across the file. Kinds: A contradiction / ownership / Blocked-by, B stale citation or quote, C untestable acceptance, D the fork NOTE, E arithmetic.

**Coverage:** read in full: #1807, #1816, and #1798's Decisions, Composition, Acceptance and NOTES. Every other body was grepped and read in sections around the writer points and the arithmetic. A second pass on #1800, #1810, #1811 and #1813 would find what greps miss.

## Cross-cutting checks (mechanical)
- **Owner quotes:** every `*"…"*` quote in the 19 bodies (195 in all) was matched against `elements.md` + `docs/adr/00*.md`, whitespace- and markup-normalised: none missing. Other double-quoted strings are labels or doc phrases, not owner quotes.
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
**T1 (A, cross-body with #1806; writer point 2).** #1798:91: "This unit ships no hop seat: a `GoOff`'s reached nodes all land in the next generation. If #1806 finds no seat for later rings, the seat is the gather's; stop and report." #1806:44: "The seat that carries the depth, and the stagger itself, are #1798's; if its contract at dispatch takes the reached set without a depth, stop and say so." Each body defers to the other, so the seam ships in neither, and #1806 acceptance 3a ("Y and W one above the hit, Z two above") cannot pass. Source: one decision, one owner (FIX-BRIEF § Rules). The reading itself is ADR 0091 §1's pass reading, tentative. **Fix (#1798):** the gather owns generations and the entry's `generation` field, so ship the seat there. A `GoOff`'s reached nodes carry a depth (default 1). The gather appends a depth-d entry at generation g + d, and admits and reads it against the terrain that generation starts from. The spend and the transfer still commit at g. One test uses a test-local `GoOff` returning a depth-2 node. A depth alone does not satisfy #1806 acceptance 3a ("with a test-local `Admits` whose second read answers 'path ends' at Y, Z takes no entry"), so the seat also carries each node's parent ring node. The gather drops a depth-d entry when every path to it runs through a node whose read said "path ends". That drop rule is the same seam as #1806's :80 fork (does the source still pay for those nodes?), so #1798 owns both. #1806 then only fills the depth and the parent from its BFS.

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
**T8 (A, with #1798).** #1808:27: "With several breakers in one generation the node is read once and releases once (tentative, not the owner's; asked of the owner)". Its NOTES name the alternative: one release per breaker, each spending the arc's Charge and adding a centre landing and copies. #1798 acceptance 6 already fixes how often an unmuted go-off fires for two same-beat arrivals at one node: "both have their go-off handed S + 2; both go off. Their spends are summed and clamped at 0". That is the owner's "a node's own go-off fires once per hit" (`elements.md` § Landing resolution; #1816's 0081 §1 item). Under #1798's rule a released arc fires once per breaking hit, so #1808's tentative "releases once" departs from the resolver's own count without saying so. The "read once" half is settled: ADR 0091 §1. **Fix:** #1808 cites ADR 0091 §1 for the one read, and says its "releases once" departs from #1798 acceptance 6's per-hit go-off count. The owner's answer goes to #1798, which owns the go-off count, and #1808 follows it. This is a spine contradiction: if the answer is "once per read", #1798 acceptance 6 changes first. Listed under F, together with which breaker's payload the release's copies carry.

Arithmetic verified. A Frozen + Shocked breaking hit takes 2 + b = 4: its own landing, b = 2 break landings, and the released arc's centre landing (ADR 0086 §1, 0090 §1, 0081 §4). Each neighbour takes 1. Two breakers take 2 + 2b = 6 beyond the centre landing, with one shatter.

## #1809 — forge
**T9 (B; writer point 8).** #1809:15: "It keeps its name for now (owner picked keeping it, 2026-11-10)." Neither `elements.md` nor an ADR carries this call. The doc's v1 spell bullet (§ Open) reads "`lightning_bolt` carries Charge (renamed, not reshaped, …)". The pick is recorded only in the handoff `BRIEF.md` item H ("(a) Keep the name lightning_bolt for now"). Quote marks were rightly dropped, but the dated call has no quotable home, and the doc says the opposite. #1809 already complies with FIX-BRIEF: it states the rule without quote marks. **Fix (doc, not the body):** the lead or the restamp pass corrects the doc's v1 bullet to "keeps its name for now (owner, 2026-11-10)", and #1809 then cites § Open.

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
2. **The hop seat.** Neither body ships it (T1). #1798 must carry it: it owns generations and the entry's `generation` field. #1806's description (depth 1 to L from `nodes_within`, a copy d generations after the arrival) is enough to build once #1798 states the entry rule: generation g + d, a parent ring node, the drop rule behind a "path ends" node, admission against that generation's start, and spend and transfer at g. Depth alone is not enough.
3. **The `light` flag.** Resolved in #1793, whose acceptance 2 no longer pins "only Burning". The stale piece is #1805 acceptance 3c's re-point clause (T7).
4. **The goo order.** Confirmed: #1810 states no goo order. The goo's 2 is today's `explosive.tres` value, and #1801 should say so (T4).
5. **`terrain_changed`.** No finding. #1796 and #1805 carry a matched add-if-absent clause, #1796 owns the spec, and ORDER gives no edge between them.
6. **D + d.** #1807 is consistent with ADR 0086 §2 and #1798:41 (every go-off entry lands damage × s + own damage). #1798:42's raw-amount definition is the body that omits the own damage (T2).
7. **The clamp order.** Confirmed stale in #1814:77 (T11). #1809 leaves the order open throughout.
8. **The name.** "Keeps its name (owner, 2026-11-10)" is sourced only in `BRIEF.md` H. The doc's "renamed, not reshaped" contradicts it and is the stale side. The only fix is that doc correction (T9); #1809 already complies.
9. **"Per beat".** Confirmed stale in #1801:38 (T5). The seat runs at every commit, twice per generation.
10. **The lone node.** Both bodies agree the law is the owner's (ADR 0081 §1) and that go-off zero keeps today's lone-node spend as a tentative interim. #1798 is ambiguous about whether the base `GoOff` or the gather enforces "0 reached, no go-off" (T3). Fix in #1798, so that #1799's stop clause never fires.

## Second pass (#1800, #1810, #1811, #1813)

Reviewer: a second fresh subagent, 2026-11-11, read-only. The four bodies were pulled at 03:13 UTC and read in full. Sibling bodies were read by grep only, where a cross-body check needed them: #1793, #1798, #1799, #1801, #1806, #1807, #1809 and #1812. #1798 and #1801 were being edited in parallel, so any line cited from them is as pulled. The bar, format and exclusions are the first pass's. T1-T11 are not repeated. Line numbers (`:NN`) point into the bodies as pulled.

**Checked and clean on all four:**
- Blocked-by and Blocks match `ORDER.md`.
- D: the NOTE is on #1813, which cites the flat breaker, and on none of the other three, which do not cite it.
- The ADR § citations hold: 0081 §7, 0084 §2/§3/§4/§8, 0086 §1-§5, 0083 §2 (its post-rider read), 0090 §1 and 0091 §1-§4.
- Arithmetic, against 0086 §1 / §3, 0090 §1 and 0091:
  - #1800: acceptance 1, 3b, 3c, 4, 5, 5b and 5c. The radii are 4R / 6R / 8R, 2R → 8R. C takes 2, N takes 1, C's Heat moves by h − 1. The chain is 6R / 4R / 9.8R. The dual reach gives 2, or 3 with the flag on.
  - #1810: acceptance 2 (n, 2n, 2n).
  - #1813: acceptance 1, 3, 4b and 5. ×2.5 / ×4 and ceil(7.5) = 8. 4b gives 8D / 4D, and 12D / 8D / 4D / 4D; #1806's arc returns own damage 0, so 4b needs no second zeroing. 5 gives 3 landings, 12D and one burst of (e + 6 × knob).
- The ammo orders 3 / 4 / 6 collide with no existing type: explosive 2, greed 5, sunder 10 and so on.

**Not findings:**
- #1800:37 sets the overflow band's travel "unless #1793 already authors it so", and #1793:18 does author it. The contingency resolves to doing nothing.
- #1800:42's mark fallback to the band below matches #1798:45 and its acceptance 11.
- #1813's "§ What breaks the ice" is the bold lead at `elements.md` "**What breaks the ice**". Its no-holder call is there.

### #1800 — burning
**T12 (A/C, with #1799).** #1800:37: "If the disc subclass hard-codes go-off zero's power, the power read becomes the subclass's one override point. No second disc class." Files touched (:47): "the disc `GoOff` subclass (created by #1799): a power source seam, if it lacks one."
- #1799:27 makes only two reads swappable, power and radius. Its spend is fixed at "`spend_of(load, present)`" and its own damage at "0".
- Burning's instance differs from go-off zero's in four reads:
  - power: the excess.
  - radius: `disc_radius`.
  - spend: 1 Heat per node reached (:39, acceptance 1).
  - own damage: `damage_per_power` × power (:32, acceptance 3c).
- On the class as #1799 builds it, Burning's instance would spend `spend_of(0, 0)` and deal no own damage. Acceptance 1, 3 and 3c would fail, and no body owns the two missing seams (one decision, one owner; FIX-BRIEF § Rules).

**Fix (#1800):** in Composition and Files touched, name all four per-instance reads it sets or adds on `DiscGoOff`, including a `damage_per_power` export that go-off zero's instance leaves at 0 and a swappable spend whose go-off-zero value is `spend_of`, and drop "one override point".

### #1810 — quiver
**T13 (C).** Acceptance 1: "`:52-58`'s "carries its own status" becomes "carries its own status, or a member status of its element" for the three element types only". Composition :25 builds each type with "one `ApplyStatusEffect` of its terrain status (Heat / Cold / Charge, #1793)". A "member status" admits any member of the element: #1793's Element Matrix lists Frostbite beside Cold, and `ElementRoster.for_status` answers membership. The pin would therefore pass an `ice` arrow carrying Frostbite.

**Fix (#1810):** pin "carries its element's `terrain` status (#1793's `Element.terrain`)".

(Not numbered: #1810:24's "#1807 points here for it" has no matching line in #1807, which carries only the Blocks edge. Harmless.)

### #1811 — forge-ui
**T14 (A, with #1800).** #1800:41: "the forge readout's own lookup (`ui/hud/command_tray/bodies/readout_lines.gd:113`) is #1811's and is untouched here." Today that lookup is `ReadoutLines.status_of`, which returns `StatusRoster.shared().by_concept(id)`, so it gives null for `fire`, `ice` and `lightning`. #1811:31 needs it: "The ride line names the terrain it plants (Heat / Cold / Charge)". Acceptance 1 needs it too. #1811 never names the lookup, in Composition, Files touched or acceptance. This is a seam #1800 hands over that #1811 does not ship.

**Fix (#1811):** Composition and acceptance 1 route `ReadoutLines.status_of` through the row's `AspectIntake.status()` (#1800's resolver), so that a forged ride, and an element row with `plants` unset, name the element's terrain.

**T15 (A, with #1809 and #1813).** #1811:27: "A spell refusing a shape, and its reason, are #1812's and #1813's (#1809 NOTES); this unit greys nothing in the shape socket on that account, so until they land every element with a count is offered there". Acceptance 3 says the same. The bodies disagree in two places:
- #1809:69 gives the refusal to one owner: "a spell refusing a shape (an Ice row with gain 0) are #1813's alone". #1812 has no refusal.
- "Until they land" promises a shape-socket grey-out that no body ships. #1813 touches only `readout_lines.gd` and `crucible_readout_line.gd`, not `infusion_sockets.gd` or `infusion_choices.gd`, and has no socket item.

**Fix:** #1811:27 and acceptance 3 say the shape refusal is #1813's alone. Then either #1813 adds the shape socket's grey-out of a refused Ice (`infusion_choices.gd` plus one socket test), or #1811 drops "until they land" and says the readout's refusal line is the only signal. The lead picks which.

### #1813 — ice-cast
**T16 (B, and a seam no body owns; with #1809 and #1811).** #1813:29: "an `AspectIntake` on Ice whose `use` is a `ConcentrateUse` (rows key on the use they run, #1793)". #1793 builds no such keying: its :15 says "This unit adds only the field" (`plants`). #1800:79 leaves the walk over two rows of one concept unbuilt. Today `Infusion.intake_of` and `ratio_of` / `rate_of` (`infusion.gd:50-86`) answer for the first row whose `aspect_id()` is the bare concept.
- #1813:33 authors a refusing Ice shape row (`affinity_gain` 0) on every def with `max_hops` 0 or `inf`.
- #1811:27 greys a ride by `Infusion.rate_of(spell, id) <= 0`.
- #1809:36's `aspect_overrun()` counts "every ride point on an element the spell refuses (rate 0)".

So once #1813 lands, `trail_blazer` and every 0-hop def refuse a Cold ride. That breaks `elements.md` § Ice on a cast ("a Cold ride still plants Cold"; rows "key on the status or use they run, never on the bare element"). The tests as written still pass: #1811's acceptance 3 and #1813's acceptance 2 and 6 use test or refusing rows and never forge a Cold ride on a refusing def. The behaviour breaks only in play.

**Fix (#1813):** #1813 adds the second kind of Ice row, so it owns telling the two apart. It splits the rate reads so that the ride refusal #1809 and #1811 test reads only plant rows and the shape's rate and refusal read only the concentrate row. One way is a use-kind argument on `intake_of` / `ratio_of` / `rate_of`. It adds an acceptance item that a 0-hop def still takes a Cold ride, and drops the #1793 pointer.

**T17 (A/E, with #1807; the T2 gap restated here).**
- #1813:18: "The damage breaker reads each arrival's raw amount as thrown: its stamped amount, crit included, × its load multiplier".
- #1813:35: "A copy of the concentrated payload that arrives at a Frozen node meets the damage breaker alone, at its stamped amount (×m included) × its share".

#1807 acceptance 3b reads a copy's raw amount as D + d, own damage included. ADR 0086 §2 has the copy carry the go-off's own damage. #1813 restates #1798:42's definition (as pulled, under parallel edit), which leaves the own damage out. That is T2. If #1798 takes T2's fix, #1813:35 contradicts it.

**Fix (#1813):** :35 reads "at its stamped amount (×m included) × its share, plus the go-off's own damage", matching #1798's definition once T2 lands. No acceptance item moves, because 4b zeroes Burning's `damage_per_power` and the arc's own damage is 0. The NOTE covers the eventual value.

### Open forks (second pass)
| Issue | Open forks (no default) |
|---|---|
| #1800 | none |
| #1810 | none |
| #1811 | none (T15's "who greys a refused shape" is a spec gap for the lead, not an owner fork) |
| #1813 | none beyond the 02:43 damage-breaker fork (the NOTE) |

**Counted as tentative with a default, not forks:**
- #1800:
  - go-off zero's exemption: `lands_on_own_node` false, share 0.5.
  - the overflow band keeping Burning's go-off and travel.
  - the overflow mark naming the band below.
  - the Cold / Frostbite row walk left unbuilt (:79).
  - the solo-cost "at least 1" and the shape multiplier 5, both #1812's.
- #1810: `stock_cap_reloads` 2; the orders 3 / 4 / 6; no int:int rate on `AmmoType`.
- #1811: shape points left out of the capacity (ADR 0085 revisit-when; #1809's `total_points()`).
- #1813:
  - `shatter_excess_per_hop_cut` 1.0, its name and value both open but carried.
  - pass reading (1): only the seed's head carries `hops_removed`.
  - pass reading (2): several concentrated breakers add their cuts to the one burst.
  - pass reading (3): the shatter as Ice's 0D go-off.
  - the owner's three shape-reaction fields idea, "Not built here".
  - the parked identity-fields recomposition.
