Child 4 of the #1716 elements split (design home `docs/design/elements.md` § Landing resolution; ADR 0082, with ADR 0083 for the order inside stage one): the two-stage hit resolver, gather only. Stage one gathers a hit's whole target set from terrain at land time, at each node admit / land / read; stage two lands the payload once per gathered entry. Today's explosive detonation is **not touched here**: it keeps running on its own compile-time path (`DetonateEffect`, both ledgers, the per-wave scope) until #{go-off-zero} ports it, so the game keeps its blast throughout.

Blocked by: #{defs}, #{terrain}, #{flow}, #{applier}
Blocks: #{go-off-zero}

## Acceptance spec

**Decisions** (owner, 2026-11-09 unless dated)
- Two stages: *"resolve elements first which settles the reach [as in, total set of targets] for the hit (including cascades..?) and then resolve the remainder of the hit for each target (riders, damage?)"* (`docs/design/elements.md:651-677`; ADR 0082 §1-2, its §1 pre-hit read replaced by ADR 0083 §1).
- Riders first (owner, 2026-11-10): *"first resolve terrain riders (only: heat/cold/charge) - then resolve hit reach + local reach"*. At each node of stage one the element riders land, then the node's primed states and their power are both read from the result, so the hit that tips a node over T sets it off itself (ADR 0083 §1). The steps at a node are admit / land / read (ADR 0083 Consequences). An arriving copy is admitted against the node as it arrives, and an absorbed copy lands no riders (ADR 0083 §2; the Frozen answer, its path-end and its break check are #{ice}'s).
- Unit is one hit: *"landing arrow = 1 hit (+optional reach etc) / landing blade contact = 1 hit / 1 spell WAVE = 1..N hits"*. A wave is N gathers (`:697-701`). Built at land time, not compile time (`:684-693`).
- One owner for the gather with an element callback: *"option 1 looks squeaky clean"*. An element answers *admits* and *go off* and nothing else (`:691-696`).
- Crit per arrival, at the gather head: *"option 1. does it then also do the CritCondition?"* — yes (`:706-713`). The conditions and the roll still read the node as it was before this hit, ahead of the hit's own riders (ADR 0083 §4): two read points inside one hit, on purpose.
- Per-hit once-per-node set, one terrain snapshot per beat: *"option 1. and can we make it order independent somehow?"*, then *one snapshot per beat*. Same-beat hits land their element riders as sums on the pre-beat terrain, the go-offs are read from that summed terrain, and the spends are summed and clamped at 0 (`:714-729`; ADR 0083 §5).
- One share scales the whole payload, `ceil` per rider, one knob per go-off, default 0.5 (`:730-733`; taken as settled by the pass).
- Spend law, 2026-11-08: a go-off pays *1 per node it reaches*; a disc reaching no other node does not go off; a spend digs under T (`:79-97`; ADR 0081 §1). Primed-ness and power are both read post-land (ADR 0083 §1). The gather commits the spend a go-off returns and never derives it from the count of nodes reached: a go-off a cast's shape has enlarged reaches more nodes than the node pays for (the node pays its solo cost, ADR 0084 §4; that go-off is #{cast-shapes}'s).
- Chains are flat, `damage × s` and riders `ceil(r × s)`, never `s^k` (2026-11-05, `:489-496`). A copy lands raw (#1733 R2, `:525-530`). A copy carries its parent's crit (ADR 0082 §4).
- Riders are one summed entry per status id per landing entry (`:334`). In-hit order is *"elemental riders first … then other status(es), then damage(s)"* (`:342-344`); per target the aspect riders still land before the damage (ADR 0083 §3; ADR 0067 unchanged). A hit carries 0 or 1 element (`:155-157`).
- Greed: *"i think Greed shouldn't multiply incoming Heat/Cold/Charge stacks"* (`:159-163`). Only this guard ships here.
- Dual reach (owner, 2026-11-10): *"riders twice, payload twice. charged burning nodes sounds like a dangerous concept"*. A node gathered by two reaches is two entries, and each entry lands every rider and the damage at its share. On the same call: the node's own go-off fires once per hit (owner, 2026-11-10, picked over once per gathered entry), through the once-per-node set, and the dedupe stays a one-line switch (`:770-781`). A cast's shape and a go-off of another element are two reaches under the same rule (owner, 2026-11-10, picked *same as dual reach: concatenate*; ADR 0084 §5): the seed node takes the seed once, in full, a node inside both takes one copy per reach, and the one dedupe switch covers both cases. The shape's reach itself is #{cast-shapes}'s. A go-off picks its nodes by shape alone, allocated or not, at every level (owner, 2026-11-10: *"so far just keep it shape blind always"*; `:532-542`; ADR 0084 §7); the hit's mask decides who the copies hurt.

**Knobs** (tentative, easy to change)
- `GoOff.share` = 0.5, `@export_range(0.0, 1.0, 0.05)` on the `GoOff` base. It is the share for that go-off's copies: damage × s and riders ceil(r × s).
- Dual-reach dedupe is one bool in the gather, default `false` (concatenate). It is a written call to make it a code switch with no editor surface. The owner framed it as *"just a "do you dedupe the list or not""*. The same bool decides a cast's shape against another element's go-off (ADR 0084 §5): it runs over the hit's reach lists whatever produced them, so no second switch is ever added.

**Composition**
- **The gather** (one class under `attack/outcome/`; name is the drone's) owns a hit's once-per-node set and its entry list (node, share, parent, generation, reach). Stage one runs inside #{applier}'s worklist drain, per beat. A beat is one `schedule_index` group (the group `apply` already flushes removals on); a spell wave is one beat. The beat's heads start from one pre-beat snapshot of the node's terrain ints (#{terrain}), and each node runs three steps in this order (ADR 0083 §1, §5). *Admit*: `Admits` is asked about each arrival against the terrain the generation starts from, before any of that generation's riders land; a refused copy is dropped whole, landing no rider and making no entry. *Land*: the admitted arrivals' element riders land as sums on that terrain, through #{flow}'s shared settle routine (which nets Heat × Cold). *Read*: the node's primed bands and their power are read from the summed result, never from the pre-beat snapshot, so a rider that carries a node past T sets it off in the same hit; each go-off is computed from that read and the spends are committed together through the same settle routine (summed, clamped at 0). The reached nodes form the next generation and run the same three steps on the copies' element riders (`ceil(r × s)`), starting from the terrain the previous generation left. Each primed band present at read fires its own `GoOff` and appends its own list (a reach). The lists are concatenated unless the dedupe switch is on, in which case a node in several reaches keeps one entry. The gather is the only terrain writer, and it records its terrain changes on the hit for peers to replay (ADR 0077).
- **The head** is the first hit of a landing's placed span (`HitLanding.place()`, `hit_landing.gd:137-156`). For a status-only spell landing, that is its first rider. `place()` marks it. The element riders land in stage one at the head and are skipped in stage two. Stage two is the existing compile-and-land path per entry: each copy is compiled through the landing's stamping callable (#{applier}) and pushed onto the worklist.
- **Crit.** The head decides the arrival's crit once. `_stamp_crit_conditions` moves from compile (`spell_resolver.gd:551-568`) to the head and is evaluated against the pre-hit node, before the admit / land / read steps touch it (ADR 0083 §4; the gather's own read comes after the riders, so the two differ on purpose). Every copy points at the head through `paired`, so `CritRoll.decide` copies it (`crit_roll.gd:53-62`) and a copy never re-evaluates. The crit stream then draws once per spell arrival rather than once per own hit, so a recorded fixture whose crit sequence moves is re-recorded (Acceptance 10). `paired` also makes a copy `rider_gated` by the head, as riding landings already are. If a spell copy turns out wrongly gated, stop and report it.
- **`GoOff` / `Admits`** are the empty bases #{defs} placed in `elements/`, sitting on each band. This unit gives `GoOff` its contract: given the gather's read of a node (its terrain after the generation's element riders have landed as sums, never the pre-beat snapshot; ADR 0083 §1, §5), return the spend, the nodes reached and the share. The spend and the nodes reached are two separate returns, and the gather commits the spend as returned. The base default is the element law (spend 1 per node reached, 0 reached means no go-off, a spend may dig under T; ADR 0081 §1). `Admits` gets one method, asked at the admit step about the head and about each copy, against the terrain before that generation's riders land (ADR 0083 §2), with null meaning admit-all; #{ice} supplies the answer. No concrete subclass ships here. #{go-off-zero} adds the disc (with a power source other than its own formula that #{burning} can swap in), and no element primes until #{burning}, so the gather has no live go-off on master after this unit.
- **Room for a cast's shape** (not built here; #{cast-shapes} builds it). A cast's shape adds reach in two ways, and the gather is shaped so neither needs a rewrite. A shape of another element than the node's go-off, or on an unprimed node, is a reach with no band behind it and no spend (ADR 0084 §5): the step that appends a reach's list therefore takes a list from any producer, tags its entries with their reach, and never assumes a reach has a spending band. A shape of the same element as a primed band adds into that band's one go-off (ADR 0084 §3), for which the node pays its solo cost (ADR 0084 §4): that is why the spend is its own return and is never recounted from the reached nodes. A landing a shape adds is an ordinary entry: the go-off's share, the head as `paired` parent (so the seed's crit), and it goes through `Admits` as a copy (ADR 0084 §6). The seed node is the head and is never an entry of a shape's reach. No shape argument, field or test ships in this unit.
- **The hit's element** is read from the hit's own element riders (the `Element` def #{defs} gives a rider row). The gather must not assume a cast-level `element_of` accessor: that lands with #{forge}, long after this unit. A hit with no element rider carries none.
- **Greed guard.** `StatusInstance._greed_arms` (`status_instance.gd:143-156`) doubles `debuff`-tagged rows. Heat, Cold and Charge never pass through it, neither doubled nor spending Greed.
- **Untouched here** (ported by #{go-off-zero}): `DetonateEffect`, `BlastEffect`, the `SPENT_KEY` ledger, `LiveGate._node_spent`, `HitLanding.detonated` and the per-wave scope (`spell_resolver.gd:297,336`), shrapnel's own crit roll.

**Files touched**
- `attack/outcome/outcome_applier.gd` (the drain runs stage one per beat), the new gather class, `attack/outcome/hit_landing.gd` (head mark)
- `elements/go_off.gd`, `elements/admits.gd` (contract methods; created by #{defs})
- `attack/spell/spell_resolver.gd` (crit conditions leave compile)
- `attack/outcome/status_instance.gd` (Greed guard)
- `docs/domain/attack-timeline.md` (two stages; admit / land / read at a node; head crit read before the hit's riders; beat snapshot)

**Acceptance**
1. New `test/unit/attack/test_hit_resolver.gd`, red first, with a test-local `GoOff` on a test `Element` band: a hit on a primed node gathers every reached node before any payload lands (no HP moved when stage one ends). Each entry's payload lands at `share`: damage × s and riders ceil(r × s). A second generation is flat, never s².
2. Same file: the default law. Spend equals nodes reached; a go-off reaching no other node spends nothing; a spend past the store digs under T. A test-local `GoOff` that returns spend 1 while reaching 3 nodes leaves the store down by exactly 1 and makes 3 entries (the gather commits the returned spend, it does not count the reach).
3. Same file, riders first (ADR 0083 §1). With a test band of threshold T: a hit carrying +1 of that element onto a node holding one stack short of primed goes off in that same hit, and the test `GoOff` is handed the post-land store (pre-hit store + 1), not the pre-hit one. The same hit with no element rider on the same node gathers only the head. A hit carrying +2 onto an already primed node is handed pre-hit store + 2.
4. Same file, admit (ADR 0083 §2): a test-local `Admits` that refuses a copy on node N leaves N's terrain ints unchanged by that copy's element riders and makes no entry for N; N's own go-off does not fire from it. The `Admits` call sees N's store as it was before that generation's riders landed (assert the value it is handed).
5. Same file, one beat (ADR 0083 §5): two arrivals of one beat, each carrying +1, on a node at pre-beat store S both have their go-off handed S + 2; both go off. Their spends are summed and clamped at 0. Swapping their order changes nothing (same entries, same final store).
6. Same file: a node reached twice through one go-off's chain lands once per hit (the once-per-node set). Two hits each land it.
7. Same file, dual reach: a node holding two primed test bands fires each once per hit (owner, 2026-11-10). A neighbour reached by both is two entries and takes every rider and the damage twice. With the dedupe switch on it takes one. The head's node is never an entry of either list: it takes the seed once, in full.
8. Same file: a spell arrival draws one crit (count the stream draws). A node-reading crit condition is evaluated once at the head, pre-hit, and every copy carries the head's `crit_tier`. Pre-hit means before the hit's own riders (ADR 0083 §4): a test condition reading the node's terrain store, on a hit carrying +1 of that element, is handed the pre-hit store while the same hit's `GoOff` is handed pre-hit store + 1.
9. Same file: summed riders give one entry per status id per entry. Order is element riders, then other statuses, then damage. A copy's rider never merges with the hit's own.
10. `test/unit/test_greed_landing.gd`: a Greed holder taking a Heat rider of r gets r, and its Greed row is unchanged. `test_outcome_fixture_replay.gd` and the `world_fingerprint` replays stay green, except a fixture whose spell crit sequence moved, which is re-recorded and named in the report.
11. Characterization pins, unedited: `test_explosive_charges.gd`, `test_blade_explosive.gd`, `test_blast_effect.gd`, `test_blast_mark.gd`, `test_paired_damage_effect.gd`, `test_heal_spell_blast.gd`, `test/unit/spell/test_cyclone.gd`, `test/unit/spell/test_firecracker.gd`. Detonation is unchanged by this unit. The only edit allowed is a spell crit-sequence assert moved by the per-arrival crit (Acceptance 8), named in the report.
12. `mise run check`, `mise run lint-transcendentals`, the full suite once, and `mise run mp:e2e` (the gather writes recorded terrain), all green.

**NOTES**
- A no-parent go-off (the "terrain hit": damage ∝ power, no riders, no crit, side-blind, attacker = latest applier) is a defined shape with no caller, so no unit builds it (pass ruling, 2026-11-10; `elements.md:498-503`). The handoff's "lands with 6 and 7" is stale.
- A blade vertex's copied primed state reaches the gather as a "go-off source" argument (pass pick, tentative, 2026-11-10): #{blade-elements} adds the argument, and the gather shape should leave room for it.
- Catalyst conversion on priming is read inside #{flow}'s settle seat. On a hit it is #{catalyst}'s, at the element-rider land step.
- ADR 0082's Context says spell shrapnel draws no crit, but it rolls its own (`hit_instance.gd:323-324`). The correction stays with #{adr-fixes}; write no ADR here.
- Still open, not this unit's to settle: the pass pick that a combined go-off's solo cost is at least 1 (tentative; `elements.md` § Shape and ride, "The node pays its solo cost"; ADR 0084 revisit-when). It is #{cast-shapes}'s knob. The base law here keeps "0 reached means no go-off" for a node's own go-off.
- Priming is no longer a turn of set-up: one rider onto a node sitting at T sets it off (ADR 0083 Consequences). That is intended; do not guard against it.
- No visual in this unit. The three blast visuals ride #{go-off-zero}.
- The stamp was cut at `bd800181`, before #{defs}…#{applier} landed. The dispatching lead re-checks `mise run issue-drift`; if it still flags, stop and say so.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp efba0bc3
docs/design/elements.md:79-108 — what a go-off pays; power post-land; copies carry everything
docs/design/elements.md:326-344 — the hit: summed riders, crit rides, rider order
docs/design/elements.md:489-530 — chains flat, no-parent go-off, a copy lands raw
docs/design/elements.md:649-784 — two stages, build shape, the five build calls, dual reach
docs/design/elements.md:155-163 — a hit carries 0 or 1 element; Greed never multiplies elements
attack/outcome/outcome_applier.gd:18-43 — apply: the drain the gather runs inside
attack/outcome/hit_landing.gd:122-156 — emit and place: where the head is
attack/outcome/crit_roll.gd:53-62 — decide: paired copies the lead's crit
attack/outcome/hit_instance.gd:318-324 — draws_own_crit
attack/spell/spell_resolver.gd:335-378 — the wave walk: stamp, land, flush
attack/spell/spell_resolver.gd:551-568 — _stamp_crit_conditions at compile
attack/outcome/status_instance.gd:132-156 — Greed doubles debuff rows
attack/outcome/attack_record.gd:205-220 — the blast table the gather will feed
attack/outcome/outcome_applier.gd — seam: drain runs stage one per beat
attack/outcome/hit_landing.gd — seam: head mark
attack/spell/spell_resolver.gd — seam: crit conditions leave compile
attack/outcome/status_instance.gd — seam: Greed guard
combat/status_host.gd — seam: greed_arm (345)
attack/outcome/attack_record.gd — seam: recorded terrain changes ride the record
docs/domain/attack-timeline.md — seam: landing order prose
test/unit/test_greed_landing.gd — seam: Greed guard test
test/unit/attack/test_outcome_fixture_replay.gd — seam: recorded crits
test/unit/attack/test_explosive_charges.gd — seam: pin, unedited
test/unit/attack/test_paired_damage_effect.gd — seam: pin, unedited
```
