# Node Specializations — Skill Tree of Life

See [skill_node_addons.md](skill_node_addons.md) for the addons/specializations distinction. This doc covers specializations only.

A specialization is either:
- **(A) Intrinsic:** the node was generated on the field in this state. Found-in-the-wild. Cannot be removed or changed.
- **(B) Transformed:** a player (or enemy) applied an irreversible or partially-reversible process to a normal node to create a specialized state. The process is costly, possibly destructive.

Both contrast with addons, which are applied freely (within resource constraints) to any compatible owned node. The following are candidate specializations — design sketches, not confirmed mechanics.

---

### Corrupted Node *(candidate)*

**Description:** A node with powerful modifiers but a significant downside that cannot be removed — the benefit and the cost are permanently fused. Might be encountered on the field as neutral (abandoned by a dead entity that couldn't afford the cost), or created through a process that involves trading something permanently.

**Examples (illustrative, not committed):**
- `+5 DEX / −3 armor` — ranged powerhouse, structurally fragile
- `+1 sp_per_turn / takes double damage` — economic engine with a death wish
- `damage_floor = −1 / 0.5× node_health_max` — heals slightly when hit, but dies in two hits

**How encountered:** Field-generated (type-A) primarily. Possibly also type-B: the Bulwark's floor-reduction perk path as a form of controlled self-corruption — choosing to make your floor-reduction permanent and irreversible in exchange for a stronger bonus.

**Design note:** Corrupted nodes make the loot system richer. A STEAL option in the loot window that says `+5 DEX (take double damage)` is a real decision. Proliferating that modifier is especially interesting — under the reframed model (PROLIFERATE = remove a core-held mod, mint **N tainted copies** across a cluster you must hold; see `combat_system.md`), you'd be spreading the double-damage downside across multiple nodes while spreading the DEX bonus. Whether the downside proliferates at the same rate as the bonus is a calibration question. Note that the **N copies are tainted** — owner-independent, non-extractable, non-re-proliferable — so you can never launder a corrupted-but-juicy mod back into a clean portable core mod by round-tripping it through the field.

---

### Crystallized Node *(candidate)*

**Description:** A normal node that has been locked into its current state — its modifiers are frozen permanently (cannot be upgraded, overwritten, or proliferated from). In exchange, those modifiers are permanently stronger than a normal node's equivalents. Cannot be deallocated by the owning entity (only force-deallocation by combat can remove it). Can be transferred to an adjacent position once (consuming the crystallization — the node becomes normal again at the destination).

**How created:** Type-B specialization. Triggered by a player ability or loot option — a deliberate act of trading flexibility for permanence. "I want this `+3 armor` node here, always, no matter what."

**Use case:** Locking a high-value node in a critical position. A Crystallized Lifeline node that cannot be voluntarily retreated becomes an ironclad topological anchor. A Crystallized Armor Ring node at a chokepoint is a permanent fortification.

**Cost:** Inability to dealloc it if the build changes. Potentially losing the investment if that node is killed in combat (crystallized doesn't mean unkillable — just unlockable).

---

### Anchor Node *(candidate)*

**Description:** A node that resists island dissolution — when it becomes part of an island, it has N turns of built-in grace before the island dissolves (like a built-in Lifeline, but intrinsic to the node rather than an addon).

**Distinction from Lifeline addon:** Lifeline protects nodes *near* it. An Anchor node protects *itself and its sub-graph* from immediate dissolution. It's stronger per-node but applies to fewer nodes (just those in its own island).

**Notes:** Potentially the rarest field-generated node type. Might be the natural-lore explanation for why some nodes survive longer than others in ancient contested regions of the tree — they've "crystallized" through long allocation history into more resilient forms.

---

## Design Principles

1. **Specializations should feel rare and meaningful.** If specializations are too common, they're just addons with extra steps. The first Crystallized node a player encounters should feel significant.

---

## Open Questions

1. **Addon/Specialization boundary:** Does the distinction hold up in practice, or does everything collapse into one system? Could revisit after first playtests. (Also tracked in [skill_node_addons.md](skill_node_addons.md).)
2. **Corrupted node downside proliferation:** When a corrupted modifier is PROLIFERATED in loot resolution, does the downside also proliferate? At the same rate? This determines how dangerous a corrupted loot pick is.
3. **Crystallized node combat interaction:** Crystallized = can't be voluntarily deallocated. Does this mean it can't participate in melee reshaping (Buffer charging requires the node to spend its action, not dealloc — so probably fine)? Does Uprooting count as force-deallocation or voluntary?
4. **Buffer addon vs Buffer specialization:** Resolve by playtesting whether the capability difference (freely-applied addon vs. a node that *is* a Buffer intrinsically) is meaningful enough to warrant two systems.
