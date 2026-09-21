---
description: The frontmatter menu is itself a skill tree — one persistent graph, a moving camera
paths:
  - "ui/frontmatter/**"
  - "scenes/meta/**"
---
The menu **is** a skill tree: one persistent graph whose nodes never move — the `Camera2D` moves (splash = zoomed onto the root; each menu level = a node docked in the hero slot, children fanned right). Panels (lobby/settings/join/exit) live in a `CanvasLayer` so the camera transform can't pan or zoom their text.

**Why:** owner, 2026-08-24: *"no detaching please, we want to stick to proper skill tree vibes."* That vetoes lifting the selected node into a transit layer, which is what forces the one-graph-moving-camera architecture.
