# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. This game is inspired by Forager and it's early game mechanics. 

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Build & Test

Godot 4.7 project (`config/features` in `project.godot`). No package manager and no
build step for development. The Godot binary is typically **not on PATH** — resolve it
first and reuse the path.

```bash
GODOT="/c/Users/gotmi/Documents/Godot_v4.7.1-stable_win64.exe"   # adjust per machine

# Headless — need no running game
"$GODOT" --headless --path . --script res://tools/lint_project.gd    # UID + scene lint
"$GODOT" --headless --path . --script res://tools/run_tests.gd       # all unit tests

# A single test (substring match on the method name)
"$GODOT" --headless --path . --script res://tools/run_tests.gd -- --filter test_food_actually_heals
"$GODOT" --headless --path . --script res://tools/run_tests.gd -- --json

# Play the game (--mute for automated runs)
"$GODOT" --path . --mute

# REQUIRED after adding any new class_name
"$GODOT" --headless --path . --import
```

**The `--import` step is not optional.** A newly added `class_name` is unresolvable
until `.godot/global_script_class_cache.cfg` is regenerated. Until then lint reports
cascading `Could not find type "X"` errors through `main.gd`, `player/player.gd` and
`items/items.gd`, and the game fails to boot — all of which look like your new code is
broken when the cache is the only problem.

**Case-only renames on Windows.** The filesystem is case-insensitive, so `git mv Items
items` records the rename in git while the directory on disk keeps its old case. Godot
then loads the same script under two paths and reports `Class "X" hides a global script
class` for many classes at once, alongside `Case mismatch opening requested file`. The
symptom looks like a duplicate-class bug in your code; it is not. Rename physically in
two steps (`Items` -> `__tmp` -> `items`), then re-run `--import`. This happened during
the `gather-c7o` reorganization and cost real debugging time.

**Reading lint output:** `SceneState: ... NodePath unresolved` lines are false
positives. Those paths resolve fine at runtime; the checker cannot see into instanced
sub-scenes. Only missing-resource and parse errors are real. See beads `gather-75k`.

**Test contract:** files are `test/unit/test_*.gd` extending `RefCounted`, with optional
`setup()` / `teardown()` run around each test. Every `test_*` method returns `""` to
pass or a failure message. The runner injects itself as `_T`, providing `assert_eq`,
`assert_true`, `assert_false`, `assert_gt`, `assert_gte`, `assert_float_eq`. Note that
`var x := _T.assert_eq(...)` fails to compile (`_T` is untyped) — write
`var x: String = _T.assert_eq(...)`.

**Known runner limitation (`gather-1t9`):** a runtime error inside a method declared
`-> String` is still counted as a pass, because GDScript aborts the method but the
typed signature still yields `""`. A green suite is therefore not sufficient — also
check the runner's stderr for `SCRIPT ERROR`.

## Architecture Overview

Single-scene game. `main.tscn`'s root node `Main` runs `main.gd` (`class_name
TileMapHandler`) and owns world generation, tile writes and the save format.

**The scene tree has exactly three branches under `Main`** (`gather-ue3`), and new
nodes belong in one of them rather than loose at the root:

```
Main
├── World      (Node2D, y-sorted)  everything with a world position
│   ├── TileMap, EnemySpawner, ResourceTimer, PickUps
│   └── Player
│       └── Camera2D
│           └── HUD  (Control, ui/camera_hud.gd)  the *diegetic*, world-space HUD
│               ├── FpsLabel, FloatingText/XpLabel
│               └── PlayerInfo (HpBar, XpBar, HpCaption, XpCaption)
├── UI         (CanvasLayer)  screen space: HotBarInventory, MobileControls,
│                             CraftingUI, SkillTreeUI, InventoryInterface, and
│                             everything main.gd builds at runtime
└── Systems    (Node)  Items, Resources, ResourceManager, SoundManager, InputManager,
                       DestroyManager, SaveLoad, InventoryManager, LevelUpManager,
                       WorldClock
```

Three things about this are load-bearing and easy to undo:

- **`Systems` is declared after `UI` in the scene file, and must stay there.** Godot
  readies siblings in tree order, and `InventoryManager._ready()` reaches straight into
  `UI/InventoryInterface` and `UI/HotBarInventory` `@onready` fields. Move `Systems`
  above `UI` and those are still null: a first-frame crash whose stack points at
  `hot_bar_inventory.gd`, nowhere near the edit that caused it.
- **`UI` (screen space) and `HUD` (world space) are different things.** `HUD` hangs off
  `Camera2D` at the camera's `8` zoom; a full-screen panel put there is drawn into
  the world. These were `UI2` and `UI` respectively, which is why so many scripts still
  carry a comment warning you not to confuse them.
- **`LandManager`, `IslandManager`, `SkyLighting` and the `Ocean` CanvasLayer are created
  by `main.gd` at runtime as direct children of `Main`**, so they sit outside the three
  branches by design — their save entries and `land_manager.gd:65`'s `get_parent()` both
  depend on it. `SkyLighting` is there for a different reason from the rest: it writes into
  three separate canvases (see **Day/night lighting** below) and none of them is a natural
  parent for it.

Renaming or moving a node here is a save-format change: see **Saving** below.

Source is grouped by domain: `player/` (+`states/`), `enemies/` (+`states/`), `items/`,
`inventory/`, `crafting/`, `turrets/`, `world/` (+`resource_nodes/`, `tile_scenes/`,
`vfx/`), `systems/`, `ui/`, and `assets/` (+`art/`, `audio/`, `tilesets/`, `materials/`,
`shaders/`). The harness dirs `addons/`, `devtools_ext/`, `tools/` and `test/` sit at
root, as do `main.gd`, `main.tscn`, `default_bus_layout.tres` and `icon.svg` — those
four are pinned by `project.godot` or by an implicit `res://` default, so they must not
move. There is deliberately no `Resources/` folder: that name collided both with Godot's
`Resource` type and with the game's own tree/stone "resource" concept, so art and audio
now live under `assets/`.

Autoloads (see `[autoload]` in `project.godot`): `GameItems` (`items/items.gd`),
`GameSoundManager` (`systems/sound_manager.gd`), `Recipes` (`crafting/recipes.gd`),
`PlayerManager` (`player/player_manager.gd`), `PickUpManager`
(`items/pick_up_manager.gd`), `DevTools` (`addons/godot_selftest/dev_tools.gd`).

**One ID space.** `Types.Item` (`items/types.gd`) is a single enum covering
inventory items, world resources and placeable tiles. Everything keys off it.

**Item model.** `GameItem` (`items/game_item.gd`) is the base; behavior is added by
overriding `use()` / `stop()` / `can_use()`. Every subclass now lives in `items/` in a
file named for its class — `GameItemPickaxe` in `items/game_item_pickaxe.gd`,
`GameItemPlaceable` in `items/game_item_placeable.gd`, and so on — so the class name is
enough to find the file. (Before the `gather-c7o` reorganization these were scattered
across `Items/` and `Inventory/` under unrelated filenames; if older notes or beads
mention `ItemDataEquip.gd` or `GameItemCraftingStation.gd`, those are the two above.)
Registries are built imperatively in `_ready()`: `items/items.gd` populates `item_list`,
and `items/resources.gd` populates `resources` then applies `Resources.TUNING`.

