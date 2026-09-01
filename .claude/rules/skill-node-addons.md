---
description: How SkillNodeAddons attach to a carrier — direct-child contract, adoption, idempotence, and the editor modifier guard
paths:
  - "skill_node/**"
  - "procgen/graph_procgen.gd"
  - "entity/keystone/**"
  - "systems/loot_system.gd"
---

# SkillNode addons

## Attaching an addon is `skill_node.add_child(addon)` — nothing else

There is no anchor node to file into and no `attach_addon()` method to call.
Procgen, `Keystone.stamp`, `LootSystem`, editor authoring and the future
player-facing path all use the one call.

**Why:** the old `Visuals/AddonAnchor` bin (deleted in #334) was a *filing*
node, not a positioning one — a bare `Node2D` at identity with no offset and no
z_index. It bought nothing visually while costing real DX: authoring a SkillNode
scene with an addon needed "editable children" to reach an inner node, and an
addon added as a plain child was silently ignored. Two valid homes, one of them
inert.

**How to apply:**

- `add_child` at any point. Ordering is free — see adoption below.
- Only **direct** children are adopted. An addon nested under `Visuals` or under
  another addon resolves `SkillNodeAddon.carrier` (the lookup walks up
  arbitrarily) but never attaches. That asymmetry is a documented non-contract,
  not a half-built feature; don't "fix" it by deepening the scan.
- New behaviour on attach (slot caps, compatibility checks) goes in
  `SkillNode._attach_addon` — the `child_entered_tree` handler every path
  already flows through. Don't add a second entry point; that's the anchor
  rebuilt with extra steps.

## Pre-tree parenting is safe now — `_ready` adopts

`SkillNode._ready` sweeps its existing children and attaches every
`SkillNodeAddon` it finds, then connects `child_entered_tree` /
`child_exiting_tree` on **itself**. So an addon parented before the carrier
enters the tree lands correctly the moment it does.

This **reverses** the rule that used to live here ("parent an addon only after
the carrier is inside the tree"; `Keystone.stamp` carried an `is_inside_tree()`
bail-out and a warning, both now deleted). The old objection to a `_ready`
re-scan was double-application, and it was a fair objection — it's answered
structurally below, not by ordering discipline.

`child_entered_tree` fires for **direct children only** — verified empirically;
a grandchild added under `Visuals` never fires it. That's what makes the
`is SkillNodeAddon` type filter a sufficient contract rather than a heuristic.

## The `_addons` ledger is what makes attach idempotent — not call ordering

`_attach_addon` / `_detach_addon` no-op when membership in `_addons` already
says so. This is load-bearing, not defensive.

**Why:** a SkillNode re-entering the tree re-fires `child_entered_tree` for
**every** existing child (verified). So "the adoption sweep runs before the
signal is connected, therefore no overlap" is true on first `_ready` and wrong
forever after — any reparent would stack an addon's modifiers a second time.
Membership decides; ordering doesn't.

`get_addons()` reads that ledger and returns a `duplicate()` (callers mutate
accessor results — see `graph.md`). Internal loops iterate `_addons` directly.

`test/unit/test_addon_attachment.gd` pins all of this, including the re-entry
case.

## The modifier transfer is skipped in the editor

`_attach_addon` guards the `entity_modifiers` / `local_modifiers` handoff with
`not Engine.is_editor_hint()`. Visuals still attach; stats don't.

**Why:** `SkillNode.modifiers` is an `@export` **and** the sink for
addon-derived modifiers. `SkillNode` is `@tool`, so transferring under the
editor would serialize those modifiers into the `.tscn` and re-apply them on the
next load — compounding on every save. That's exactly godot-workflow.md's "never
write a DERIVED value back into an `@export`". The bug was already reachable via
editable-children before #334; the pre-tree inertness merely masked it.

**How to apply:** don't remove the guard while `modifiers` stays exported. #335
tracks splitting authored from derived modifiers, which retires the guard
properly.

## Positioning: an addon's own transform stays identity

Addons render concentric with the carrier at its origin and inherit its
transform for free. An addon wanting an offset or rotated element bakes it into
its **child** visuals, never its root transform.

`SkillNodeAddon.BASE_Z` (relative `1`, set in the addon's own `_ready`) lifts it
above the carrier's whole `Visuals` subtree regardless of child order, and stays
below the health bars' relative `10`. It's uniform across every addon, so it
costs no batching (see `rendering-performance.md`).

**It lives on the addon, not the carrier** — draw order is the addon's own
presentation concern, and `SkillNode` has no business writing its children's z.

**In the script, not per-scene.** There is no base addon scene — every concrete
addon is its own standalone scene carrying its own script, and `addon_tile.gd`
builds one in code. A scene-level value would have to be repeated in all of them
and would be missed by the next addon anyone adds. (`skill_node_addon.tscn` used to exist as a one-node
"template" — a bare `Node2D` + script that nothing inherited. Deleted: a base
scene earns its keep by packaging internal children every instance needs, and
that one packaged nothing.)

Don't reach for `Visuals.z_index = -1` as the alternative — a sensed SkillNode
goes absolute `z = 1001`, which would drop `Visuals` onto the `FOG` band (1000)
and lose the punch-through.


## An addon's visual goes in an OUTBOARD register, never the centre

The disk's centre is the single-winner CARVE slot, outranked by
KEYSTONE/LOOT/SPELL — an addon that contributes its visual there via
`get_emblem()` goes invisible on exactly the loaded nodes worth caring about.
Draw your own geometry outside the emblem, the way SpikeRing does.

**The trap:** `SkillNodeAddon.icon` is right there, so a `Sprite2D` at the origin
looks like the cheap move. Bunker, Fortification and Watchtower all shipped that
way and all three were replaced — those icons are buildings in *elevation* and
the gem is a dome lit from *above*, so it was a projection clash on top of a
register clash.

**How to apply:** an addon that changes the node's shell draws a concentric band
in plan; one that builds a structure on the territory stands in elevation on a
bearing (straight up belongs to the health bars); Clamp's answer — nothing on the
carrier, thicken its edges instead — is also valid. Bands stack, so claim a
radius range and a tone and check them together. Judge every one of these at
three zooms AND on an **allocated** carrier, in the sandbox host's **Node
Visuals** tab — `check` cannot see any of it. Two failed only at distance, and a
third (Bunker, which overlaps the rim) looked right on every unallocated preview
and then vanished into the bronze allocated rim underneath it.

Band budget, the geometry helpers, the elevation constraints and the incidents
behind all of it: **docs/domain/addon-visual-registers.md**.
