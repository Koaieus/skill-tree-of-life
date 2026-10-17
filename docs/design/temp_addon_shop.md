---
status: settling
---

# The temp-addon shop

How a melee swing's budget is spent on temporary addons: a radial fan on the
node, a quickbar on the tray, a receipt of what this swing already bought.
Hub: #1605. Settled with the owner in a `/swarmify` pass, 2026-10-17; every
quoted sentence below is the owner's, that date unless marked.

## Why a shop, not a row

Placeable is the default for every addon (`aspect_matrix.md` § The addon
recipe, item 6), and the catalog grows toward ~12–15 temp-offered addons
(one per aspect, plus structural ones). A flat row of cards, one hotkey each,
stops working at six.

> *"we might need a different (menu?) structure for selecting an addon. it's
> some kind of shop, but linked to your aspect budgets and current-attack
> spending, and it's also pretty much a blueprint bar "pick blueprint apply it
> to a node [w placement feedback on hover etc]" and you're limited to what
> you can buy (+what you have spent on should ofc remain visible for
> undoing/mgmt/clarity) … should be easy and intuitive to use"*

The 2026-10-14 framing still holds: every card is *"essentially shop items
with each a price of blade size and 0..2 (maybe 3?) aspect currencies"*.

## The three surfaces

**1. Radial fan on the node (node first).** Hovering a node in placement mode
opens a fan of the blueprints you can place *there, now*. It never shows the
catalog: what you can afford is limited by the aspects you hold budget in
and the blade size left, so the fan stays small at any catalog size.

- **A growing fan, not a circle.** Fixed-width sectors fan out from the top,
  in a stable canonical order. Only placeable entries are drawn, so the fan's
  length gives nothing away: *"we also kinda dont want to give away the total
  amount of available sectors! so stability is fine but the sizing should
  be.. clever"* → picked: growing fan.
- **The canonical order is grouped by role** (offence, debuff, utility, …),
  so the role shelves the owner liked for discovery live in the fan's order:
  *"2 is neat if you dont know what contents each aspect has, "if you're
  looking for offense you're gonna find it here" solves that."*
- **The fan's tooltip stays minimal** (icon, costs). The detail goes to the
  tray: *"3 is a very strong pick that leaves room for the tray to instead
  show just (extra) info on what you are hovering where the tooltip hover on
  the radial is minimal or just concise / some icons/costs"*.
- **Its look is open:** reuse the tooltip-fan module or a new look for a menu
  with *"more (and more uniform) leafs"*. Settled on the radial's own child
  issue.

**2. Quickbar on the tray (blueprint first).** Z X C V B are the player's
five favourites. Pressing or clicking one arms that blueprint as it does
today. **Both paths ship:** arm from the quickbar and then pick a node, or
open the fan on a node and then pick a blueprint.

- Right-click a favourite to swap it for another blueprint *"where you have
  >0 aspect for"*.
- **Favourites are per run**, not a profile fact.
- **Auto-fill:** *"if you have empty favorite slots and acquire an aspect
  from 0→>0, pick it in the first open slot"*.

**3. Receipt and detail on the tray.** The tray does not grow with the
catalog any more. It holds the quickbar, a **receipt strip** of what this
swing has bought (click an entry to refund it), and a **detail panel** for
the blueprint being hovered, whether in the fan or on the quickbar.

## Role tags

No addon taxonomy exists yet. Every temp-offered addon gets a role tag, and
the tags set the fan's order. The category list is a design call on its own
child issue.

## Open questions

- The fan's look (see surface 1).
- The role categories and which addon goes where.
- Auto-fill for an aspect that owns two addons (Corruption: Compromiser,
  Abyssal Conduit), and for blade-only addons with no aspect (Spike Ring,
  Clamp).
