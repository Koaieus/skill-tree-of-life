@tool
class_name StatEffect
extends Effect

## Concrete [Effect] that is nothing but a hand-crafted modifier set, plus the
## text/icon an effect carries. Uses the base grant/revoke behaviour as-is —
## exists so designers can pick a concrete script in the inspector without
## overriding anything. Exact mirror of [StatKeystone]'s role.
##
## Reach for this only when a bundle wants effect lifecycle (text, icon,
## revocation by handle). A carrier's plain `modifiers` array remains the right
## home for a pure stat bundle with nothing behavioural about it.
