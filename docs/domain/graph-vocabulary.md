# Graph vocabulary — the mechanics are the math

Graph-theory terms are load-bearing here: each names a mechanic, so the casual
paraphrase is quietly wrong. Owner correction that set this: "connected
subgraph" → "connected **induced** subgraph".

| Say | Not | Because |
|---|---|---|
| **connected induced subgraph** (an entity's territory) | "connected subgraph", "set of connected nodes" | induced = *every* edge the board has between those vertices is the entity's; that is what makes islanding and bridge severing mean what they mean |
| **cut vertex** (a node whose loss islands an arm) | "chokepoint node" | it is a *vertex* property — `EntityNavigator` answers it |
| **bridge** (an edge whose severing disconnects) | "cut vertex" | a bridge is an *edge*; the two are not interchangeable |
| **degree** | "neighbour count" | three legitimate accessors, see [degree.md](degree.md) |

Applies to docs, code comments, commit messages and issue text alike. Unsure
whether a casual phrasing is equivalent? Look it up rather than guessing — the
GDD and the combat docs use the formal terms deliberately.
