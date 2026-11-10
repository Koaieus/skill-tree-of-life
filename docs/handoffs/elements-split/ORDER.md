Milestone "Content depth" for every new issue. Every file named here is in this directory.

New issue {defs} "Elements: counts, the Element def and its bands, Heat / Cold / Charge": under #1716, body defs.md, Ready.
New issue {terrain} "Elements: terrain is node state — two ints, bands, the live index": under #1716, body terrain.md, blocked by {defs}, Ready.
New issue {flow} "Elements: the world-turn settle — diffusion, decay, the shared commit": under #1716, body flow.md, blocked by {terrain}, Ready.
New issue {terrain-ui} "Elements: terrain on the skill node — bars, labels, tooltip, glow": under #1716, body terrain-ui.md, label ui, blocked by {terrain} and {flow}, Ready.
New issue {applier} "Elements: the outcome applier drains a worklist (refactor, no behaviour change)": under #1716, body applier.md, label tech-debt, Ready.
New issue {resolver} "Elements: the two-stage hit resolver — the land-time gather": under #1716, body resolver.md, blocked by {defs}, {terrain}, {flow} and {applier}, Ready.
New issue {go-off-zero} "Elements: detonation ported onto the gather as go-off zero": under #1716, body go-off-zero.md, blocked by {resolver}, Ready.
New issue {burning} "Elements: Heat's ride row and Burning's disc": under #1716, body burning.md, blocked by {go-off-zero}, Ready.
New issue {catalyst} "Elements: Explosive is retagged as Catalyst": under #1716, body catalyst.md, blocked by {burning}, Ready.
New issue {catalyst-blade} "Elements: the blade's explosive path is removed": under #1716, body catalyst-blade.md, blocked by {catalyst}, Ready.
New issue {refresh} "Elements: re-cut the late specs once the spine has landed (board only)": under #1716, body refresh.md, blocked by {catalyst-blade}, Ready.
New issue {blade-elements} "Elements: blade base — element addons, vertex copy-on-fill, sweep speed": under #1716, body blade-elements.md, blocked by {refresh}, Ready.
New issue {fire} "Elements: Fire — burn, light, the Heat addon, the Burning vertex": under #1716, body fire.md, blocked by {blade-elements}, Ready.
New issue {lightning} "Elements: Lightning — Shocked arcs, conduction, the Charge addon, the Shocked vertex": under #1716, body lightning.md, blocked by {blade-elements}, Ready.
New issue {ice} "Elements: Ice — Frozen, the breakers, the shatter, the Cold addon, the Frozen vertex": under #1716, body ice.md, blocked by {blade-elements}, Ready.
New issue {pairs} "Elements: pair rules — Frozen mutes and releases, dual reach, thaw": under #1716, body pairs.md, blocked by {fire}, {lightning} and {ice}, Ready.
New issue {forge} "Elements: the forge's element field and the starter counts": under #1716, body forge.md, blocked by {fire}, {lightning} and {ice}, Ready.
New issue {quiver} "Elements: element arrows — one ammo type per element": under #1716, body quiver.md, blocked by {fire}, {lightning} and {ice}, Ready.
New issue {forge-ui} "Elements: forge and quiver display": under #1716, body forge-ui.md, label ui, blocked by {forge}, {quiver} and {terrain-ui}, Ready.
New issue {ice-cast} "Elements: Ice on a cast — the concentrate": under #1716, body ice-cast.md, blocked by {forge} and {forge-ui}, Ready.
New issue {inner-tree} "Elements: which inner-tree shape holds them, and the card cadence": no parent, body inner-tree.md, label design, Needs design.
New issue {adr-fixes} "Element ADR corrections: 0081 §1 and §5-§9, 0082's Context, 0061 / 0062 / 0070": no parent, body adr-fixes.md, label documentation, Backlog.

#1716: post split-comment.md as a comment; drop the design label. It is a hub — leave its status.
#1444: blocked by {ice}.
#1695: post close-1695.md as a comment, then close as completed.
#1696: post close-1696.md as a comment, then close as completed.
#1660: post close-1660.md as a comment, then close as completed.
#1733: post close-1733.md as a comment, then close as completed.
#1735: post close-1735.md as a comment, then close as completed.
#1765: post close-1765.md as a comment, then close as completed.

Check the drift stamps on the twenty children of #1716 before setting Ready. Then hygiene.
