# Handoff: Skill Tree of Life — In-Game HUD

## Overview
A full-fledged combat HUD for *Skill Tree of Life* (turn-based PvP-on-a-skill-tree, Godot 4.4). The player is an **entity** = a connected subgraph on a shared procgen graph. This HUD surfaces the entity's stats, derived combat power, turn resources, and the per-mode action flow, arranged as floating panels around the live graph playing field.

## About the design files
`Game HUD.dc.html` in this bundle is a **design reference built in HTML** — a working prototype of the intended look and behavior, not production code to lift. The task is to **recreate this in the Godot UI** (Control nodes / themes) using the project's existing patterns (`ui/stats_panel.gd`, `LabeledProgressBar`, StatDef-driven rows, etc.). The `StatDef.display_type`/`display_group` metadata contract should still drive what renders.

## Fidelity
**High-fidelity** for layout, composition, color, type, widget behavior, and interaction feedback. Recreate faithfully. The **center graph is a placeholder** — the real procgen field already exists in-engine; the HUD is the chrome around it. Numeric stat values shown are the Allround prototype starting state (see `docs/design/entity_stat_board_prototype.md`).

---

## Visual system — "Arcane Terminal"
- **Fonts:** `Cinzel` (700/800) for headers, level, entity name, mode tabs, announcer, End Turn (arcane serif). `Chakra Petch` (400–700) for all data/numbers (tabular, techy). Both Google Fonts.
- **Surfaces:** near-black glass panels, `linear-gradient(158deg, rgba(22,25,38,.94), rgba(10,11,19,.95))`, 1px border `rgba(120,140,190,.16)`, radius 13–14px, `backdrop-filter: blur(7px)`, drop shadow `0 10px 34px -14px rgba(0,0,0,.85)`.
- **Background:** `radial-gradient(120% 90% at 50% 42%, #0b0d16, #06070d 55%, #030409)`.
- **Attribute / node colors (canonical, from `stat_system.md`):**
  - STR (Red) `oklch(0.64 0.21 27)` · DEX (Green) `oklch(0.74 0.16 150)` · INT (Blue) `oklch(0.68 0.18 258)` · WIS (Gold) `oklch(0.81 0.14 88)` · PER (Purple) `oklch(0.66 0.21 305)` · CON (White, reserved 6th axis) `oklch(0.92 0.02 250)`.
- **Vitals:** Health crimson `oklch(0.60 0.21 25)`, Mana cyan `oklch(0.72 0.14 220)`, XP/gold accent `oklch(0.80 0.14 88)`.
- **SP buckets:** to-spend `oklch(0.70 0.16 250)` · wounded `oklch(0.60 0.20 25)` · staked `oklch(0.78 0.13 75)` · allocated `rgba(150,165,200,.30)`.
- **Glow scales with magnitude:** attribute number text-shadow blur = `4 + (v/60)*10` px; values ≥ 40 gain an `ember` brightness flicker (STR 51 "flames").

---

## Layout (1440×900 reference)
- **Center-top:** Turn tracker pill — initiative bar + "Your Turn" / next-actor readout. *Shows only when it is NOT the player's turn in-game* (here shown always for reference). See Initiative note below.
- **Top-left → down:** Hero sigil card → Attributes panel → Skill Points / resources panel.
- **Top-right → down:** Sandbox demo (prototype-only, remove in engine) → Combat Readout.
- **Center-bottom:** Command tray (mode tabs + contextual action bar).
- **Bottom-right:** Action Points widget + unspent-AP warning + End Turn.

### Hero sigil card
Class emblem (Allround = ✦ glyph on a slow-spinning conic ring), **level inset badge** bottom-right of the portrait. Right side: entity name (Cinzel 800), class subtitle, then the three persistent vitals as bars: **Health**, **Mana**, **XP** (all `cur/max` + dimmed `+N/t` regen). XP full bar = level-up; caption "+1 XP/turn per 10 WIS". This card is the **origin point for stat-change floaters** ("you got it" toasts rise from here).

