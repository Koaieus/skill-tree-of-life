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

**1. The blade-node menu (node first).** Left-click a node that is already
in the blade (pivot or member) to open its management menu. Left-click an
unpicked node still picks it. Any armed mode overrides the menu: with a
quickbar blueprint armed, the click places that blueprint as it does today.

> *"on unpicked node -> picks it as blade; on picked node: menu for mgmt
> including list of upgrades (if slots and budget etc, the wheel thing) and an
> option to un-pick it … it also gets overridden by any other armed mode e.g.
> from hotbar"*

- **Un-pick sits at the hub, under the cursor.** The cards fan out around
  it, so a double-click on a picked node un-picks it without needing a new
  button or a timer.
- **A growing fan of cards, not a circle.** Uniform fixed-size cards (the
  same card as the quickbar slot) fan out from the hub in a stable canonical
  order. Only what you can place there right now is drawn, so the fan's
  length gives nothing away: *"we also kinda dont want to give away the
  total amount of available sectors! so stability is fine but the sizing
  should be.. clever"*.
- **Cards never move once the menu is open.** The menu has its own geometry,
  chosen for usability, and does not use the tooltip fan's trunk-and-branch
  shape or its viewport clamping: *"needs to be a clear pick of cards that
  don't move around though! … this menu doesn't need to follow that, it
  could do its own variety to suit good usability"*.
- **Near a screen edge the camera nudges** just enough to fit the menu. The
  menu's layout is the same everywhere. This is reusable camera plumbing
  with a nudge policy and a centre policy, so *"anything else that wants
  this could fold it in with little to no extra code"*.
- **The canonical order is grouped by role** (offence, debuff, defence, utility),
  so the role shelves the owner liked for discovery live in the fan's order:
  *"2 is neat if you dont know what contents each aspect has, "if you're
  looking for offense you're gonna find it here" solves that."*
- **The menu's tooltip stays minimal** (icon, costs). The detail goes to the
  tray: *"3 is a very strong pick that leaves room for the tray to instead
  show just (extra) info on what you are hovering where the tooltip hover on
  the radial is minimal or just concise / some icons/costs"*. While the menu
  is open, the node's tooltip fan stays down.

**2. Quickbar on the tray (blueprint first).** Z X C V B are the player's
five favourites. Pressing or clicking one arms that blueprint as it does
today. **Both paths ship:** arm from the quickbar and then pick a node, or
open a picked node's menu and then pick a blueprint.

- Right-click a favourite to swap it for another blueprint *"where you have
  >0 aspect for"*.
- **Favourites are per run**, not a profile fact, and are *"saved with the
  run"*.
- **Run start fills every empty slot** with whatever can be placed, in
  canonical order.
- **Auto-fill:** *"if you have empty favorite slots and acquire an aspect
  from 0→>0, pick it in the first open slot"*.

**3. Receipt and detail on the tray.** The tray does not grow with the
catalog any more. It holds the quickbar, a **receipt strip** of what this
swing has bought (click an entry to refund it), and a **detail panel** for
the blueprint being hovered, whether in the fan or on the quickbar.

## Role tags

Four roles, in this order: **offence, debuff, defence, utility** (owner,
2026-10-20, #1681). An addon's role is **the job it does when copied onto your
blade**: *"from the shopper's perspective (== blade forging == offensive) it's
just one of the two"*. One tag per addon, even when the addon also defends a
board node against blades; that anti-blade face plays no part in the tag.

The tag is `SkillNodeAddon.role`, an exported enum read without an instance
through `SkillNodeAddon.role_of(scene)`. `TempUpgradeCatalog.offered()` is the
only owner of the order, so the fan and the quickbar auto-fill follow it:

1. by role, in the enum's order (reordering the roles is a one-line change);
2. then blade-size price ascending (`temp_costs_of(scene, 0)`);
3. then scene path, for a stable tie-break.

The enum's default is a fifth value, `UNSET`, that no def keeps. It exists
because Godot omits an export equal to its default when it saves a scene, so a
default of offence would erase every explicit offence tag on the next editor
resave and leave "is this def tagged?" unanswerable. A test fails on any def
left at `UNSET`; an untagged addon would sort after every role.

Order within a role and the role order are tentative knobs. Each assignment is
a judgement call that the owner retunes by flipping the export:

| Addon | Role | Offered | Note |
|---|---|---|---|
| spike_ring | offence | yes | raises `blade_damage` |
| explosive_barrel | offence | no | |
| abyssal_conduit | offence | no | grants corruption arrows |
| toxin | debuff | yes | ambiguous: poison is damage over time, could be offence |
| ashfall | debuff | yes | wither |
| dune | debuff | yes | blindness |
| sapling | debuff | yes | weakened |
| shredder | debuff | yes | sunder, armour break |
| doombrand | debuff | yes | curse |
| compromiser | debuff | yes | corruption |
| bunker | defence | no | |
| clamp | utility | yes | ambiguous: a rigid joint, could be defence |
| watchtower | utility | yes | scouting |
| midas_mark | utility | yes | ambiguous: greed on contacts, could be debuff |
| ring_cell | utility | no | |
| skill_dust | utility | no | |

With toxin as a debuff, spike_ring is the only offered offence addon.

## Open questions

- Whether Clamp gets a pinned or special slot: *"possibly `clamp` option is
  pinned; or special (it also has special ramping up costing planned for
  it)"*.
- Quickbar favourites across a save/load in multiplayer, where the host
  writes the save but the favourites are each peer's own.
