# Board sweep — 2026-10-16

Swept 90 Needs design, 168 Backlog, 10 Intake + 1 Ready, 17 In progress, 11 In review issues (counts verified: 90/168/11/17/11).
- Needs design: 89 got a prep comment (#657 is both prepped and `stale?`) (research, no decisions) plus the `prepped` label; each is graded by readiness below. Intake issues got a "Triage prep" comment.
- `stale?` label = "close candidate, awaiting the owner": the sweep found the premise gone or overtaken but did not close it. Remove the label to keep an issue; close it to confirm.
- Closed outright by the sweep: 6 (shipped or dead on evidence; list in section 3). 12 more writes were refused by the permission classifier and wait for you (section 2).
- No priority field exists in the sweep data, so rows are sorted by number within a group.
- No board status was moved by the sweep; Intake/In review/In progress findings are suggestions only.
- The "should be Needs design" and keep-refresh (body rot) Backlog rows carry no label; this report is their only index.

### Find them

```
gh issue list --label 'stale?' --state open    # close candidates awaiting you
gh issue list --label 'stale?' --state closed  # closed outright by the sweep — reopen if wrong
gh issue list --label prepped --state open     # Needs design with a Swarmify prep comment
```
Prep comments start `## Swarmify prep — 2026-10-16`; Intake ones start `## Triage prep — 2026-10-17`.

## 2. Needs your hand

### Refused writes (12)

Review the comment bodies in `work-bl2/`, `work-bl3/`, `work-bl4/` next to the script, then run:

```
bash docs/handoffs/board-sweep-2026-10-16.pending/pending-board-actions.sh
```

| # | Gist | Intended action |
|---|---|---|
| #446 | Design fork: wire Staking, or label it pre-wired for #337? — Audit fork asking whether the stake/extract economy verbs should get a UI or be marked unwired. | comment + `stale?` + close; Staking now has production callers (stake/extract armed verbs and commands). |
| #450 | Design fork: export preset ships every dev tool in release builds — The release export preset packed test tooling and docs into builds. An exclude filter now strips them. | comment + `stale?` + close; export_presets.cfg now excludes gut, sandbox addons, test, docs, tools. |
| #505 | rules-hygiene: the always-on crumb tier is over budget, and was before #494 — The always-on rule crumbs exceeded their byte budget. The budget check now passes. | comment + `stale?` + close; rules-hygiene now: rule tier 4994/5000, no violations. |
| #1052 | balance(procgen): armor moves from universal to the CON archetype — Proposed making armor a CON-archetype roll instead of universal for balance. | comment + `stale?` + close; armor already left universal via 6a09dad; |
| #1540 | Whip run 2026-10-10 — Tracking issue for one overnight Whip run; morning report landed as a comment. | comment + `stale?` + close; PROPOSED close (gh write denied): ledger, report posted, all listed issues closed |
| #1589 | Whip run 2026-10-12 — Tracking issue for one overnight Whip run; morning report posted. | comment + `stale?` + close; PROPOSED close (gh write denied): ledger, report posted, all 12 listed issues closed |
| #448 | Design fork: reconcile first_level.tres against the procgen-v4 seed table — The first-level procgen config had drifted from the documented seed table. | comment + `stale?` label (stays open); Doc was re-derived (base 1..4 matches .tres); |
| #451 | Design fork: what should crest_r actually be? (escalated from A3.7) — Question of what rim bevel crest radius skill nodes should use. Code now sets it to radius minus a 4px inset. | comment + `stale?` label (stays open); SkillNode forwards crest = radius - 4 so shipped nodes are non-zero; |
| #484 | perf: core gimbals cost ~5ms each - 4+ visible entity cores drops 144fps to 20 — Entity core gimbal visuals cost milliseconds of CPU each and tank framerate with several visible. | comment + `stale?` label (stays open); 2D CPU gimbal deleted in 615449c, replaced by 3D CoreGimbal; |
| #595 | Claude Code teammates yield after one action on their first mailbox message — Swarm workers named as teammates idle after one action on their first message, costing a nudge. | comment + `stale?` label (stays open); Cause never settled; mitigation in swarm skill; |
| #1565 | Whip run 2026-10-11 — Tracking issue for one overnight Whip run; morning report posted. | comment + `stale?` label (stays open); PROPOSED stale? (gh write denied): finished ledger; issues 1393, 1561 still open but not children |
| #1603 | Whip run 2026-10-14 — Tracking issue for one overnight Whip run; morning report posted. | comment + `stale?` label (stays open); PROPOSED stale? (gh write denied): finished ledger; issue 1596 still open but not a child |

Issue 55 was closed by the orchestrator afterwards (owner comment 2026-10-15 "not doing this"); it is already in section 3.

### Board-state fixes from the audits

**In review that already landed (move to Done):**
- #914 docs: stat→surface map with owner-confirmed hidden stats — docs/domain/stat-surfaces.md on master (e902189, since touched through e2e8ad1); last comment says acceptance met, closeable
- #1491 Blindness × Spell: reshape dazzle to climb the vision gradient — d0a3940 (2026-10-08) feat(spell) on master plus docs 97d39bd; no comments, no open questions

**In progress with no live work (stale hubs):** all 17 audited rows are hubs with no worktree; see section 7. Note-worthy:
- #187 The Gate - a 2-node addon that toggles an edge on/off (hub) — Children 1207 and 1210 are In review yet shipped 09-30.
- #432 Unify the test fixture layer — Fresh (updated 10-16); route Intake children to Ready, hub then legitimately stays open.
- #1253 Blindness row — Child 1491 is In review though landed on master 10-08: move to Done.
- #1313 Whip: unattended overnight supervisor above swarm leads (hub) — Close-candidate once 1523 decided.
- #1369 Refit the pre-aspect addons (SpikeRing, clamp, bunker, fortress) to the aspect m — Fresh; one design child left.
- #1378 Corruption row — Could close once 1580 is closed/dropped.
- #1379 Curse row — Child 1561 has a stalled worktree.

**Ready issue drifting:**
- #1606 Explosive barrel: temp-placeable — one AoE hit on impact — Spec part 1 landed e25ee90; flip pending on 1605 (still Needs design); apply-time ESS question unresolved. Suggested route: Needs design.

**Intake routes:** see section 7 (8 ready-as-is, 2 ledgers to close, 1 drift).

## 3. Closed by the sweep

| # | Title | Why |
|---|---|---|
| #55 | Design: face/cycle melee damage bonus (post-MVP) | Owner comment 2026-10-15 "not doing this. can reopen if we want something like this"; closed by orchestrator after the sweep labelled it |
| #331 | Harden swarm + drone skills to be harness-independent | Drone skill replaced by agent; opencode framing deliberately removed; worktree-first now unconditional (commit ebc5224; .claude/agents/drone.md:17; charters/swarm.md:15; drone.md:242) |
| #421 | Bring self-loops into the edge batch; retire the second render path | Self-loops were folded into the shared MultiMesh. (commit d345e69; graph/edge.gd header; graph/graph.tscn:18 Edges is Node2D) |
| #659 | perf: sleep-polling — background + Monitor instead of sleep/tail timer turns | prose landed as rule + domain doc + drone.md; only optional hook and measurement remain (.claude/rules/long-running-commands.md;) |
| #789 | Always-on context tiers over budget | acceptance met: always-on 14585B/16500B, rules-hygiene reports no violations (mise run rules-hygiene at 69e5876) |
| #938 | Scoped paths: rules never fire on Bash reads — inert under auto mode; hook or ac | Option 1 shipped as rule-path-hook in d132978 (2026-10-09), wired in settings.json, doc updated. (d132978; .mise/tasks/rule-path-hook; docs/domain/breadcrules.md:103) |

## 4. Close candidates (`stale?`, open)

| # | Gist | Reason | Keeps it alive if… |
|---|---|---|---|
| #50 | Colorblind palette options — Offer alternate colorblind-friendly palettes with a settings toggle. Labelled wontfix yet left open. | Already labelled wontfix but open, no explanation, no code or plan |  |
| #57 | Design: node specialization system (Corrupted/Crystallized/Anchor/Doubled) — Decide a model for special node states like Corrupted or Crystallized. | Design doc is declared early spitball, nothing built or scheduled |  |
| #401 | Tooltip fan sandbox tab: Bg ColorRect obscures fan content — A background rectangle in the tooltip-fan sandbox tab hides content despite z-order, unexplained. | Cosmetic mystery with workaround (Bg.visible=false) shipped; only lost background fill |  |
| #440 | Per-repaint quadratic walks in the melee and ranged attack plans — Hovering/previewing melee and ranged attacks re-walks the graph per node on every repaint. | Owner left a bare 'stale?' comment 2026-09-02; melee half still real, ranged half unclear. |  |
| #519 | client state fidelity under fog — Plan for correct bars/tooltips on nodes a client cannot see, once fog is authoritative. | Deferred by owner and ADR 0015. |  |
| #661 | Flaky: test_link_mount host-role socket assertion — A LAN host-role test failed about 1 run in 6 right after other runs. | two later fixes (ephemeral port, wait_until is_reveal_ready) target this test; no recurrence recorded |  |
| #748 | mise run test hangs when GUT pre_run_script hook fails to load — The test runner could spin forever when its hook script failed to load. | the stale-class-cache trigger is now auto-refreshed (#919); only a hook parse error can still hang, and no pre-flight check exists |  |
| #794 | Crit doubles blunting: a critical blade contact spends twice the spike budget — A critical melee hit on a spiked node would burn double the spike-pop budget. | owner 2026-10-07 asked if superseded; blunting still live but aspect_matrix marks it a Struck candidate |  |

(After the refused-write script runs, #448 #451 #484 #595 #1565 #1603 join this list.)

## 5. Needs design (90)

### no-real-forks (8)
_Closest to Ready: the research found no genuine open decision, only a spec to write._

| # | Gist | Forks | Blockers / note |
|---|---|---|---|
| #165 | pre-authored graph components stitched into procgen — Hand-authored multi-node fragments grafted into generated graphs. | 3 | Design settled; decomposition into children not done; blockers closed. |
| #249 | Sandbox host: unify live-tab scaffolding — An epic to give sandbox-host live tabs a shared scenic base. The base shipped and all tabs migrated; only a few children remain. | 3 | All 23 tabs migrated; body stale; 4 open children. |
| #655 | swarm: post-report idle notifications are disposition-only — After a drone reports, the harness sends another idle ping that costs the expensive orchestrator several tool calls. | 3 | [partly shipped] |
| #948 | swarm: the Sage spawn message carries run content only — never restates or overr — Add a rule that the Sage spawn message holds only run content, not agent-file instructions. A small charter edit. | 2 | Charter law not yet written; direction set by owner 2026-09-17; docs-only. |
| #1070 | test purity: real-clock tail — A hub for the remaining real-clock waits in unit tests. Four of five children are closed; one remains open. | 2 | #1624 |
| #1153 | Scope GameRoot's TurnManager to its own world — Two in-process GameRoots share initiative stagger/opener. | 3 | Claim verified; likely a one-line wiring plus test. |
| #1249 | Attribute archetype per aspect — Which primary attribute owns each status aspect; | 5 | #1419, #1425 (soft) |
| #1255 | Status model: decay & spread slots, proc timing, cures — Hub for the status model design. Tracks decay, spread, proc timing and cure design for status effects. Carries no work itself. | 1 | #967, #1203, #969, #968 |

### forks-enumerated (50)
_Forks are listed in the prep comment; needs your picks._

| # | Gist | Forks | Blockers / note |
|---|---|---|---|
| #251 | Live-sync: source-scene edits reflect in the running sandbox tab without an edit — Make sandbox tabs refresh automatically when their source scene changes. Needs a feasibility spike. | 3 | Spike/investigation; manual reload exists; no file-watch present. |
| #259 | Core Classes authoring tab (live proximity-Effect preview) — A new sandbox tab for tuning core classes with a live preview of their proximity effects. | 4 | Unbuilt tab; real design surface (scratch graph, live evaluation). |
| #354 | Spell preview UI: per-node damage/hit-count chips + skull-on-deplete icons — Show players what a spell will do before they cast it: damage numbers, convergence hit counts, kill skulls. | 4 | [live, mostly build] |
| #355 | New spell: Chromatic Cascade (colour-rule variant of Resonator — distinct-origin — A proposed spell like Resonator that crits only when hits arrive from different seed branches. | 5 | Unbuilt; blocker 356 closed; |
| #453 | Minimap: real rendering + camera control + zoom — The real minimap. v0 shipped in August; this tracks deferred slices and the owner's bloom-for-one-UI-element question. | 3 | v0 shipped; remaining slices plus bloom question. |
| #565 | Turn-start narration is simultaneous, and plays under the banner that hides it — At turn start a big YOUR TURN banner covers a burst of simultaneous stat changes the player cannot read. | 4 | [live, seam names stale] |
| #658 | perf: read discipline — whole-file Reads are 62% of a blown drone's context — Drone agents that run out of context mostly did so by reading whole files, often repeatedly. | 4 | [partly shipped] |
| #732 | Five spell visuals copy ComposedProjectileVisual's drain machinery — Five spell visual scripts hand-copy the same bookkeeping for when a projectile's child effects finish. | 4 | [live, WIP warning stale] |
| #738 | tags granted by an aura are invisible to the effect readout panel — The hover panel that lists what affects a node cannot show tags granted by auras, only numeric modifiers. | 4 | #no shipped effect grants a tag [live, deferred by owner] |
| #770 | Lobby: make procgen addon density controllable — A lobby setting to reduce or turn off procgen addons after LAN feedback. The underlying density knob changed since filing. | 4 | slot_count_weights replaced by addons_per_100_nodes (ADR 0052). |
| #786 | Implement the Halo core class (spike-ring shell, shell-swing, aura-granted spike — Build the Halo core class, a ring of spiked nodes around the core. How the aura grants spikes and shows itself is open. | 6 | Halo unbuilt; collision-model blockers closed; owner raised aura-VFX concern. |
| #826 | Presentation rate should follow RELEVANCE (vision + ownership), not the seat — How fast a melee swing plays back should depend on whether you can see it or it touches your nodes, not on whose seat it is. | 5 | [live, owner-directed] |
| #1088 | Victory: a run is lost when no human stands — Ends a run as lost when no human is left even if an AI ally stands. | 5 | Owner decided the outcome (lost); forks are rule placement and outcome shape. |
| #1099 | mp:e2e rung 4: AI stall on poison arrows — An intermittent e2e timeout where the AI repeatedly proposes an ammo-infeasible ranged plan. | 3 | #1186 (soft) |
| #1100 | Participant.ai_tier: type it as the AI tier enum — break the ai_controller load  — A small type-safety cleanup: Participant.ai_tier is an int to dodge a script-load cycle. Two fix options exist. | 1 | Still valid; one fork (new AiTier script vs lazy preload); _new_ai_controller seam stale. |
| #1109 | force_deallocate costs ~0.8 ms/node — Profile-then-fix: stripping 200 owned nodes was a 155 ms frame. | 4 | Measurement predates cascade refactors; needs re-measure; 5 benches still lack camp_sizes. |
| #1110 | Explore: coalesce O(world) signal handlers (DeferredOnce) — Exploration hub hunting handlers that redo whole-world work per signal burst. | 3 | #1109 (soft) |
| #1144 | Shadow allocation lookahead: deep NodeState.clone() — Deep clone of node state + shadow-safe scale mutator so AI lookahead cannot touch the live world. | 3 | #AI lookahead consumer (soft) |
| #1213 | Audit: GuaranteedPlacement / PlacementContext — Audit of procgen placement layer; | 5 | Audit report already posted; owner must pick option (A default) and cleanup scope. |
| #1342 | is_quiescent() true while a volley's beat clock may be live — Is the save gate's 'world at rest' check true too early, or is it teardown noise? A drone saw a script error freeing a level righ… | 3 | Needs repro test first; existing save-gate tests don't assert beats drained. |
| #1364 | Save/load: pause-menu RESTART after a LOAD hangs (world_source stays ARRIVES) — After loading a save, pressing RESTART in the pause menu hangs because the session still thinks a world will arrive. | 2 | Bug is real; open pick is restart = re-park save vs regenerate from seed. |
| #1388 | Wither x Addon — Aspect-matrix cell: a wither node upgrade for map and blade. Recipe forks open. | 7 | Recipe forks open. |
| #1391 | Blindness x Addon — Aspect-matrix cell: blindness node upgrade; blade face gist is on-hit blindness stacks. | 7 | Aspect-matrix cell: blindness node upgrade; blade face gist is on-hit blindness stacks. |
| #1392 | Blindness x Spell 2 (Throw Sand) — Second blindness spell: a sand cone hopping the enemy front line. Previously blocked on #1488, now closed. | 3 | Previously blocked on #1488, now closed. |
| #1396 | Armor break x Addon — Armor-break node upgrade; fork between reducing armor and ignoring it. | 3 | #1401 |
| #1397 | Armor break x Spell 2 — Possible armor-ignoring second spell beside Sunder; first question is whether a gap exists. | 4 | #1401 |
| #1401 | armor penetration stat — New attacker-side armor penetration stat; flat vs percent undecided. | 3 | New attacker-side armor penetration stat; flat vs percent undecided. |
| #1413 | Arrow production split from firing: reload by degree — Make arrow production a degree-based formula while firing stays leaf-only. | 5 | Direction decided by owner; formula shape and balance open. |
| #1423 | Greed x Addon — Aspect-matrix cell: greed node upgrade; status now exists. | 3 | Aspect-matrix cell: greed node upgrade; status now exists. |
| #1424 | Greed x Spell — First Greed spell; pick of four coverage shapes. | 2 | First Greed spell; pick of four coverage shapes. |
| #1428 | Weakness x Addon — Aspect-matrix cell: weakness node upgrade; status exists. | 2 | Aspect-matrix cell: weakness node upgrade; status exists. |
| #1429 | Weakness x Spell — First Weakness spell (Enfeeble?); pick of four shapes. | 2 | First Weakness spell (Enfeeble?); pick of four shapes. |
| #1459 | Greed: a more elegant shape for the landing term — Greed doubles a hit's debuff stacks and spends one Greed stack per hit. The issue asks for a cleaner implementation. | 4 | Greed works but is hard-coded in StatusHost; |
| #1468 | Threshold formulas describe as log10, NumFmt shorthand — Loot and stat descriptions print long threshold ladders like '+1 at 50 / 150 / 500 / 1000 / 5000 INT'. | 4 | prepped for swarmify |
| #1499 | Perf: aimed spells take SpellTargetUnion's O(N)-per-source fallback — Aimed spells enumerate targets by scanning every node per caster. | 3 | Real O(N) sweep via inherited base valid_targets; |
| #1500 | Aimed casts: streak vs wave-0 seed bolts — The Flare Line shows both a hitscan streak and per-node bolts. Owner decides whether the streak replaces the bolts. | 3 | Verified both visuals play; nothing nulls visual_scene. |
| #1529 | Blessed / blighted nodes: visual + aspect delivery — Blessed/blighted nodes are only faintly tinted so players cannot see them. | 3 | #1249 (soft) |
| #1535 | Territory look: per-CoreClass visual worn by every owned node — The Dormant Core's null-field look currently dresses only the core node. | 3 | prepped for swarmify |
| #1562 | Riders land before their paired damage (every aspect) — Today a status 'rider' (curse, armor break, hex) lands after the damage it came with, so it only helps later hits. | 3 | prepped for swarmify |
| #1587 | Hoverable concept badges inside prose lines — Concept names in tooltip prose should be inline hoverable badges that explain the concept. | 4 | affinity_line.gd cite is gone; BadgeText is the real seam. |
| #1590 | Corruption x Spell: forced topple as an existing spell's signature — The owner wants the 'forced topple' (pop a corrupted pile now, whatever its size) to be the signature move of one existing corrup… | 2 | #1580 |
| #1596 | Explosive spell: Flamestrike — An explosive spell that spreads one damage pool evenly over a circle of enemy nodes, with the circle shrinking as explosive load … | 2 | #1597 |
| #1604 | Explosive death blast: who is the shooter, and a recorded carrier — When an explosive-charged node dies, the design says it should detonate once, but a death has no attacker and the recording path … | 1 | prepped for swarmify |
| #1605 | Melee temp tray: wrapping grid of same-size shop-item cards — The melee tray shows temporary-addon cards in a single row with five hotkeys, and a sixth card would overflow the 890 px width bo… | 4 | prepped for swarmify |
| #1607 | Temp price or explicit exclusion: four addons — Four addons lack a temp_placeable setting despite the owner ruling that addons are placeable by default. | 5 | fortification has no scene. |
| #1619 | Explosive VFX: goo coat on a charged non-barrel node — A node carrying explosive charges from goo arrows has no visual beyond a generic status tint. | 2 | prepped for swarmify |
| #1621 | VFX: attack/blast rings draw through fog — Attack and blast rings are drawn above the fog with no visibility check, so they show where unseen fights are. | 1 | prepped for swarmify |
| #1622 | Explosive blade: a charged pivot arms a blast it can never fire — A blade handle (pivot) that carries explosive charges arms blasts on its contacts but is exempt from the blast gate, so the blast… | 1 | prepped for swarmify |
| #1624 | test purity tail: TweenClock for EdgeEnergize, FanTrace, modifier pulse, trail b — Four test scripts waited on real time. | 1 | #1070 |
| #1634 | Bunker x bunker: elastic recoil, momentum-threshold destroy, heavy member — A bunker blade member hitting a bunker plate should bounce off physically, and if it hits hard enough, destroy the defender's Bun… | 4 | prepped for swarmify |

### design-beat (20)
_Open question is "what would be fun": a design conversation, not a spec._

| # | Gist | Forks | Blockers / note |
|---|---|---|---|
| #47 | Strategy-pattern NPC controller — A future AI layer where NPCs pick strategies based on archetype affinity. Mostly undesigned. | 4 | Large post-MVP AI idea needing a design pass; depends done; ai.md doesn't exist. |
| #49 | Tutorial / first-session guidance — A guided, skippable first-launch tutorial. Entirely undesigned; weak backlog candidate. | 4 | Three-line stub; nothing built; UI still moving. |
| #197 | Double-crit: crit becomes a tier (int), not a bool — stacking juice — Crit stacking: a hit can crit multiple times for escalating damage and visuals. | 3 | crit_tier int already shipped; |
| #199 | milestone level-up bonus picker / core mini skill trees — Milestone levels should grant a bigger choice or a point spent inside the entity. | 6 | #1249 |
| #256 | blade nodes visual upgrade — Blade nodes were plain circles; wants a weaponized look, pop animation and pre-swing bling. Pop shipped; look and bling remain. | 3 | Pop shipped; look and bling remain. |
| #297 | Lifelink addon — permanent unbounded life source as a virtual edge to core — An exploratory addon that ties a node to the core with a virtual edge so it never islands. Priced by mutual risk; not committed. | 5 | #240 |
| #348 | Addon placement UX (parked): where addons come from, what places them, what keep — A parked design question about how players obtain and place addons. Nobody should build against it yet. | 5 | Explicitly parked design placeholder; FOCUS.md reference is dead. |
| #469 | Edge width vs. zoom: clamp the screen-constant width, and add bolt dots at conne — Edges stay a fixed pixel width while nodes shrink when zoomed out, so the graph looks like a mat of lines. | 4 | [design-beat, line refs stale] |
| #740 | Reuse #734's charge-glow + outward-fade language for allocation VFX generally — The splash screen's charge-up glow looked great, and the owner is considering using it for every node allocation in a level. | 4 | [live design beat] |
| #744 | Spell targeting: heatmap enemy nodes by best available caster power — When aiming a spell, paint enemy nodes by how hard your best casting source could hit them. | 4 | #playtest signal that source choice matters [live, premise partly stale] |
| #1087 | AI: Warlord-tier growth habits — The hardest AI tier should also choose smarter nodes to grow into: defensive picks, avoiding exploitable shapes, and looking ahead. | 4 | [live design beat] |
| #1123 | Tooltip fan: gentle non-locking camera nudge — Nudge camera when the tooltip fan cannot fit on screen. | 5 | Design open: trigger, distance, hover-or-not; needs new non-locking camera path. |
| #1331 | spell playground: eyeball targeting rings — Look at the spell playground to confirm targeting rings relight. | 2 | #interactive editor session |
| #1368 | Addon visuals when several addons share a node — How to draw two or three addons on one node: blend or arc sections. | 4 | Pure visual design; blend vs arc-split. |
| #1375 | a cross-turn caster resource worth having (mana's successor) — Parking issue for a replacement of the retired mana resource. | 1 | Parked until an idea exists; candidate for Backlog. |
| #1467 | Surplus aspect past the per-action caps — Large aspect totals stop mattering once per-action caps bind. The issue asks how surplus keeps paying off. | 4 | Option (e) names infusion_points which no longer exists. |
| #1556 | Vaccinate: resistance-building spell — A spell giving temporary decaying resistance to healthy nodes, with herd-immunity spread. Which aspect houses it is undecided. | 5 | Pure design stage; no code. |
| #1563 | Reliquary: an addon that collects debuffs — An addon that gathers debuffs for later release or conversion. Routing, payoff and blade face are open. | 5 | Idea only; one doc line. |
| #1591 | Corruption x Spell: a damaging cleanse, the 4th corruption spell — A new Corruption spell that removes corruption, still hurts, does not pop piles, and does not treat own and enemy nodes different… | 2 | #1580 |
| #1636 | Clamp: trade blade damage for rigidity on clamped nodes? — A floated idea: clamped blade nodes could deal less damage in exchange for rigidity, as a second lever on how far a clamped blade… | 2 | prepped for swarmify |

### blocked (3)
_Waiting on another issue before it can be decided._

| # | Gist | Forks | Blockers / note |
|---|---|---|---|
| #1208 | Gate: procgen placement — Procgen pass choosing which node pairs get gates, scored by hops saved per span. | 4 | #1213 |
| #1393 | Scout x Addon — Watchtower scout addon; map face shipped, only the temp-blade face remains, held by the five-card tray cap. | 2 | #1605 |
| #1561 | Curse x Spell: Gloomflux — A Curse spell that hits for 1, adds curse, doubles the node's curse, then copies part of it to neighbours via Curse's spill, with… | 1 | #1562 |

### suggest-backlog (5)
_Real but not now; the prep suggests moving to Backlog._

| # | Gist | Forks | Blockers / note |
|---|---|---|---|
| #258 | StatBoard tab: %Sidebar of stat defs (needs selection semantics) — Add a stat-def card list to the StatBoard sandbox tab. | 0 | Owner resolved fork 2026-07-30 (reference-only); remaining work mechanical; 261 closed. |
| #519 | client state fidelity under fog — Plan for correct bars/tooltips on nodes a client cannot see, once fog is authoritative. Deferred by owner and ADR 0015. | 2 | [labelled-stale] |
| #887 | Design: AP tempo sources beyond the killing blow — Ideas for earning extra action-point tempo beyond a kill: cutting enemy territory, closing a cycle, maxing a stake. | 4 | #stake usage data for Mastery [live parking lot, owner says backlog for mastery] |
| #1077 | visuals: bosses get the SOLID_GLYPH gimbal (sibling of #804) — Bosses should wear the opaque rune-covered gimbal instead of the transparent holo-glass one. | 3 | #1108, #bosses do not exist [live, mostly settled, no consumer yet] |
| #1612 | Explosive v2: filter-gated face entries on the intake row ('both' from one heal) — A spec to let one Explosive spell row both plant and detonate via a list of gated face entries. Nothing needs it yet, so it waits. | 2 | Spec complete, owner decisions recorded, blocker 1609 closed; |

### suggest-close (4)
_Shipped, superseded or doubtful; the prep suggests closing._

| # | Gist | Forks | Blockers / note |
|---|---|---|---|
| #657 | EXPERIMENTAL: Auras scale-carrying bindings — An experiment to restructure how aura scaling is bound to stats to cut recompute cost. Its cost drivers were fixed another way. | 3 | Owner calls it stale; target symbols gone; no branch exists; drivers closed. |
| #659 | perf: sleep-polling — background + Monitor instead of sleep/tail timer turns — Agents were burning whole model turns as kitchen timers by polling long commands with sleep+tail instead of backgrounding them. | 0 | [shipped] [closed] |
| #794 | Crit doubles blunting: a critical blade contact spends twice the spike budget — A critical melee hit on a spiked node would burn double the spike-pop budget. | 3 | #1369, #1437 [close candidate, owner doubts] |
| #998 | Destinking hub — Hub for a code-smell audit. All children done except #732. | 2 | #732 |

## 6. Backlog (168)

Verdicts: keep 107, keep-refresh 38, closed-dead 1, stale? 13, closed-shipped 9. Nothing was moved; "stale?" and closed rows are in sections 3/4.

### keep-refresh (38) — idea alive, issue text has rotted

| # | Gist | What rotted |
|---|---|---|
| #35 | Tune addon procgen ratios/spread — Balance pass on how many addons procgen puts on nodes and how common each addon is. | Valid balance pass but body rotted: names AddonPolicy.slot_count_weights and procgen-v3.md, both gone |
| #38 | Damage type taxonomy implementation — Post-MVP reopening of which damage types exist (per-type resists). | Owner-triaged as low-priority reference; DamageInstance.Type is still PHYSICAL/MAGIC/TRUE; body cites mvp_decisions.md (now legacy-mvp-decisions.md) |
| #51 | Metagame: main menu + intro + overworld (tracking) — Umbrella for the game's metagame layer: menu, intro lore and a 2D overworld. | Tracking issue: main-menu half shipped (MetaRoot, 5053afc; follow-ups #461/#456 closed); intro and overworld remain |
| #53 | Performance budget + procgen scaling profile — Profile procgen at 100/500/1k nodes and write down a performance budget. | Still unbuilt: docs/domain/performance.md does not exist; owner-cited related #133 is now closed |
| #54 | Design: "overqualified casting" bonuses (non-range) — Decide what extra benefit a spell gets when cast from a node with more degree than its minimum (besides range). | Pure design question never touched; body cites mvp_decisions.md (now legacy-mvp-decisions.md); min_degree still exists in spell code |
| #56 | Design: melee swing drive easing variations — Explore non-linear easing for melee swing drives and related swing stats. Still a vague design question. | Open design exploration with owner comment widening to swing angle/linger/count stats; body cites mvp_decisions.md (now legacy) |
| #75 | Staggered bulk-allocation VFX (system-level) — Make a spawned entity's bulk allocation ripple outward from its core like the deallocation cascade. | Still no allocation wave (only force_allocate, allocation_system.gd:223); |
| #131 | visuals: inner disk is too bright when unallocated — Make unallocated node discs dimmer so they recede against the background. Its stated blockers have shipped. | Blockers #157 and #304 are both closed so it is actionable; shader lines cited have shifted (sn_disk_color now ~lines 57-66) |
| #142 | Rune Ring: render actual runes instead of placeholder lines — Replace the rune ring's placeholder lines with real rune glyphs. | Owner parked it 2026-08-02 (Real Attempt, FOCUS); rune_ring.gd unchanged since 2026-07-09; body says issue 129 |
| #181 | Canonicalize radial scaling with a mini resource (flexbox-like ring ergonomics) — Node ring radii (disk, rim, bonus band, halo) are each wired by hand; | Idea intact (no RingSpec exists) but body cites RIM_CREST_INSET / RIM_BONUS_DEFAULT_WIDTH which are gone from the code; |
| #245 | SkillNode emblem: baked CARVE-art substrate (arbitrary shapes for spell/keystone — The epic for letting a node's carved emblem be arbitrary art (spell icons, glyphs) rather than just polygons. | Parked by owner 2026-08-02; |
| #278 | Spell balance pass: mana cost × degree requirement × reach (hops vs euclidean) — A joint balance pass over each spell's degree requirement and reach (hops vs distance) so high-INT casters ar… | Pinning session with owner, prerequisites 268/274 now closed; body stale: mana retired (ADR 0045), D-18 multiplier superseded by spell_hops. |
| #335 | SkillNode.modifiers conflates authored export with derived runtime modifiers — SkillNode uses one serialized array for both authored and runtime-derived modifiers, risking editor-save comp… | Still @export var modifiers (now skill_node.gd:104, body says :41); editor_hint guard still present |
| #364 | Stop + UserPromptSubmit hooks for context horizon — Proposes harness hooks so an agent sees its own context size and cannot idle dirty at high context. | No Stop or UserPromptSubmit hook exists; |
| #394 | Faction-shared vision reveal — Idea to let a faction share one reveal set so a camp reacts together, as an AI difficulty lever. | Still unbuilt (no shares_vision); Faction (#384) now exists; cited lines vision_system.gd:51/143 have shifted (_effective_viewers now :195) |
| #422 | Split graph_procgen.gd's six phases into typed objects — The map generator is one huge static file whose generate() threads many locals through six phases. | Still a static god-class, now larger than the body says. |
| #442 | AllocationVFX: five code-composed effect trees to scenes — The node-allocation visual effects are built in script so they cannot be previewed or tuned in the editor. | Still code-composed; file is now 720 lines (body says 430). |
| #447 | Design fork: build the addon weight-profiles/cost pass, or delete it? — Addon policy has weight-profile and cost knobs that the addon draw never reads. | Fork still real (addon draw ignores weight_profiles and cost; |
| #691 | AttackOutcome carries no deallocation set — An attack result does not record which nodes it removes or entities it kills, so the AI's XP preview underval… | gap still real (attack_outcome.gd has no removed/killed set) but owner noted #774 made XP additive so it may be moot; re-read after #774 |
| #829 | StatDef.description hand-writes its ratio clause; compose it from the formula in — Stat tooltips hand-write numbers like '+1 per 10 STR' that go stale when the formula changes. | Still valid and drift has recurred: strength.tres now says 'per 40 STR' for blade size; |
| #832 | AI: buying SPIKE_UPGRADE on reach members needs the budget API to see phantom sp — An AI idea to let rollouts buy spike upgrades on blade members, which first needs the blade-size budget to co… | Gap persists (only ai_phantom_clamp_nodes exists, budget API blind to it), but body cites TEMP_UPGRADE_CATALOG at melee_attack_plan.gd:45 and _budget… |
| #855 | blade_obstacle_field.gd still carries a GDScript FieldCtx per-substep pass — a m — Cleanup: a GDScript copy of the native per-substep obstacle-field pass survives only for one test helper. | Still present, but line range drifted: begin_sample/after_drivers/project/end_substep now at 305/311/342/456 not 340-565; |
| #856 | ShatterField's CPU reference curves mirror the shader with nothing pinning agree — Cleanup: CPU copies of the shatter effect's curves exist only for tests and could silently diverge from the s… | Still true; functions moved to ui/vfx/shatter/shatter_field.gd:214-247 (body said 193-226) and test_shatter_field.gd still asserts on them. |
| #933 | flaky: test_game_root_join_wait link-lost assertion fails under full-suite load — A test that fails intermittently under full-suite load because it waits a fixed time instead of the real link… | Flake unfixed: the link-lost test still ends with a fixed wait_seconds(0.2) at line 89. |
| #985 | melee: the instant clock does not honour swing_duration — Melee swings still cost about 1.65 s real time even in instant-mutation mode, which blocks fast melee tests. | Fade constant (melee_preview.gd:19 _SWING_FADE 0.45) and tweens still present; |
| #1010 | Strip issue-number citations from code comments (~6 000 sites) — Mechanical cleanup removing '(#NNN)' issue references from code comments, keeping only contracts. | Still valid, partially done: hygiene now reports 3759 issue-cites (was 6065); blocker 1001 closed. |
| #1011 | Move the remaining 153 comment essays to docs/domain — Mechanical cleanup moving 25+ line comment essays out of code into docs, leaving one-line pointers. | Still valid; hygiene reports 168 comment-essay files (body says 153). |
| #1012 | LootSystem: credit the killing blow to the hit's attacker — Kills by damage-over-time or cascades are credited to whoever holds the turn, not the real attacker. | Still current_entity-based (loot_system.gd _resolve_killer); blocker 1007 closed; body says needs design for null source. |
| #1026 | SpellCatalog: const preload list + ALL array -> authored .tres catalog — Replace the hand-maintained spell list with an authored resource catalog wired through an export, as was done… | Still a const preload list; blocker 1008 closed so it is unblocked; two open forks remain. |
| #1111 | dx: worktrees come up warm — borrow main's .godot cache + native bin on creation — Make new git worktrees launch-ready by copying main's Godot caches. | body predates shipped halves: native bin and .godot copy shipped, fail-fast declined; only deferred acceptance check remains |
| #1113 | Tooltip renders a node-carried Effect as an empty aura — A node-carried Effect shows in the tooltip as an aura section with no contents. | bug likely still real; fixture path rotted (test/fixtures -> test/support) |
| #1193 | AI spends DP: deallocation for mobility, tactical positioning and build tuning — Teach the AI to spend its deallocation points to shed nodes, reposition territory and retune its build. | Still valid; AI still never deallocates. Body cites ai_controller.gd:10/:197 which have drifted (now :10 and :206). |
| #1197 | Close the no-applier launch_attack hatch: a fixture CommandApplier for tests — Tests currently launch attacks without the command applier via a fallback branch; | No-applier branch still exists; line refs rotted (battle_system.gd:488-496 is now ~289+). |
| #1242 | Volatility colour: owner_panel scalar rows + recolour on a flip that leaves the  — Two UI spots miss the violet 'volatile stat' colour: scalar rows in the owner panel, and rows whose value doe… | Probably still valid but path rotted: owner_panel.gd is now ui/tooltip_fan/panels/owner_panel.gd (has no is_stat_volatile reference); |
| #1269 | AI: place aspect temp upgrades within the aspect cap — Teach the AI to spend melee blade budget on aspect (e.g. | Still valid; AI only places clamp temp upgrades. Line ref rotted (:724 now ~:783-785). Self-described as awaiting a scorer shape. |
| #1296 | Melee: blade edges drawn stretched ('spaghetti') slamming a bunker+fortress node — Owner saw blade edges stretch absurdly long when slamming a node with both bunker and fortress; | Unreproduced playtest bug; its stated precondition (issues 1294 and 1295) is now met - both CLOSED - so the re-test it asks for is due. |
| #1443 | Hex × Spell: the shipped `hex` renamed or repointed, then a first shape — Design a brand-new first spell for the Hex row. | Body's rename/repoint fork was answered by owner comment 2026-10-11: hex becomes Malediction in 1560; this is a fresh Hex spell |
| #1523 | swarm-train: the first night comparison run — A checklist of measurements for the first swarm-train overnight run versus Whip. | Still a pending measurement run, but names transport ADR 1316 which is closed (ADR 0056 exists) |

### Should be Needs design (55) — Backlog rows that hold open design forks

| # | Verdict | Gist | Why |
|---|---|---|---|
| #54 | keep-refresh | Design: "overqualified casting" bonuses (non-range) — Decide what extra benefit a spell gets when cast from a node with more degree than its minimum (bes… |  |
| #56 | keep-refresh | Design: melee swing drive easing variations — Explore non-linear easing for melee swing drives and related swing stats. |  |
| #57 | stale? | Design: node specialization system (Corrupted/Crystallized/Anchor/Doubled) — Decide a model for special node states like Corrupted or Crystallized. |  |
| #75 | keep-refresh | Staggered bulk-allocation VFX (system-level) — Make a spawned entity's bulk allocation ripple outward from its core like the deallocation cascade. |  |
| #88 | keep | UI: plan-mode global feedback (screen-edge glow/tint per attack mode) — Add a persistent screen-edge glow keyed to the active attack plan mode so players know why clicks d… |  |
| #242 | keep | feat: add CoreClass that turns overhealing into armor plates (and has lowered hp — A proposed core class with lower HP where overhealing converts into temporary armor plates on nodes. | Body is an unspecced idea ('not sure' about the pool extension); needs a design pass before it is actionable. |
| #313 | keep | Revise ArchetypePolicy's clustering + weighting dials — Question of whether the procgen archetype tuning knobs (ratio, cluster sizes, jitter, forbid tags) … |  |
| #342 | keep | Node-visual baking pipeline — Idea to pre-render node rim/disk visuals to textures reused across all nodes. |  |
| #394 | keep-refresh | Faction-shared vision reveal — Idea to let a faction share one reveal set so a camp reacts together, as an AI difficulty lever. |  |
| #398 | keep | Redesign #376 composition-swap to avoid leaf-set swapping — SkillNode still tracks swapped scaled modifier sets as bookkeeping. |  |
| #403 | keep | Tech Seeds acquired from defeating passive blocker enemies — Pitch to give Tech Seeds a source: defeating inert blocker enemies drops one. |  |
| #408 | keep | design: find a secondary use for Clamp addon — Brainstorm a second purpose for the Clamp addon because it does only one thing. Entirely unscoped. |  |
| #409 | keep | design: edge sharpeners — Idea of an upgrade that makes an edge deal extra damage. |  |
| #416 | keep | Visual hint for the two-tier fan: tell players Shift reveals the full fan — Hovering a node now shows a reduced tooltip stack until Shift is held, and nothing tells the player… |  |
| #418 | keep | Should an edge leaving vision fade to zero instead of the 0.30 dim floor? — An edge that runs from a visible node to a fogged one fades to a 30% floor rather than vanishing, w… |  |
| #447 | keep-refresh | Design fork: build the addon weight-profiles/cost pass, or delete it? — Addon policy has weight-profile and cost knobs that the addon draw never reads. |  |
| #631 | keep | feature: blade slowdown/stutter FX on hits and crits — Idea for slow-motion or stutter emphasis on blade hits and crits. Several unresolved design forks. |  |
| #632 | keep | refactor: scale-carrying stat bindings (provenance) instead of N duplicated modi — Parked redesign so aura scaling binds one shared modifier plus a scale instead of duplicating it pe… |  |
| #666 | keep | ui: inline icon glyphs in UI prose — Wants small icons embedded in hint text such as 'you can {icon} Stake a node'. |  |
| #701 | keep | Graph.add_edge admits parallel edges — The graph lets two edges join the same pair of nodes, which some spells would misread as cycles. |  |
| #747 | keep | Victory: author three bonus conditions + multi-select lobby row — Builds the concrete extra win conditions (reach level, hold nodes, reach stat) and a lobby multi-se… |  |
| #828 | keep | Sweeping your own CORE as a blade member should mean something — An idea that swinging a blade through your own core should carry a distinct bonus and risk. |  |
| #829 | keep-refresh | StatDef.description hand-writes its ratio clause; compose it from the formula in — Stat tooltips hand-write numbers like '+1 per 10 STR' that go stale when the formula changes. |  |
| #859 | keep | A skipped starter slot mis-zips every later participant onto the wrong spawn — If the starter placer cannot seat someone it returns fewer spawn points, and every later participan… |  |
| #924 | keep | Tempo: lit/hollow pip + kill-refund transfer beat next to the AP gauge — A HUD pip next to the AP gauge showing whether tempo is armed, plus a +1 transfer animation on kill. |  |
| #925 | keep | ap_transfer_rate: restyle ConversionLabel into a muted/hover-reveal named-rate s — Restyle the existing end-turn conversion text into a muted row that reveals the AP-transfer rate on… |  |
| #961 | keep | Ranged2.0 follow-up: spatial reload — Reloading would count only leaves near the core, turning re-arming into a positional choice. |  |
| #967 | keep | Connectedness cures: status decay scales with entity degree — Statuses would clear faster on well-connected nodes, so a poisoned leaf lingers while a deep node r… |  |
| #968 | keep | Cleansing / healing fountain addons — Addons that strip status stacks or heal on nearby nodes each turn, the defensive mirror of DoT addo… |  |
| #969 | keep | One cleanse spell per DoT family, and a rare costly cure-all — One cleanse spell per damage-over-time family plus a rare expensive cure-all. |  |
| #970 | keep | Contagion: a spreading DoT as a multiplier on any family — A spell that copies or splits a target's status stacks onto its neighbours, making connectedness do… |  |
| #1012 | keep-refresh | LootSystem: credit the killing blow to the hit's attacker — Kills by damage-over-time or cascades are credited to whoever holds the turn, not the real attacker. |  |
| #1026 | keep-refresh | SpellCatalog: const preload list + ALL array -> authored .tres catalog — Replace the hand-maintained spell list with an authored resource catalog wired through an export, a… |  |
| #1055 | keep | tech-debt(procgen): ArchetypeStamp shipped with #163 and no preset has ever auth — ArchetypeStamp, a procgen pass for hand-placed archetype regions, exists but no preset uses it. |  |
| #1115 | keep | StatEffect: delete, or narrow to carriers without their own modifiers array — Decide whether to delete the StatEffect class or keep it narrowed to runtime-granted stat bundles. |  |
| #1192 | keep | Deeper AI: plan across every per-turn toolset (SP/DP/MP/AP), not one greedy pass — Hub for making the AI use every turn resource (SP, DP, movement, AP) and plan across them rather th… |  |
| #1193 | keep-refresh | AI spends DP: deallocation for mobility, tactical positioning and build tuning — Teach the AI to spend its deallocation points to shed nodes, reposition territory and retune its bu… |  |
| #1215 | keep | AI self-risk counts a melee gate fuse's own severance as a loss? — Question whether the AI should treat the edge severance caused by its own gate fuse as damage to it… |  |
| #1269 | keep-refresh | AI: place aspect temp upgrades within the aspect cap — Teach the AI to spend melee blade budget on aspect (e.g. |  |
| #1302 | keep | Spell picker hover previews possible sources and targets — When hovering a spell in the picker, the map would light up where it can be cast from and what it c… | Open owner-ownership fork (transient plan vs preview provider) needs a design pass |
| #1418 | keep | Loot rarity tiers (white → green → blue → purple → orange), formalized when need — A classic white-to-orange loot rarity ladder, parked by the owner until the game needs it. | Has open hue-collision forks; design before build |
| #1430 | keep | Pure-coolness archetype: a low-weight procgen node rolling only coolness, rainbo — A rare procgen node archetype that rolls only the coolness stat and draws a morphing rainbow rim. | Design pass pending (weight, rolls, rim shader) |
| #1437 | keep | Bleeding × Addon: Spike Ring refit (blade damage + bleed rider) — Turn the Spike Ring addon into Bleeding's addon: keeps blade damage, adds a bleed on hit and a +1 b… | Body itself says design pass pending / Needs design |
| #1438 | keep | Bleeding × Spell: first shape — Design the first Bleeding spell, choosing a shape with a topological twist (or skipping it if an in… | Body says design pass pending |
| #1442 | keep | Hex × Addon: map +1 aspect, blade rider — Design an addon for the Hex row: map face grants +1 hex aspect and blade face lands a hex stack on … | Body says design pass pending |
| #1443 | keep-refresh | Hex × Spell: the shipped `hex` renamed or repointed, then a first shape — Design a brand-new first spell for the Hex row. | Needs a design pass for the fresh first spell |
| #1444 | keep | Creep (inward trail aspect): design the contender — A contender aspect whose stacks creep along owned paths toward the core, damaging it on arrival. | Explicitly a design task |
| #1445 | keep | Exposed (surface DoT, STR × INT pair row): design the contender — A DoT whose tick scales with a node's edges to non-owned neighbours, so consolidating territory cur… | Explicitly a design task |
| #1446 | keep | Combos, pairs and third rows: exploration — Explore duo/pair mechanics across aspects, in the Hades-duo-boon vein, and whether a school's third… | Exploration, no spec |
| #1447 | keep | Codex: uniform status tooltip + a help page per game concept — Make every status effect show the same tooltip shape and grow the spell catalog into a help codex w… |  |
| #1458 | keep | Inverted crit: x-1 on crit_multiplier — A class and keystone that multiply crit_multiplier by -1 so attack crits heal and heal crits hurt. |  |
| #1533 | keep | Extract as addon procurement — Design extract so it pops an addon into a new addon inventory, one answer to how addons reach the b… |  |
| #1553 | keep | Turn-order strip: show the world turn — Add a marker in the turn-order strip showing when the world turn falls. Needs design on its look. |  |
| #1554 | keep | Per-status tick beat (parked) — Parked idea: let a status choose its own tick beat instead of the single world turn. |  |
| #1580 | keep | Corruption x Spell: rip corruption for damage — Hub for designing a corruption spell that cashes stacks in for damage; |  |

### keep (107) — still valid; by area

- **ai** (4): #280 Improves how the AI spends skill points and picks nodes.; #410 Adds a small data Resource of per-attack-mode affinity multipliers (magic/…; #1192 Hub for making the AI use every turn resource (SP, DP, movement, AP) and p…; #1215 Question whether the AI should treat the edge severance caused by its own …
- **aspects** (8): #1434 Hub for the STR Bleeding aspect row (flat-HP wound DoT on exerted nodes).; #1437 Turn the Spike Ring addon into Bleeding's addon: keeps blade damage, adds …; #1438 Design the first Bleeding spell, choosing a shape with a topological twist…; #1439 Hub for the INT Hex aspect row, a defender-side status making hexed nodes …; #1442 Design an addon for the Hex row: map face grants +1 hex aspect and blade f…; #1444 A contender aspect whose stacks creep along owned paths toward the core, d…; #1445 A DoT whose tick scales with a node's edges to non-owned neighbours, so co…; #1446 Explore duo/pair mechanics across aspects, in the Hades-duo-boon vein, and…
- **audio** (1): #48 Add sound effects for impacts, UI clicks and ambient layer plus a volume b…
- **aura** (1): #946 A new aura reach that selects nodes between N and M hops from the source i…
- **balance** (2): #788 Would let slow blades deal less than base damage, with base damage lowered…; #885 A request for a core class with no modifiers to serve as a clean baseline …
- **bug** (2): #859 If the starter placer cannot seat someone it returns fewer spawn points, a…; #1037 A poison arrow fired inside a real start_turn lands 0 poison in the live r…
- **combat** (1): #1471 The AI's kill-XP preview counts nodes only, ignoring the Avarice bounty bo…
- **core** (12): #240 A node cut off from core by an enemy hit would get one turn of grace befor…; #242 A proposed core class with lower HP where overhealing converts into tempor…; #398 SkillNode still tracks swapped scaled modifier sets as bookkeeping.; #452 Hub to finish a codebase audit that ran out of budget on stats_system, too…; #471 The vision-circle spatial grid uses cells as large as the biggest circle, …; #701 The graph lets two edges join the same pair of nodes, which some spells wo…; #817 A parked plan for replacing the physics-engine hit-scan on melee blades wi…; #960 Shorten the replay of back-to-back ranged volleys in one turn so peers do …; #1034 Makes StatBoard.add_modifier return the modifier instances actually active…; #1115 Decide whether to delete the StatEffect class or keep it narrowed to runti…; #1145 Refactor to move node hit-flash, blink and shake tween code out of SkillNo…; #1281 Make sure that if some effect lowers an entity's initiative cap below its …
- **core,tech-debt** (7): #427 A node's self-loop list is stored and saved in scenes though it is derivab…; #428 The melee blade is assembled in three near-identical places which have alr…; #433 Nothing automatically runs the tests before a broken change reaches master.; #434 Duplicated stat boards and their stats reference each other, so test board…; #435 HUD panels still use the old GlassPanel while the tooltip fan uses the new…; #436 Effect grants are stored as loose dictionaries with a hand-rolled kind swi…; #441 Spell-propagation has six small reducer classes that are near-duplicates.
- **design** (21): #403 Pitch to give Tech Seeds a source: defeating inert blocker enemies drops o…; #408 Brainstorm a second purpose for the Clamp addon because it does only one t…; #409 Idea of an upgrade that makes an edge deal extra damage.; #418 An edge that runs from a visible node to a fogged one fades to a 30% floor…; #445 The skill-node visual stack has two retired rim encoders (RimBonuses, Rune…; #631 Idea for slow-motion or stutter emphasis on blade hits and crits.; #632 Parked redesign so aura scaling binds one shared modifier plus a scale ins…; #828 An idea that swinging a blade through your own core should carry a distinc…; #961 Reloading would count only leaves near the core, turning re-arming into a …; #967 Statuses would clear faster on well-connected nodes, so a poisoned leaf li…; #968 Addons that strip status stacks or heal on nearby nodes each turn, the def…; #969 One cleanse spell per damage-over-time family plus a rare expensive cure-a…; #970 A spell that copies or splits a target's status stacks onto its neighbours…; #1200 Owner idea to let players mix and match the ~4 behaviour resources that ma…; #1201 Owner noticed spell propagation is effectively a graph automaton and wants…; #1203 Owner thinks the shipped halving decay for poison/armor break etc.; #1282 Owner idea for the Ninja core class: trade 1 max AP for 1 max tempo so it …; #1458 A class and keystone that multiply crit_multiplier by -1 so attack crits h…; #1533 Design extract so it pops an addon into a new addon inventory, one answer …; #1554 Parked idea: let a status choose its own tick beat instead of the single w…; #1580 Hub for designing a corruption spell that cashes stacks in for damage;
- **design,ui** (1): #416 Hovering a node now shows a reduced tooltip stack until Shift is held, and…
- **documentation** (1): #731 A documentation task: write down when effects are created, applied and rea…
- **frontmatter** (1): #747 Builds the concrete extra win conditions (reach level, hold nodes, reach s…
- **graph** (1): #1214 Small behaviour-preserving refactor so a gate flip goes through a GraphMir…
- **loot** (1): #1418 A classic white-to-orange loot rarity ladder, parked by the owner until th…
- **multiplayer** (3): #662 A placeholder for making the chosen victory rule travel to peers as data r…; #665 A manual task: play a real versus match across two physical machines on di…; #757 Adds a test flag where the client drops mid-game so the host's takeover is…
- **perf** (1): #387 Proposes a grid index so reach queries skip scanning all nodes.
- **procgen** (3): #313 Question of whether the procgen archetype tuning knobs (ratio, cluster siz…; #1055 ArchetypeStamp, a procgen pass for hand-placed archetype regions, exists b…; #1430 A rare procgen node archetype that rolls only the coolness stat and draws …
- **spell** (1): #283 Spells currently see the board as it was at cast time, so a node killed mi…
- **stats** (3): #287 Entity-only stats like core_health_scaling can be read or minted on a node…; #290 Reading a stat 'as this node sees it' merges entity and node bins separate…; #1415 Rename the once-per-turn kill-AP-refund stat from tempo to momentum, becau…
- **tech-debt** (5): #831 A measurement note saying cutting melee resolve cost via substeps barely h…; #836 An evaluation of replacing our hand-rolled git-worktree mise tasks with th…; #986 One integration test failed once when run sharded alongside others but pas…; #1014 A hygiene check that flags In-progress issues with no activity for a few h…; #1579 Delete the unused status-tag system and its save-format row.
- **testing** (1): #1246 The two-process multiplayer test never has the client player submit comman…
- **tooling** (2): #1038 The compile gate mise run check does not parse scripts under scenes/dev, s…; #1186 The multiplayer end-to-end gate times out randomly depending on the seed b…
- **ui** (14): #88 Add a persistent screen-edge glow keyed to the active attack plan mode so …; #282 Node HP and core HP are drawn as two unrelated bars though at the core nod…; #347 The SkillNode lab scene in the editor has no controls;; #580 Two edge-colour lift routines duplicate the same HDR algorithm and reasoni…; #666 Wants small icons embedded in hint text such as 'you can {icon} Stake a no…; #721 The lobby screen is still built in code rather than as a scene.; #924 A HUD pip next to the AP gauge showing whether tempo is armed, plus a +1 t…; #925 Restyle the existing end-turn conversion text into a muted row that reveal…; #1124 FanAnchor builds its TraceRouter params by hand and omits shoulder.; #1216 Pressing Esc or right-click doesn't cancel a half-confirmed gate toggle th…; #1302 When hovering a spell in the picker, the map would light up where it can b…; #1417 Pool gauge cells past the cap are all drawn in one amber;; #1447 Make every status effect show the same tooltip shape and grow the spell ca…; #1553 Add a marker in the turn-order strip showing when the world turn falls.
- **vfx** (4): #210 Adding one spell icon still needs manual mapping edits and a task run.; #735 A by-eye tuning guide for spell visual effects, to be done by the owner in…; #1054 When the camera follows a melee blade and the view widens, zoom is sized f…; #1112 Nodes seen via sense are lifted wholesale in z above the fog, which forced…
- **visuals** (6): #167 The hero-card sigil is drawn as a flat filled polygon and should get a sha…; #184 Edge rendering branches on 'sensed' in about four places.; #243 A real-3D boss halo around core nodes exists in a showcase but needs look …; #342 Idea to pre-render node rim/disk visuals to textures reused across all nod…; #350 Two baked icons (family_tree, trailblazer) have clamped gradients so their…; #1548 On the 800-node level under opengl3, shader instance-variable slots overfl…

## 7. Other lanes

### Intake + Ready (11)

| # | Lane | Gist | Suggested route | Note |
|---|---|---|---|---|
| #1606 | ready | Explosive barrel: temp-placeable — one AoE hit on impact — Let the Explosive barrel be placed as a temp for one blast. | needs-design | Swing face landed e25ee90; flip held on Needs-design 1605 |
| #1620 | intake | Whip run 2026-10-14 — Ledger issue for the overnight Whip run of 2026-10-14. | close-completed | Finished overnight run ledger; report posted |
| #1637 | intake | Whip run 2026-10-16 — Ledger issue for the overnight Whip run of 2026-10-16. | close-completed | Finished overnight run ledger; report posted |
| #1638 | intake | Test fixtures, sweep: test/unit/ (top level) onto TestWorld — Mechanical test refactor moving hand-built worlds in test/unit/ (top level) onto the TestWorld help… | ready | Complete spec, pure refactor, parent 432 in progress |
| #1639 | intake | Test fixtures, sweep: test/unit/attack/ onto TestWorld — Mechanical test refactor moving hand-built worlds in test/unit/attack/ onto the TestWorld helper. | ready | Complete spec, pure refactor, parent 432 in progress |
| #1640 | intake | Test fixtures, sweep: test/unit/systems/ onto TestWorld — Mechanical test refactor moving hand-built worlds in test/unit/systems/ onto the TestWorld helper. | ready | Complete spec, pure refactor, parent 432 in progress |
| #1641 | intake | Test fixtures, sweep: test/unit/ui/ onto TestWorld — Mechanical test refactor moving hand-built worlds in test/unit/ui/ onto the TestWorld helper. | ready | Complete spec, pure refactor, parent 432 in progress |
| #1642 | intake | Test fixtures, sweep: test/unit/effects/ onto TestWorld — Mechanical test refactor moving hand-built worlds in test/unit/effects/ onto the TestWorld helper. | ready | Complete spec, pure refactor, parent 432 in progress |
| #1643 | intake | Test fixtures, sweep: test/unit/network/ onto TestWorld — Mechanical test refactor moving hand-built worlds in test/unit/network/ onto the TestWorld helper. | ready | Complete spec, pure refactor, parent 432 in progress |
| #1644 | intake | Test fixtures, sweep: test/unit/combat/ onto TestWorld — Mechanical test refactor moving hand-built worlds in test/unit/combat/ onto the TestWorld helper. | ready | Complete spec, pure refactor, parent 432 in progress |
| #1645 | intake | Test fixtures, sweep: test/unit/vfx/ onto TestWorld — Mechanical test refactor moving hand-built worlds in test/unit/vfx/ onto the TestWorld helper. | ready | Complete spec, pure refactor, parent 432 in progress |

### In progress (17) — audit, read-only

| # | Gist | Verdict | Note |
|---|---|---|---|
| #187 | The Gate - a 2-node addon that toggles an edge on/off (hub) — Hub for the Gate addon that toggles an edge. | stale-hub | Closed: 1205,1206,1209; 1207,1210 In review but landed (cdfb050, db2172e) -> should be Done; 1208 Needs design |
| #395 | Armor break row — Aspect-matrix row for Armor break (arrow shipped, addon/spell/penetration stat pending). | stale-hub | Open children 1396,1397,1401 all Needs design; owner 10-12 said armor break should be a 100% Status, shape undecided |
| #420 | Audit 2026-08-13: structural cleanup hub (bucket C) — Hub of structural cleanups from an August audit. | stale-hub | Open children 422,427,428 Backlog + 432 hub; no activity since 08-14 |
| #432 | Unify the test fixture layer — Hub for moving the test suite onto one shared TestWorld fixture. | stale-hub | Child 1 (1628) landed 69e5876 2026-10-16; remaining sweep children 1638-1645 sit in Intake, none started |
| #1199 | design: one status stat per effect feeds arrows, melee temp upgrades and spell i — Design hub for how each status effect gets one stat feeding arrows, blades and spells. | stale-hub | Design hub; open children 1249,1253,1254,1211,395 all Needs design |
| #1211 | Explosive row — Aspect-matrix row for the Explosive effect (charges, barrel, spells). | stale-hub | Open children 1596,1604,1612 Needs design; 1608/1615 hubs also parked; no worktree |
| #1253 | Blindness row — Aspect-matrix row for Blindness (arrow, addon rider, sand spell, dazzle). | stale-hub | Open children 1391,1392 Needs design; 1491 In review but landed d0a3940 (should be Done) |
| #1254 | Scout row — Aspect-matrix row for Scout (scouting spells, lantern, blade face). | stale-hub | Only open child 1393 is Needs design; 1394,1490,1557 closed |
| #1313 | Whip: unattended overnight supervisor above swarm leads (hub) — Hub for the overnight-supervisor effort. | stale-hub | Only open child 1523 (swarm-train first night) is Backlog; ADR 0056 settled transport |
| #1369 | Refit the pre-aspect addons (SpikeRing, clamp, bunker, fortress) to the aspect m — Rework of four older addons to fit the aspect system. | stale-hub | Children 1629-1633 closed; 1634 (bunker x bunker) Needs design |
| #1378 | Corruption row — Aspect-matrix row for Corruption (arrow, addons, cures, sandpile). | stale-hub | All children closed except 1580 (Backlog) |
| #1379 | Curse row — Aspect-matrix row for Curse (Doombrand, Malediction, Gloomflux). | stale-hub | Only open child 1561 Gloomflux (Needs design) with a 6-day-old WIP worktree wt-gloomflux |
| #1380 | Wither row — Aspect-matrix row for Wither. Arrow and spell shipped; addon pending. | stale-hub | Only open child 1388 (addon) Needs design |
| #1419 | Greed row — Aspect-matrix row for Greed (status, avarice, arrow done). Addon, spell and a status reshape remain. | stale-hub | Open children 1423,1424,1459 Needs design |
| #1425 | Weakness row — Aspect-matrix row for Weakness (status and arrow done). Addon and spell remain. | stale-hub | Open children 1428,1429 Needs design |
| #1608 | Explosive grammar v2: three faces on the intake row, spend/power formula, a blas — Redesign of how Explosive charges spend and carry hits. | stale-hub | Children 1609-1611,1613 closed; only 1612 (filter-gated faces) Needs design |
| #1615 | Explosive VFX: the blast family (hub) — Hub for blast visual effects. Ring, riders and armed-piece look shipped; goo coat remains. | stale-hub | Children 1614,1616-1618 closed; 1619 (goo coat) Needs design |

### In review (11) — audit, read-only

| # | Gist | Verdict | Note |
|---|---|---|---|
| #653 | Post-swarm sweep: drain In review, reconcile the board, and evaluate five mid-sw — A one-off August checklist for draining In review after two swarms and ruling on five mid-swarm dec… | landed-but-open-questions | Last comment 2026-08-30 says nothing mechanical remains; only the owner calls on 589 and 652 are left |
| #793 | CombatReadout cards: missing stat rows — Hub for adding missing stats (node health, spike regen, blunting) to the combat HUD cards plus a st… | landed-but-open-questions | Hub with children A (rows) and B (914); 914 doc shipped; magic-card rows wait on 912 |
| #804 | perf/visuals: put the gimbal on the real 3D renderer — Parent epic to render core gimbal rings as real 3D objects instead of CPU-simulated 2D. | landed-but-open-questions | Children 1074/1075/1106 closed; |
| #914 | docs: stat→surface map with owner-confirmed hidden stats — An audit doc mapping every stat to the HUD surface that shows it (or why hidden). | landed-should-be-done | docs/domain/stat-surfaces.md on master (e902189, since touched through e2e8ad1); |
| #922 | experiment: autocompact / 200k window for drones only — An experiment to cap drone context mechanically via autocompact. | landed-but-open-questions | Config landed 1aebe14 (300k window, 350k guard); |
| #1076 | gimbal: wire the winning substrate onto live cores, HOLO_GLASS default, delete t — Hub for putting the chosen 3D gimbal on every live core and deleting the old 2D one. | landed-but-open-questions | Hub; children 1106 closed, 1107/1108 In review (landed 2026-09-24, owner gates remain); fog fix 0232673 2026-09-30 |
| #1107 | gimbal(world): fold A2 into GimbalWorld, delete B + occluder, MSAA, sleep at zer — The world half of the gimbal 3D move: one GimbalWorld, losers deleted, idle sleep. | landed-but-open-questions | Landed 2026-09-24 (sweep comment 10-03); |
| #1108 | gimbal(live): CoreGimbal register on CorePresence, delete the 2D CPU gimbal, lev — The live half of the gimbal 3D move: cores wear a CoreGimbal look, level drives ring count, 2D gimb… | landed-but-open-questions | Landed 2026-09-24; same owner gates as 1107; editor preview gap closed by 45238a3 |
| #1207 | Gate: flip animation — thrown rope, latch, thwang, snap; Edge.reveal — The Gate's edge toggle gets a rope-throw, handshake and snap animation. | awaiting-review | Landed cdfb050 2026-09-30; left open explicitly for the owner's sign-off on the feel (Gate rope sandbox tab) |
| #1210 | Gate: fuse scrubber over the hot window + plan-time self-cut warning — A UI scrubber to pick when gates in a melee blade fuse, with a self-cut warning. | landed-but-open-questions | Landed db2172e 2026-09-30; |
| #1491 | Blindness × Spell: reshape dazzle to climb the vision gradient — The Dazzle spell (Blindness row) now walks uphill along vision range, forking on ties, to hit watch… | landed-should-be-done | d0a3940 (2026-10-08) feat(spell) on master plus docs 97d39bd; no comments, no open questions |

## 8. Process notes

- The `gh` shim rejects a bare "@sha"; shas in posted headings are in backticks.
- Some leads used direct greps instead of haiku Explores.
- nd2 code claims were haiku-sourced with spot checks only; treat them as leads, not proof.
- Leads that spawned background children were force-handed-back before the children finished.
- Sweep rows carry no priority; ordering is by issue number.
