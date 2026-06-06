# First Session Walkthrough — From Boot to First Snipe

> A spoiler-free, second-person narrative of what a player actually goes through, from the first frame of the game to the first time they dismember an enemy entity by sniping a cut vertex. Sister doc to `lore.md` and `combat_system.md`, but written from the *player's* seat, not the designer's.

## Why this doc exists

The other design docs describe systems. This one describes **what the player goes through.** It tracks the felt arc — the boring bits, the off-bits, the click-of-understanding bit — from the title screen to the moment the player executes the game's signature move: severing an enemy entity into pieces by hitting the right load-bearing node.

It is **spoiler-free.** 

---

## Beat 1 — Boot. It looks like a Zelda clone.

The title screen is sincere. A sword icon, a pixel-arty landscape, maybe a fairy crosses the splash. You press *Start.* You drop into a top-down green field with a hero sprite and an HP bar.

A small companion — a fairy, more or less — chirps a greeting and points you toward the nearest grove of round, blinking creatures. *Kill those for XP,* it says, helpfully.

> **Questionable.** The creatures don't read as enemies. They blink, they wobble, they don't attack. They look like things you'd find in a children's hospital plushie aisle. You're being asked to kill them anyway.

You swing the sword. They die. A number floats up. The HUD ticks a fraction of an XP bar. You keep going. Three more, six more, ten more.

## Beat 2 — Level up. The Fairy nudges you to spend a point.

The XP bar fills. A chime fires. **Skill point earned,** the Fairy says, eyes a little too wide. *Why don't you open the skill tree and spend it?*

You open the tree. It's a panel. It has nodes, it has connections between them. The starter node glows; three neighbors are clickable. You hover one: **+10 STR.** You click. The number on your character sheet ticks up.

You close the panel. You keep killing things.

> **Questionable.** The Fairy is **really** insistent about the skill tree. Not in a bad way. In an aunt-at-Christmas way. You'll remember this later.

You hit level 2. The Fairy chirps again. You open the tree, allocate **+10 DEX,** close it. Level 3. Open, **+10 INT,** close.

The panel does a tiny shudder on one of the clicks. A single frame of *wrong.* Probably a graphics hiccup.

> **Questionable.** Was that a shader artifact, or did the panel just twitch?

## Beat 3 — The crash.

You hit level 4. The Fairy is enthusiastic. *Spend your point!* You open the panel, hover over the next node…

The screen tears. The audio rips into a clipping howl. The image freezes, then strobes. For a second you think your GPU has died. Then it really freezes. Hard.

You hold the power button. Or you don't. Either way, after a moment the game comes back on its own — a generic loading bar, slow and blue.

> **Funny.** By the time the loading bar appears, you have already started typing into Discord: *"yo did anyone else's game just —"*

## Beat 4 — The game resumes. The skill tree panel is open. You can't close it.

You're back at the desktop only briefly; the game reasserts itself. The skill tree panel is on screen.

You press *Esc.* Nothing.
You click the X. There is no X.
You hit *Tab.* The panel doesn't move.

> **Funny.** You spend a real, embarrassing amount of time looking for the close button. There isn't one. There will never be one again.

The camera does something subtle. The panel's borders thin, the background dims, and the panel **grows.** It fills the screen. The icons on the nodes resolve into structures, not glyphs. The lines between them resolve into paths you could walk.

Your hero sprite is gone. Your HP bar is gone. The old HUD is gone.

You are standing on a node.

## Beat 5 — Orientation. You realize the tree is the world.

Your starter node — labeled **ENTITY CORE — +10 XP/TURN** — is beneath you, glowing warm. The three nodes you allocated in the panel earlier are **here,** lit in your color, connected to your core by visible edges. **+10 STR.** **+10 DEX.** **+10 INT.** The numbers are the same; the substrate is not.

> **Questionable.** So when you clicked +10 STR in the panel during the adventure game, you weren't *configuring a build.* You were claiming a node in a place. You just didn't know you were here yet.

You look outward. Edges run off your three leaf nodes to unallocated neighbors — cold and silent in the dark. Past those, edges trail off into a **fog.** You can see a few hops; beyond that, nothing.

