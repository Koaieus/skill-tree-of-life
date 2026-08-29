---
description: Baked game-icons assets — turn mipmaps on for any icon drawn small, and judge the silhouette at the size it ships at
paths:
  - "assets/icons/**"
---

# Baked icon assets

`mise run icons:update` rasterizes every `mapping.txt` entry to a flat
single-colour silhouette at **256px**. Two things that size does not decide for
you:

## Turn mipmaps on for any icon drawn below ~64px

A new icon's `.import` lands on the Godot default `mipmaps/generate=false`. At
tooltip or card size that is fine and is why the existing ones ship that way. At
tab (~32px) or cursor-badge (~24px) size it is a >8x minification with no mip
chain, so bilinear sampling undersamples and the icon **shimmers while it moves** —
the worst case being anything glued to the pointer.

**How to apply:** set `mipmaps/generate=true` in that icon's `.png.import`. The
setting survives `icons:update` (`godot --headless --import` rewrites `[deps]`,
not `[params]`) — it is only *new* icons that arrive with it off, silently
differing from the neighbours you copied.

Cosmetic and one line, in git. Notice it, fix it, move on.

## Mipmaps fix sampling, not semantics

A glyph at 24 screen px carries ~24px of information however well it is filtered;
mipmapping turns aliased mush into *smooth* mush. So a candidate icon is judged by
rendering it through the real bake at its shipping size, not by how it looks in
the browser:

```bash
sed -e 's/fill="#fff"/fill="#8CD9FF"/g' -e 's|<path d="M0 0h512v512H0z"/>||g' \
    ~/.cache/skill-tree-of-life/game-icons/<author>/<name>.svg > /tmp/i.svg
rsvg-convert -w 24 -h 24 /tmp/i.svg -o /tmp/i.png   # then upscale 400% to inspect
```

Thin-stroke and many-part glyphs fragment; bold closed silhouettes hold. Picking
by name or by the 512px preview is how a "perfect" icon ships as noise.

Related: `docs/domain/emblem-bake.md` (the CARVE LUT half of the same pipeline),
`.claude/rules/ui-palette.md` (icons are tinted, never recoloured at the source).
