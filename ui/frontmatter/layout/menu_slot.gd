@tool
class_name MenuSlot
extends Control

## One authored seat in a [MenuFanHarness] — an invisible spacer that stands for
## exactly one [MenuGraph] item (#589 D2/D5).
##
## [b]A slot carries no pixels.[/b] It is a rectangle in a container, and the
## only thing [FrontmatterLayout] asks it is where its centre landed once the
## container had its say. The node that eventually draws there is a
## [MenuNodeView] living under `%GraphLayer` in WORLD space; this Control tree is
## screen space and is freed before anything animates (#589 D3).
##
## [b]The row height IS the pitch knob.[/b] A [VBoxContainer] separates adjacent
## children by `separation`, so the distance between two slot CENTRES is
## `(height_a + height_b) * 0.5 + separation`. Giving one slot a taller box is
## how a fan buys room around a single option without loosening the whole fan —
## the defect #589 names, where the root fan applied the clearance `MULTIPLAYER`
## needed uniformly to `OPTIONS -> EXIT`, which needed none of it.
##
## [b]This script is a contract two later units extend.[/b] #591 adds the look
## fields (title, subtitle, archetype, per-node radius) and a "decorative, skip
## the cross-check" opt-out; #593 adds a per-fan zoom. Both are ADDITIONS here —
## nothing below should have to be rewritten to make room for them.


## The [MenuGraph] id this seat stands for. Empty is a programming error:
## [method FrontmatterLayout.solve] cross-checks every slot against the tree, so
## an unnamed slot fails loudly at build rather than silently placing nothing.
@export var menu_id: StringName = &""