A new HUD has arrived. Buttons: **Allocate, Move Core, Attack, End Turn.** A **Skill Points** pool sits at 1. An **Initiative** bar fills slowly. There is no inventory. There is no map. There is no sword.

> **Questionable.** Where did your character go? Are you the entity now? Were you always the entity? The game does not answer.

## Beat 6 — Your first turn. You expand.

You hover an unallocated neighbor. A tooltip: **+5 STR. +3 armor.** You click *Allocate.* 1 SP spent. The node lights up in your color. An edge between it and one of your existing nodes brightens. Your stat board ticks up.

Your **vision** extends with the new node. The fog peels back a hop or two. You see more nodes — and at the edge of vision, a **cluster lit in a color that is not yours.**

> **Questionable.** Someone else is here.

You end your turn. The screen says **NPC TURN.** Your initiative bar empties, refills. In your visible area, one of the foreign nodes expands by one. Then the message clears and it is your turn again.

## Beat 7 — You meet an entity.

You spend the next few turns growing toward the foreign cluster, partly out of curiosity and partly because the nodes on the way have decent modifiers. The cluster comes into clearer view. It is **larger than you.** Maybe eight or ten nodes. It has a Core — a glowing nucleus deeper in its body. It has arms reaching outward, claiming territory.

It is, unmistakably, an entity. The same kind of thing you are.

> **Questionable.** Realizing *I am one of these, and there are others, and they are not friendly* is a fairly large pill to swallow in silence. The game does not narrate the realization. It just lets you have it.

You hover its nodes. Some show stat modifiers. Some show **damage taken** if you struck them. Some show node HP — 10 of 10. Some show *unusual* things.

> **Funny.** One of its outer nodes grants **+2 to Coolness.** Coolness is, apparently, a stat. You don't know what it does. You're not sure it does anything. You'll think about it later.

The enemy ends their turn with another small expansion. They don't seem to have noticed you. Or they have, and don't think much of you. Hard to say.

## Beat 8 — You see the cut vertex.

You stare at the enemy's shape. One of its arms — three nodes — is connected to its body through a **single bridge node.** The bridge has degree 2: one edge in, one edge out. The arm dangles off it.

You hover the bridge. Its HP reads **10/10.** The tooltip helpfully tells you about its modifiers and its color. It does not tell you "this is a cut vertex." You figure that out yourself, because you can see the shape.

> **Questionable.** The game has just become a topology puzzle and **did not announce it.** It expects you to look.

You count your leaves. You have four allocated nodes with degree 1. You hover the bridge with *Attack → Ranged.* The tooltip lights up: **3 leaves in range. Each fires DEX//10. Combined volley resolves once against this target.**

> **Funny.** You read the tooltip the way you used to read items in Dark Souls: too long, twice, lips moving slightly.

## Beat 9 — The first volley.

You commit. Three of your leaves fire at the bridge. A line of light from each, converging on the one node. Numbers float up. The bridge's HP drops from 10/10 to 4/10.

You stop, because you don't have a second action this turn and you have to think. You did **not** kill the bridge. You **dented** it. The enemy is about to take a turn, and when their turn begins, that dent is going to heal.

> **Questionable.** Oh. So a single round of fire is the unit of survival. Not turns, not chip damage. *Burst, or nothing.*

You end your turn. The enemy moves. The bridge ticks back to 10/10 at the start of their turn, as if nothing happened. They expand somewhere irrelevant. They are still not visibly worried about you.

## Beat 10 — You set up the snipe.

Your turn again. You spend SP to allocate one more node — pulling a fourth leaf into firing range of the bridge. You hop your Core one node closer to bring its aura into your firing line. You don't fully understand the aura yet. You can feel it helping.

You queue the volley. Four leaves. The damage readout is now enough.

You hover the *Attack* button.

> **Funny.** You hesitate. You triple-check. You want to make sure you're hitting the **bridge** and not one of the dangly arm nodes — those, your gut says, will not matter. The bridge is the one. You click.

## Beat 11 — The dismemberment.

