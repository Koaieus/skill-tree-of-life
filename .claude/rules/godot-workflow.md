---
description: Godot project workflow — class cache refresh, scene round-trip safety
---

# Godot workflow

## Refreshing the class cache after class_name changes

After renaming a `class_name` or adding a new one, the project's
`.godot/global_script_class_cache.cfg` is stale. Runtime parse fails with
*"Could not find type X"* even though the source is correct. The cache
only rebuilds when the editor enumerates the project. Force it via:

```bash
godot --headless --editor --quit
```

## Always git status after a refresh

The editor pass round-trips any scene OR `.tres` it briefly touches and
can silently mutate them. Observed:

- **Dropped node instances** — `[node name="UIRoot" ...]` vanished from
  `dev_sandbox.tscn` during a refresh, with the matching ext_resource
  removed too. Runtime then failed on `$UI/UIRoot` lookup.
- **Regenerated sub_resource ids** — `Resource_umwfs` → `Resource_qrijo`,
  with the consumer reference updated in lockstep (cosmetic, but noise).
- **Position normalisation** — node positions tweaked by a few pixels
  if the editor briefly re-laid out something.
- **Stripped `.tres` fields + sub-resources** — `spark.tres` lost its
  `damage = 5` line, its `range_finder` sub-resource, and the
  `HopRangeFinder` ext_resource entry. The author code (`SpellDef.damage`,
  `SingleHostileNodeTargeting.range_finder`) was correct; the editor
  re-serialized with a *stale view* of the class's field set, omitting
  fields it didn't recognise at that moment. Functionally castrates the
  resource silently — runtime parses it fine, behaves wrong.

Position/id noise is fine. Dropped instances and stripped fields are not.
Mandatory pattern:

```bash
git status                   # before refresh
godot --headless --editor --quit
git diff scenes/ '*.tres'    # immediately after
# restore anything load-bearing that disappeared
```

For `.tres` files specifically: also boot and exercise the resource's
behaviour if you can — silent strip won't cause a parse error, so the
diff is your only signal until the bug surfaces in gameplay.

## Don't refresh while the user is editing

If the user has the editor open and is actively saving, a second
`--editor --quit` invocation can race their autosave and lose work.
Either:

- Wait until they confirm they're done, or
- Leave the parse error visible — they'll see it next time they open
  the editor, which triggers its own refresh.

## When the refresh is safe to skip

Pure script changes (function body edits, new methods, new files
WITHOUT a new `class_name`) don't need a refresh — the runtime parses
those fresh. Only `class_name` introduction / rename / removal requires
the cache to be rebuilt.
