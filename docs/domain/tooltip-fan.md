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

## The `progress(0..1)` contract — and who owns the Tween (settled #226)

Every reveal in this system is expressed as **`progress(0..1)`**: a component
renders whatever `t` it is handed and never animates itself. That is why #223
(`FanPanel`) doesn't build the four entry-anim Tween recipes #215 left TBD —
the clock-driven scale+fade reveal (cubic ease-out) already does the job, and
`FanPanel.set_progress(t)` just makes it reusable instead of hand-rolled per
destination.

An earlier phrasing of this rule ("one fixed clock … never a per-component
Tween chain") was read as mandating a single **fan-wide** clock, and #224's
`FanUnit` was flagged as violating it. It does not. The line meant *leaf
components own no Tween* — it never meant the fan is one timeline. Settled:

**Tween ownership stops at `FanUnit`.** Three tiers, no ambiguity:

| Tier | Owns a Tween? | Contract |
|---|---|---|
| Leaf components — `FanPanel`, `ModSlabRow`, `PanelHeader`, `StatValueRow`, `AddonItem` | **No** | Expose `set_progress(t)` (or a `progress` property). Render `t`, nothing else. Rest state is `t = 0`; never set your own alpha as a side effect of an entry call. |
| `FanUnit` (+ `FanTrace`'s `play_draw_in`/`play_erase`) | **Yes** | One independent, sequential chain per unit: line draws out → completes → panel animates in → completes → holds. OUT is the reverse read: panel fades → completes → trace erases (no glowing tip) → completes. |
| `TooltipFan` coordinator | **No** | Owns *only* a per-index start delay. It fires N independent unit sequences and awaits them; whether that's 2 units or 6 changes nothing but the delays. |

**There is no fan-wide clock.** Independent tweens with a variable delay are
the simple form of exactly the choreography wanted, and they keep the sequence
readable as a chain of completions rather than as arithmetic on a normalized
`t`.

**Interrupt = kill and reverse.** A hover→unhover mid-reveal kills the running
tweens and plays OUT from the **current** progress — a half-drawn trace
retracts from half-drawn; it never pops to full first, and never hard-cuts.
`FanUnit._generation` stays: a tween that finishes on the same frame as the
interrupt would otherwise resume a stale continuation.

Two implementation facts that contract implies:

- **`FanPanel` is write-only** — `set_progress(t)` is a method, with no getter
  (`FanTrace.progress` *is* readable). `FanUnit` caches the last `t` it pushed.
  Don't add a panel getter and don't read the Tween's elapsed time: the leaf
  stays a pure sink, and the unit already owns the tween that produced the value.
- **Each leg scales its reverse duration by its own progress** — panel fade by
  the cached panel progress, trace erase by `_trace.progress`. Not a composite:
  the legs run sequentially and each retracts its own thing. A zero panel
  progress then degenerates to a zero-length panel leg, which *is* the "skip the
  fade leg when the panel never opened" rule — no `if` needed. Floor both at
  ~0.03s so a near-zero leg still yields a frame.

`fan_trace_sandbox.gd` drives its five trace+destination pairs off one `_clock`
var. That is a **preview scrubber**, not the shipped drive model — it exists so
an author can drag a slider and see any frame of the reveal, and it does not
contradict the table above.

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

- **`FanUnit`** (`ui/tooltip_fan/fan_unit.gd`, #224) — pairs one `FanTrace` +
  one `FanPanel` under a `HIDDEN → IN → LOOP → OUT → HIDDEN` state machine;
  trace→panel ordering is baked sequential per decision 4. The sole Tween owner
  (see the table above).
- **Shared rows** (`panel_header`, `stat_value_row`, `addon_item`, #293) —
  leaf components on the `set_progress(t)` contract. `AddonItem.bind()` takes an
  optional `icon` override and carries a real `GradientTexture2D` placeholder
  (never `PlaceholderTexture2D`, per `.claude/rules/godot-workflow.md`).

## What's still open

- `TooltipFan` coordinator (#226) — the real node-anchored fan, driving
  `FanUnit`s from a hovered `SkillNode`; this is where the tree-sprout variant
  actually gets authored (decision 2), and where `TooltipFanConfig` (#216)
  should be revisited once real knobs emerge.
- The **z-sandwich** (HoloPanel `z=-1` / content `z=0` / ScanlineOverlay `z=+1`)
  is pinned but has never been verified to render as intended. #226 confirms it
  in the sandbox and reports back either way.
- Entry-anim *style* — which reveal a panel plays is still the "owned by the
  animation setup" bucket of decision 7. *Who owns the Tween* is no longer open.
