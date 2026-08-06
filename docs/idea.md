# Idea list — replayability and features

Design ideas, not commitments. Nothing here is scheduled. When one gets approved it becomes a
beads issue and this entry gets a line pointing at the id.

**All of section B is built and shipped** (2026-08-04): B1 `gather-0ez`, B2 `gather-1zv`,
B3 `gather-dj2`. How each works and what is load-bearing in it is in the doc header of its own
file (`systems/raid_director.gd`, `systems/run_stats.gd`, `systems/quest_board.gd`); CLAUDE.md's
subsystem index lists them. B3 shipped as
a panel rather than as the buildable signpost the entry describes — that half is `gather-3vv`.
The size estimates below turned out roughly right except B1, which was worse than "medium" for
exactly the reason flagged: enemies had nowhere to walk to, and it also turned out this game has
no baked navigation at all.

Written 2026-08-04, from a "the game is missing something" session. The code notes under each
idea are the honest starting point, not a plan — check them against the tree before trusting them.

---

## The diagnosis this list came from

The loop is: gather → craft → skill → buy land → gather more. It runs forever and it never
resolves. Three things are absent, and most ideas below are aimed at one of them.

1. **Nothing is at stake.** Enemies trickle in from `EnemySpawner` on a cadence that never
   threatens anything. Walls, doors and turrets defend nothing, so building them is decoration.
2. **There is no finish.** Max the island at 34 parcels and the game keeps going, identically.
3. **Every run is the same.** Same start, same three islands, same order to walk the skill tree.

The best thing already in the game is the **charged skeleton** (`gather-8ft`): the storm changes
what the player goes and *does*. It is worth noticing that this idea is not a new system — it is
a small rule connecting two systems that already existed. Most of the good ideas below are that
same trick used again, and the expensive ones are the ones that are not.

---

## A. Make each run feel different

### A1 — Pick a start (small)

New game offers three: **Miner** (ore common, trees scarce), **Forester** (the reverse),
**Hunter** (more enemies, richer drops, a free net). Changes spawn weights and one starting item.

*Touches:* `Resources.TUNING` weights are already overridable per region
(`IslandManager.ISLANDS` does exactly this), so a start is a mainland weight override plus one
`give_item`. The catch: `MAINLAND_ORE_SHARE` in `items/resources.gd` is pinned by a test, so a
start that moves ore needs the test to take the start into account rather than assert one number.

### A2 — Roll the islands (medium)

Always forest / ore / boss today. Draw three from a pool of six or seven. Candidates: a
**graveyard** (thick with skeletons and bone, a reason to bring the net), a **mushroom island**
(odd food), a **ruins island** with no resources at all — just chests to crack.

*Touches:* `world/island_manager.gd` `ISLANDS` and `world/land_region.gd`. The region already
carries its own spawn weights and its `ambient_resources` / `ambient_enemies` flags, so a new
island is mostly a data entry. Watch the seeded-placement trap: `test_island_manager.gd` sweeps
200 seeds because placement strands islands on a few percent of them, and a bigger pool means
more chances to strand one.

### A3 — Buried treasure (medium)

Rare dig spots. Need a shovel. Pay out coins, a rare recipe, or a map pointing at the next spot.
Gives a reason to walk over ground already stripped bare.

*Touches:* wants to be a scene tile (it holds state — dug or not), so `berry_bush.gd` is the
model to copy, including the save-fidelity rules. New `Types.Item` entries, a tool item in
`items/`, and the atlas-coordinate uniqueness rule in `items/resources.gd`.

---

## B. Give the run a point

### B1 — Nights get worse (medium) — DONE, `gather-0ez`

Day 1 night is quiet. Day 8 night sends a group at the base. Walls, doors and turrets become the
reason you live through it instead of decoration.

*Touches:* `systems/world_clock.gd` already owns day count and phase and already emits into the
combat loop once (the lightning → charged-skeleton chain). Escalation is a curve read by
`enemies/enemy_spawner.gd`, which already floors its cadence at `MIN_INTERVAL` and caps
population at `MAX_ENEMY_CAP` — both bounds have to bend for this or the escalation is invisible.
Enemies also currently wander; "at your base" needs a target, which the enemy state machine does
not have today. That is the real cost of this one.

