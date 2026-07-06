# Skill Tree of Life — node design program

## Canonical snippet
`ArcheNode.dc.html` is the ONE source of truth for a skill node. Every lab imports it via
`<dc-import name="ArcheNode" ...>`. Never fork it — add/adjust aspects as **props** so all labs
update at once. Key props: `weldK`, `sigil`/`sigilStyle`, `tintMix`, `glowMode`/`glowAmt`,
`core`/`haloScale`, `stakeStyle`/`stakeCap`/`stakeAlloc`, `arch`, `hue`, `allocated`.

## Workflow
Per aspect: build/extend a lab → twirl in the Tweaks panel → lock the winner → move on.
When all aspects are picked → export & hand to Claude Code with the reuse decomposition intact.

## Labs (hub: `Lab Index.dc.html`)
- `Skill Node Lab.dc.html` — all-in-one bench (every slider).
- `Sigils Lab.dc.html` — entity-core marks (shape/astroid/star8/occult/rune/kanji + boss ring-of-runes).
- `Stake Lab.dc.html` — alloc/cap depth (pips/rims/unison/ticks/arc).
- `Skill Node Well.dc.html` — original crater anatomy study.
- PLANNED: Addons Lab (plates, fortify/bunker, bridge/gate, lifeline, clamp), Edges & Ports Lab.

## Conventions
Fonts: Cinzel (display) + Chakra Petch (UI). Dark arcane bg. Owner tint = `hue`; archetype
color drives metal tint + rim glow. Vibe: arcane, nerdy, glowy, abstract graph-theoretic.
