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
  `UI2` CanvasLayer. Do not put full-screen menus under `Player/Camera2D/UI` —
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
camera's `4.935` zoom. Nothing may hardcode a viewport dimension:

- Screen-space UI goes in the `UI2` CanvasLayer and must be anchored to a viewport
  edge or centred, never placed at absolute pixels. `skill_tree_ui.gd` and
  `land_purchase_ui.gd` build themselves with `PRESET_FULL_RECT` + a
  `CenterContainer` and need nothing further.
- The diegetic HUD under `Player/Camera2D/UI` is world-space and gets no viewport
  rect for free, so `ui/camera_hud.gd` sizes that Control to
  `viewport_size / camera.zoom` and centres it on the camera, on `_ready` and on
  `size_changed`. **Its children must therefore use ordinary anchors** — `0` is the
  left/top screen edge, `1` the right/bottom, `0.5` the centre. `PlayerInfo` and
  `Crafting` are bare `Control`s that exist only to pin a group to a corner; anchor
  the group and leave the offsets of the things inside it alone.
- Anchors were retrofitted in `gather-6fx`. Before it every offset was hand-tuned to
  the old `1152x648` window (the HUD's left edge was literally `x = -115`, one unit
  inside `1152 / 4.935 / 2`), and every element drifted toward the middle of the
  screen the moment the window grew. If you see a raw `-115` or a `470` in a layout,
  it is a leftover of that and is a bug at any other size.

**Tilemap layers** (`main.gd`): `0` ground/terrain, `1` objects (resources, walls,
buildings), `2` floors, `3` highlight overlay. A tile is mapped back to its registry
entry by matching `atlas_location` + `tile_source_id`, so those coordinates are
effectively the persistence key — changing an atlas position silently changes save
compatibility. Resources flagged `is_scene_tile` are instead instanced as
`GameSceneResource` children of the TileMap, so any code that enumerates resources must
handle both representations (`main.gd:resource_node_census` does).

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

**Saving.** Nodes add themselves to the `SaveLoad` group (`systems/save_load.gd`) and implement
`saveObject() -> Dictionary` / `loadObject(dict)`; entries are JSON-stringified
individually. Bound to `[` (save) and `]` (load).

**DevTools extension.** `devtools_ext/commands.gd` registers project verbs —
`player_state`, `revive_player`, `damage_player`, `give_item`, `add_xp`,
`gather_stats`, `spawn_stats`, `goto_resource`, `island_census` — plus a status provider
merged into every response. Use `goto_resource` before any gather test: gathering only
engages with a node in reach, so otherwise the test stands in empty grass and proves
nothing.

`island_census` is the one to reach for on anything touching land, resources or spawning.
It reports every region's tile and node counts, the per-region resource census, the boss
and its chest, and — via a flood fill — whether each island is walkable now and whether it
will be once all the land is bought. `count_land_tiles` is a single scalar that reads the
same whether the world is one landmass or four, and a screenshot only shows the ~24x14
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

- **`main.tscn`'s root node belongs to every group in the project** (`Player`, `Items`,
  `LevelUpManager`, `SoundManager`, …). `get_first_node_in_group()` therefore returns
  the root, not what you asked for. Always iterate `get_nodes_in_group()` and
  type-check (`if node is LevelUpManager`). `enemies/enemy.gd` does this correctly;
  `crafting/crafting_station.gd` instead indexes `[1]` to skip the root, which breaks
  as soon as another node joins that group.
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
block is required either way.

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
`harness:` comes from `python3 tools/devtools.py harness-version`. **Hitting a known gap
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
is a query. `python3 tools/verify_ledger.py stats` reads the history back; `reach`
computes reach alone without writing a row. Commit the ledger.

### Command cheat-sheet (`python3 tools/devtools.py <verb>`)
Launch first: `godot --path . --mute &` then `sleep 5 && python3 tools/devtools.py ping`.

| Verb | Use |
|---|---|
| `ping` / `quit` | Confirm bridge is live / shut game down cleanly |
| `scene-tree` | Discover root scene name + node paths (don't assume names). Each node carries `script` and `scene_file`, so a changed file maps to the node that runs it |
| `get-state --node PATH [--property N ...]` | Read a node's properties. **Always pass `--property`** — an unfiltered `Label` is ~120 keys. Repeatable; unknown names are reported, not dropped |
| `set-state --node PATH --property N --value V` | Set raw property (bypasses setters/signals) |
| `run-method --node PATH --method N --args "[...]"` | Call a method — preferred when a signal should fire |
| `node-bounds PATH` | Exact position/size (deterministic layout ground truth) |
| `ui-snapshot` / `ui-snapshot-diff` / `save-ui-baseline` | Structured UI state vs baseline |
| `validate-all` / `validate-ui` | Scene + UI layout validation (expect 0 issues) |
| `performance [--reset-baseline]` | FPS vs `fps_min`, orphan **growth** vs `orphan_growth_max` |
| `input <press\|release\|tap\|clear\|list\|sequence>` | Simulate input actions |
| `touch <press\|release\|drag\|clear\|list> --index N --pos X,Y` | Real `InputEventScreenTouch`/`Drag` — the only way to exercise multi-touch |
| `set-feature --touchscreen true` | Makes touch UI show itself on desktop (it hides when no touchscreen is reported). Set it **before** the scene loads |
| `set-game-speed N` / `wait-frames N` | Speed up / advance N physics frames |
| `step-time --seconds N` | Advance ~N game-seconds with `time_scale` pinned to 1.0. Physics exact; process tweens land ±1 frame — it does not pause and step the tree |
| `clear-nodes --group G` (or `--method`/`--class`) | Free matching nodes |
| `screenshot` | Visual check only (`sleep 0.5`–`1` after a state change) |
| `list-commands` | Discover all registered verbs (generic + project) |
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
