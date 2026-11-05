# Inner ring UI

The surface the player sees and touches for the inner aspect ring. The ring's data and rules are `entity/ring/` (`RingTable`, `aspect_ring.tscn`; a cell is buyable iff an edge links it to the centre core or a bought cell, [ADR 0064](../adr/0064-the-inner-ring-is-an-authored-graph-scene-and-its-edges-are-its-buy-rules.md)). The UI never mutates the ring: it submits a `SpendRingCellCommand` and reflects the result.

## Door and notice

`HeroSigilCard` (`ui/hud/hero_sigil_card/`) is the entry point. A left click anywhere on the card emits `ring_requested`; `HudRoot.open_ring` then raises the modal through `_enqueue_modal`. A ring-point mint never opens the ring: `%RingBadge` on the card shows the hero's unspent `ring_points.current` while above zero and pops on `Events.ring_point_minted`. The ring never joins the loot pickers as a mid-run interrupter.

## Modal

`RingModal` (`ui/ring/ring_modal.gd`) is a `ModalBase` whose body, `RingBody`, holds a `RingView` plus a detail panel for the hovered (else selected) cell: glyph and noun, exact grant, cost and, when it cannot be bought, why. A confirm submits the buy and does not close the modal: the body marks the cell pending and re-populates on the entity's `ring_changed`, so a player with points left keeps buying, and at zero it stays open read-only. Only the cancel path (Later, Esc, right-click) closes it. In a peer game the cell stays pending until the host's confirmed command lands; a refused buy reaches the body through `CommandApplier.command_applied(cmd, false)` on every peer.

## View

`RingView` draws a display instance of the authored ring scene (positions, edges and keystones are authored, never computed) in its own bloom viewport, with its own background and a core sigil in place of the inert centre node. It is presentation only: no `owned_by`, no `AllocationSystem`, and its viewport forwards no picking, so a display `SkillNode` never emits onto `Events`. Each cell is coloured bought, buyable or locked as `RingTable.can_buy` says; hit-testing is `RingView.cell_at`. Aspect hues and glyphs come from `identity/defs/*.tres`, never hardcoded in the UI. `ui/ring/ring_sandbox_panel.tscn` is the tuning tab before a run exists.

## Wearing and inspecting the build

`RingSilhouette` (`ui/ring/ring_silhouette.gd`) is a pure builder from a `RingTable` and an entity's `ring_spent` to a read-only `AspectWheel`'s entries (one per aspect in ring order; a bought cell adds its tier, so depth reads) and the dominant sector for the rim. `HeroSigilCard`'s `%RingSilhouette` shows the player's build and its emblem rim takes the most-invested sector's hue. `NodeInspectorCard` shows the same silhouette for a pinned core, only while `VisionSystem` sees that core, and never the exact cells or unspent points; a non-core node, a fogged core, or a card missing either system shows no wheel.

Not built: arrow / D-pad navigation along links (mouse and Esc/confirm only).
