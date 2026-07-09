# SkillNode addons

## Parent an addon only after the carrier is inside the tree

`SkillNode` connects its `AddonAnchor.child_entered_tree` /
`child_exiting_tree` signals in `_ready`. Those handlers (`_on_addon_added`) are
what transfer an addon's `entity_modifiers` / `local_modifiers` onto the carrier.

So `anchor.add_child(addon)` on a freshly `instantiate()`d SkillNode — before it
enters the tree — attaches the addon **visibly and mechanically inert**. No
error, no warning: `get_addons()` reports it, the sprite draws, and
`get_local_value(&"armor")` reads `0.0`.

Verified empirically while wiring `Keystone.stamp` (#149): stamping a
bunker_addon pre-tree gave `addons: 1, armor: 0.0`; stamping post-tree gave
`armor: 5.0`.

**How to apply:**

- In procgen, mint addons *after* `graph.add_skill_node(sn)` — that's why both
  `GraphProcgen._roll_and_attach_addons` and the `Keystone.stamp` call sit there.
- `Keystone.stamp()` guards this with an `is_inside_tree()` check and a
  `push_warning`. Any new addon-minting path should do the same rather than
  trusting call-site discipline.
- Don't "fix" this by null-guarding in `_ready` and re-scanning the anchor — the
  ordering is the contract, and a re-scan would double-apply modifiers for
  addons that *did* go through the signal.
