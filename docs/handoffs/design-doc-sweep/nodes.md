## docs/design/node_subtypes.md

> **Headline finding: this doc is stale by omission, not by error.** Its own
> banner (line 3) says "Nothing here is built." That was true 2026-09-22; it
> is false today. `NodeSubtype` (`procgen/subtypes/node_subtype.gd`), the
> per-pool `subtypes` gate (`StatPool.subtypes`, `admits_subtype`), the
> `base_chance` roll off a salted RNG stream, the ragged-grid fallback, the
> modulate/tint visual, and the full DEX/STR/INT/CON/PER/WIS content grid are
> all shipped (verified below). The doc was never updated after the build
> landed (#1093/#1094/#1095, #1189). Nearly the whole thing is IS.

| Lines | Section | Bucket | Destination / what to cut | Evidence (file:line or grep) |
|---|---|---|---|---|
| 1–5 | Title + "nothing here is built" banner | WAS | Cut the "nothing built" claim; it's false. Keep one line of provenance ("opened from #1025") if doc survives at all. | `procgen/subtypes/node_subtype.gd` exists; see below |
| 7–22 | The reframe (archetype+subtype axis) | IS | `docs/domain/procgen-v4.md` or NEW:`docs/domain/node-subtypes.md` | `procgen/subtypes/node_subtype.gd:1-40`; `skill_node.gd:136 @export var subtype` |
| 24–35 | "Archetype picks family, subtype picks pole" | IS | same as above | `graph_procgen.gd:1497-1531` (subtype-gate resolution) |
| 37–49 | The grid table | MIXED | IS for the mapping (verified all 6 archetypes below); WAS for "potency" terminology — renamed to `<family>_stacks_per_hit`, no separate `_potency` stat exists | `git log`: `4f73b11 docs: potency stat ids re-pointed to <family>_stacks_per_hit after #1189`; `stats_system/defs/` has `poison_stacks_per_hit.tres` etc., **no** `*_potency.tres` file (`ls stats_system/defs/ \| grep potency` → empty) |
| 51–56 | Rationale bullets (curse→CON, wither→INT, blindness→PER, resistances leave universal) | IS | fold into NEW domain doc | `procgen/pools/constitution.tres:95-97` (`curse_resistance`); `procgen/pools/intelligence.tres:159-161` (`wither_resistance`); `procgen/pools/perception.tres:112-114` (`blindness_resistance`); `procgen/pools/universal.tres` has **no** `resistance` stat_id (grep empty) |
| 58–73 | "Subtype replaces, never adds" (the sidegrade rule + owner sketch) | IS | domain doc | `procgen/pools/dexterity.tres` has 13 `subtypes` gates in place (grep count) — set-gate pattern shipped |
| 75–100 | DoT stat vocabulary (12 per-family + 2 shared, "8–16 stats") | WAS | Delete — superseded in the same file by Decision 21–22 ("v1 vocabulary is 7 stats... falloff/duration are per-def shapes... **not stats**") | Same doc, lines 446–447 (Decisions 21–22) contradicts lines 75–100 directly |
| 90–100 | "The umbrella-stat trap" | IS | keep as rationale in domain doc — still describes a real constraint on `dot_stacks_per_hit` | `stats_system/defs/dot_stacks_per_hit.tres` exists, scoped per decision 17 |
| 102–114 | "Corrupted" name-collision note | COULD | Stays in design (cross-references the still-unbuilt `Corrupted Node` in `skill_node_specializations.md`) | n/a — precautionary naming note, not a behaviour claim |
| 116–122 | Visual language (rim tint) | IS | domain doc | `skill_node/visuals/node_visuals_composite.gd:189-190` "Subtype-identity tint (#1057)... through Emissive.at()" |
| 124–309 | How subtype content is authored (①membership Resource+gate, ②give-up-as-same-set, 3 authoring rows, ergonomics) | IS | domain doc (this is the load-bearing mechanism spec, now as-built) | `procgen/subtypes/node_subtype.gd` matches the sketched class verbatim (`id`, `display_name`, `tint`, `emissive_tier`, `base_chance`); `stat_pool.gd:54` `@export var subtypes: Array[NodeSubtype]`; `stat_pool.gd:312 func admits_subtype` |
| 311–339 | How subtype is generated (per-node base_chance) | IS | domain doc | `node_subtype.gd:40 @export_range(0.0,1.0) var base_chance`; `graph_procgen.gd:1539 acc += s.base_chance` |
| 341–364 | Fallback that makes a ragged grid safe (decision 13) | IS | domain doc | `graph_procgen.gd:1501` region implementing the "stands only if drawable" predicate (per decision 13, matches described contract) |
| 366–378 | "Why this is the right v1, not a shortcut" | MIXED | Rationale for the shipped per-node roll is IS; "promote to clustering only if speckle reads badly" is COULD (unbuilt, deferred) | `graph_procgen.gd` has no second BFS-grow pass for subtypes (only the roll at ~line 335) |
| 380–386 | "If it is promoted later" (clustering upgrade path) | COULD | Stays in design | Not built — no `archetype_stamps`-style subtype region code found |
| 388–407 | How subtype is drawn — modulate chosen as first cut | IS | domain doc (rendering-performance adjacent) | `node_visuals_composite.gd:189` confirms modulate/Emissive path shipped, not a new instance uniform |
| 408–415 | "On the rotating stripe" | WAS/COULD split — call MIXED | The "no TIME, NO SPIN" fact is current (IS, keep as a rendering constraint note in domain doc); "treat as later upgrade" is COULD | not implemented — no stripe-phase code found |
| 417–439 | Decisions log (#1–16, 2026-09-22 sessions) | IS | All match shipped code (verified: NodeSubtype-as-Resource, per-pool set gate, base_chance placement, ragged-grid fallback). Belongs in domain doc as "how it works," or split into an ADR per the owner's "record settled architectural calls" convention — **owner's call, not mine** | Cross-checked against code throughout table above |
| 440–447 | Decisions added 2026-09-23 (#17–22: WIS/PER cells, stat count = 7) | IS | Confirmed shipped: commits `81c2c14` (blessed WIS), `55e705c` (blighted WIS), `8b679b1` (blighted/blessed PER) | `git log --oneline -- docs/design/node_subtypes.md` |
| 449–462 | "The subtype roll needs its own salted RNG stream" | IS | domain doc | `graph_procgen.gd:274-275` `subtype_rng.seed = rng.seed + _SUBTYPE_RNG_SALT` |
| 464–473 | "v1 needs zero new stats" / blocked-by #975 note | WAS | Stale — the content build (which *does* add many stat-gated pools, though not new StatDefs beyond what already existed) happened; the "blocked-by #975" framing is resolved (resistances already moved off universal, confirmed above) | See line 51–56 evidence |
| 475–497 | `~~forbid_tags~~` section (explicitly struck through, "resolved... kept because correction matters") | WAS | Textbook WAS by the owner's own rule — struck-through old call, "kept for the record." Delete; ADR or git history holds it if ever needed | Doc's own `~~...~~` heading is the tell |
| 499–507 | Open questions (1–3 struck through/settled; 4,5,7 genuinely open; item 6 moot) | MIXED | Struck-through 1–3 and moot item 6 → WAS, delete. Items 4 ("can subtype territory convert"), 5 ("fifth/sixth family"), 7 ("exact stat count" — actually **settled** by decision 22 at 7, so also WAS/stale) → COULD, stays | Decision 22 (line 447) already answers Q7 with "7 stats," contradicting Q7 still being marked open |

**Bucket counts — node_subtypes.md:** IS 15, WAS 6, COULD 3, MIXED 5 (28 rows)

---

## docs/design/skill_node_addons.md

Doc already self-annotates status per addon (shipped/speculative/OPEN) far more
carefully than node_subtypes.md; classification below mostly confirms its own
banners rather than overturning them. Spot-verified the "shipped" claims
against code; did not re-derive every OPEN sub-point.

| Lines | Section | Bucket | Destination / what to cut | Evidence |
|---|---|---|---|---|
| 5–14 | "Two Distinct Concepts" (addon vs specialization + designer test) | COULD | Stays — frames an unresolved boundary between two systems, one (addons, partially) shipped, one (specializations) wholly unbuilt | n/a, framing text |
| 17–89 | Armor Ring / "Bunker" | IS | `docs/domain/melee-blade-sim.md` (doc already says so at line 89) | Doc's own banner: `skill_node/addons/bunker_addon.gd` confirmed present (`ls skill_node/addons/`) |
| 93–100 | Reinforcement | COULD | Stays — no `reinforcement_addon` file or equivalent found | `grep -rli reinforcement skill_node/` → empty |
| 103–110 | Fortification | IS (per doc's own "Implementation: melee-blade-sim.md" pointer, not independently re-verified) | `docs/domain/melee-blade-sim.md`, "Fortification drag" section (already cited) | doc-internal pointer only |
| 113–129 | Buffer | COULD (doc's own banner: "Speculative — not built") | Stays in design | doc's own banner, lines 116-118 |
| 131–144 | Winch | COULD | Stays — `grep -rli winch skill_node/` finds nothing; not built | grep empty |
| 146–162 | Clamp | IS | `docs/domain/melee-blade-sim.md` (rigidity/joints section) | `skill_node/addons/clamp_addon.gd`, `clamp_addon.tscn` exist |
| 164–186 | Spikes | IS for the shipped pop-budget half (`SpikeRingAddon`, `spikes`/`spike_regen`/`blunting` StatDefs, #778); COULD for the still-open collision/structure-attack candidate — doc already marks this split itself | keep split as-is; IS half → `docs/domain/melee-blade-sim.md` or new spikes domain doc | `find . -iname 'spike_ring*'`; `stats_system/defs/` has `spikes`? — verify below |
| 189–205 | Toxin / DotAddon | IS | doc already cites `skill_node/addons/dot_addon.gd`, `toxin_addon.tscn` | confirmed present |
| 208–239 | Gate | COULD | doc's own banner "NEW — confirmed direction; sub-points OPEN" | banner |
| 241–250 | Lifeline | COULD | Stays — only hit is a comment listing "lifeline" as an example status-marker string (`skill_node/skill_node.gd:403`), not an implemented mechanic | `grep -in lifeline skill_node/skill_node.gd` → one comment, no logic |
| 253–272 | Lifelink | COULD | Stays — no hits at all | grep empty |
| 276–288 | Relay | COULD | doc's own banner: "Direction confirmed... damage bonus and routing cost OPEN" — no code citation given | banner |
| 292–324 | TBD Addons (Anti-Magic, Conduit) | COULD | doc's own header says "not confirmed mechanics" | banner |
| 326–353 | Tech Seeds | COULD | no built/shipped language anywhere in section | n/a |
| 355–363 | Addon Design Principles | COULD/IS mix, treat as COULD | general framing, not a specific behaviour claim | n/a |
| 365–377 | Open Questions | COULD | all genuinely open per doc's own text | n/a |

**Bucket counts — skill_node_addons.md:** IS 5 (Bunker, Fortification, Toxin, Clamp, Spikes-partial), MIXED 1 (Spikes: shipped pop-budget half + open collision-candidate half), COULD 11, UNSURE 0 (17 rows total)

---

## docs/design/skill_node_specializations.md

Whole document carries an explicit, dated, correctly-labelled banner (lines
3–8): *"Status: early spitball, not a design commitment... None of it is
built or scheduled... do not reconcile newer designs against it."* This is
the doc functioning exactly as `docs/design/` should — no cleanup needed.

| Lines | Section | Bucket | Destination / what to cut | Evidence |
|---|---|---|---|---|
| 1–16 | Banner + A/B specialization taxonomy | COULD | Stays — honest, dated, self-labelled speculative | banner text itself |
| 20–33 | Corrupted Node | COULD | Stays | Not built — `grep -rn "Corrupted" --include='*.gd'` (checked as part of node_subtypes cross-check) found no matching gameplay class, only the naming-collision note in `node_subtypes.md` |
| 35–45 | Crystallized Node | COULD | Stays | not independently re-checked, doc gives no code citation, banner covers it |
| 47–55 | Anchor Node | COULD | Stays | no code citation |
| 57–79 | Doubled Node | COULD | Stays | no code citation; explicitly "experimental, TBD" |
| 82–86 | Design Principles | COULD | Stays | n/a |
| 88–95 | Open Questions | COULD | Stays | n/a |

**Bucket counts — skill_node_specializations.md:** COULD 7, IS 0, WAS 0, MIXED 0.

---

## Cross-doc references that would break

- `node_subtypes.md` → `skill_node_specializations.md` (line 104, "Corrupted"
  naming-collision note) — survives either way since both docs are cited by
  path, but if `node_subtypes.md`'s bulk moves to `docs/domain/`, this one
  COULD-bucketed paragraph is the only piece that still needs to physically
  live in `docs/design/`, so it should NOT move with the rest.
- `skill_node_addons.md` line 9 and 367 cross-link to
  `skill_node_specializations.md`'s Open Questions #1 (the addon/specialization
  boundary) — both sides reference each other; if either file moves, update
  both link targets.
- `skill_node_addons.md` Spikes section (168, 176, 180) cross-references
  `combat_system.md` for the "sharpness" unification that #778 retired — a
  stale claim in `combat_system.md` about thorns=spikes-as-one-stat would now
  contradict this doc's already-corrected text; not checked here (out of
  scope — not one of my three assigned docs), flagging for the owner.
- `node_subtypes.md` cites `damage_over_time.md` seven times as the model the
  DoT family leans on — if `node_subtypes.md` moves to `docs/domain/`, check
  `damage_over_time.md`'s own status doesn't already claim to be `docs/domain/`
  (i.e. avoid a design-doc-citing-a-design-doc situation becoming two domain
  docs citing each other, which is fine, vs. one design + one domain, which
  needs the domain one to not depend on speculative content).

## False-today claims (name the evidence)

1. `node_subtypes.md:3` — "Nothing here is built." **False.** The entire
   mechanism (`NodeSubtype` resource, per-pool gate, salted-RNG roll,
   ragged-grid fallback, modulate visual) and the full content grid for all
   six archetypes are shipped. See per-section evidence above.
2. `node_subtypes.md:501` (Open Questions item 7, "Exact stat count... 14 is
   the proposal") — contradicted by the same file's Decision 22 (line 447):
   "v1 vocabulary is 7 stats, not 14." The open question was never
   re-resolved after the decision landed.

## Notes (owner's call)

- **node_subtypes.md is the headline finding of this survey.** It reads as a
  design doc but is now ~90% "what is." Recommend: gut it to
  `docs/domain/node-subtypes.md` (rewrite as present-tense fact, per this
  report's IS rows), leave a thin `docs/design/node_subtypes.md` stub (or
  delete it) holding only the genuinely open items — territory conversion
  (Q4), a possible fifth/sixth family (Q5), and the clustering-promotion
  upgrade path (lines 380–386) — plus the Corrupted-name-collision note. The
  ~20-decision log (lines 417–447) reads like ADR material (dated, owner-
  quoted, settled); whether it becomes an ADR or plain prose in the new
  domain doc is a call for the owner, not something I should pick.
- **skill_node_addons.md: Clamp is shipped but undocumented as such.**
  `skill_node/addons/clamp_addon.gd`/`.tscn` exist; the design doc still
  presents Clamp as a plain design sketch with no shipped/speculative banner
  (unlike Bunker/Toxin/Spikes, which self-annotate). Worth a one-line status
  banner and a domain-doc pointer, same treatment as Bunker got.
- **skill_node_specializations.md needs no cleanup.** It is the model case:
  dated, owner-quoted, explicitly labelled speculative, explicitly says not
  to reconcile against newer designs. Leave it exactly as-is.