### Attributes panel
- **Pentagon radar** (5 axes, one per attribute; CON slots in as a 6th → hexagon if promoted). Data polygon fill gold-translucent, per-axis colored vertex dots, axis letters colored per attribute.
- **Numeric list** beside it: colored dot + label + big value; value color = attribute color, glow scales with magnitude, ≥40 flickers.
- **Hover an attribute row → tooltip** listing what it *drives* with rule + current value (e.g. STR → "Blade size +1/20 → 3", "Blade dmg +1/10 → 6"). This is the requested intrinsic-link surface.
- **Senses row** (PER): Vision (euclidean px) + Sensor (hops), noted "scales / PER".

### Skill Points & turn resources
- **Action / Dealloc / Move** = segmented **parallelogram "battery" cells** (skewX(-15deg)), N-of-max filled, `flex-wrap` so ~10 late-game cells tile into rows instead of overflowing; each has a `cur/max` label.
- **Skill Points = composition bar** (the growth currency). One stacked bar split by proportion into **to-spend / wounded / staked / allocated**, with a count legend. Big "to-spend" number glows only when > 0 (mostly 0 — all invested). Wounded segment pulses (heals back over turns). Wound-heal sliver shows rate + progress-to-next-heal when wounds > 0.

### Combat Readout (right)
Four cards: **Melee** (blade size as diamond pips + blade damage), **Ranged** (damage/leaf + range px), **Magic** (potency/instance + hop reach), **Defense** (armor + R/G/B resists + damage floor). Each combat stat shows its **scaling rule + progress-to-next-breakpoint sliver** ("+1 / 20 STR · next @60"). The card matching the selected mode is highlighted (colored border + glow); others dim. **On a stat change, the affected card briefly un-mutes even if not selected**, and a lingering **▲+N / ▼−N delta chip** (2.7s) appears next to the changed value so multi-stat swings stay legible.

### Command tray (mode tabs)
Tabs **Manage(1) / Melee(2) / Ranged(3) / Magic(4)** across the top of a **fixed-size chrome** (120px content area — only the content swaps). Keyboard `1–4` switch tabs; `Space` (⎵) triggers Launch. Selecting a combat tab highlights its readout card. Per-tab content:
- **Manage** (no attack mode): three quick-action cards — Allocate (left-click, 1 SP) · Move Core (click core→dest or drag, costs Move) · Deallocate (hover + D, costs Dealloc, no self-islanding). **Manage un-dims all combat readouts** (reference state).
- **Melee:** pivot/blade builder hint (pivot ● + up to `blade_size` linked pips), **Swing CW/CCW** toggle, **Launch ⎵**.
- **Ranged:** target hint + firing-leaves count, **Launch ⎵**.
- **Magic:** **spell bar** — each slot: glyph, name, ◈ mana cost, degree icon (vertex + fanning lines) min-degree; greys/locks 🔒 when mana too low or source-node degree too small; then **Cast <spell> ⎵**.

### Action Points + End Turn (bottom-right)
AP battery (near End Turn because *no action = no attack*) with an **unspent-AP warning** ("⚠ 2 unspent Action Points") and the End Turn button **dimmed** while not-ok (full opacity on hover). End Turn is a chunky rounded (16px) gold seal with `⟫⟫` chevrons — **placement is final: bottom-right corner.**

---

## Stat formulas (SETTLED — use these)
The `//N` gear-ratio spine decouples chunky modifier loot from single-digit damage.
- **Blade size** = `1 + floor(STR / 20)`
- **Blade damage** = `1 + floor(STR / 10)` per contact
- **Ranged damage** = `2 + floor(DEX / 10)` per firing leaf (`base_ranged = 2` per volley)
- **Ranged range** = `round(400 * (1 + DEX * 0.01))` px (euclidean; ~400 base, +1%/DEX)
- **Magic potency** = `1 + floor(INT / 10)` per instance; **reach** = `bonus_hop_count` only (ultra-rare), INT never buys reach
- **XP / turn** = `floor(WIS / 10)`
- **Vision** = `round(420 * (1 + PER * 0.02))` px (euclidean); **Sensor** = `3 + floor(PER / 10)` hops (structure-only into fog)
- **Armor** flat, then per-color `resist_r/g/b`, floored at `damage_floor` (default 1)

