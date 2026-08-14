# Handoff — codebase audit 2026-08-13

**Status: audit ~85% delivered, zero fixes applied.** 8 of 11 slice reports are
complete and committed under `docs/handoffs/audit-2026-08-13/`. Nothing has been
refactored yet. A fresh session should start at **§4 What to do next**.

---

## 1. Autopsy — why the token budget died

The fan-out (11 parallel opus auditors over ~65k LOC of first-party GDScript)
consumed **0% → 115% of a 5-hour window in under 10 minutes**. Reports were
salvaged only because the auditors were ordered to dump partial results ~40
seconds before the cutoff.

**Correct the instinct before repeating this:** the work was *not* 20% done at
cutoff. All 8 surviving reports are complete — 20–25 ranked findings each, no
`## Incomplete` sections. Only 3 slices (stats, tooltip-fan, hud) were lost. So
the true cost of this fan-out was roughly **115–130% of one window**, not the
400–500% it felt like. That is close enough to affordable that the fixes below
bring it comfortably inside one window.

### Root causes, in order of size

1. **Subagents inherited the `advisor` tool. This is the big one.** `advisor`
   forwards the calling agent's *entire transcript* to another opus model. For a
   code auditor that transcript is every file it has read. An auditor that read
   4000 lines and called advisor twice paid for that corpus **three times** —
   once accumulating it, twice more re-sending it to a second opus. The
   orchestrator already *is* the advisor for a subagent; the subagent calling one
   is pure duplicated spend.
   → **Every subagent prompt must say: do NOT call `advisor`.** The tool
   description tells them to call it before substantive work and again when done,
   so they will do it unless explicitly forbidden.

2. **Monotonic context re-send.** An agent's context only grows as it reads, and
   every subsequent tool call re-sends the whole thing. 40 tool calls averaging a
   40k context ≈ 1.6M input tokens for *one* agent, before any advisor call.
   × 11 × opus rates.

3. **"Read every `.gd` in scope in full" was the wrong instruction** — it
   maximises precisely the quantity that gets re-sent every turn. Scope by
   symptom (churn, size, the named hypotheses) and read selectively.

4. **All-opus at 11-wide was the orchestrator's call and it was wrong.** The
   owner's concern — a Sonnet-written module graded by Sonnet — is legitimate,
   but the answer is *fewer opus units*, not eleven of them.

### Budget rules for any future fan-out in this repo

- Forbid `advisor` in every subagent prompt, explicitly.
- Ceiling **~6 opus subagents per 5-hour window**, or ~11 if advisor is off *and*
  reading is scoped rather than exhaustive.
- Reports go to **disk**, never into the orchestrator's context as return values.
  This worked and should be kept regardless of budget.
- Commit salvaged artifacts to the **repo**, not the scratchpad — the scratchpad
  is session-scoped and evaporates.
- With a 1M context, the orchestrator's own context is the *cheap* resource and
  subagent spend is the scarce one. Prefer the orchestrator reading and fixing
  sequentially over another fan-out.
- "You've hit your monthly spend limit" in this account means the ordinary token
  limit; the monthly spend limit is $0.

---

## 2. Phase 0 + 1 results (done, durable)

- `mise run check`: **clean.**
- `mise run test`: **1443/1449 — master is red**, verified identical on a pristine
  `HEAD` worktree, so the owner's uncommitted WIP is innocent. Failures:
  `test_spell_defs::test_reverberator_preset_well_formed`,
  `test_node_visuals_contract` ×2, `test_tooltip_v2_accessors::test_spike_ring_…`,
  `ui/test_fan_scene::test_every_fan_traces_terminus_is_self_consistent`.
  **Auditors say the tests are right and the code/scenes are wrong** — see
  audit-skill-node #3 and audit-attack #3.
- Rules that held: **zero** `get_neighbours().size()` degree violations, **zero**
  raw `PoolStat.base_value` writes.
- Rules that did not: legacy sandbox `panel_scene` tabs — the grep found 6, the
  devtools auditor found **9**.
- ~220 bare `Dictionary`/`Array` without type params (ui 40, procgen 38, attack
  34, skill_node 28, tools 23, systems 21). Untyped `var` is rare (≤3/dir, except
  `tools/` at 11). Missing `-> ` return types cluster in attack (26), procgen (22).

Working tree still carries the owner's self-loop WIP in
`scenes/dev_sandbox.tscn`, `addons/spell_playground/playground_panel.tscn`, and
resave churn in `bruiser.tres` / `reverberator.tres`. **Left deliberately dirty**
— it is the reproduction case for the bugs below. `bruiser.tres` also gained an
unused `rank_pass.gd` ext_resource.

---

## 3. The owner's three reported smells — all diagnosed

**Smell 3 — "adding one self-loop made all other edges vanish."** Root-caused
independently by two auditors, and **the multimesh hypothesis in the brief was
wrong**. `addons/spell_playground/playground_panel.gd:200` builds the grid edges
at `_ready` behind an all-or-nothing guard: `if not graph.get_edges().is_empty():
return`. The scene authors zero `Edge` children at HEAD, so the owner's one
authored self-loop makes that check non-empty and **all 24–27 grid edges are
never built**. They did not vanish from a renderer; they were never created.
`dev_sandbox.tscn`, which authors its edges properly, is the control case and
does not break. Related: that panel is half-authored/half-generated — `_layout_world`
also overwrites every authored position, so editor-authored topology *and* shape
are both fiction. The panel's own TODO ("THIS IS SUPPOSED TO BE A PRE-AUTHORED
SCENE") is currently unimplementable.

