# Save fixtures

Committed save files, for the one thing CI and a fresh clone can never give you: a save
written by an **older build**. `saveFile` and `user://saves/` are gitignored, so without
these the only way to test a load path against a real historical payload is to have been
running the game on that machine at the time.

Install one by copying it over the slot you want, then press `]` (or open SAVES with `O`):

```bash
cp test/fixtures/demo_homestead_save \
   "$APPDATA/Godot/app_userdata/Gather/saves/slot_1.save"
```

Back up whatever is in that slot first — the copy is destructive and there is no undo.

| File | Format | What it is |
|---|---|---|
| `demo_homestead_save` | **v4** (current) | The one to load if you just want a populated world. |
| `demo_homestead_save_v3` | v3 | Backward-compatibility fixture. Do not regenerate. |
| `demo_homestead_save_v1` | v1 | Backward-compatibility fixture. Do not regenerate. |

## `demo_homestead_save`

A maxed island — 12 parcels, radius 34 — with a player-built homestead on it:

- a 7x5 wood-walled house with a door, floored inside
- 2 chests, a sawmill and a furnace inside it
- 4 bone turrets on the corners, 2 bone workers and 2 stone workers flanking
- level 18, banked skill points, the Industry chain taken through `smelting`, and
  wood/stone/planks/ore in the bag
- **all three islands open and stocked** — 30 nodes on the forest grove, 24 on the ore
  island including its four iron and its gold veins, the elite alive in the arena with its
  reward chest beside it

**The furnace is deliberately left mid-smelt** — iron bars, 52 of an original 60, part-way
through the current one. That is not decoration: it is the state `gather-9x0` was about,
where a load restored `count` and `starting_count` (so the progress bar looked right) while
silently restarting the in-flight item. A fixture that only ever holds idle stations cannot
catch that coming back.

It also has to hold a *real* recipe. The first attempt at this fixture had a running timer
with `selected_recipe: -1`, which is a state `save()` can write whenever the recipe is null
— and loading it threw `Invalid access to property or key 'product' on a base object of
type 'Nil'` on the first tick, because `_on_timeout` read `selected_recipe.product`. Both
sides now enforce the invariant (no recipe means no work order), but the fixture carrying a
real one is what keeps the happy path honest.

Regenerate with the `build_demo_world` devtools verb rather than by hand — placement scans
for a clear site because the island is noise-thresholded, so a fixed offset is open water
on a good share of seeds:

```bash
python tools/devtools.py cmd build_demo_world
```

Then check `island_census` before you keep the result. Island placement is seeded, and a
seed can leave one island unopened even at max land (`gather-37z`); a fixture whose boss
arena cannot be reached is worse than no fixture, because nothing in the suite reports it.
The rest of the state — the level, the Industry skills, the bag, and the furnace's 52 of 60
— is set with `add_xp`, `learn_skill`, `give_item`, `queue_craft` and `advance_crafting`.
Use `advance_crafting` rather than `step_time` for the part-finished order: the furnace
smelts at one item a second, so real time overshoots by tens of items while you type.

## `demo_homestead_save_v3`

The world this fixture used to be, kept because the file is now the only committed
artefact in the **pre-`stations` recipes shape** — `furnace_recipes` / `sawmill_recipes` as
top-level keys, which `Recipes.loadObject` still has to read (gather-uaq). Do not
regenerate it.

It is also the record of the bug that produced the current file. Its mainland carries **30
resource nodes across 1807 ground tiles** and both stocked islands are empty, because
`build_demo_world` grew the island without emitting `land_purchased` and so never stocked
the new land or opened the islands (`gather-3m9`). Loading it beside the current fixture is
the clearest possible before-and-after.

## `demo_homestead_save_v1`

The same world, saved by the build that existed before two format changes. **Keep it, and
do not regenerate it** — its value is entirely in being old. It is the only committed
artefact that exercises:

- the pre-v3 **double-encoded** payloads, where every sub-list held `JSON.stringify`'d
  dictionaries instead of nested ones (`SaveLoad.decode_entries` reads both shapes, and
  this is what proves the old branch still works);
- a **v1 header**, with no `saved_at` / `level` / `land_radius`, which `slot_info()` must
  report as readable-with-zeroed-metadata rather than as damaged;
- crafting stations with **no `time_left`** and workers with **no `carry`**, the payloads
  that predate the save-fidelity pass and must still load.

Size note, since it looks backwards at a glance: the v1 file is *larger* (71067 bytes) than
the v3 one (53218) despite holding *fewer* tiles. The difference is the escaping the inner
`JSON.stringify` layer added to every entry.
