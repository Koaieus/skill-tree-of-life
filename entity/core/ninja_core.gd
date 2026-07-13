@tool
class_name NinjaCore
extends CoreClass

## The Phantom (#39, `docs/design/core_classes.md` "The Ninja"). High
## deallocation budget for in-turn reshaping, a low SP cap that keeps the
## constellation compact, and an intense-but-very-short-range core aura that
## makes nearby owned nodes hit harder. Reach is deliberately bounded (unlike
## the Serpent's) — the Ninja is rewarded for staying compact, not for
## sprawling. Modifier set + aura live in ninja_core.tres.