### B2 — The boss ends the run, with a score (small–medium) — DONE, `gather-1zv`

Kill the boss → the run stops → a card shows Day, Level, gold, things built, islands opened.
Then **New Run**.

This is the highest fun-per-hour idea on the list. It is what turns a sandbox into something you
replay to beat your last score, and almost everything it needs to display is already tracked
somewhere — `LevelUpManager` has level and xp, `LandManager` has parcels, `island_census` already
counts nodes and regions.

*Touches:* a new end-of-run UI in the `UI` CanvasLayer (see `skill_tree_ui.gd` for the
build-in-code + `PRESET_FULL_RECT` pattern — do **not** hang it off `Player/Camera2D/HUD`), a
"run over" state, and a reset path. The reset is the unknown: nothing in the game currently tears
the world down and rebuilds it, and the save format is keyed on node paths, so "New Run" is
closer to a fresh boot than to a load.

### B3 — A quest board (medium) — DONE, `gather-dj2`

A signpost you build. It asks for things — "20 planks", "kill 15 skeletons", "own 3 turrets" —
and pays small rewards. It also quietly teaches a new player what the game wants from them.

*Touches:* a placeable scene tile, a small quest registry built imperatively the way
`systems/skill_tree.gd` and `items/items.gd` are, and counters that have to be **saved as
progress, not configuration** — a half-done quest that resets on load is exactly the failure
class the save-fidelity section of CLAUDE.md exists for.

---

## C. Make the minutes better

### C1 — More weather that changes the plan (small each)

Rain makes berry bushes regrow twice as fast — go picking. Clear nights make ore veins glint so
they can be spotted at a distance — go mining. Storms are already fight night. Weather should
tell you what today is *for*.

*Touches:* `systems/world_clock.gd` owns weather and already exposes it. The bush regrow is a
multiplier on the 900s timer in `world/resource_nodes/berry_bush.gd` — mind that `regrow_left` is
persisted as `time_left` and that `Timer.start()` clobbers `wait_time`. The glint is a shader or
modulate on ore tiles; note the `gl_compatibility` light budget before reaching for `Light2D`.

### C2 — Loot that rolls (medium)

A chest or a boss drops a pickaxe with a random extra: +20% speed, sometimes double drops, swings
free at night. Opening a chest becomes a moment instead of a formality.

*Touches:* `GameItem` subclasses are currently one fixed thing per `Types.Item`, and the save
format stores the type. Rolled modifiers mean an item instance carries state the type does not,
which is a real change to how `SlotData` persists. Worth doing, but it is the deepest change on
this list relative to how small it sounds.

### C3 — Fighting needs one verb (small)

A dodge roll, or hold-to-charge a heavy swing. Right now combat is walking into a skeleton and
waiting. One button makes it a skill instead of a stat.

*Touches:* `player/states/` — a new state in the player state machine (the `change_to(name)` one;
do not carry the enemy machine's pattern across). Probably the cheapest idea here that improves
every single minute of play.

### C4 — A follower (medium)

A pet that walks around picking drops up for you. Craftable, upgradeable. Makes the pickup-radius
skills matter more than they do.

*Touches:* `bone_worker.gd` is already a wandering agent that carries items to a chest and has a
fully-guarded save implementation — it is the reference to copy, and it means this is less new
code than it looks.

### C5 — Machines you place, not just workers (medium)

A conveyor or a chute, so a furnace can feed a chest without a worker walking. Watching a base run
itself is a lot of why Forager sticks.

### C6 — Daily challenge seed (small, but only after B2)

Everyone gets the same seed that day, scored at the end. Pointless until a run has an ending, so
this is strictly downstream of **B2**.

---

## If only two get taken

**B2** (run ends, with a score) then **B1** (nights escalate). Together they turn everything
already built — walls, turrets, workers, the storm — into things that matter. **A1** is the
cheapest way to add replay value on top of both.

**C3** is the honourable mention: it is small, and it improves every minute of play rather than
the shape of the run.
