# Adversarial review of the recent landings — 2026-09-12

Scope: the ~60 code commits behind `b4b1a83`, i.e. the #850/#851/#852 spell
pipeline seams, #853's spell catalogue, #847's native-only blade solver,
#742/#758's starter placement, and #764's tooltip sections. None of it played.

Six commits landed (`b4b1a83..c8ece5e`). Two issues filed. One owner question.

## The two that would have bitten in play

**1. `BladeSim` returns null now, and two callers dereference it** — fixed in
`91d35e0`. #847 deleted the GDScript fallback and made "missing binary is a loud
error" the contract: `simulate`/`simulate_range` `push_error` and return null
when the native solver is absent, stale, or declines the inputs. `SkillBlade`
handles that (passes it to `play()`, which null-checks). The other two didn't:

- `AiBladeRollout._closest_approach` walked `traj.samples` — **inside a
  `WorkerThreadPool` task**, so the `push_error` that just named the cause got
  buried under a nil-access crash on a worker thread. Exactly the audience
  #847's error message was written for.
- `MeleeAttackPlan`'s bake loop read `chunk.samples.size()` one line after the
  call.

Reachable today by authoring (a custom `BladeArcDriver` ease is declined) and by
anyone with a stale native build. Red first — the test failed with the literal
`Invalid access to property or key 'samples' on a base object of type 'Nil'`.

**2. A placed starter read its camp off the wrong index** — fixed in `c8ece5e`.
`CenterCoreStarters.plan` compares each candidate against every already-placed
point and asked `camp_of[j]` whether that point is a camp-mate — `j` indexes the
**output**, `camp_of` indexes **participant slots**. They agree only while
nothing has been skipped, and an unplaceable contender *is* skipped (pinned by
`test_crowded_map_warns_when_cross_camp_floor_is_unsatisfiable`). After one skip
a cross-camp pair can be compared on the halved same-camp ask — weakening the
non-degrading floor #758 added expressly to stop an enemy opening on top of you,
in precisely the crowded map where it matters most. The camp now travels on the
point. No shipped preset reaches it (`first_level.tres` still seats all 14).

## Cleanups

**`Targeting.get_range_finder()`** (`2dfb68e`) — asking a `Targeting` for its
reach model had three spellings: reflective `.get(&"range_finder")` in
`SpellSections`, a bare `.range_finder` property read in `EdgeHighlightOverlay`
on a field typed `Targeting` (a crash the day a second subclass ships), and a
cast in `SpellTargetUnion`. The third is legitimate — it also reads
`ownership_filter` off the same `nt` — so it kept its cast.

**Four stale claims retired** (`6818e79`), all introduced by the recent work:
`spell_resolver` still said magic's crit roll is layered by `CritRoll.decide_all`
"once the whole cast has resolved" (#536 made it per-wave `decide`);
`RangeFinder._fmt_num` pointed at a `SpellTooltip._format_num` that #853 deleted;
`RandomPickSpread` said "delete if nothing needs it" when two determinism tests
depend on it — deleting it would have quietly weakened that suite. Plus two new
catalogue-wide lints over `SpellCatalog.ALL` (the file only pinned five
hand-picked presets), including one for #851's new failure mode: a
`ScaleDamageEffect` authored *after* the `DamageEffect` it means to scale.

**A correction to my own finding** (`93f8ccd`) — I chased what looked like a
broken invariant in `CompositeFilter` on the strength of `PropagationFilter`'s
promise that `allows` and `narrow` "cannot drift apart". They provably can't be
made to agree: narrowing a one-element set asks "does this tie for first among
itself", trivially yes. Chaining children's `allows` and deriving from `narrow`
are equivalent in both modes, so there was nothing to fix in code — the *claim*
was what needed fixing, and now says so, with tests pinning the gap.

## Filed, not fixed

- **#858** — `TrailBlazerSpread` is now byte-identical to `FanAllSpread`. #851
  took the slam, #852 took the mint; what's left is a class holding a docstring.
  Retiring it touches an authored `.tres`, five doc cross-refs and a test rename
  — one unit, not a drive-by. The docstring is genuinely valuable and the issue
  says where it should go.
- **#859** — a skipped starter slot mis-zips every *later* participant onto the
  wrong spawn. `GraphProcgen` consumes `starters` positionally three times and
  the level zips spawns to the roster by index, so one skip can turn a 2v2 into
  an effective 3v1. The skip itself is specified and tested, so this is a
  caller-side policy call: four options costed in the issue, my read is
  "never return short" or "fail the generation".

## One question for you

**A Trailblazer cast seeded *directly onto* a junction is now slammed — it never
was before.** Posted on #851 as a comment; needs your ruling, not a fix.

#851's thread enumerates its behaviour deltas carefully (merged-vs-per-branch
scaling, `MULTIPLY_BY_DEGREE` being entity degree all along, why the goldens
didn't move). This one is named only in `trail_blazer_spread.gd`'s docstring.
It's a consequence of the *right* architecture — "arrival transforms are on-hit
effects" means hop 0 is an arrival like any other — so if it's unwanted the fix
is a condition composing `JunctionCondition` with `hop_index > 0`, not a
resolver special case.

Before: aiming at a junction was a wasted cast. After: an instant slam at seed
damage, no walk needed. Keep it (consistent, rewards target selection) or gate
it (the Trailblazer's identity is the *walk*; "click the junction" shouldn't
outrank "find the string")? No test pins either reading yet.

## Also delivered

`docs/handoffs/post-lan-swarmify-dag.md` — the swarmify clustering DAG for
milestone #20. **Its first pass planned a wave of already-written code**: it read
#849's body and treated the three seams as future work, when #850/#851 closed
2026-09-10 and #852 on 2026-09-11. Corrected in place — the hub's first action is
to be *closed*, and #356/#397 are the unblocked pair. Both of their bodies still
name four deleted files; flagged for re-pointing before any drone is briefed off
them. Worth knowing the failure mode is real: a stale hub misled a fresh reader
within minutes.
