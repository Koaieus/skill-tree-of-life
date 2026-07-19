# Circuit-fan node tooltip (V2)

Epic #159: replace the old single-card `SkillNodeTooltip` with panels that
sprout from a hovered `SkillNode` along circuit-trace lines. This doc records
the design decisions from the #215 prune session — they only lived in GitHub
issue comments before this — plus the components built so far.

## The #215 prune session (2026-07-18)

The original brainstorm (issue #159) sketched a large tunable surface (a
`TooltipFanConfig` resource with ~28 exported knobs: `fanRadius`, `fanSpread`,
per-unit sync modes, four entry-anim styles, three trace styles, ...). #215
pruned that down. **Locked decisions:**

1. **Hand-authored variant scenes, not programmatic fan geometry.** Panel
   positions, line attach points, and line targets are authored in-scene with
   `@tool` live preview, not computed from `fanRadius`/`fanSpread` math.
2. **Build one variant now** (tree-sprout, parallel-start), clone for a radial
   variant later. Shared contract across variants: `line in → card in → card
   out → line out`, plus idle-while-open.
3. **Trace: one style only** — PCB / 45°-elbow family (`straight` dropped;
   `elbow == tree`). `corner`/`bend`/`bend_start` are exports on the line scene
   (`FanTrace`, #222); `trace_idle` on/off stays until a favorite lands.
4. **`sync_in`/`sync_out` baked to sequential** — line draws in → glowing tip
   arrives → card unfurls at the tip (the "sprout" read). The 3-way
   sequential/simultaneous/reverse enum from #224 is dropped.
5. **HP is just a panel** placed in the fan with keep-open-when-damaged
   retraction logic — no dedicated geometry system.
6. **Skin / mod-row = "which packed scene to instantiate"** (glass vs. holo;
   mod-row variants). Keep swappable while ≥2 options exist — not a
   monolithic enum baked into one scene.
7. **`TooltipFanConfig` (#216) deferred.** Don't build the 28-prop resource
   now; let it emerge from authoring the first variant.

**Knob reclassification** (from #215's raw brainstorm comment, pruned):

| Bucket | Knobs |
|---|---|
| Hand-authored in-scene | panel positions, line attach/target, per-unit stagger |
| Exports on the line scene (`FanTrace`) | `corner`, `bend`, `bend_start`, `trace_idle` |
| "Which packed scene" | `panelSkin` (glass/holo), `modRowStyle` |
| Owned by the animation setup — TBD | `entryAnim`/`idleAnim`/`leaveAnim`/`loopAnim` |
| A concrete panel's own job | `statChart`, `coreDetail` |
| Dropped entirely | `fanRadius`/`fanSpread`, `simpleCore`, `playMode`, `sprout`, `straight` trace style, the sync enum |

## The shared `progress(0..1)` clock contract

Every reveal in this system is driven by **one fixed clock**, read as
`progress(0..1)` by whichever component needs it — never a per-component
Tween chain, and no hop/component ever gates when the next one starts. This
is the same contract the spell-VFX system already uses (propagation clock is
fixed; animations read `progress`, never gate the next hop) — `fan_trace_sandbox.gd`
documents it explicitly and drives all five `FanTrace` + destination pairs off
one `_clock` var. **This is why #223 (`FanPanel`) doesn't build the four
entry-anim Tween recipes #215 left TBD** — the existing clock-driven
scale+fade reveal (cubic ease-out) already does the job; `FanPanel.set_progress(t)`
just makes that reveal reusable instead of hand-rolled per-destination.

## Components so far

- **`FanTrace`** (`ui/tooltip_fan/fan_trace.gd`, #222) — one circuit-trace
  connector: `Line2D` + glowing `Sprite2D` tip, geometry from `TraceRouter`
  (PCB-elbow only, per decision 3). `progress` (0..1) truncates the drawn
  arc-length. `play_draw_in()`/`play_erase()` return a `Tween` to `await`.
- **`FanPanel`** (`ui/tooltip_fan/fan_panel.gd`, #223) — thin wrapper around
  a hand-placed skin child (`GlassPanel` or `HoloPanel`, swapped by editing
  which scene is instanced under it — decision 6, not a runtime enum).
  Forwards a single `glow` (0..1) to whichever skin is present, and exposes
  `set_progress(t)` implementing the clock-driven scale+fade reveal described
  above. **Does not own Tween entry-anim recipes** — entry-anim ownership is
  still TBD per decision 7's "owned by the animation setup" bucket.
- **`fan_trace_sandbox.gd`/`.tscn`** (#233) — in-editor preview harness,
  reachable from the sandbox host's "Fan Trace" tab. Five `FanTrace`s sprout
  from a mock node to four corner `FanPanel` destinations (mixed glass/holo
  skins, demonstrating the swap) plus a top row of `ModSlabRow` tiles. Drives
  everything off one clock (`_clock`), matching the contract above.

## What's still open

- `FanUnit` (#224) — pairs one `FanTrace` + one `FanPanel` with a
  `HIDDEN → IN → LOOP → OUT → HIDDEN` state machine; trace→panel ordering is
  baked sequential per decision 4.
- `TooltipFan` coordinator (#226) — the real node-anchored fan, driving
  `FanUnit`s from a hovered `SkillNode`; this is where the tree-sprout variant
  actually gets authored (decision 2), and where `TooltipFanConfig` (#216)
  should be revisited once real knobs emerge.
- Entry-anim ownership — still undecided whether panels/lines need to know
  about it at all, or whether it lives entirely in whatever drives the shared
  clock.
