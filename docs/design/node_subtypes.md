---
status: exploring
---

# Node subtypes — open threads

The shipped subtype axis (`regular` / `blight` / `bless`, archetype picks the
family, subtype picks the pole) is
[docs/domain/node-subtypes.md](../domain/node-subtypes.md). What follows is
not built.

## Clustered placement

v1 places subtypes by an independent per-node roll, so subtyped nodes read as
individual opportunities along a route rather than territories. Promote to
clustered regions only if that speckle reads badly on a real map.

If it is promoted, do **not** add `ArchetypeStamp`-style placed regions for
it — that mechanism shipped with #163 and no preset has ever authored it
(see #1055). The upgrade is a second run of the existing BFS-grow pass over
subtype policies, with each subtype's authored `base_chance` becoming its
`target_ratio` more or less verbatim. Nothing authored today changes.

## The name "Corrupted" is already spoken for — loosely

[skill_node_specializations.md](skill_node_specializations.md) sketches a
**Corrupted Node**. Owner, 2026-09-22: that doc is *"one of the earliest
design docs where spitballing was more prominent than ever — at best see it
as inspiration for mechanics we don't yet have."* So it is not a competing
axis and nothing here needs to reconcile with it.

The vocabulary could still collide: its "Corrupted" is a rare **per-node**
fused benefit-plus-permanent-downside, while a subtype is a common
**territory** flavour that changes which pools procgen draws from. Prefer
`blight` over `corrupted` in code and UI.

## Open questions

1. **Can a subtype's territory be converted?** Does holding blessed nodes cleanse adjacent blighted ones, or is subtype fixed at generation? A conversion mechanic would make the map a battleground in a second dimension; fixed is far cheaper.
2. **Do the four families each need a fifth/sixth sibling** now that PER takes blindness and WIS takes none? Owner noted *"Blight is a good name also for if we ever need a 5th."*