**Where gameplay tuning lives** — these are the files to edit for balance, not the
logic: `Resources.TUNING` in `items/resources.gd` (xp, yield range, spawn weight,
secondary drops per resource), the `items/items.gd` constructor calls (pickaxe gather
time and bonus yield, consumable heal values), `crafting/recipes.gd` (recipe costs),
`systems/skill_tree.gd` (every skill's effect, prerequisite and unlock) and
`LevelUpManager.XP_FIRST_LEVEL` / `XP_GROWTH` (the level curve).

**Skill tree** (Forager-style, replaced the five hardcoded upgrade buttons):

- `systems/skill_tree.gd` is the registry — four branches (Foraging, Industry,
  Combat, Building), three tiers each, built imperatively like `items.gd`. A skill
  carries `effects` (stat deltas), `recipes` and `resources` (unlocks), so adding
  one is a data edit, not a new `_apply_*` method.
- `systems/player_stats.gd` sums the taken set into the totals the game reads:
  gather time (`resource_manager2.gd`), bonus yield, xp, damage / max health /
  move speed (`player.gd`) and pickup radius (`items/pick_up.gd`). It **recomputes
  from scratch** on every change — never apply a delta incrementally, or load and
  repurchase will double it.
- `systems/level_up_manager.gd` owns xp, level and banked points. It no longer
  draws anything and no longer seizes the screen on level-up; points bank and the
  player opens the panel with `K` when they choose to.
- `ui/skill_tree_ui.gd` builds the panel in code from the registry and lives in the
  `UI` CanvasLayer. Do not put full-screen menus under `Player/Camera2D/HUD` —
  that Control is world-space at `0.23` scale for the diegetic HUD.
- Unlocks are applied on purchase only, never on load: `Recipes` and
  `ResourceManager2` persist their own unlocked lists, so replaying them would
  append every recipe twice.
- The devtools verbs `skill_panel` and `learn_skill` drive it from the CLI, and
  `player_state` spells out the stat totals (`PlayerStats` is a RefCounted, so
  `get-state` shows only an opaque object id).

**Window size and UI layout.** The window is `1920x1080` with `window/stretch/mode`
explicitly `"disabled"` (`[display]` in `project.godot`), so growing the window shows
*more world* rather than scaling the same view up — sprites stay pixel-exact at the
camera's `8` zoom. Nothing may hardcode a viewport dimension:

- Screen-space UI goes in the `UI` CanvasLayer and must be anchored to a viewport
  edge or centred, never placed at absolute pixels. `skill_tree_ui.gd` and
  `land_purchase_ui.gd` build themselves with `PRESET_FULL_RECT` + a
  `CenterContainer` and need nothing further.
- The diegetic HUD under `Player/Camera2D/HUD` is world-space and gets no viewport
  rect for free, so `ui/camera_hud.gd` sizes that Control to
  `viewport_size / camera.zoom` and centres it on the camera, on `_ready` and on
  `size_changed`. **Its children must therefore use ordinary anchors** — `0` is the
  left/top screen edge, `1` the right/bottom, `0.5` the centre. `PlayerInfo` and
  `Crafting` are bare `Control`s that exist only to pin a group to a corner; anchor
  the group and leave the offsets of the things inside it alone.
- Anchors were retrofitted in `gather-6fx`. Before it every offset was hand-tuned to
  the old `1152x648` window (the HUD's left edge was literally `x = -115`, one unit
  inside `1152 / 4.935 / 2` at the `4.935` zoom the camera ran at back then — it is `8`
  now), and every element drifted toward the middle of the
  screen the moment the window grew. If you see a raw `-115` or a `470` in a layout,
  it is a leftover of that and is a bug at any other size.

**Day/night lighting, and the three canvases.** `Systems/WorldClock`
(`systems/world_clock.gd`) owns the time of day and the weather and draws nothing;
`SkyLighting` (`world/vfx/sky_lighting.gd`) draws what it says. The split is the
`LevelUpManager` / `SkillTreeUi` one, for the same reasons.

The thing to know before touching any of it: **a `CanvasModulate` tints exactly one
canvas — the one it is a child of — and this game has three.**

| Canvas | Holds | Under a `CanvasModulate` in `World`? |
|---|---|---|
| root (no CanvasLayer) | `World`, TileMap, Player, Camera2D, **and the diegetic HUD** | tinted |
| `Ocean`, layer `-100` | the sea (`main.gd:_setup_ocean_backdrop`) | **not** tinted |
| `UI`, layer `1` | hotbar, panels, screen flash | **not** tinted |

Two of those three rows are wrong by default, so `SkyLighting` makes three writes, not one:

- The **sea** is missed. Left alone it stays daylight blue at midnight while the land it
  surrounds goes dark, which reads as a rendering bug rather than as night. It gets the
  same tint multiplied into `OCEAN_COLOR` by hand — against a *captured base colour*, never
  against the current one, or the multiply compounds to black in about a second.
- The **HUD** is hit when it should not be: it hangs off `Camera2D`, so it is in the root
  canvas, and the HP and XP bars dim exactly when the player most needs to read them. It is
  cancelled with the reciprocal tint in `modulate` — a per-item multiply against a
  whole-canvas multiply, which is exact. That is deliberately cheaper than moving the HUD
  into the `UI` layer: it is world-space by design and `camera_hud.gd`, the anchor rules
  above and the save paths all depend on it staying there.
- The **`UI` layer is left alone on purpose.** Screen-space UI is not in the world and does
  not take the world's weather.

`NIGHT_TINT`'s `0.42` floor is a *readability* floor, not an aesthetic one — below roughly
`0.35` the 16px art stops being identifiable. Turn the blue up, not the floor down.
`test_world_clock.gd` pins the floor, and pins that the tint curve is continuous across
every phase boundary *and across the wrap at midnight* — a seam no single screenshot can
show you.

**Lightning is those same three writes with a brighter number going into them.** A storm
fires bolts on a countdown — `WorldClock.lightning_time_left`, re-rolled between
`LIGHTNING_MIN_GAP` and `LIGHTNING_MAX_GAP` after every strike — and fires them *only* while
`weather` is `RAIN`. Starting rain arms the countdown, going clear disarms it to `0.0`. An
armed countdown under a clear sky is a bolt waiting to flash out of nothing, and it is the one
way those two fields can contradict each other, which is why `world_clock` reports both rather
than deriving one from the other.

`distance` — `0.0` overhead to `1.0` on the horizon — is the single number `lightning_struck`
carries, and every consumer derives from it instead of rolling its own: the flash brightness
(`SkyLighting.flash_peak_for`) and the thunder's volume *and pitch*
(`GameSoundManager.play_thunder`). Two independent "how close was it" rolls would disagree on
every strike, and a bolt that looks overhead while sounding far off does not read as two
randomisations — it reads as broken audio.

**There is deliberately no delay between the flash and the thunder**, and the absence is the
decision. `play_thunder` used to model light outrunning sound, so a horizon bolt cracked 4.5
seconds after its flash; in a game whose whole day is ten minutes that read as broken audio
rather than as distance, because the flash was long gone and the bang arrived attached to
nothing. Distance carries in volume and pitch instead, which reads as distance without cutting
the sound loose from what the player just saw. If you come here looking for
`WorldClock.thunder_delay` or `THUNDER_DELAY_MAX`, this paragraph is what replaced them.

**The flash is folded into the tint *before* the three canvas writes, and that placement is
load-bearing.** `SkyLighting` multiplies the envelope into the colour it is about to hand out,
so the sea brightens with the land on the write that already keeps those two agreeing, and the
HUD's reciprocal cancels the flash for free — the health bar does not strobe, and nobody had to
add a second rule saying it must not. Both are consequences of the ordering rather than
features anyone wrote. Tidying this into a separate white overlay on the `UI` layer
reintroduces both problems at once and neither of them looks like the edit that caused it: a
flat dark sea sitting under land that goes white, and an HP bar blowing out every few seconds
during a storm — which is precisely when the player is fighting in the dark and reading it.

At most one bolt fires per tick, however large the delta. A `step-time --seconds 300`, a frame
stalled behind an import, or a load that fast-forwards can cover a dozen gaps; looping until
the countdown went positive would emit a dozen `lightning_struck` into a single frame, and the
player would still see one flash and hear one thunder because every consumer draws into the
same screen and the same audio bus. The re-arm is a full fresh gap and not the remainder, so a
long step visibly *eats* the bolts it skipped instead of banking them into a burst on the far
side. A later reader who reads the `if` as a missed `while` should read this paragraph instead.

`lightning_time_left` is progress, not configuration, so it is saved — the `time_left` versus
`wait_time` distinction the save-fidelity section below already spells out. Re-rolling it on
load takes a bolt off the player who saved eighteen seconds into a nineteen-second gap, and
nothing reports that.

**Rarely, a near bolt lands on a skeleton and what gets up is a different enemy** (`gather-8ft`).
That is the one place the weather reaches into the combat loop, and the chain it starts is the
reason the storm is worth standing out in:

```
WorldClock.lightning_struck(distance)
  -> EnemySpawner.should_charge(distance, randf())   # CHARGE_CHANCE 0.08, near bolts only
  -> the struck Bone is REPLACED by an EnemyRegistry.CHARGED ("ChargedBone")
                                                     # charged_bone_enemy.tscn, same spot, full health
  -> the player NETS it                              # -> Types.Item.ChargedBoneEnemy
  -> GameItemChargedBoneEnemy.use()                  # set_loaded() + make_charged(), one EMPTY machine
  -> BoneWorker: 20s chop -> 10s      BoneTurret: 1.0s fire -> 0.55s, +2 bullet damage
```

Six things here are load-bearing and easy to undo:

- **Lightning is that type's only source, because `CHARGED` is `ambient: false`.** Letting the
  spawn timer trickle one in puts the rare reward on the ordinary cadence, and a player who can
  simply wait for one has no reason to be outside in a storm. The sky would still flash and
  rumble; it would just stop meaning anything.
- **Only `EnemyRegistry.BONE` is replaced.** Not spiders — what the capture loads is a *bone*
  machine — and not the elite, which is a bone enemy underneath but is the boss island's placed
  guard. `charged_bone_enemy.tscn` is an inherited scene over `bone_enemy.tscn`, the way
  `elite_enemy.tscn` is, and overrides it to 30 health and 5 damage: netting one is a real fight
  rather than a free pickup that happens to be blue.
- **It is collected with the Net, exactly like an ordinary skeleton, and killing one is a loss.**
  `player_net.on_hit()` is entirely registry-driven (`EnemyRegistry.is_nettable` /
  `capture_item`), so this needed no change to the net at all — the type just names its own
  capture item. Its loot table is deliberately barely better than a plain skeleton's and has to
  stay that way: a rich one makes killing competitive with catching, which inverts the point of
  hunting it. The reward is the capture.
- **The blue and the sparks are baked into the `.tscn`, not applied by code.** That is the point
  of a scene rather than a flag: the look comes back from a load because the scene is what gets
  instantiated, with no load path involved. The flag design had to split `_apply_charged_tint()`
  out of `make_charged()` purely so the load could re-apply the colour past the idempotence
  guard, and a miss there brought the enemy back grey while it still paid out — the worst
  version, the reward intact and the warning that earns it gone. That hazard is now gone for the
  enemy. The machines keep their own `charged` flag and `_apply_charged_look()` split, and must:
  a skull is fitted to a turret at runtime, so for them it genuinely is per-node state.
- **The blue goes on the Sprite2D's `modulate`, never the root's.** The root's modulate carries
  the hit flash and the death fade; something that stopped flashing white when struck would read
  as invulnerable. Per-item modulate multiplies, so the flash still lands on top of the blue.
- **Making this a real type made the save format simpler, not more complex.** `type` is already
  persisted and `scene_for_type()` already rebuilds from it, so being blue, being tougher and
  netting into a different item all survive a load for free, and the `charged` key — with its
  `typeof(...) == TYPE_BOOL` normalize guard and its re-application after `add_child` — was
  deleted rather than added to. A flag would have been a second copy of a fact the save already
  carried, and two copies can disagree.

The capture **loads an empty machine only**: `find_closest_loadable()` skips any `BoneTurret` or
`BoneWorker` whose `loaded` is true. It is a loading item, not a retrofit for one already
working, and without the skip a player standing beside a running turret has the skull ranked
toward it while an empty worker a step further out goes without.

`BoneTurret` captures `_base_fire_interval` in `_ready` and always multiplies *that*, never the
live `wait_time`. `Timer.start()` assigns `wait_time`, so deriving the charged interval from
the current one compounds on every call — the `gather-9x0` furnace bug in a new place, and the
reason `make_charged` is idempotent in effect as well as in its guard. Measured: still `0.55`
after four calls, not `0.55^4`.

The devtools verbs are `charge_skeleton` (forces the replacement on a live skeleton, bypassing
both the roll and the distance gate, and reporting honestly when there was no skeleton to hit)
and `charged_state`, which counts enemies by type — `EnemyRegistry.CHARGED` against `BONE` —
alongside charged workers and turrets in one read, and lists `ground_drops` by item name. That
last field exists because a `PickUp`'s `slot_data` is a Resource and `get-state` reports it as
an opaque object id, so what a kill actually left on the ground is otherwise unanswerable
without walking the player over it — which conflates the drop with the pickup radius.

**From night three, the dark comes to you** (`gather-0ez`). `Systems/RaidDirector`
(`systems/raid_director.gd`) is the model and `ui/raid_banner.gd` is the view — the same split
as `WorldClock`/`SkyLighting`, for the same three reasons. On `night_started` it opens a raid
whose size and toughness grow with the day, spawns it in a stagger, and pays a clear bonus when
the last raider goes down. Before it, night was `NIGHT_CAP_MULT` and `NIGHT_INTERVAL_MULT` — a
few more wanderers, somewhere else — and walls, doors and turrets were decoration, because
nothing was ever coming for anything.

Six things here are load-bearing:

- **Raiders are their own registry types, not a flag on a skeleton.** `EnemyRegistry.RAIDER_BONE`
  and `RAIDER_SPIDER` are inherited scenes over the ordinary ones, exactly as `CHARGED` is, and
  for the reason that note already gives: `type` is persisted and `scene_for_type()` rebuilds
  from it, so the ember tint and the wide `hunt_range` come back from a load with no code on the
  load path. It is also what makes **"how many raiders are left" a live count rather than a
  counter** — `RaidDirector.live_raiders()` walks the spawner's children. A counter decremented
  from each raider's `died` signal is wrong the instant the player quicksaves mid-raid: the
  enemies come back through `EnemySpawner.loadObject`, which connects nothing, so every later
  kill is invisible and the raid never clears.
- **`Enemy.hunt_range` is the dial that makes a raid arrive.** `EnemyIdle` used to hardcode 30px
  — two tiles — so a raider spawned across the island simply wandered where it landed. Ambient
  enemies still get 30 from the export's default; only the raider scenes widen it, so the
  ordinary island is unchanged.
- **Raiders spawn in the player's OWN region, and `accepts_ambient_enemies` is deliberately not
  consulted.** The first implementation picked any far-enough land and got this exactly
  backwards: a fresh home island is 160px across, so *no* home cell cleared the 200px minimum
  and every candidate that did was on a pregenerated island. Those raiders pathed at the player,
  walked into the sea and stopped — right type, right toughness, velocity set, position
  unchanged. A raid that never arrives is worse than none: the banner counts seven enemies the
  player cannot find. Nothing headless sees this and no screenshot shows it; it took reading one
  raider's position twice, eight seconds apart, to find it had moved 0.13 pixels.
- **There is no baked navigation in this game**, and `EnemyFollow` now compensates. The tileset
  declares navigation source groups but nothing in `main.tscn` is a `NavigationRegion2D`, so
  `get_next_path_position()` returns a point on the straight line to the target — walk it into a
  tree and `move_and_slide()` cancels the velocity and the enemy stands there pushing. That was
  invisible while chasing was a two-tile affair; a raid is the first thing that asks an enemy to
  cross an island. `EnemyFollow` measures actual displacement (never `velocity`, which is what
  was *written* and stays nonzero against a wall) and sidesteps along the obstacle after
  `STUCK_AFTER`. Baking navigation is the real fix and is a change to the tilemap, the save
  format's terrain replay and every scene tile that writes a cell.
- **Raiders are spawned outside `EnemySpawner`'s population cap, on purpose**, so `MAX_SIZE` is a
  frame-rate bound before it is a difficulty one. A raid that counted against the ambient
  ceiling would simply stop the trickle and feel like nothing had changed.
- **Health scales with the night; damage deliberately does not.** The game has no armour, so a
  raider that hits harder every night is a difficulty setting the player has no dial to answer.
  More health is answered by every dial they *do* have: a better sword, the Combat branch, a
  turret, a wall to fight behind.

Dawn ends a raid without paying and **leaves the surviving raiders alive** — a wave evaporating
at sunrise reads as the game tidying up after itself and cancels the night's tension in one
frame. `raid_survived` and `raid_cleared` are separate signals because surviving until morning
and clearing the field are different things, and only the second is a clear.

The devtools verbs are `raid_state` (the director's state *and* the banner's, for the reason
`world_clock` reads the tint back off all three canvases), `start_raid` — which **moves the
clock to night first if it is daylight**, the same way `strike_lightning` starts a storm,
because `_process` ends any raid it finds running outside the dark and the verb otherwise
reported a cheerful success for a raid that was over one frame later — and `end_raid`, which is
the dawn path rather than a clear, so it can never be used as a coin faucet.

Note also that `project.godot` runs `gl_compatibility` on mobile, which caps `Light2D`s per
canvas item. The player lantern is deliberately one light; anything added later (a torch, a
campfire) has to be distance-culled against the same budget.

**Tilemap layers** (`main.gd`): `0` ground/terrain, `1` objects (resources, walls,
buildings), `2` floors, `3` highlight overlay. A tile is mapped back to its registry
entry by matching `atlas_location` + `tile_source_id`, so those coordinates are
effectively the persistence key — changing an atlas position silently changes save
compatibility. Resources flagged `is_scene_tile` are instead instanced as
`GameSceneResource` children of the TileMap, so any code that enumerates resources must
handle both representations (`main.gd:resource_node_census` does).

**Physics layers, and why "solid" is three different things.** Tilemap *layers* (above) are
about drawing order. Collision layers are a separate axis, named in `project.godot`'s
`[layer_names]`, and the split between them is what stops enemies getting stuck on rocks
(`gather-eqrl`):

| Bit | Value | Name | Carries | Blocks |
|---|---|---|---|---|
| 1 | `1` | World | terrain and coastline, **and** walls and doors | everything |
| 7 | `64` | Structure | a **duplicate** of wall and door collision | nothing — it is a raycast target |
| 8 | `128` | Prop | trees, rocks, ore, bushes, stations, chests, turrets | the player and nothing else |

Four things about this are load-bearing:

- **Structure blocks nothing, and that is the point.** Those tiles keep their layer-1
  polygon; the layer-7 copy exists so `Enemy.has_line_of_sight_to()` can ask "is there a
  WALL between me and the player" without terrain, water or a tree answering. Delete the
  duplicate and the ray passes through everything: every enemy hunts through every wall,
  and *nothing reports it* — a vacuous gate and a working gate read identically from every
  other tool. `enemy_vision`'s `structure_polygons` is the one number that tells them apart,
  and it counts off the TileSet the running game loaded, not the file on disk.
- **Terrain stays on layer 1 and must.** Enemies mask bit 0, so the coastline is what stops
  them walking into the sea. Move terrain to Prop "for consistency" and raiders swim.
- **Prop is off layer 1, so enemies simply do not feel it.** There is no baked navigation
  here (see `enemies/states/enemy_follow.gd`), so a blocked enemy does not path around
  anything — `move_and_slide()` cancels the velocity and it stands there pushing. Not
  colliding at all is the fix; the sidestep in `EnemyFollow` is the fallback for walls.
- **Seven props are scene tiles and are not in the tileset at all.** `stone_node.tscn`,
  `berry_bush.tscn`, `chest.tscn`, `bone_turret.tscn`, `sawmill.tscn`, `furnace.tscn`,
  `test_chest.tscn`. None of them authored a `collision_layer` before this change — an
  absent line defaults to `1`. So the tileset can be perfectly split while a home island
  full of stone nodes and bushes goes on catching every skeleton, which is the original bug
  surviving in the one place the player spends all their time. Stations and chests keep the
  Interactable bit (`4`); it is what the player's `Interact` area masks and what puts the
  OPEN prompt on them.

`test/unit/test_collision_layers.gd` pins all of it, deriving from the registries and
resolving layer indices *by bit* rather than hardcoding index `0` — a resource added later is
covered the day it is registered, and renumbering the layers in the editor cannot make the
test pass vacuously. That matters more than the change itself: this is a split that one save
from the Godot tileset editor can silently undo.

**The berry bush is the one resource a gather does not destroy** (`gather-j2n`,
`world/resource_nodes/berry_bush.gd`). Every other node is a single event — hold the
pickaxe, it pays out, the cell is cleared. A bush has two states and two gathers:

| State | Gathering it | Result |
|---|---|---|
| fruiting | *picks* it | Berries drop (heal 1 each), **the bush stays**, a 900s regrow starts |
| picked | *uproots* it | Exactly one placeable `BerryBush` item, cell cleared |

Four things about this are load-bearing:

- **The order is the anti-duplication rule.** A bush can only be uprooted once it is
  already picked, and a *replanted* bush comes up picked with a full regrow — otherwise
  pick / uproot / replant / pick is an infinite berry faucet. A planted bush knows it was
  planted through `BerryBush._planted_cells`: `GameItemBerryBush.use()` marks the cell, the
  node claims the mark in `_ready()` a frame later. They have no reference to each other —
  the item is a RefCounted outside the tree and the node does not exist yet — which is why
  that hand-off is a static with a TTL rather than a signal.
- **The uproot deliberately bypasses `remove_resource`.** That function rolls yield against
  the pickaxe's bonus chance, and a bonus roll on a bush hands back two bushes for one: an
  item duplicator built out of the code that makes a gold pickaxe worth buying.
- **Picking emits `resource_removing_stop`, never `resource_removed`.** The second is what
  makes `main.gd` clear the cell; the first only takes the layer-3 selector back off. Emit
  the wrong one and the bush vanishes on its first harvest.
- **It is a scene tile because a cell has nowhere to keep a clock.** `regrow_left` is
  persisted as `time_left`, not `wait_time`, and `_restart_regrow` puts the interval back
  after `Timer.start()` assigns over it — the `gather-9x0` furnace bug in a new place.

The reason `ResourceManager2` now branches on `resource.is_scene_tile` rather than naming
`StoneResourceTest`, and the reason `main.gd` grew `scene_tile_at(cell)` next to
`get_nearest_scene_tile()`, are both this: with two scene-backed resources, "the node on the
cell the player is working" and "the nearest scene node" are no longer the same node, and the
old code answered the second while meaning the first.

Food no longer drops from trees. It is a 4% drop off every enemy type
(`EnemyRegistry.FOOD_DROP`), so the biggest early heal is bought with a fight, and berries are
what the forager gets instead.

**Food is now an input to nothing** (`gather-as9`). `CookedFood` and `Bandage` were priced
against the old 0.2 tree drop and both moved onto berries — 4 Berries + coal, and 2 String +
2 Berries. The rule that broke is worth knowing because a bare "the crafted thing heals more"
does not catch it: Cooked Food cost 2 Food, which heal 4 each where they stand, and healed 10.
It was an *improvement*, by two points, for a station, fuel, a walk and ~50 kills' worth of
input. `test_ore_chain.gd:CRAFTED_HEAL_MULTIPLE` now requires a station recipe to pay at least
2x what its own edible inputs are worth eaten raw, which is the version of the rule with teeth.

**Gather loop**, the most-touched path and the one that spans the most files:

```
InputManager (systems/input_manager.gd, signals)
  -> Player (player/player.gd)
  -> HotBarInventory (inventory/hot_bar_inventory.gd)
  -> InventoryData.use_slot_data (inventory/inventory_data.gd)
  -> SlotData.item.use() (inventory/slot_data.gd)
  -> Player StateMachine (player/states/state_machine.gd)
  -> PlayerGather (player/states/player_gather.gd)
  -> ResourceManager2.start_removing_resource(pickaxe)   # world/resource_manager2.gd
                                                         # hold_timer.wait_time = pickaxe.power
  -> on timeout: remove_resource() -> rolls yield,
                                      PickUpManager.create_pickup()  # items/pick_up_manager.gd
                                      LevelUpManager.add_xp(resource.xp)  # systems/level_up_manager.gd
```

Releasing the key goes through `Player._gather_input_release` →
`ResourceManager2.stop_removing_resource()`. The hotbar's own stop signal only halts
the animation — driving a gather test through it leaves the timer running.

**Two incompatible state machines.** `player/states/state_machine.gd` (player) uses
`change_to(name)`, and states expose `enter()` with `fsm` injected.
`enemies/states/enemy_state_machine.gd` (enemies) uses states extending `EnemyState`
that transition by emitting `Transitioned` and expose
`enter()/update()/physics_update()/exit()`. Do not carry patterns between them.

**Enemies.** A single `enemies/enemy.gd` backs `enemies/bone_enemy.tscn` (has a
`Sprite2D`, no `AnimatedSprite2D`), `enemies/spider_enemy.tscn` (the reverse) and
`enemies/elite_enemy.tscn` (the boss island's guard, an inherited scene overriding the
bone enemy), so any sprite access must be null-checked and looked up with
`get_node_or_null`. `EnemySpawner` (`enemies/enemy_spawner.gd` — there is no
`EnemyWaveManager`, and no waves) trickles enemies in forever, floors its cadence at
`MIN_INTERVAL` and caps population at `MAX_ENEMY_CAP`; both bounds exist because the
cadence was previously unbounded.

Health and damage are `@export`s on `Enemy` and must be set **before** `add_child()` —
`_ready()` is what turns `max_health` into a `HealthManager`. Persisted enemies are
rebuilt through `EnemySpawner.scene_for_type()`; a type missing from that match falls
back to a bone enemy, which is how a saved elite would silently come back a skeleton.

**Islands.** `world/island_manager.gd` draws three pregenerated islands — forest, ore and
a boss arena — at fixed distances from the home island on a ring inside its maximum
radius (`LandManager.radius_for(MAX_PARCELS)`, currently 34). There is no boat and no
bridge: they are reached by buying land until the home coastline grows out to meet them.

Two things about that are not obvious and are easy to undo:

- The *distance* is fixed but the *angle* is chosen at generation. `land_cells_for_radius`
  thresholds noise at the default 0.01 frequency, so across ±34 tiles the field is sampled
  over ±0.34 — a smooth gradient, not an archipelago, and the maxed home island is
  routinely a lopsided crescent. A hardcoded angle strands an island for a good fraction
  of seeds. Islands claim directions furthest-first, and anything still unreachable gets a
  carved isthmus.
- Placement anchors to `IslandManager.main_body()`, not to the raw land set. Thresholding
  leaves detached islets, and an isthmus anchored to one joins the island to a rock in the
  sea. This stranded 6% of seeds and is invisible in any single playthrough —
  `test/unit/test_island_manager.gd` sweeps 200 seeds, which is the only reason it
  surfaced. Do not judge island placement from one run.

Each island is a `LandRegion` (`world/land_region.gd`) with its own spawn-weight override
and `ambient_resources` / `ambient_enemies` flags. Regions are what stop the global
respawn timer eroding a themed island back into a generic one, and a region that opts out
of ambient spawning is also excluded from the ceilings those systems scale against —
otherwise the boss arena's grass buys extra enemies for the mainland. `region_for_cell`
resolves islands before home, so an island absorbed by the growing mainland keeps its
identity. A region states its cells outright rather than using its radius: an isthmus
trails well outside the disc.

**`LandRegion.connected` gates enemies, and only enemies.** An island is stocked with
resources at world generation and stays stocked by the respawn timer whether or not the
player can walk to it — that is what makes the ore island across the water read as an ore
island and worth saving the parcels up for. What waits for the coastline to arrive is the
ambient enemies and the boss, so unreachable ground is never threatening ground. The two
halves are one word apart at every call site (`accepts_ambient_resources` vs
`accepts_ambient_enemies`) and `test/unit/test_island_gating.gd` asserts the split as a
transition, precisely because a refactor that reunites them reads as a tidy-up.

**Growing the island outside a purchase goes through `LandManager.grant_parcels()`.**
`land_purchased` is what stocks the newly revealed mainland and opens any island the
coastline now reaches (`main.gd:_on_land_purchased`), and `parcels_bought` / `radius` /
`_expand()` are merely what the node *persists*. The devtools demo builder wrote those
three directly and skipped the signal, so `build_demo_world` produced a radius-34 island
still carrying the starting island's 28 nodes, ringed by three walkable islands nobody had
opened — for long enough to be baked into two committed fixtures (`gather-3m9`). If you
need land without charging for it, call `grant_parcels`; do not re-derive it.

**The boss ends the run, and the run has a score** (`gather-1zv`). `Systems/RunStats`
(`systems/run_stats.gd`) is the model and `ui/run_summary_ui.gd` is the card — the same
model/view split again. `IslandManager.boss_killed` is the hook; `RunStats.end_run()` freezes the
score and emits it. Before this, killing the boss changed nothing and the world carried on
identically forever, so there was nothing to be good at.

- **RunStats owns only what nothing else counts** — kills, nodes gathered, deaths, time — and
  reads level, gold, land, raids and skills from their owners when the card is built. A counter
  here shadowing `LevelUpManager.level` would be a second copy of a fact, and it *would* diverge:
  a load restores theirs and would have to remember to restore this one too.
- **Three fields are the deliberate exception and are frozen at `end_run`**: day, level and gold.
  The player may choose KEEP PLAYING and earn another thousand gold, and a card rebuilt from live
  values afterwards would quietly rewrite what the run scored.
- **`end_run` is idempotent, and `loadObject` deliberately does not emit `run_ended`.** Loading a
  finished run must not throw the epitaph in the player's face; what they asked for by loading is
  the world. The restored flag is what stops the boss ending the run a second time.
- **`Enemy._on_died` records the kill BEFORE its two awaits**, and that ordering is load-bearing.
  The method suspends for 0.2s of particles, so anything after the first `await` runs after every
  other listener on the same `died` signal has finished — including the one that ends the run and
  builds the card. Recorded further down, the boss's own death showed on the card as
  "Enemies slain: 0".
- **NEW RUN is `reload_current_scene()`**, which is a decision rather than a shortcut: every save
  entry is keyed on `get_path()` and nothing anywhere unwinds world generation. Reloading is the
  only path guaranteed to produce what a fresh boot produces, because it is one. It asks twice
  before acting, and Escape / the X / the backdrop all mean KEEP PLAYING — the destructive option
  is never on a route taken by reflex.

The devtools verbs are `run_summary` (the model's tally *and* whether the card is open, for the
reason `world_clock` reads its tints back), `end_run`, and `kill_enemy` — which exists because
`clear-nodes --group Enemy` is not a death: `queue_free()` skips `HealthManager.died`, so nothing
drops, no xp is paid and the boss chain never fires. `kill_enemy --args '{"type":"Elite"}'` drives
`take_damage` instead, so a test of the ending exercises the ending.

**The quest board asks the player for things** (`gather-dj2`). `systems/quest_board.gd` is the
registry (built imperatively like `SkillTree`), `Systems/QuestLog` owns claiming and persistence,
`ui/quest_ui.gd` is the panel on `J` / the QUESTS button. Nothing in the game had ever asked the
player for anything, so a new player had no idea what it wanted from them and an experienced one
had no short-term goal between the long ones.

**Every quest is a question about state something else already owns, and that is what keeps the
whole feature small.** A quest is not accepted, subscribes to nothing, and accumulates no counter
— its progress is derived on every read from the inventory, `RunStats.enemies_killed`,
`RaidDirector.raids_cleared`, `WorldClock.day`, `LevelUpManager.level` or
`LandManager.parcels_bought`. So `QuestLog` persists exactly one thing, the set of claimed ids,
and there is no per-quest progress to save, migrate or lose. A per-quest counter fed by a signal
is the same shape as the raid's "how many raiders are left" problem: right until the first
quicksave, silently wrong after. It also means a quest added later works retroactively, which
would otherwise take a migration.

Two smaller rules: **rewards are coins and xp only**, never recipe or resource unlocks — an
unlock must be applied exactly once and never on load (`Recipes` and `ResourceManager2` persist
their own lists), and coins carry no such rule. And **a `HAVE` quest spends the items, so its
button says HAND IN rather than CLAIM** before it is pressed; the spend happens *before* the
quest is marked claimed, or a failed spend leaves it done and the items still in the bag.

**The toolbar row is an `HFlowContainer` now**, because the quest button was the fifth. It used
to be an `HBoxContainer` anchored top-right growing leftwards, so an over-wide row neither
clipped nor wrapped — the leftmost button ended up off the edge, reachable by nothing and
announced by nothing. Four buttons cleared a 390px portrait phone by about two pixels, which was
a coincidence rather than a budget. It cannot be fixed by narrowing the buttons either: what
sets a Button's minimum width is its *text* plus `style_button`'s margins, and the widest face in
the game is `"SKILLS +99  [K]"`. `occupied_top_height()` measures the buttons as well as the
container, because `HFlowContainer.get_combined_minimum_size()` is width-dependent and answers
for whatever width it had when asked — the one-line height, for a strip about to wrap.

**A panel needs a button in TWO tables, and the second one is silent when you forget it.**
`hud_toolbar.gd` hides its whole strip the moment `DisplayServer` reports a touchscreen, so
`ui/mobile_controls.gd`'s `BUTTON_SPECS` is the *only* route into a panel on a phone — and its
`MENU_ACTIONS` list is what keeps that button alive while the player is dead or mid-respawn. The
quest board shipped in the toolbar alone: a key, a desktop button, and no way into the board at
all on the device the web build is played on. Nothing errored, no button looked missing, and
every test passed. `test_mobile_controls.gd` now walks `HudToolbar.BUTTON_SPECS` and asserts each
action is reachable from the overlay and present in `MENU_ACTIONS`, so the next one added to one
table cannot go missing from the other in silence. The faces differ on purpose (`QUESTS  [J]` on
the strip, a square `QUEST` on the overlay) — the overlay's buttons are sized from the screen's
shortest edge, so the label is fitted to the button.

Devtools: `quest_state` (every offered quest with live progress, plus whether the panel is open)
and `claim_quest`, which goes through the real `claim()` so the spend, the payout and the signals
all happen — and reports *why* a refusal happened, since "already claimed", "not complete" and
"not offered yet" are three different answers.

**Saving.** Nodes add themselves to the `SaveLoad` group (`systems/save_load.gd`) and implement
`saveObject() -> Dictionary` / `loadObject(dict)`; entries are JSON-stringified
individually. Bound to `[` (save) and `]` (load).

**Every save entry is keyed on `get_path()`, so renaming or moving a node in
`main.tscn` invalidates part of every save written before it.** `_load()` resolves that
absolute path with `has_node()`; a path that no longer exists used to fall through in
total silence, dropping that node's entire state. The symptom is not an error — it is a
player who loads back at the origin with an empty inventory and no levels.

Two things guard this now, and both must be maintained:

- `SaveLoad.LEGACY_PATHS` maps old paths to new. The `gather-ue3` restructure added four
  entries; **add to it in the same commit as any future rename**, never afterwards.
- An unresolvable entry now emits `push_warning("SaveLoad: no node at '%s'…")` instead of
  vanishing, so the next such mistake is visible in the log the first time it happens.

`saveFile` is gitignored, so a broken load is not something CI or a fresh clone will ever
show you — the only way to catch it is to load a save written before your change.
`test/fixtures/` holds committed saves for exactly that — see its README.
`demo_homestead_save` is the current-format one (a maxed island with a walled house, chests,
both stations, turrets and workers, all three islands open and stocked, and a furnace left
deliberately mid-smelt at 52 of 60); regenerate it with the `build_demo_world` devtools verb
rather than curating it by hand, and check `island_census` before keeping the result — island
placement is seeded and a seed can leave one island unopened even at max land (`gather-37z`).
`demo_homestead_save_v3` and `demo_homestead_save_v1` are **backward-compatibility fixtures
and must never be regenerated** — their whole value is being old. v3 is the only file left in
the pre-`stations` recipes shape; v1 predates the double-encoding removal, the metadata header
and the fidelity pass, so it is the only thing that exercises those older branches.

**Saves live in slots.** `user://saves/slot_<n>.save`, `SLOT_COUNT` of them, listed by
`SaveLoad.list_slots()` and shown by `ui/save_slot_ui.gd` (`O`, or SAVES in the toolbar and
the mobile cluster). `[` and `]` are quicksave/quickload against `current_slot`. The format
header carries `save_format_version` plus the metadata a slot row needs (`saved_at`,
`level`, `land_radius`) so the list renders without loading a save. **Bump `FORMAT_VERSION`
and add the migration in the same commit** — a version nobody branches on is worse than
none, because it looks like a promise.

### Save fidelity is a feature requirement, not a nice-to-have

**A load must return the world to exactly where it left off, including work in progress.**
The failure mode here is never a crash. It is a load that succeeds and quietly hands the
player back less than they had, which no gate detects and no error reports:

- A furnace 95% through smelting restarted that ore, because `time_left` was not saved and
  `Timer.start()` reloads from `wait_time` (`gather-9x0`).
- A worker carrying wood to a chest reloaded empty — the items were destroyed, not just
  un-animated (`gather-z3o`).
- Ground drops were rebuilt with `Vector2i`, so every item jumped toward the origin
  (`gather-d3m`).

So, when you add or change anything that holds state over time — a timer, a queue, a
carried amount, a partially-filled container, an in-flight projectile:

1. **Persist the progress, not just the configuration.** `wait_time` is how long one item
   takes and never moves; `time_left` is how far through this one you are. Saving only the
   former looks correct in a diff and loses work every load.
2. **Beware `Timer.start(t)` — it *assigns* `wait_time = t`.** Restoring a remaining time
   with it silently reschedules every later cycle to that length. Put the interval back on
   the next line.
3. **Add the key with a default, never a bare index.** Every payload read is
   `dict.get(key, default)` and every `JSON.parse` result is checked against `OK`. An
   unguarded index raises, and a raise inside `-> void` / `-> Dictionary` / untyped `load()`
   aborts the method and returns the type's default — indistinguishable from success. See
   `world/tile_scenes/bone_worker.gd:778` for the fully-guarded reference implementation,
   and note `typeof(x) == TYPE_BOOL` rather than `x == true`: comparing a String to a bool
   *raises* instead of evaluating false.
4. **Cover it in `test/unit/test_save_fidelity.gd`**, which exists to assert exactly this
   class of loss, and verify a real round-trip in a running game. The `wait_time` clobber
   above passed lint and the whole unit suite; only reading the live Timer after a load
   caught it.

Registry lookups on a load path deserve special care: `GameItems.get_item()` returns null
for an unregistered type (`item_list` is deliberately not total over `Types.Item` — the
world resources live in `items/resources.gd`), and every load path that calls it has
*already cleared* the container it is about to refill. An unguarded raise there does not
lose one slot, it empties the whole container permanently.

**DevTools extension.** `devtools_ext/commands.gd` registers project verbs —
`player_state`, `revive_player`, `damage_player`, `give_item`, `add_xp`,
`gather_stats`, `spawn_stats`, `goto_resource`, `island_census`, `world_clock`,
`set_time_of_day`, `set_weather`, `strike_lightning` — plus a status provider merged into every response. Use `goto_resource` before any gather test: gathering only
engages with a node in reach, so otherwise the test stands in empty grass and proves
nothing.

`world_clock` is the one to reach for on anything touching lighting or weather. It reports
the hour *and* reads the tint back off all three canvases (`world_tint`, `ocean_color`,
`hud_modulate`), which is the only way to tell "the clock never advanced" apart from "the
clock advanced and SkyLighting did not follow" — a `get-state` on the CanvasModulate alone
cannot. `set_time_of_day` takes `{"phase": "night"}` as well as a raw `t`, and every setter
here repaints before replying so the answer describes a world you could screenshot. The same
reply carries the lightning model — `lightning_time_left` and the `lightning_gap` range it is
rolled from — next to `flash`, the strength `SkyLighting` is drawing *right now*, read back off
the node for exactly the reason the tints are: a verb that echoed only the countdown cannot
tell "the bolt never fired" apart from "the bolt fired and the lighting never heard it", and
those two live in different files. `strike_lightning` forces a bolt immediately, at an optional
`{"distance": 0.0..1.0}` and otherwise at a rolled one, and **it starts a storm first if the
sky is clear** — lightning under clear weather is a state the game itself cannot reach, so the
verb reaches the state rather than faking one frame of it, and its message names which of the
two happened so nothing about the returned `weather` is a surprise. The status provider carries
`phase`, `weather`, `day` and `lightning_in` on every reply, because `live_enemies` above the
daytime cap is correct at 3am and a bug at noon, and a storm that is quiet reads identically to
a storm whose countdown never armed.

`island_census` is the one to reach for on anything touching land, resources or spawning.
It reports every region's tile and node counts, the per-region resource census, the boss
and its chest, and — via a flood fill — whether each island is walkable now and whether it
will be once all the land is bought. `count_land_tiles` is a single scalar that reads the
same whether the world is one landmass or four, and a screenshot only shows the ~15x8
tiles around the player, which is less than the distance to the nearest island.

## Conventions & Patterns

### File naming (in force since `gather-c7o`)

- **snake_case for every file and folder.** PascalCase is reserved for `class_name`
  declarations and for node names inside scenes.
- **A script's filename is the snake_case of its `class_name`** — `GameItemPickaxe`
  lives in `items/game_item_pickaxe.gd`, `EnemyStateMachine` in
  `enemies/states/enemy_state_machine.gd`. Scenes follow the same rule
  (`enemies/bone_enemy.tscn`). If you know the class, you know the path.
- **Deliberate exceptions, left alone because renaming a class touches every call site
  and belongs in its own change:**
  - `world/resource_manager2.gd` holds `ResourceManager2` — the trailing `2` is legacy;
    there is no `ResourceManager1`.
  - `items/game_item_wall2.gd` holds `GameItemWall2` — same, and the file was renamed to
    match the class rather than the reverse.
  - `world/tile_scenes/test_chest.gd` holds `TestChest` — despite the name this is live
    game code (the scene tile registered in the tileset), not a test.
  - `items/types.gd` holds `Types` — a deliberately generic name for the one shared
    `Types.Item` enum.
  - Two files genuinely do not match their class: `main.gd` holds `TileMapHandler`
    (pinned by `run/main_scene` and by every existing `saveFile`), and
    `inventory/slot.gd` holds `NewSlot`.

- **The root node's scene-declared groups are gone** (`gather-ue3`). `main.tscn`'s root
  used to be authored into all 18 groups in the project — `Player`, `Items`,
  `LevelUpManager`, `SoundManager`, … — so `get_first_node_in_group()` returned the
  root instead of what was asked for, and every consumer had to type-check around it.
  Nothing needed those declarations: each script adds itself to its own group in
  `_ready()`, and the root re-adds `SaveLoad` and `TileMapHandler` at `main.gd:77-78`.
  Removing them is what makes a group lookup mean what it says.

  Still iterate and type-check rather than indexing — `if node is LevelUpManager` —
  because an index encodes how many members a group happens to have today. The
  restructure proved the point: `world/tile_scenes/test_chest.gd` indexed `[1]` purely
  to skip the root, so dropping the root's groups made `[1]` out of bounds. It and
  `items/pick_up.gd` (which indexed `[0]` and had therefore been reaching the *root*,
  never the real `SoundManager`) are now type-checked lookups.
- `HealthManager` (`systems/health_manager.gd`) extends `RefCounted` and is held as a
  plain field — never add it to the tree. It previously extended `Node`, was never
  freed, and leaked one object per enemy spawned.
- Godot 4.4+ writes a `.uid` sidecar next to every script. Commit them alongside the
  script, and delete them with it.
- Only one Godot instance may run against the DevTools bridge at a time — it is a
  single command/result file pair in `user://`, so concurrent instances silently answer
  each other's commands. To test while another instance is live, copy the project to a
  scratch dir and set `use_custom_user_dir=true` in its `project.godot`.
- `run-method` passes raw JSON to `callv` with no vector coercion, so methods taking a
  `Vector2` cannot be called through it and fail quietly (`gather-6sp`). Add a project
  verb in `devtools_ext/commands.gd` instead.
- `bin/`, `*.tmp` and `saveFile` are gitignored — the exporter and editor regenerate
  them, and they were previously committed by accident.

<!-- BEGIN godot-selftest-harness -->
## Self-Test Harness (godot-selftest-harness)

This project ships a **self-test harness**: a file-based DevTools bridge (control a
running game from the CLI), headless lint + unit-test runners (no game needed), and a
diff-aware **`/verify`** pre-commit gate. It is game-agnostic; project-specific behavior
is discovered at runtime or read from the config file below.

### DEVELOPMENT RULE (REQUIRED)
After **any** gameplay, script, or scene change, run **`/verify`** before considering the
work complete — don't wait for a commit request. It runs lint + tests, launches the game
muted, and asserts your actual diff at runtime (catching errors lint/tests can't).
Headless lint and unit tests need **no running game**; run them anytime:

```bash
godot --headless --path . --script res://tools/lint_project.gd   # UID + scene + dup-id lint
godot --headless --path . --script res://tools/run_tests.gd      # unit tests (test_dir)
```

Exit codes (both): `0` pass, `1` findings, `2` **the runner couldn't run** — a `2` means you
verified nothing. Redirect to a file and read it back; the Windows Godot build often prints
nothing to the console, so a failed run looks like silent success.
Test flags (after `--`): `--filter NAME` (matches method name **or** test script filename),
`--file NAME` (one script; combines with `--filter` via AND), `--json`. A selector matching
nothing is exit `2` (`SELECTED NOTHING — …selected 0 of N discovered`), never a pass — check
the `Selected: N of M discovered` line, not just the exit code.
`UIDs: OK` covers both halves: no stale `uid=` reference **and** no `.gd` missing its
`.uid` sidecar. A script you just wrote outside the editor has none — commit the sidecar
Godot generates alongside the script.
Lint flags (after `--`): `--strict` (warnings fail), `--baseline-write PATH` /
`--baseline PATH` (split findings into `NEW` vs `PRE-EXISTING` so repo debt isn't re-triaged
by hand), `--find-orphans` (public functions called only from tests — advisory).

**Writing tests.** Alongside `_T.assert_*`, use `await _T.instantiate_ui(scene, Vector2i(w, h))`
/ `_T.free_ui(node)` for anything `Control`-shaped: headless pumps no frames, so without it
`size` stays `(0, 0)` and `@onready` vars never initialize. Test methods may `await`.
**Always read stderr**: a runtime error inside a test aborts only that method and returns
`""` for a `-> String` test — identical to a pass. `[ERR]` lines are the only signal.

### DEVTOOLS LOG (REQUIRED)
At the end of **every** response, append an entry to `log-devtools.md` (create it if
missing). Two required halves: **was using the harness worth it**, and **what was
missing from it**. If nothing was missing, write one explicit "no gaps this turn" line —
that is what makes an absent gap distinguishable from a forgotten log. The `Value:`
block is required either way. After running a skill or devtools, reflect on it's usage and suggest concrete imrpovements for it. 

```markdown
## YYYY-MM-DD — <what this response did>

- Value: **<warranted|overkill|insufficient|inconclusive>** — <one sentence of why>
  - Expected: <what you predicted runtime would reveal, written before running it>
  - Got: <what it actually told you — quote the assertion, not "it passed">
  - Cheaper: <the cheapest thing that would have given the same confidence>

- Gap: **<what was missing>** — <the command run, the output it gave, the workaround used>
  - [G-001] status: open | seen: 1 | harness: 0.7.0
  - Improvement: <the smallest change that would have closed it>
```

`warranted` = runtime produced a claim the diff could not (name it). `overkill` =
everything passed and confirmed what was already known — renames, comments, pure
refactors, anything lint alone settled. `insufficient` = it ran but never reached or
asserted what mattered (**reach decides this, not your impression**); file the gap.
`inconclusive` = aborted or too small to judge.

**`overkill` is a useful entry, not an admission.** It is also the one that goes
unwritten, because a run that passed feels like a run that helped. `Cheaper:` must name
something concrete — "reading `player.gd:40-60`", "lint alone, 4s", "nothing, this needed
the running game". "Probably still worth it" is not an answer.

The `[G-NNN]` line is required and is what makes the log answerable: ids are stable and
never reused, `status:` is `open`/`fixed`/`wontfix` (`fixed` adds `fixed-in: X.Y.Z`),
`harness:` comes from `python tools/devtools.py harness-version`. **Hitting a known gap
again bumps its `seen:` count** — don't file a second entry for it. `tools/upstream_gaps.py`
reads exactly these fields to pool open gaps into the harness repo.

Quote real output; a gap without evidence can't be acted on later. This log is the
harness's feedback channel — entries here are what get upstreamed into
`godot-selftest-harness` itself, so a gap logged here becomes a fixed feature for every
project using it. A `Stop` hook (`tools/check_devtools_log.py`, wired in
`.claude/settings.json`) prints a reminder when a session changes code without touching
the log; it is advisory, not a gate.

### THE VERIFY LEDGER
`/verify` Phase 5 appends one line per run to `.devtools/verify-runs.jsonl` — including
the clean ones, which is the point. The gaps log records what the harness couldn't do;
the ledger is the denominator it lacks.

The field worth reading is **reach**: computed by intersecting the diff against the
`script`/`scene_file` paths in a `scene-tree` snapshot, so it says whether a run actually
loaded the code it claimed to verify rather than asking the run to grade itself. A pass
on an unreached file is a statement about the diff, not the running game — report it that
way. Each row also carries the `value` verdict above, so "how often was this overkill?"
is a query. `python tools/verify_ledger.py stats` reads the history back; `reach`
computes reach alone without writing a row. Commit the ledger.

### Command cheat-sheet (`python tools/devtools.py <verb>`)
Launch first: `godot --path . --mute &` then `sleep 5 && python tools/devtools.py ping`.

| Verb | Use |
|---|---|
| `ping` / `quit` | Confirm bridge is live / shut game down cleanly |
| `scene-tree` | Discover root scene name + node paths (don't assume names). Each node carries `script` and `scene_file`, so a changed file maps to the node that runs it |
| `get-state --node PATH [--property N ...]` | Read a node's properties. **Always pass `--property`** — an unfiltered `Label` is ~120 keys. Repeatable; unknown names are reported, not dropped |
| `set-state --node PATH --property N --value V` | Set raw property (bypasses setters/signals) |
| `run-method --node PATH --method N --args "[...]"` | Call a method — preferred when a signal should fire |
| `node-bounds PATH` | Exact position/size (deterministic layout ground truth) |
| `canvas-scale --node PATH` | Accumulated canvas scale + effective texture filter — the crisp/blurry question as one read |
| `set-resolution --size W,H` | Resize the window (honest read-back; headless may clamp) |
| `ui-snapshot` / `ui-snapshot-diff` / `save-ui-baseline` | Structured UI state vs baseline |
| `validate-all` / `validate-ui` | Scene + UI layout validation (expect 0 issues) |
| `performance [--reset-baseline]` | FPS vs `fps_min`, orphan **growth** vs `orphan_growth_max` |
| `input <press\|release\|tap\|clear\|list\|sequence>` | Simulate input actions. `tap` releases on the NEXT frame and replies after the release, reporting `pressed_during`/`pressed_after` |
| `input state [ACTION ...]` | Polled pressed/strength per action (all project actions when none named) — what the game is actually seeing |
| `key NAME [--count N] [--hold-frames N]` | Raw `InputEventKey` by OS keycode name (`E`, `LEFT`, `SPACE`) — for game code reading keys directly instead of actions |
| `touch <press\|release\|drag\|clear\|list> --index N --pos X,Y` | Real `InputEventScreenTouch`/`Drag` — the only way to exercise multi-touch |
| `set-feature --touchscreen true` | Makes touch UI show itself on desktop (it hides when no touchscreen is reported). Set it **before** the scene loads. `--query` reads the flags without writing |
| `set-game-speed N` / `wait-frames N` | Speed up / advance N physics frames |
| `step-time --seconds N [--hold ACTION]` | Advance ~N game-seconds with `time_scale` pinned to 1.0. Physics exact; process tweens land ±1 frame — it does not pause and step the tree. `--hold` keeps an action pressed across the step and releases it at the end |
| `tilemap-cells --node PATH [--layer N] [--rect X,Y,W,H]` | Used cells with source/atlas ids as data (capped at 2000; pass `--rect`) — not a screenshot guess |
| `tilemap-region --node PATH --atlas X,Y [--layer N] [--source-id N]` | 4-neighbor connected components of matching cells, largest first — "is this island one landmass?" as data |
| `scripts-seen [--json]` | Every distinct script path that has entered the tree since launch; `--json` prints the full reply envelope |
| `launch [--godot PATH] [--isolated]` | Start the game detached, logs under `.devtools/`. `--isolated` prints a fresh `--session`/`--userdata` pair to use on later calls |
| `clear-nodes --group G` (or `--method`/`--class`) | Free matching nodes |
| `screenshot` | Visual check only (`sleep 0.5`–`1` after a state change) |
| `list-commands` | Discover all registered verbs (generic + project). `--offline` statically parses the scripts when no game is running |
| `logs --tail N [--category C]` | Read the game's JSONL debug log directly (no bus call; works on a hung game) |
| `harness-version` | Installed harness revision (game + client). Read it once per session — it fills the `harness:` field on every gap you log. Exits 1 on a mismatch, which means a half-refreshed install |
| `cmd <verb> --args '{...}'` | Invoke any project-registered verb |

### Add project-specific debug verbs
Register domain verbs in `res://devtools_ext/commands.gd` (loaded after generic verbs,
last-writer-wins). Each handler returns exactly `{success:bool, message:String, data:Dictionary}`.

```gdscript
func register_commands(dev: Node) -> void:
    dev.register_command("spawn_enemy", func(args): 
        return {"success": true, "message": "ok", "data": {}})
```

Reach them from the CLI via `cmd spawn_enemy --args '{"count":3}'`; discover them via
`list-commands`. Use these for setup/trigger steps the generic primitives can't express.

**Attach liveness to every reply.** Register one status provider and its Dictionary is
merged into *every* response as `status` — the fact you need on every read and never
remember to ask for separately. Without it, a session that has silently died or frozen
keeps answering with well-formed zeros, which looks exactly like a clean pass.

```gdscript
    dev.register_status_provider(func(_args):
        var p = dev.get_tree().get_first_node_in_group("player")
        return {"player": "absent"} if p == null else {"player": "dead" if p.is_dead else "alive"})
```

Pair it with verbs that can *undo* the dead state (a `revive_player` that clears the
flag and leaves the death state, or a `god_mode` toggle). Restoring a health value is
usually not enough on its own — the death flag and state machine outlive it, so the
run stays frozen and unrescuable short of a relaunch.

**A setter verb must leave the game in a state the game itself can reach.** Writing one
half of an invariant pair is a latent trap — a `set_combo` that sets the count but not
the combo window tests nothing the moment the readout starts fading on that timer.

### Gotchas
- **One command at a time.** The bus is one command file / one result file. Requests
  carry an id the game echoes, so a crossed reply now errors (`Crossed replies: …`)
  instead of silently returning another request's data — detection, not concurrency.
  For *parallel* instances give each its own bus: launch with
  `-- --devtools-session <id>` and call with `--session <id>`. `ping` then reports which
  session answered. Buses only — a shared `user://` still shares screenshots, baselines
  and the `.godot/` import cache, so add `GODOT_USERDATA` per instance to isolate fully.
- **`game not running` in ~2s** means a dead game *or* the wrong `user://` dir; the
  error can't tell them apart. Check `--userdata` before assuming a crash.
- **Assert transforms on `data.transform`, not the property dump.** Godot hides
  `position`/`scale`/`rotation` on container children, so a scale animation on a
  `VBoxContainer` child is invisible to a property read while working on screen.
- **A run that never changes is broken, not passing.** Check the `status` field.

### Config
`res://addons/godot_selftest/devtools_config.json` holds thresholds and hooks:
`fps_min`, `orphan_growth_max` (gate on this — `orphan_max: 0` is unreachable),
`safe_area_inset`, `mute`, `main_scene`, `entry_hook {node_path, method}` (advances past
a menu into the playable scene), `entry_points` (named alternates for scenes the default
hook can't reach), `test_dir`, `scan_root`, `hud_layer_name`.

### Token-aware
- Prefer `node-bounds` / `ui-snapshot` (compact, deterministic) over `screenshot`; only
  open a screenshot PNG when a genuine **visual** regression is suspected.
- `get-state` dumps ~120 keys for a `Label` — pass `--property NAME` (repeatable).
- Run `/verify` **inline**; don't wrap routine validation in subagents/workflows.
- Launch with `--mute` for automated testing.
- On Windows, probe Python by running it (`python3` may be a Store alias stub that
  exists and refuses to run).

### (Re)install
Run **`/scaffold-godot-harness`** to install or refresh the harness. Re-running it also
refreshes this very section in place (it never duplicates it).
<!-- END godot-selftest-harness -->