> The breakpoint slivers read the *rule* per stat. To generalize cleanly, promote derived stats (e.g. `blade_damage`) to real stats with a formula `StatModifier`, and have the UI read the modifier's per/step from the StatDef rather than hardcoding — so a node's spike addon that raises local `blade_damage` shows correctly. (See `docs/domain/stat-ui-visibility.md`.)

## SP accounting (SETTLED)
`max = current + wounded + staked + allocated` (allocated = non-core owned node count; core is free).
- **Allocate** node: current−1, allocated+1.
- **Force-deallocation** (node killed): allocated−1 → **wounded**+1 (SP not returned to hand). Heals to current at `wound_heal_per_turn` (currently 1/turn; if fractional e.g. 0.5, the wound-heal sliver tracks progress → 1 wound per full bar).
- **Stake:** spend 1 SP to raise a node's `alloc_cap_max` (1/1→1/2→2/2…) → **staked** bucket. Recovered via **Extract** (core within 0–1 hops). Killing an enemy's staked node and extracting it leaves the *enemy* with the permanent staked reservation — capture-and-heal play.

## Interaction model (per attack mode — SETTLED intent)
- **No mode (Manage):** left-click = allocate (if SP); click core then destination (or drag) = move core (if Move pts); hover + `D` = deallocate (if Dealloc pts and no self-islanding).
- **Melee:** right-click = set pivot; left-click = toggle node into blade (grows from pivot, ≤ blade_size, connected); direction toggle CW/CCW; Launch when blade has ≥1 node besides pivot.
- **Ranged:** click enemy node to target; owned leaves that can reach auto-fire on commit; Launch (⎵). One volley/turn.
- **Magic:** click own node = source; pick spell (gated by source degree + mana); click enemy node = target (range per-spell: max hops from source, or euclidean px, bonus modifiable by stats); Launch/Cast (⎵).
- **Always:** hover a *visible* node → tooltip (contents + owner), gated by vision/fog-of-war. `action_points` default 2 (attacks/turn).

## Announcer FX (SETTLED)
Full-width bar grows vertically from the midline (`annBar`: 0→134px→0, TV-turnoff snap at end). Big Cinzel text flies in from the left, settles, nudges back slightly, then continues off-screen right (`annText`). ~2.6s. Color per mode (Melee red / Ranged green / Magic = spell name, blue). Fired on Launch.

## Initiative (RECOMMENDATION)
Turn order matters for PvP, but it's another balancing/procgen knob on a system already rich with them. **Recommendation:** keep the *concept* but make initiative a near-fixed value with only rare modifiers (like `bonus_hop_count`), or derive order from a simpler speed proxy — don't invest in a fully-scaled `initiative` stat unless a build axis demands it. The center-top tracker only appears off-turn (nothing for the player to do while waiting), so the center-top real estate is otherwise free for other transient UI.

## Open items / notes
- Graph is **planar**; nodes in the reference are inert decoration (real interaction lives in Godot).
- CON is not currently a live attribute (docs may be stale); radar is a pentagon (5). Promote to hexagon if CON becomes core.
- Degree icon = a vertex with lines fanning out (not a convex hexagon).
- Consider whether Move/Dealloc want a dedicated floating cluster (mirroring the AP+End Turn cluster bottom-right) so the three per-turn action tools read as the player's primary verbs; SP then owns the left panel outright.

## Files
- `Game HUD.dc.html` — the reference prototype (open in a browser). All widgets, formulas, colors, and interactions above are implemented in it; read its logic class (`renderVals`) for exact values.