**Smell 2 — "self-loops don't glow."** Exact divergence point found:
`graph/edge.gd:364`, `_draw_self_loop()` calls `_display_color()`, which its own
docstring marks SDR-only. The multimesh path calls `_display_color_lifted()`
(`edge.gd:325`), the only place the `pow(2, lit_glow_stops)` HDR lift is applied.
A lit self-loop's colour never crosses 1.0, so the shared `WorldEnvironment` glow
pass never fires, and the authored `lit_glow_stops = 4.5` is silently a no-op for
self-loops. A **third** divergence was also found: `edge.gd:113` sets a sensed
self-loop to z 991 (`ZLayers.EDGE + ZLayers.SENSED` = -10 + 1001), which is
*below* the fog overlay at z 1000, so sensed self-loops are painted over.

**Smell 1 — "`Edges` vs `EdgeMesh`, why two nodes?"** The auditor's answer is
"neither" — `MultiMeshInstance2D` accepts children, so merging the *nodes* is
cosmetic. The real duplication is **two complete render pipelines for one
concept**: stretched-quad multimesh + `edge_mesh.gdshader` vs. per-instance
`_draw_self_loop`; `_display_color_lifted` vs `_display_color`; per-fragment
vision self-shading vs `FogOverlay`'s `modulate.a` + z dance. Smells 2 and 3 are
both symptoms. #413 scoped self-loops out and never came back. Fix shape: bring
the loop ring into the batch (second `MultiMeshInstance2D` with a ring mesh, or
an SDF branch keyed off custom data), after which `Edges` can stop being a
CanvasItem and become a plainly-named `Node` container.

**Bonus, same cluster:** `skill_node.gd:137` `@export var self_loops: Array[Edge]`
is a *derived runtime index that the editor serializes* — the owner's WIP baked
`[null, NodePath(...)]` into the scene, so `self_loop_count` reads 2 for one loop
and `GraphMirror.get_degree` over-reports degree by +2 while `Graph._ensure_topology`
counts it correctly. Two disagreeing degree answers feeding spell `min_degree`
gating.

---

## 4. What to do next

**Do not fan out again.** Read the reports directly and fix sequentially.

1. `ls docs/handoffs/audit-2026-08-13/` — 8 reports, ~167 findings total, each
   ranked most-severe-first in a fixed `SEVERITY | file:line | title` /
   **Defect** / **Breaks** / **Fix** format. Read them; they are dense and
   already filtered for style-only noise.
2. Write a consolidated triage doc before touching code.
3. **Apply NITs and small fixes directly**, in file-disjoint batches,
   `mise run check` + tests + commit per batch (standing commit-as-you-go
   authorization).
4. **MEDIUM findings: ask the owner once**, as a single numbered list with an
   apply-vs-issue recommendation per item. This fork was raised and never
   answered.
5. **LARGE findings → GitHub issues** under one new hub, `gh issue create
   --parent`, heredoc + `--body-file` (never `--body` with backticks).
6. **Three slices were never audited: `stats_system/` + `skill_node/addons/`,
   `ui/tooltip_fan/` + `ui/spell_tooltip/`, and `ui/hud/` + `ui/gauges/`.** The
   hud one carries an unfulfilled owner ask: an explicit inventory of which HUD
   elements use real emissive vs. faked pre-bloom glow, with `ui/gauges/`
   (`pool_gauge`, `composite_bar_gauge`, `capacity_pip`) named directly. The
   original prompts for all three are reconstructable from `00-brief.md`.

### The LARGE findings, at a glance

| Slice | LARGE findings |
|---|---|
| skill-node | RimRing's unbatched escape hatch on every node; committed baked instance uniforms defeat the fog gate; the 2 failing visual-contract tests are right and the scenes are wrong; `skill_node.gd` god object (5 concerns, 3 clean seams); `self_loops` exported derived state |
| attack | blade construction written three times; parallel per-effect-kind slots instead of a hit list (cf. #381); `reverberator.tres` contradicts its own description and test |
| procgen | 1066-line static class hiding six phases; self-flagged stub owns the content hot path; `already_rolled` permanently empty in v4; addon pass's documented pipeline does not exist; `generate` mutates the config it is handed |
| vfx | two live panel systems, migration stalled; three parallel aura mechanisms; bounce-coordinator drain loop can end before later beats fire; verdict delivered on the `effect_context` TODO |
| systems | scene-authored ownership never applies node modifiers; teardown duplicated across deallocate/force_deallocate; cascade authority is a second system inside BattleSystem |
| test-infra | no fixture layer, 44 tests rebuild the world; nothing gates the suite, so the process pre-authorizes red master; Board↔Stat cycle leaks every duplicated board |
| graph-core | two edge render paths (see §3) |
| devtools | the self-loop edge bug (§3); playground half-authored/half-generated; **nine** legacy `panel_scene` tabs |

### Cheap early wins

`graph/edge.gd:364` (one-line `_display_color` → `_display_color_lifted`) and
`graph/edge.gd:113` (z-band fix) close two of the owner's three smells. Verify on
a real opengl3 renderer, **never headless** — `edge.gd:279-301` records that the
headless path previously lied about exactly this.

---

## 5. Housekeeping

- A pristine `HEAD` worktree may still exist at
  `<scratchpad>/pristine` — `git worktree remove` it when convenient.
- Delete this handoff and `docs/handoffs/audit-2026-08-13/` once the findings
  have been converted to issues and fixes.
