# DemoDirector helper vocabulary

Everything below lives in `devtools_ext/demo_director.gd`. Read this when writing or
editing a beat; the file's own doc comments are the authority and go further.

## Contents

- [Movement and position](#movement-and-position)
- [Input](#input)
- [Inventory and hotbar](#inventory-and-hotbar)
- [Waiting and reporting](#waiting-and-reporting)
- [World pokes](#world-pokes)
- [Staging](#staging)
- [Framing constants](#framing-constants)
- [Anatomy of the four existing clips](#anatomy-of-the-four-existing-clips)

## Movement and position

| Helper | What it does, and the trap it exists for |
|---|---|
| `_walk_to(handler, player, cell, timeout=8.0) -> bool` | Holds real movement actions to reach a cell — **horizontal leg first**, because facing follows the last *horizontal* step (`move_up`/`move_down` leave `flip_h` alone). Polls position rather than counting frames, since a wall changes how far a held key travels. Snaps to the exact target at the end to kill the sub-pixel overshoot that accumulates across several walks into a set visibly off its grid. |
| `_aim(handler, player, cell)` | Turns the player to face a cell and puts him back where he stood. Needed because facing is `flip_h = velocity.x < 0` sampled every physics frame, so *any* sideways motion after a walk rewrites it — including `move_and_slide` pushing the player off a tile he just built beside himself. Only works left/right; a placeable never goes up or down. |
| `_chase(player, target, timeout) -> bool` | Walks toward a moving `Enemy`, re-choosing direction **every frame**, with separate deadbands per axis (`CHASE_BAND_X` 4px, `CHASE_BAND_Y` 5px — the swing is not symmetric, and one tight band makes the player jitter between two opposing presses and never commit to a facing). Use this instead of a single held direction whenever the target can move. |
| `_close_in(player, target)` | Leans into a target until inside `REVEAL_REACH` (13px). Exists because `InventoryInterface` force-closes a container whose owner is >15px away and a tile is 16px — standing on the adjacent tile centre is one pixel too far. |

## Input

| Helper | Notes |
|---|---|
| `_press(action)` / `_release(action)` | Drives **both** paths: `Input.action_press` for polled state (movement) and a dispatched `InputEventAction` for the event path (the use press). Tracked in `_held` so `_release_all()` can clean up. |
| `_hold(action, seconds)` | Press, wait, release. |
| `_use(seconds = 0.3)` | One hotbar use press, **held**. The hold is load-bearing: releasing `gather` calls `animation_player.stop()`, so a two-frame tap kills the 0.2s net swing ~15 ms in, before the net sweeps anywhere. Nothing reports it — `stop()` emits no `animation_finished`. |
| `_tap_key_for(action)` | A raw `InputEventKey` taken from the InputMap. Required for anything the game reads with `Input.is_action_just_pressed` (the interact key), because an `action_press` from a coroutine already resumed inside a frame stamps a frame the reader has finished with. Silent failure otherwise. |
| `_release_all()` | Call before `_running = false`, always. |

## Inventory and hotbar

| Helper | Notes |
|---|---|
| `_select(type) -> bool` | Selects the hotbar slot holding an item type, moving the stack into the hotbar if the inventory put it past slot 6. False when the player has none — always branch on it and `_note()`. |
| `_has(player, type) -> bool` | Count > 0. |
| `_stock(player)` / `_stock_worker_kit(player)` | Clear slots and deal the clip's kit. `_stock` empties all six; the worker variant empties only four so the save's own wood and stone stay visible in the last slots (a player standing beside a full chest holding nothing reads as the chest's contents having come out of his pockets). |

## Waiting and reporting

| Helper | Notes |
|---|---|
| `_wait(seconds)` | Scene-tree timer. Prefer seconds over frame counts — the game runs uncapped in a dry run and at fixed fps under the movie writer, so "twelve frames" is two different durations. |
| `_frames(n)` | For settling one or two frames after a write, not for pacing. |
| `_until(condition, timeout) -> bool` | Polls a `Callable` once a frame, timed off the frame clock. Returns whether it held. |
| `_mark(label)` | Records `Engine.get_frames_drawn()` into `marks`. `show_start` and `show_end` are what `capture_clip.py` trims on; the per-beat marks are for diagnosis. |
| `_note(text)` | Records a degradation and pushes a warning, then execution continues. **This array is the recording gate.** |
| `_fail(message)` | Notes, sets `beat = "failed"`, stops, releases input. For staging that could not proceed at all. |

## World pokes

`_spawn_enemy(handler, cell)` (skips open water — the sea is the *absence* of a ground
tile, and a spawn there bobs about unreachable with nothing reporting it),
`_telegraph_wave(handler, cells)` (shows the spawner's `X` first, so a wave arrives the way
the game announces one), `_place_turret`, `_plant(handler, cell, type)`,
`_freeze_ambient()` (pauses the spawner and the resource respawn timer — an ambient
skeleton strolling into a beat is a reshoot), `_clear_enemies()`, `_set_zoom(player, zoom)`
(also resizes the diegetic HUD, which only sizes itself on `_ready` and `size_changed`),
`_hide_fps()`, `_load_slot(n)`.

Lookups: `_player()`, `_handler()`, `_spawner()`, `_hot_bar()`, `_clock()`, `_sky()`,
`_worker_at(handler, cell)`, `_chest_at(handler, cell)`, `_turrets()`, `_nearest_turret()`.
All are group scans with a type check, never an index — the group's membership is not
something to encode.

## Staging

Each clip has its own `_stage_*` that: finds a spot by *scoring* candidates, freezes
ambient systems, clears enemies, positions the player, sets zoom, hides the FPS label,
stocks the kit, and returns the anchor cell or `null`.

The scoring keys are the interesting part and are worth copying:

- `_find_arena` ranks on land under the battle rect, **then land across the visible
  frame**, then nearness. Without the middle key every all-land candidate tied and the
  nearest won — which put a coastline diagonally through the first take with a third of
  the frame open sea. The fight was fine; the shot was wrong, and no assertion about the
  fight could have said so.
- `_find_pocket` (workers) ranks on how many *built* cells the opening frame would
  contain, so the set lands against the house rather than out in a field — without
  hardcoding coordinates that do not survive the save being regenerated.
- `_find_coast_stand` (weather) ranks on how close the frame's sea fraction is to
  `WEATHER_SEA_TARGET` (0.34) and **refuses below `WEATHER_SEA_MIN`** (0.10), because
  without water in frame the clip is of a screen getting darker — which is what the
  day/night feature looks like when it is broken.

## Framing constants

| Constant | Value | Meaning |
|---|---|---|
| `CLOSE_ZOOM` | `(8, 8)` | The shipped camera zoom. Shows about ±7 x ±4 tiles. Pulling back shrinks the 16px art and the bullets to specks; the engagement radius, not the object count, sets the shot. |
| `VIEW_HALF` | `(7, 4)` | Half-extents of what the camera actually shows. Used for framing scores. |
| `BATTLE_HALF` | `(4, 3)` | What must be dry land. Deliberately smaller than `ARENA_HALF` — scoring the clearing instead of the battle asked for a 13x9 solid patch on an island only ~20x13 across, and the clip refused worlds it could have filmed fine. |
| `ARENA_HALF` | `(6, 4)` | What gets cleared of trees and rocks. Wide enough for the action, tight enough that the untouched treeline stays in frame — a fully cleared field reads as a test harness. |
| `ARENA_SEARCH` | `12` | How far staging will walk looking for a spot. |
| `NET_REACH` | `13.0` | Swing geometry, not preference. The first cut swung at 22 and missed every time, silently — a swing that connects with nothing is animated exactly like one that does. |
| `AGGRO_RANGE` | `30.0` | `EnemyIdle` only hands over to `EnemyFollow` inside this, so an enemy spawned further out just wanders. Walk the player to it. |

## Anatomy of the four existing clips

| Clip | World | Subject | The one thing that shaped it |
|---|---|---|---|
| `turrets` | fresh | Place a turret, net a skeleton, load the skull, a bank of them holds a wave. | The engagement radius (40px LineOfSight) sets the whole shot; the second bank is written straight to the tilemap because repeating the placement beat five times is not footage. |
| `workers` | save slot 3 | Chest + two worker bases, skulls in, a full errand each, chest opened to show the haul. | Shot in a finished base because automation is a thing you build once you have one — so staging *checks* for a clear pocket instead of bulldozing one. Existing save workers are parked (path cleared and state reset, not just timer paused, or they swing at nothing all clip). |
| `weather` | fresh | One held coastal shot: afternoon to dusk to night, lantern, storm, three bolts, dawn. | Staged on a coastline because the sea is the checkable one of the three canvas writes. Sweeps aim at the twilights; the flat DAY and NIGHT stretches are skipped or crossed fast. |
| `charged` | fresh | A grey skeleton in a night storm, a bolt onto it, the blue one that gets up, the net, and its skull outshooting the ordinary turret beside it. | A rate can't be read off one stream of bullets, so the last beat is **one frame holding both turrets** with their own lanes — which set every offset in the clip. |
