@tool
class_name SerpentCore
extends CoreClass

## The Coil (#39, `docs/design/core_classes.md` "The Serpent"). Two auras
## side by side (no `CompositeEffect` needed — `Array[Effect]` composes them):
## a hop-distance buff that grows the further a node is topologically, and a
## euclidean-distance penalty that grows the further a node is spatially. The
## sweet spot is many hops away but spatially close to the core — a coil or
## chasm-crossing wind that buffs the same node from both sides at once.
## Modifier set + auras live in serpent_core.tres.
