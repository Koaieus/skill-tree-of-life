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

## Three tiers of composition (settled #226, #303)

The fan is **components composed into a unit, composed into a coordinator**.
Each tier does exactly one job, and each tier is a scene you can open and watch
on its own.

| Tier | Job | Contract |
|---|---|---|
| **Component** — `FanTrace`, `FanPanel` | Animate itself | `play_in()` / `play_out() -> Tween`, plus a **readable `progress`**. Knows how to reveal itself, how to reverse itself, and how long that should take. |
| **Unit** — `FanUnit` | Sequence two components | `await _trace.play_in().finished` then `await _panel.play_in().finished`; OUT is the reverse read. Owns **no** Tween of its own — it holds ordering and state, nothing else. |
| **Coordinator** — `TooltipFan` | Fire N units | A per-index start delay, and nothing else. Whether the variant has 2 units or 6 changes only the delays. |

Below the components sit the **content rows** — `ModSlabRow`, `PanelHeader`,
`StatValueRow`, `AddonItem`. These are *not* fan participants: they take
`set_progress(t)` and are driven by the panel they live in, from inside that
panel's own reveal tween. Rest state is `t = 0`, set at bind — never as a side
effect of an entry call.

**There is no fan-wide clock.** Independent components with a variable start
delay are the simple form of exactly the choreography wanted, and they keep the
sequence readable as a chain of completions rather than as arithmetic on a
normalized `t`. An earlier phrasing here ("one fixed clock … never a
per-component Tween chain") was read as mandating a single fan-wide timeline and
got #224's `FanUnit` flagged as violating it. That reading was wrong, and the
rule that produced it is gone.

**Interrupt = kill and reverse.** A hover→unhover mid-reveal kills the running
tweens; each component then plays OUT **from its own current progress**. A
half-drawn trace retracts from half-drawn — it never pops to full first and
never hard-cuts. Because a component owns its `progress`, it also owns the
arithmetic: **each scales its reverse duration by how far it actually got**, and
a component sitting at `progress == 0` yields a zero-length leg, which *is* the
"skip the panel fade when the panel never opened" rule — no `if`, and no cache
of someone else's state. Floor each leg at ~0.03s so a near-zero one still
yields a frame.

`FanUnit._generation` stays: a tween that finishes on the same frame as the
interrupt would otherwise resume a stale continuation.

### Why `FanPanel` gained `play_in`/`play_out` (#303)

It shipped (#223) as a pure sink — `set_progress(t)` and no getter — while
`FanTrace` shipped self-animating. That asymmetry meant `FanUnit` sequenced one
component and *puppeted* the other, holding a tween on the panel's behalf and
caching `_panel_progress` so it could compute the reverse. The cache existed only
because the panel could not answer "how far in am I?". Making the panel a peer
deletes the cache, the puppet tween, and the duration arithmetic from `FanUnit`
in one move. `set_progress(t)` survives as the content-row contract, where a
pure sink is the right shape.

`fan_trace_sandbox.gd` drives its five trace+destination pairs off one `_clock`
var. That is a **preview scrubber**, not the shipped drive model — it exists so
an author can drag a slider and see any frame of the reveal, and it does not
contradict the table above.

## Components so far

- **`FanTrace`** (`ui/tooltip_fan/fan_trace.gd`, #222) — one circuit-trace
  connector: `Line2D` + glowing `Sprite2D` tip, geometry from `TraceRouter`
  (PCB-elbow only, per decision 3). `progress` (0..1) truncates the drawn
  arc-length. `play_in()`/`play_out()` return a `Tween` to `await` (named
  `play_draw_in`/`play_erase` until #303 unified the component contract).
- **`FanPanel`** (`ui/tooltip_fan/fan_panel.gd`, #223 + #303) — thin wrapper
  around a hand-placed skin child (`GlassPanel` or `HoloPanel`, swapped by
  editing which scene is instanced under it — decision 6, not a runtime enum).
  Forwards a single `glow` (0..1) to whichever skin is present. Since #303 it is
  a **peer of `FanTrace`**: owns a readable `progress`, and `play_in()` /
  `play_out()` returning a `Tween` — the scale+fade reveal (cubic ease-out) it
  already had, now self-driven. Drives its content rows' `set_progress` from
  inside its own tween.
- **`fan_trace_sandbox.gd`/`.tscn`** (#233) — in-editor preview harness,
  reachable from the sandbox host's "Fan Trace" tab. Five `FanTrace`s sprout
  from a mock node to four corner `FanPanel` destinations (mixed glass/holo
  skins, demonstrating the swap) plus a top row of `ModSlabRow` tiles. Drives
  everything off one clock (`_clock`), matching the contract above.

- **`FanUnit`** (`ui/tooltip_fan/fan_unit.gd`, #224) — pairs one `FanTrace` +
  one `FanPanel` under a `HIDDEN → IN → LOOP → OUT → HIDDEN` state machine;
  trace→panel ordering is baked sequential per decision 4. Owns **no** Tween
  since #303 — it sequences its two components and holds state.
- **Shared rows** (`panel_header`, `stat_value_row`, `addon_item`, #293) —
  content rows on the `set_progress(t)` contract, driven by their panel. `AddonItem.bind()` takes an
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
