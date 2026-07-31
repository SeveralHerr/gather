# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
cascading `Could not find type "X"` errors through `main.gd`, `Player.gd` and
`Items.gd`, and the game fails to boot — all of which look like your new code is
broken when the cache is the only problem.

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
Autoloads (see `[autoload]` in `project.godot`): `GameItems` (`Items/Items.gd`),
`GameSoundManager`, `Recipes`, `PlayerManager`, `PickUpManager`, `DevTools`.

**One ID space.** `Types.Item` (`Items/ItemTypes.gd`) is a single enum covering
inventory items, world resources and placeable tiles. Everything keys off it.

**Item model.** `GameItem` is the base; behavior is added by overriding
`use()` / `stop()` / `can_use()`. Subclasses live in scattered files whose names do not
match their classes — notably `GameItemPickaxe` is in `Inventory/ItemDataEquip.gd` and
`GameItemPlaceable` is in `Items/GameItemCraftingStation.gd`. Registries are built
imperatively in `_ready()`: `Items.gd` populates `item_list`, and `Resources.gd`
populates `resources` then applies `Resources.TUNING`.

**Where gameplay tuning lives** — these are the files to edit for balance, not the
logic: `Resources.TUNING` (xp, yield range, spawn weight, secondary drops per
resource), the `Items.gd` constructor calls (pickaxe gather time and bonus yield,
consumable heal values), and `Crafting/Recipes.gd` (costs, and which recipes are
unlocked by which `LevelUpManager` upgrade).

**Tilemap layers** (`main.gd`): `0` ground/terrain, `1` objects (resources, walls,
buildings), `2` floors, `3` highlight overlay. A tile is mapped back to its registry
entry by matching `atlas_location` + `tile_source_id`, so those coordinates are
effectively the persistence key — changing an atlas position silently changes save
compatibility. Resources flagged `is_scene_tile` are instead instanced as
`GameSceneResource` children of the TileMap, so any code that enumerates resources must
handle both representations (`main.gd:resource_node_census` does).

**Gather loop**, the most-touched path and the one that spans the most files:

```
InputManager (signals) -> Player -> HotBarInventory -> InventoryData.use_slot_data
  -> SlotData.item.use() -> Player StateMachine -> PlayerGather
  -> ResourceManager2.start_removing_resource(pickaxe)   # hold_timer.wait_time = pickaxe.power
  -> on timeout: remove_resource() -> rolls yield, PickUpManager.create_pickup(),
                                      LevelUpManager.add_xp(resource.xp)
```

Releasing the key goes through `Player._gather_input_release` →
`ResourceManager2.stop_removing_resource()`. The hotbar's own stop signal only halts
the animation — driving a gather test through it leaves the timer running.

**Two incompatible state machines.** `StateMachine.gd` (player) uses
`change_to(name)`, and states expose `enter()` with `fsm` injected. `EnemyStateMachine.gd`
(enemies) uses states extending `EnemyState` that transition by emitting `Transitioned`
and expose `enter()/update()/physics_update()/exit()`. Do not carry patterns between them.

**Enemies.** A single `Enemies/Enemy.gd` backs both `BoneEnemy.tscn` (has a `Sprite2D`,
no `AnimatedSprite2D`) and `SpiderEnemy.tscn` (the reverse), so any sprite access must
be null-checked and looked up with `get_node_or_null`. `EnemyWaveManager` ramps its
spawn timer toward `MIN_SPAWN_INTERVAL` and caps population at `MAX_LIVE_ENEMIES`;
both bounds exist because the ramp was previously unbounded.

**Saving.** Nodes add themselves to the `SaveLoad` group and implement
`saveObject() -> Dictionary` / `loadObject(dict)`; entries are JSON-stringified
individually. Bound to `[` (save) and `]` (load).

**DevTools extension.** `devtools_ext/commands.gd` registers project verbs —
`player_state`, `revive_player`, `damage_player`, `give_item`, `add_xp`,
`gather_stats`, `wave_stats`, `goto_resource` — plus a status provider merged into
every response. Use `goto_resource` before any gather test: gathering only engages
with a node in reach, so otherwise the test stands in empty grass and proves nothing.

## Conventions & Patterns

- **`main.tscn`'s root node belongs to every group in the project** (`Player`, `Items`,
  `LevelUpManager`, `SoundManager`, …). `get_first_node_in_group()` therefore returns
  the root, not what you asked for. Always iterate `get_nodes_in_group()` and
  type-check (`if node is LevelUpManager`). `Enemy.gd` does this correctly;
  `Crafting/CraftingStation.gd` instead indexes `[1]` to skip the root, which breaks
  as soon as another node joins that group.
- `HealthManager` extends `RefCounted` and is held as a plain field — never add it to
  the tree. It previously extended `Node`, was never freed, and leaked one object per
  enemy spawned.
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
godot --headless --path . --script res://tools/lint_project.gd   # UID + scene lint
godot --headless --path . --script res://tools/run_tests.gd      # unit tests (test_dir)
```

### Command cheat-sheet (`python3 tools/devtools.py <verb>`)
Launch first: `godot --path . --mute &` then `sleep 5 && python3 tools/devtools.py ping`.

| Verb | Use |
|---|---|
| `ping` / `quit` | Confirm bridge is live / shut game down cleanly |
| `scene-tree` | Discover root scene name + node paths (don't assume names) |
| `get-state --node PATH` | Read a node's properties (verbose — prefer one property) |
| `set-state --node PATH --property N --value V` | Set raw property (bypasses setters/signals) |
| `run-method --node PATH --method N --args "[...]"` | Call a method — preferred when a signal should fire |
| `node-bounds PATH` | Exact position/size (deterministic layout ground truth) |
| `ui-snapshot` / `ui-snapshot-diff` / `save-ui-baseline` | Structured UI state vs baseline |
| `validate-all` / `validate-ui` | Scene + UI layout validation (expect 0 issues) |
| `performance` | FPS vs `fps_min`, orphan nodes vs `orphan_max` |
| `input <press\|release\|tap\|clear\|list\|sequence>` | Simulate input actions |
| `set-game-speed N` / `wait-frames N` | Speed up / step time deterministically |
| `clear-nodes --group G` (or `--method`/`--class`) | Free matching nodes |
| `screenshot` | Visual check only (`sleep 0.5`–`1` after a state change) |
| `list-commands` | Discover all registered verbs (generic + project) |
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

### Config
`res://addons/godot_selftest/devtools_config.json` holds thresholds and hooks:
`fps_min`, `orphan_max`, `mute`, `main_scene`, `entry_hook {node_path, method}` (advances
past a menu into the playable scene), `test_dir`, `scan_root`, `hud_layer_name`.

### Token-aware
- Prefer `node-bounds` / `ui-snapshot` (compact, deterministic) over `screenshot`; only
  open a screenshot PNG when a genuine **visual** regression is suspected.
- `get-state` dumps all node properties — read the specific property you need.
- Run `/verify` **inline**; don't wrap routine validation in subagents/workflows.
- Launch with `--mute` for automated testing.

### (Re)install
Run **`/scaffold-godot-harness`** to install or refresh the harness. Re-running it also
refreshes this very section in place (it never duplicates it).
<!-- END godot-selftest-harness -->
