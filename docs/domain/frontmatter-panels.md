# Frontmatter panels — one base scene, inherited per screen

`ui/frontmatter/panels/frontmatter_panel.gd` + `.tscn` is the base scene for
every screen on the frontmatter's `%PanelLayer` — the lobby, the settings, the
join prompt, the parked load screen, the exit confirm. The menu itself is a
skill tree with a moving camera (`docs/GDD.md`); a panel is the static
page that slides in beside it. This page is the base scene's contract.

## A base scene that packages children

Per `.claude/rules/scene-composition.md`, every concrete panel is an
*inherited scene* of `frontmatter_panel.tscn` that fills `body`; none composes
its own frame or title, so a structural change to the chrome propagates to all
of them for free.

**Authoring a panel is authoring a static page.**
Anchors and containers, `@tool` so the editor shows the truth, no
code-composed layout.

## A panel never knows where the camera is

It lives under a `CanvasLayer`, immune to the graph camera's pan and zoom by
design — the whole reason the two layers are split, and why panel text stays
crisp and stationary while the tree moves behind it. Nothing in a panel may
reach for `Camera2D`, the graph layer, or `FrontmatterPanels`.

## The chrome is a right-hand region, not a centred modal

There is one baseline layout at every depth — hero column, then whatever fills
the remainder (`frontmatter_columns.tscn`) — and a leaf panel fills that
remainder the same way a fan of children would.

**This scene IS the region, not a positioner for one.** It is parented straight
into `%Remainder` (`frontmatter_root.tscn`, under `%PanelLayer`), so its root
`Control`'s `anchors_preset = 15` already fills exactly the rect a panel gets, and
nothing is chased per frame. It never computes a left edge off
`FrontmatterLayout.hero_slot` plus a gutter: that would express the two-column split
a second time, in code.

**A panel knows nothing about column 1 either.** Nothing in the scene reads a
hero-column width or a gutter; a panel dropped into `%Remainder` grows to take the
space it is given, and authors itself standalone.

## The nesting is inside-out from what it draws

Margins apply to top, right and bottom (possibly left), then the glass panel is
centred in there, and inside it are more margins around headers and content. So:

```
FrontmatterPanel        (this scene's own root, already fills %Remainder)
  %OuterMargin           top / right / bottom (and left)
    GlassPanel            fills the outer margin's inset rect
      %InnerMargin          the legibility padding around content
        %Column               %Title  +  %Body
```

The OUTER margin insets the glass itself, visibly, from the viewport's edges.
There is no content max-width, and none should be added: the column sizes off its
content and its column.

## Dismissal goes up, never sideways

A panel asks to be dismissed; it does not dismiss itself. `dismissed` goes up
to `FrontmatterPanels`, which re-emits it as `panel_dismissed` for the
navigation state machine — the panel has no idea what "back" means in graph
terms. There is exactly one back affordance (`BackAffordance`, in the hero
column) rather than one per panel; `dismiss()` survives as the route an
inherited scene's own cancel affordance (the exit-confirm's "no") uses to reach
the same exit.

## The reveal clock

`set_progress(t)` / `set_exit_progress(t)` follow the repo's animated-unit
contract — no `Tween`, one external caller (`FrontmatterRoot`) owns the clock
and drives the slide off the SAME `t` as the camera travel it overlaps
(`FrontmatterRoot.panel_lead`). The method docs in the script carry the two
gotchas (why entry and exit are separate curves; why it writes `position`
rather than an inner offset).