Four beams. One target. The bridge's HP collapses past zero. The node force-deallocates — its color drains out, and it sits on the map as an unowned, cold neutral node.

Then — and this is the part you'll remember — the **three nodes past it** pause for a half-second, as if checking the map, and **wink out in sequence.** Pop. Pop. Pop. The connecting edges go dark. Their stats vanish from the enemy's board. The enemy's silhouette is suddenly missing an entire arm.

You did not kill three nodes. You killed *one.* The other three could not exist without the path home.

> **Questionable.** You sit with this. The game has just taught you, in one move, that **you are not fighting an enemy.** You are fighting a graph — a connected subgraph held together by very specific load-bearing nodes. Find those, and the rest unmakes itself.

> **Funny.** You immediately, audibly, say "oh **no.**"

The enemy's stat board has shrunk visibly. Whatever those arm nodes were granting — gone. Their core, deeper in their body, looks **worse off** now. Not dying, but diminished. Smaller. Wounded in a way that isn't just HP.

It is the enemy's turn. For the first time, they look at you.

## Beat 12 — The session ends here (for this doc).

What happens next — the retaliation, the loot resolution if you can finish the kill, the strange structures protruding inward from the boundary wall — is the rest of the game. This doc ends at **the click of understanding.** The moment the player realizes they have not been handed a tactical puzzle; they have been handed a graph, and the graph is alive, and they are inside it.

Two design guardrails fall out of this arc:

- If a playtester does not reach Beat 11 in their first hour or two, **onboarding is wrong** — the path from "I'm a sprite with a sword" to "I am dismembering an entity by reading its topology" is the tutorial the game has to teach silently.
- If they reach Beat 11 and do **not** say "oh no" out loud, **the dismemberment visualization is wrong.** The pop-pop-pop has to land as a felt consequence, not a UI update. The whole vibe of the game lives or dies here.

---

## Appendix — every Questionable / Funny in order

| # | Beat | Type | One-liner |
|---|---|---|---|
| 1 | The cute creatures don't read as enemies | Questionable | The game asks you to kill things that read as pitiable. |
| 2 | The Fairy is too insistent about the tree | Questionable | Endearing, but a hair off-pitch. |
| 3 | The panel twitches | Questionable | A frame of wrongness. Easy to dismiss. |
| 4 | The crash feels real | Funny | You're already typing into Discord. |
| 5 | The panel has no close button | Funny | You will look for it. There is no X. |
| 6 | "Where did my character go?" | Questionable | You are now a node. You used to be a sprite. |
| 7 | Someone else is here | Questionable | Other entities, on the same tree, not friendly. |
| 8 | Coolness is a stat | Funny | The mechanical purpose is left as an exercise. |
| 9 | The bridge is silently a cut vertex | Questionable | The game does not say so. It expects you to see it. |
| 10 | Long tooltip read | Funny | "DEX//10 per leaf" you say, twice. |
| 11 | The dent heals at the owner's turn | Questionable | Survival is per-round burst, not chip. |
| 12 | The targeting hesitation | Funny | You triple-check before clicking. |
| 13 | The arm dissolves in sequence | Questionable | You killed one node, three more died. |
| 14 | "oh no" | Funny | Said out loud. |

---

## Open questions (for the playtest, not the player)

- **Beat 7 timing.** Is the first foreign entity visible early enough to feel discoverable, or so early it feels staged? The map seed and starting fog radius need to play here.
- **Beat 9 tutorialization.** Does the player need a one-time hint at "your dent will heal when their turn starts" — or does forcing them to fail the snipe once *teach* the focus-soak rule more effectively than any tooltip? Lean toward the latter; confirm in playtest.
- **Beat 11 readability.** Is the cascade-deallocation animation legible enough that the player connects *killing the bridge* to *the arm dissolving*, without a tutorial pop-up? If they don't make the connection, the whole rest of the game's combat lesson misfires.
- **Beat 4 panic.** How much real distress does "the close button is missing" cause before it tips into delight? The window between *worried about my save* and *amused at the bit* is narrow. Playtest with eye-tracking on the corners where an X should be.
