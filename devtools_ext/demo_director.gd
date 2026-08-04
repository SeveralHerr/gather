extends RefCounted
class_name DemoDirector

## Scripted, self-driving gameplay choreography for the README capture clips.
##
## The clips are recorded with Godot's movie writer (`--write-movie`), which advances game
## time by exactly one frame per *rendered* frame. Anything driven from the CLI would
## therefore bake every file-bus round-trip into the footage as dead air of a length that
## varies from take to take, so the entire performance runs inside the game as one
## coroutine and the CLI only starts it and asks afterwards where the interesting frames
## were.
##
## `marks` is what makes the trim exact. Under the movie writer `Engine.get_frames_drawn()`
## *is* the output frame number, so recording it at the start and end of the performance
## lets ffmpeg cut on a frame the director chose rather than on a stopwatch that has to
## guess how long world generation took this time.
##
## Nothing here reaches past the game's own entry points. The player is walked by holding
## real input actions, the turret is placed by the hotbar's own use press, and wave enemies
## arrive behind the spawner's `X` telegraph tile — so the clip shows the game rather than a
## puppet show that merely resembles it. The two deliberate exceptions are marked at their
## call sites: `player.invulnerable` (the demo must not end with a respawn) and the second
## bank of turrets, which is written straight onto the tilemap because the placement beat
## has already been shown and repeating it five times is not footage anyone wants.

const BONE_ENEMY := preload("res://enemies/bone_enemy.tscn")

## The clip never changes zoom, and that is a finding rather than a simplification. A
## turret's LineOfSight is a 40px circle and a bullet crosses it in about a second, so the
## whole battle happens inside roughly nine tiles by seven — smaller than the 15x8.4 tiles
## the camera's shipped zoom of 8 already shows. Pulling back to fit "a bunch of turrets"
## framed mostly ocean (the starting island is only about 20x13 tiles) and shrank the
## bullets to specks. The engagement radius, not the turret count, is what sets the shot.
const CLOSE_ZOOM := Vector2(8, 8)

## Half-extents, in tiles, of the patch cleared of trees and rocks before the show. Wide
## enough for the turret ring and the lanes the wave arrives down, tight enough that the
## untouched treeline stays in frame — a fully cleared field reads as a test harness rather
## than as the game.
const ARENA_HALF := Vector2i(6, 4)

## Where the wave beat puts things, as offsets in tiles from the player.
##
## Every number here is set by the 40px turret LineOfSight: each enemy cell is within 2.3
## tiles of a turret cell, which is the only reason the turrets engage at all. Widen the
## ring and the skeletons stand around unshot. The vertical spread is capped at 3 because
## the camera only shows ±4.2 tiles at zoom 8 — a lane at y=±5 is off the bottom of frame.
const TURRET_RING := [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]
const WAVE_ONE := [Vector2i(-4, -1), Vector2i(4, -1), Vector2i(-4, 1), Vector2i(4, 1)]
const WAVE_TWO := [Vector2i(-4, -3), Vector2i(4, -3), Vector2i(-4, 3), Vector2i(4, 3)]

## Half-extents of the rectangle that actually has to be dry land: the turret ring, the two
## wave lanes and the ground between them, and nothing else.
##
## Deliberately smaller than ARENA_HALF, and the two started out as one constant. Scoring
## the *clearing* instead of the *battle* asked a 13x9 patch of an island only about 20x13
## across to be solid ground, which no seed reliably has, so the clip refused to start on
## worlds it could have filmed perfectly well. Coastline in shot is fine; coastline under a
## turret is not.
const BATTLE_HALF := Vector2i(4, 3)

## Half-extents of what the camera actually shows at zoom 8 (1920x1080 over a 16px tile),
## used only to break ties between candidate centres. Land under the turrets is a hard
## requirement; land across the rest of the frame is what stops the clip being shot with a
## coastline through the middle of it and half the picture open sea.
const VIEW_HALF := Vector2i(7, 4)

## How far out the arena search is willing to walk from wherever the player spawned, in
## tiles, looking for a battle rectangle that is entirely land.
const ARENA_SEARCH := 12

## Seconds the spawner shows its `X` before an enemy appears. Copied from
## EnemySpawner.TELEGRAPH_SECONDS rather than read from it: the constant is the *game's*
## pacing and this is the *clip's*, and the wave wants a shorter tell than a 21-second
## ambient cycle does.
const TELEGRAPH := 1.0

## Beat lengths in seconds. Everything the clip's pacing depends on is here so it can be
## retimed without reading the choreography.
const BEAT := {
	"settle": 0.8,
	"before_place": 0.5,
	"after_place": 0.9,
	"after_select": 0.45,
	"before_swing": 0.35,
	"after_capture": 1.0,
	"after_load": 1.2,
	"between_waves": 4.0,
	"wave_hold": 6.0,
	"tail": 0.8,
}

## How close the player has to be before the net swings, and it is reach rather than
## preference. `Net_Right` sweeps the area from (0,-3.6) to (5.2,2.4) over 0.2s and its
## circle is 4.7 across, so the far edge of the swing is about 15px from the player — with
## the skeleton's own 11x5 body that leaves a capture window of roughly 10 to 15 pixels.
## The first cut swung at 22 and missed every time, silently: a swing that connects with
## nothing is animated exactly like one that does.
const NET_REACH := 13.0

## Long enough for the 0.2s swing to play out before the catch is judged. Counted in
## seconds rather than frames on purpose — the game runs uncapped here and at 60fps under
## the movie writer, so "twelve frames" is two different durations.
const SWING_SETTLE := 0.35

## EnemyIdle only hands over to EnemyFollow inside 30px, so an enemy spawned any further
## out than this simply wanders. The net beat therefore walks the *player* to the skeleton
## rather than waiting for a skeleton that is never coming.
const AGGRO_RANGE := 30.0

var _dev: Node
var _running := false
var _clip := ""
var _beat := "idle"
var _marks: Dictionary = {}
var _notes: Array = []
var _held: Array = []


func _init(dev: Node) -> void:
	_dev = dev


# --- public surface -------------------------------------------------------------------

func is_running() -> bool:
	return _running


func state() -> Dictionary:
	return {
		"running": _running,
		"clip": _clip,
		"beat": _beat,
		"marks": _marks.duplicate(),
		"notes": _notes.duplicate(),
		"frames_drawn": Engine.get_frames_drawn(),
	}


func clips() -> Array:
	return ["turrets", "workers", "weather"]


## Starts a clip. Returns immediately — the performance continues as a coroutine, and the
## caller polls `state()` or simply waits out the clip's own running time.
func start(clip_name: String) -> Dictionary:
	if _running:
		return {"success": false, "message": "clip '%s' is already running" % _clip, "data": state()}
	if clip_name not in clips():
		return {"success": false, "message": "unknown clip '%s'" % clip_name, "data": {"clips": clips()}}

	_clip = clip_name
	_beat = "starting"
	_marks = {}
	_notes = []
	_running = true

	match clip_name:
		"workers":
			_run_worker_clip()
		"weather":
			_run_weather_clip()
		_:
			_run_turret_clip()
	return {"success": true, "message": "clip '%s' started" % clip_name, "data": state()}


# --- the turret clip ------------------------------------------------------------------

func _run_turret_clip() -> void:
	var handler := _handler()
	var player := _player()
	if handler == null or player == null:
		_fail("no TileMapHandler or player in the scene")
		return

	var centre = _stage(handler, player)
	if centre == null:
		_fail("found no all-land %sx%s battle rect within %s tiles of the player" % [
			BATTLE_HALF.x * 2 + 1, BATTLE_HALF.y * 2 + 1, ARENA_SEARCH,
		])
		return

	# Everything above this line is setup and is expected to be trimmed off the front of
	# the recording; everything below it is the clip.
	await _wait(BEAT["settle"])
	_mark("show_start")

	await _beat_place_turret(handler, player, centre)
	await _beat_net_capture(handler, player, centre)
	await _beat_load_turret(player)
	await _beat_wave(handler, player, centre)

	_mark("show_end")
	await _wait(BEAT["tail"])

	_release_all()
	_beat = "done"
	_running = false


## Beat A — the player places a bone turret with the hotbar, exactly as a key press would.
func _beat_place_turret(handler: TileMapHandler, player: Player, centre: Vector2i) -> void:
	_beat = "place_turret"
	_mark("place_turret")

	# Face left, and place to the left. The turret only ever goes into the cell the player
	# faces, so putting it behind him is what leaves the ground to his right clear for the
	# skeleton to be met on — and gives beat C a walk back to it rather than a standing use.
	await _hold("move_left", 0.2)
	await _wait(BEAT["before_place"])

	if not _select(Types.Item.BoneTurret):
		_note("no bone turret in the hotbar to place")
		return
	await _wait(BEAT["after_select"])

	var front := _front_cell(handler, player)
	await _use()
	await _frames(2)

	if handler.tileMap.get_cell_source_id(1, front) == -1:
		_note("the placement press left cell %s empty" % front)
	await _wait(BEAT["after_place"])


## Beat B — the player walks out to a bone skeleton and takes it with the net.
func _beat_net_capture(handler: TileMapHandler, player: Player, centre: Vector2i) -> void:
	_beat = "net_capture"
	_mark("net_capture")

	# Four tiles out: far enough to be a walk worth watching, close enough that the last
	# stretch of it is inside AGGRO_RANGE, so the skeleton turns and comes at the player
	# instead of being ambushed standing still.
	var enemy := _spawn_enemy(handler, centre + Vector2i(4, 0))
	if enemy == null:
		_note("could not spawn the enemy for the net beat")
		return

	if not _select(Types.Item.Net):
		_note("no net in the hotbar")
		return

	# Closing on the enemy rather than swinging on a timer: it wanders while idle and
	# charges once it notices, so where it is at any given second is not knowable from here.
	_press("move_right")
	var closed := await _until(func() -> bool:
		return not is_instance_valid(enemy) \
			or player.global_position.distance_to(enemy.global_position) < NET_REACH, 8.0)
	_release("move_right")

	if not closed or not is_instance_valid(enemy):
		_note("never got within net reach of the skeleton")
		return

	await _wait(BEAT["before_swing"])

	# Two swings at most. The first is the shot; the second only exists because the net's
	# Area2D is narrow and a skeleton that stepped aside on the swing frame would otherwise
	# end the clip with an empty hand and nothing to load.
	var caught := false
	for _attempt in 3:
		await _use()
		await _wait(SWING_SETTLE)
		caught = _has(player, Types.Item.BoneEnemy)
		if caught:
			break

	if not caught:
		_note("the net beat finished without a skull in the inventory")
		if is_instance_valid(enemy):
			enemy.queue_free()

	await _wait(BEAT["after_capture"])


## Beat C — the player carries the skull back to the turret, which lights up as loaded.
func _beat_load_turret(player: Player) -> void:
	_beat = "load_turret"
	_mark("load_turret")

	if not _select(Types.Item.BoneEnemy):
		_note("no skull in the hotbar to load")
		return

	# `GameItemBoneEnemy.use()` reads the player's overlapping areas, so the walk back is
	# not decoration — outside the turret's LineOfSight the press finds nothing and the
	# stack is (correctly) not spent, which on film is a player fumbling at nothing.
	var turret = _nearest_turret(player)
	if turret != null:
		_press("move_left")
		var arrived := await _until(func() -> bool:
			return player.global_position.distance_to(turret.global_position) < 20.0, 6.0)
		_release("move_left")
		if not arrived:
			_note("did not reach the turret to load it")

	await _wait(BEAT["after_select"])

	await _use()
	await _frames(4)

	if _loaded_turrets() == 0:
		_note("the load press did not light a turret")
	await _wait(BEAT["after_load"])


## Beat D — a ring of loaded turrets takes two waves of skeletons apart around the player.
func _beat_wave(handler: TileMapHandler, player: Player, _centre: Vector2i) -> void:
	_beat = "wave"
	_mark("wave")

	# Anchored on where beat C actually left the player, not on the arena centre: the
	# camera is a child of the player, so the ring has to be built around him or the shot
	# is of the ground beside the fight.
	var here: Vector2i = handler.tileMap.local_to_map(player.global_position)

	# The placement beat has already been shown once; four more identical presses would be
	# four seconds of the same shot. These are written straight onto the tilemap and lit,
	# which is the same end state the hotbar press reaches.
	for offset in TURRET_RING:
		_place_turret(handler, here + offset)
	await _frames(2)
	for turret in _turrets():
		turret.set_loaded()

	# Two waves rather than one: a single volley is over in about four seconds, which is
	# less footage than the beat needs and reads as a skirmish rather than as a defence.
	await _telegraph_wave(handler, _offset_cells(here, WAVE_ONE))
	await _wait(BEAT["between_waves"])
	await _telegraph_wave(handler, _offset_cells(here, WAVE_TWO))
	await _wait(BEAT["wave_hold"])


# --- the worker clip ------------------------------------------------------------------
#
# The automation loop end to end: lay out a chest and two worker bases, drop a captured
# skull into each, then watch one fell a tree and the other break a rock and both carry the
# haul back to the chest — which the player opens on the last beat to show what arrived.
#
# Shot on a save rather than on a fresh world, which the turret clip is not. A worker chain
# is a thing you build once you already have a base; standing it up on empty starting grass
# films the mechanic and loses the reason anyone would want it.

## Which save slot the worker clip loads before it starts.
##
## Slot 3 on this machine is the demo homestead — the same world as
## `test/fixtures/demo_homestead_save`, regenerable into any slot with the `build_demo_world`
## devtools verb. The clip needs a walled house, chests and turrets standing behind the
## action, and nothing about the choreography below cares which slot they come from, so a
## slot whose contents have moved on is a one-word change here rather than a reshoot.
const WORKER_SLOT := 3

## What one chop or one mine is shortened to for the recording, against
## `BoneWorker.CHOP_SECONDS`' twenty.
##
## This is the clip's second deliberate lie — `player.invulnerable` in the turret clip is the
## first — and the only one that touches a number a player would feel. Twenty seconds is a
## balance decision and a load-bearing one (its own comment explains that automation is meant
## to be the *slow* way to clear a node), but it is also twenty seconds of a skeleton standing
## still, twice, in a clip that has about twenty-five to spend in total. Five is the 4.0s the
## feature shipped with before the 400% slowdown, rounded up: long enough that the chips read
## as work rather than as a flicker, short enough that both workers complete a whole errand —
## walk out, fell, carry back, deposit — on camera.
const WORKER_CHOP := 5.0

## The set, as offsets in tiles from the pocket centre.
##
## Two rules shaped every number here. The camera is a child of the player and shows about
## ±7 by ±4 tiles at zoom 8, so the whole errand has to fit in a strip six wide; and a
## placeable lands in `get_tile_in_front_of_player()`, which is the cell horizontally beside
## the player, so every `stand_*` mark sits exactly one tile from what it puts down.
##
## The chest is on the far side of the player from the trees on purpose. Worker and target
## two tiles apart with the drop-off four the other way makes the delivery the long leg,
## which is the half of the loop worth watching — a chest tucked in beside the tree would
## show the same behaviour as a shuffle on the spot.
const WORKER_SET := {
	"mark": Vector2i(1, 0),
	"stand_chest": Vector2i(0, 0),
	"chest": Vector2i(-1, 0),
	"stand_wood": Vector2i(1, 0),
	"wood_worker": Vector2i(2, 0),
	"stand_stone": Vector2i(1, 1),
	"stone_worker": Vector2i(2, 1),
	"tree_a": Vector2i(4, 0),
	"tree_b": Vector2i(4, -1),
	"stone": Vector2i(4, 1),
	"stand_watch": Vector2i(0, -1),
	"stand_reveal": Vector2i(0, 0),
}

## The rectangle, relative to the pocket centre, that has to be clear grass before anything
## is staged. It is exactly the bounding box of WORKER_SET, and it is checked rather than
## cleared: the turret clip bulldozes its arena, but this one is shot in someone's finished
## base and flattening a wall of it to make room would be filming a different save.
const POCKET_MIN := Vector2i(-1, -1)
const POCKET_MAX := Vector2i(4, 1)

## Distance in pixels within which a walk counts as having arrived. Under a pixel, because
## the walk stops on the first frame past its mark and at 50px/s over a 60fps frame that
## overshoot is 0.83px — a tighter test would never pass and a looser one accumulates across
## four walks into a set visibly off its own grid.
const WALK_EPSILON := 0.5

## Ceiling on the work beat. A full errand is a ~2 tile walk out, WORKER_CHOP standing at the
## node and a ~4 tile walk back, so about fifteen seconds for both workers; the rest is slack
## for a path that has to route around the turret standing between the bases and the grove.
const WORKER_WORK_TIMEOUT := 45.0

const WORKER_BEAT := {
	"settle": 0.8,
	"after_select": 0.45,
	"after_place": 0.7,
	"after_assemble": 0.9,
	"after_delivery": 1.0,
	"before_reveal": 0.5,
	"reveal_hold": 3.0,
	"tail": 0.6,
}


func _run_worker_clip() -> void:
	if not _load_slot(WORKER_SLOT):
		_fail("could not load save slot %d" % WORKER_SLOT)
		return
	# A load rebuilds most of the world, and the scene tiles it re-instances are not in the
	# tree — so not in their groups, and not findable — until the frames after it returns.
	await _frames(4)

	var handler := _handler()
	var player := _player()
	if handler == null or player == null:
		_fail("no TileMapHandler or player after loading slot %d" % WORKER_SLOT)
		return

	var centre = _stage_worker_set(handler, player)
	if centre == null:
		_fail("no clear %sx%s pocket within %s tiles of where slot %d put the player" % [
			POCKET_MAX.x - POCKET_MIN.x + 1, POCKET_MAX.y - POCKET_MIN.y + 1,
			ARENA_SEARCH, WORKER_SLOT,
		])
		return

	await _wait(WORKER_BEAT["settle"])
	_mark("show_start")

	await _beat_place_set(handler, player, centre)
	var workers := await _beat_assemble(handler, player, centre)
	await _beat_deliver(handler, player, centre, workers)
	await _beat_reveal(handler, player, centre)

	_mark("show_end")
	await _wait(WORKER_BEAT["tail"])

	_release_all()
	_beat = "done"
	_running = false


## Beat A — the player lays the station out: a chest on his left, two worker bases on his
## right.
##
## Every placement is preceded by a walk in the direction it goes down, and that is the
## reason the marks are arranged the way they are. Facing is `AnimatedSprite2D.flip_h`, set
## by the last horizontal step, and a placeable lands in the cell the player faces — so
## walking to the mark *is* aiming. Nothing here taps a key to pivot on the spot, which is
## both what a person does and what keeps the player on a whole tile between beats.
func _beat_place_set(handler: TileMapHandler, player: Player, centre: Vector2i) -> void:
	_beat = "place_set"
	_mark("place_set")

	await _walk_to(handler, player, centre + WORKER_SET["stand_chest"])
	await _place_from_bag(handler, player, Types.Item.Chest, centre + WORKER_SET["chest"])

	await _walk_to(handler, player, centre + WORKER_SET["stand_wood"])
	await _place_from_bag(handler, player, Types.Item.BoneWorker, centre + WORKER_SET["wood_worker"])

	# Down a tile rather than along: `move_down` leaves flip_h alone, so the player is still
	# pointed right and the second base goes in beside the first without a walk that would
	# take him past it.
	await _walk_to(handler, player, centre + WORKER_SET["stand_stone"])
	await _place_from_bag(handler, player, Types.Item.StoneWorker, centre + WORKER_SET["stone_worker"])


## Beat B — a captured skull into each base, which is what turns a prop into a unit.
##
## No walk between the two presses: `GameItemBoneEnemy` searches the areas the player's own
## Area2D overlaps, and a WorkArea is a 40px circle, so from the mark both bases are already
## in reach. The first press takes the nearer one and the second skips it — a machine that is
## already loaded is not a candidate at all, which is exactly why two presses load two bases
## rather than one base twice.
func _beat_assemble(handler: TileMapHandler, player: Player, centre: Vector2i) -> Array:
	_beat = "assemble"
	_mark("assemble")

	var mine := []
	for key in ["stone_worker", "wood_worker"]:
		var worker = _worker_at(handler, centre + WORKER_SET[key])
		if worker != null:
			mine.append(worker)
	if mine.is_empty():
		_note("neither base is in the tree to be loaded")
		return mine

	if not _select(Types.Item.BoneEnemy):
		_note("no skull in the bag to assemble with")
		return mine
	await _wait(WORKER_BEAT["after_select"])

	for _i in mine.size():
		await _use()
		await _wait(WORKER_BEAT["after_assemble"])

	var loaded := 0
	for worker in mine:
		if worker.loaded:
			loaded += 1
	if loaded < mine.size():
		_note("%d of %d bases took a skull" % [loaded, mine.size()])
	return mine


## Beat C — the loop itself. The player steps out of the lane and the two workers fell a
## tree, break a rock, and carry both back to the chest.
##
## Waiting on the chest's contents rather than on a stopwatch: a worker plans its errand on
## its own tick and routes around whatever is in the way, so how long the round trip takes is
## not knowable from here. The chest filling is also the only evidence that matters — a
## worker can walk the whole path and arrive holding nothing if the tree went down before the
## swing landed.
func _beat_deliver(handler: TileMapHandler, player: Player, centre: Vector2i,
		workers: Array) -> void:
	_beat = "deliver"
	_mark("deliver")

	await _walk_to(handler, player, centre + WORKER_SET["stand_watch"])

	var chest = _chest_at(handler, centre + WORKER_SET["chest"])
	if chest == null:
		_note("no chest at %s to deliver into" % [centre + WORKER_SET["chest"]])
		return

	# One of each worker's own drop, not a total count. A tree yields one or two logs, so a
	# total of two is reached by the wood worker alone about half the time — and a beat that
	# ends there cuts the stone worker off mid-walk with the shot's other half unfinished.
	var wanted := _drops_of(handler, workers)
	var waited := 0.0
	while waited < WORKER_WORK_TIMEOUT:
		_compress_work(workers)
		if _chest_holds_all(chest, wanted):
			break
		await _dev.get_tree().process_frame
		waited += _dev.get_process_delta_time()

	if not _chest_holds_all(chest, wanted):
		_note("only %d item(s) reached the chest in %.0fs, wanted one of each of %s" % [
			_chest_count(chest), WORKER_WORK_TIMEOUT, wanted])
	await _wait(WORKER_BEAT["after_delivery"])


## Beat D — the payoff: the player opens the chest and the haul is in it.
##
## Through the `action` key rather than by calling `player_interact()`, because the thing
## being shown is that this is the ordinary chest the player already uses. `Player._process`
## reads that key with `is_action_just_pressed` and routes it through `nearest_chest`, which
## is set by the Interact area — so standing on the adjacent tile is a precondition of the
## beat and not just where the walk happened to end.
func _beat_reveal(handler: TileMapHandler, player: Player, centre: Vector2i) -> void:
	_beat = "reveal"
	_mark("reveal")

	await _walk_to(handler, player, centre + WORKER_SET["stand_reveal"])
	await _wait(WORKER_BEAT["before_reveal"])

	if player.nearest_chest == null:
		_note("standing at %s the player has no chest in interact range"
			% [centre + WORKER_SET["stand_reveal"]])

	await _tap_key_for("action")
	await _frames(2)

	if not _bag_open():
		_note("the action press did not open the chest")
	await _wait(WORKER_BEAT["reveal_hold"])


# --- worker staging -------------------------------------------------------------------

## Puts the loaded save into the state the worker clip opens on, and returns the pocket
## centre — or null when the save has nowhere clear to build.
func _stage_worker_set(handler: TileMapHandler, player: Player):
	_beat = "staging"

	var centre = _find_pocket(handler, player)
	if centre == null:
		return null

	_freeze_ambient()
	_clear_enemies()
	# Every worker that exists at this point belongs to the save, not to the clip.
	_still_existing_workers()

	# The grove, planted rather than found. `BoneWorker.SEARCH_CELLS` records the measurement
	# that makes this necessary: in this very save the two bone workers' nearest trees were
	# 19.4 and 20.6 cells out, because a developed homestead sits in an apron its owner
	# cleared by hand. Anywhere with the house in frame has nothing to harvest, and anywhere
	# with something to harvest has no house — so the clip brings three nodes with it and
	# leaves the rest of the save alone.
	_plant(handler, centre + WORKER_SET["tree_a"], Types.Item.Tree)
	_plant(handler, centre + WORKER_SET["tree_b"], Types.Item.Tree)
	_plant(handler, centre + WORKER_SET["stone"], Types.Item.StoneResource)

	player.position = handler.tileMap.map_to_local(centre + WORKER_SET["mark"])
	player.velocity = Vector2.ZERO
	player.invulnerable = true

	_set_zoom(player, CLOSE_ZOOM)
	_hide_fps()
	_stock_worker_kit(player)
	return centre


## The pocket centre: the cell whose WORKER_SET bounding box is entirely clear grass, ranked
## on how much *built* world its opening frame would contain, then on nearness to where the
## save put the player.
##
## The middle key is the whole reason this is a search and not a constant. Clear ground is
## abundant on a maxed island and the nearest clear pocket is out in a field, which films the
## automation loop against grass — the exact thing loading a homestead save was meant to
## avoid. Ranking on built cells in shot pulls the set back against the house without
## hardcoding the house's coordinates, which no longer survive the save being regenerated.
func _find_pocket(handler: TileMapHandler, player: Player):
	var origin: Vector2i = handler.tileMap.local_to_map(player.global_position)
	var best = null
	var best_key := [-1, -(1 << 30)]

	for dy in range(-ARENA_SEARCH, ARENA_SEARCH + 1):
		for dx in range(-ARENA_SEARCH, ARENA_SEARCH + 1):
			var candidate := origin + Vector2i(dx, dy)
			if not _pocket_clear(handler, candidate):
				continue
			var key := [_built_in_frame(handler, candidate), -(dx * dx + dy * dy)]
			if key > best_key:
				best = candidate
				best_key = key
	return best


## Whether every cell the clip writes to is empty, buildable grass.
##
## `is_occupied(cell, true)` is the game's own build test, so this asks exactly what the
## placement presses will ask a few seconds later — including the ground check, which is what
## keeps the set off the water, and the scene-tile check, which is what keeps it off a rock
## that has no cell of its own on the object layer.
func _pocket_clear(handler: TileMapHandler, centre: Vector2i) -> bool:
	for y in range(POCKET_MIN.y, POCKET_MAX.y + 1):
		for x in range(POCKET_MIN.x, POCKET_MAX.x + 1):
			if handler.is_occupied(centre + Vector2i(x, y), true):
				return false
	return true


## How many cells of the frame this pocket would open on already have something on them —
## walls, floors, stations, turrets, ore. A proxy for "is the base in shot", counted over the
## same VIEW_HALF the turret clip uses to reason about framing.
func _built_in_frame(handler: TileMapHandler, centre: Vector2i) -> int:
	var built := 0
	var mark: Vector2i = centre + WORKER_SET["mark"]
	for y in range(mark.y - VIEW_HALF.y, mark.y + VIEW_HALF.y + 1):
		for x in range(mark.x - VIEW_HALF.x, mark.x + VIEW_HALF.x + 1):
			var cell := Vector2i(x, y)
			if handler.tileMap.get_cell_source_id(1, cell) != -1 \
					or handler.tileMap.get_cell_source_id(2, cell) != -1:
				built += 1
	return built


## Writes a resource node onto a cell, through the same call `main.gd` uses for a placed
## tile — atlas_location and source id together, which is the pair a cell is mapped back to
## its registry entry by, and therefore the pair `_is_tree_at` will match on.
func _plant(handler: TileMapHandler, cell: Vector2i, type: Types.Item) -> void:
	if handler.resources == null:
		return
	# get_item_or_resource_by_type, not Resources.Get: the latter indexes its dictionary
	# directly and errors on a type that is not registered.
	var entry = handler.resources.get_item_or_resource_by_type(type)
	if entry == null:
		_note("no resource registered for type %d, nothing planted at %s" % [type, cell])
		return
	handler.set_tile_item(cell, entry)


## The kit, into the first four hotbar slots only.
##
## Deliberately not the turret clip's `_stock`, which empties all six. The demo save keeps
## the player's own wood and stone in the slots past those four, and this clip ends with the
## bag open beside a chest — a player standing there with nothing of his own would read as
## the wood in the chest having come out of his pockets rather than off a tree.
func _stock_worker_kit(player: Player) -> void:
	var slots: Array = player.inventory_data.inventory_slot_datas
	for index in mini(4, slots.size()):
		slots[index] = null

	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(Types.Item.Chest), 1))
	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(Types.Item.BoneWorker), 1))
	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(Types.Item.StoneWorker), 1))
	# Two skulls in one stack: the assemble beat spends them one press at a time, and the
	# hotbar shows a count going 2 -> 1 -> gone, which is the feedback the beat is about.
	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(Types.Item.BoneEnemy), 2))
	player.inventory_data.inv_updated()


## Stops the think tick of every worker already standing in the save.
##
## A loaded worker with nothing in range does not stand still — it wanders, on purpose, so
## that a starving one does not read as a broken one. That is right in the game and wrong in
## a clip: it puts a second skeleton drifting through the shot doing something the footage
## never explains. The demo save ships four of them, two already loaded.
##
## Pausing the timer alone is not enough, and the first take showed why: a worker restored
## mid-errand keeps whatever state the save left it in, and a paused timer means the tick that
## would END that state never arrives. Two of them stood there swinging at nothing for the
## whole clip. Clearing the path and the swing as well is what actually parks them — and
## `_set_working(false)` rather than a direct `visible` write, because it is what puts the
## pickaxe back at its authored offset instead of leaving it frozen mid-arc.
func _still_existing_workers() -> void:
	for node in _dev.get_tree().get_nodes_in_group("BoneWorker"):
		if not (node is BoneWorker):
			continue
		if node.work_timer != null:
			node.work_timer.paused = true
		node._path.clear()
		node._state = BoneWorker.State.IDLE
		node._set_working(false)


## Holds the clip's own workers at WORKER_CHOP, called once a frame through the work beat.
##
## It has to run repeatedly rather than once at load: `_on_arrived` restarts the timer with
## `CHOP_SECONDS` at the start of every chop, so a single override lasts exactly one cycle.
## The `wait_time` test is what stops this being a bug — `Timer.start()` *restarts* the
## countdown, so calling it unconditionally every frame would produce a timer that never
## fires at all and a worker that swings forever.
func _compress_work(workers: Array) -> void:
	for worker in workers:
		if not is_instance_valid(worker):
			continue
		var timer: Timer = worker.work_timer
		if timer != null and timer.wait_time > WORKER_CHOP:
			timer.start(WORKER_CHOP)


# --- worker lookups and input ---------------------------------------------------------

## By node path, the way `commands.gd:_save_load` reaches it, and NOT by the "SaveLoad"
## group. That group is the list of nodes that *have state to save* — every chest, the
## player, the spawner — and the manager itself is not a member of it. Looking there finds
## a dozen nodes and none of them the one that can load a slot.
func _load_slot(slot: int) -> bool:
	var saves := _dev.get_tree().root.get_node_or_null("Main/Systems/SaveLoad") as SaveLoad
	return saves != null and saves.load_from_slot(slot)


## The worker standing on `cell`, or null. Matched on the cell rather than held from the
## placement call because a scene tile is instanced by the TileMap, so the placing code never
## sees the node it created.
func _worker_at(handler: TileMapHandler, cell: Vector2i):
	for node in _dev.get_tree().get_nodes_in_group("BoneWorker"):
		if node is BoneWorker and handler.tileMap.local_to_map(node.position) == cell:
			return node
	return null


func _chest_at(handler: TileMapHandler, cell: Vector2i):
	for node in _dev.get_tree().get_nodes_in_group("external_inventory"):
		if node is TestChest and handler.tileMap.local_to_map(node.position) == cell:
			return node
	return null


## What each worker in `workers` puts in a chest, as item types. Read off the resource
## registry through the worker's own `harvest_type` rather than assumed, for the reason
## `BoneWorker._fell` states: the blue machine is a wood farmer because trees drop wood, and
## a fourth variant should need no edit here.
func _drops_of(handler: TileMapHandler, workers: Array) -> Array:
	var drops := []
	if handler.resources == null:
		return drops
	for worker in workers:
		var entry = handler.resources.get_item_or_resource_by_type(worker.harvest_type)
		if entry is GameResource and entry.drop not in drops:
			drops.append(entry.drop)
	return drops


func _chest_holds_all(chest, types: Array) -> bool:
	if types.is_empty() or chest == null or chest.inventory_data == null:
		return false
	for type in types:
		var found := false
		for slot in chest.inventory_data.inventory_slot_datas:
			if slot != null and slot.item != null and slot.item.type == type and slot.count > 0:
				found = true
				break
		if not found:
			return false
	return true


func _chest_count(chest) -> int:
	if chest == null or chest.inventory_data == null:
		return 0
	var total := 0
	for slot in chest.inventory_data.inventory_slot_datas:
		if slot != null and slot.item != null:
			total += slot.count
	return total


func _bag_open() -> bool:
	var panel := _dev.get_tree().root.get_node_or_null("Main/UI/InventoryInterface") as Control
	return panel != null and panel.visible


## Taps the real key `action` is bound to, as an `InputEventKey`.
##
## `_press()` is not usable for this one and the first take is the proof: `Player._process`
## reads the interact key with `Input.is_action_just_pressed`, which is true only on the
## process frame whose counter matches the press — and `Input.action_press()` called from a
## coroutine already resumed inside that frame stamps a frame the player has finished reading.
## The chest never opened, silently, with the player standing right beside it.
##
## The keycode comes out of the InputMap rather than being written here, so a rebound interact
## key is not a clip that quietly ends on a closed chest.
func _tap_key_for(action: String) -> void:
	var key: InputEventKey = null
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			key = event
			break
	if key == null:
		_note("'%s' has no key bound to tap" % action)
		return

	var down := key.duplicate() as InputEventKey
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)

	var up := key.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


## Selects `type` in the hotbar, aims by walking, and puts the tile down with one use press.
## Reports rather than raises: a beat that placed nothing still has to hand control to the
## next one, and the note is what tells the capture script the take is not usable.
func _place_from_bag(handler: TileMapHandler, player: Player, type: Types.Item,
		cell: Vector2i) -> void:
	if not _select(type):
		_note("nothing of type %d in the bag to place at %s" % [type, cell])
		return
	await _wait(WORKER_BEAT["after_select"])

	await _aim(handler, player, cell)
	var front := _front_cell(handler, player)
	if front != cell:
		_note("aimed at %s but the set wants %s" % [front, cell])

	await _use()
	await _frames(2)

	if handler.tileMap.get_cell_source_id(1, cell) == -1:
		_note("the placement press left cell %s empty" % cell)
	await _wait(WORKER_BEAT["after_place"])


## Turns the player to face `cell`, then puts him back exactly where he was standing.
##
## Inheriting the facing from the walk that arrived is not good enough, and the first take
## proved it: facing is `flip_h = velocity.x < 0` sampled every physics frame, so ANY sideways
## motion after the walk rewrites it — including `move_and_slide` pushing the player off the
## solid tile he has just built beside himself. That take walked right, placed the wood
## worker, stepped down one tile and put the stone worker down on the player's LEFT, three
## cells from where the set wanted it; the shot then had a base standing in the delivery lane
## and nothing for the second skull to load.
##
## Held until the sprite actually flips rather than for a fixed number of frames: one physics
## frame is enough at 50px/s and the position is restored afterwards, so the cost on screen is
## a turn on the spot, which is what the key does anyway.
func _aim(handler: TileMapHandler, player: Player, cell: Vector2i) -> void:
	var here: Vector2i = handler.tileMap.local_to_map(player.global_position)
	if cell.x == here.x:
		_note("cannot aim at %s from %s: a placeable only ever goes left or right" % [cell, here])
		return

	var want_left := cell.x < here.x
	if player.is_facing_left() == want_left:
		return

	var mark := player.position
	var action := "move_left" if want_left else "move_right"
	_press(action)
	var turned := await _until(func() -> bool: return player.is_facing_left() == want_left, 0.5)
	_release(action)
	player.position = mark
	player.velocity = Vector2.ZERO

	if not turned:
		_note("the player would not turn to face %s" % cell)


## Walks the player onto the centre of `cell` by holding the movement actions a person would,
## horizontal leg first.
##
## The order is not cosmetic. Facing follows the last *horizontal* step — `move_up` and
## `move_down` leave `flip_h` alone — so doing x first would leave the player pointed by a leg
## that is not the last one he took. Doing it this way means a walk that ends vertically keeps
## whatever facing the horizontal leg set, which is what lets the reveal beat approach the
## chest from above and still be looking at it.
func _walk_to(handler: TileMapHandler, player: Player, cell: Vector2i,
		timeout: float = 8.0) -> bool:
	var target: Vector2 = handler.tileMap.map_to_local(cell)
	var reached := true

	for axis in [0, 1]:
		var delta: float = target[axis] - player.position[axis]
		if absf(delta) < WALK_EPSILON:
			continue

		var forward := delta > 0.0
		var action := ""
		if axis == 0:
			action = "move_right" if forward else "move_left"
		else:
			action = "move_down" if forward else "move_up"

		_press(action)
		# Polls the position rather than counting frames: the player is a CharacterBody2D
		# running move_and_slide, so a wall or a chest in the way changes how far a held key
		# actually travels and a frame count would walk straight through the answer.
		var arrived := await _until(func() -> bool:
			var remaining: float = target[axis] - player.position[axis]
			return (remaining <= 0.0) if forward else (remaining >= 0.0), timeout)
		_release(action)

		if not arrived:
			_note("the walk to %s stalled on axis %d" % [cell, axis])
			reached = false

	# The sub-pixel remainder. The loop above stops on the first frame past the mark, which
	# is under a pixel at 50px/s over a 60fps frame — invisible on its own and, left
	# uncorrected across four walks, a set that no longer sits on its own grid.
	player.position = target
	player.velocity = Vector2.ZERO
	return reached


# --- the weather clip -----------------------------------------------------------------
#
# One held shot on the player's own coastline while a whole day passes over him: a bright
# afternoon, a sweep down through dusk into night with the lantern coming up, a storm, three
# bolts at chosen distances, and then dawn. Nothing is placed, netted or fought. The subject
# is the sky and everything else in frame is there to be lit by it.
#
# Two properties of the feature decide almost every number below.
#
# **A CanvasModulate tints exactly one canvas and this game has three**, so SkyLighting writes
# the world, the sea and the HUD separately (the canvas table in CLAUDE.md, and the header of
# world/vfx/sky_lighting.gd). The one of those three writes a viewer can actually check is the
# SEA: land going dark while the water stays daylight blue is precisely the failure that write
# exists to prevent, and it is what "night" looks like when it is broken. So this clip is
# staged on a coastline and candidates are scored on how much open water the frame holds — a
# clip shot inland shows a screen that got dimmer and proves nothing about any of it.
#
# **The tint is constant across DAY and constant across NIGHT**; only the two twilights move
# (WorldClock.tint_for). A clock swept at one rate therefore spends most of its footage on
# frames pixel-identical to their neighbours. Every sweep here is aimed at a twilight, and the
# flat stretches either side are either skipped before the recording starts or crossed fast.
#
# The clip tells one deliberate lie, flagged at its call site the way `player.invulnerable`
# and WORKER_CHOP are: the storm's own lightning countdown is parked so that the only bolts
# are the three the clip chose. See WEATHER_BOLT_HOLD_OFF.

## Where the clock is set before the recording starts.
##
## Inside DAY, whose tint is flat DAY_TINT everywhere, so this is visually indistinguishable
## from noon — but it is only 0.01 of a day (six world-seconds) short of DAY_END, which is
## where the light actually starts to move. Opening at noon instead would mean either a long
## sweep across frames that do not change or a jump, and a jump reads as a cut.
const WEATHER_OPEN_T := 0.59

## Where the nightfall sweep stops. A little past DUSK_END (0.70), where the tint has already
## settled to flat NIGHT_TINT, so a frame of timing wobble cannot leave the sweep ending
## halfway down the twilight ramp with the sky still visibly moving under the next beat.
const WEATHER_NIGHT_T := 0.72

## The two stops of the daybreak sweep: one just short of the midnight wrap, one in full
## morning. Split because everything between here and 1.0 is flat NIGHT_TINT and everything
## from 1.0 to DAWN_END (0.10) is the sunrise — one rate across both would spend most of the
## beat on an unchanging dark screen and then hurry the only part worth filming.
const WEATHER_PREDAWN_T := 0.99
const WEATHER_DAWN_T := 0.13

## How long the storm is asked for. The game's own full-length storm, the same number
## `set_weather` defaults to in devtools_ext — the clip only lives in the first ten seconds of
## it and then clears it by hand, but asking for a real one means every value the clip puts
## into the clock is one the clock could have rolled for itself.
const WEATHER_STORM_SECONDS := WorldClock.RAIN_MAX_FRACTION * WorldClock.DAY_LENGTH_SECONDS

## The bolts, in order, as `distance` — 0.0 overhead, 1.0 on the horizon.
##
## Far, middle, near, and the order is the point of the beat rather than decoration. That one
## number drives the flash brightness (SkyLighting.flash_peak_for), the thunder's volume and
## its pitch (GameSoundManager.play_thunder), so a horizon bolt and an overhead one differ in
## every channel at once — and showing both is the only way that shared derivation is visible
## at all. A single bolt would be indistinguishable from a hardcoded flash.
##
## Note there is no thunder DELAY to space around: sound_manager.gd plays the crack
## immediately and says why (a 4.5-second gap in a ten-minute day read as broken audio, not as
## distance). The gaps below are therefore about the eye recovering, not the ear catching up.
const WEATHER_BOLTS := [0.92, 0.45, 0.06]

## What `lightning_time_left` is parked at after the storm starts and after every forced bolt.
##
## **This is the clip's one lie about a number**, and it is out of the range the game itself
## can roll (LIGHTNING_MIN_GAP..MAX_GAP is 5..20). The storm beat and the bolt beat run about
## ten seconds of world time between them, so one or two natural bolts would land inside them
## — and two strikes closer together than FLASH_DURATION read as one long flicker rather than
## as two events, which is the artefact WorldClock's own five-second floor exists to avoid. A
## clip that is *about* the difference between a near bolt and a far one cannot afford a
## fourth, unchosen one landing on top of either.
##
## It is not left behind: the daybreak beat's `set_weather(CLEAR, 0.0)` zeroes this field on
## its way past, and a clear sky with a disarmed countdown is exactly the invariant WorldClock
## documents. The clip cannot end with an armed countdown under a dry sky.
const WEATHER_BOLT_HOLD_OFF := 60.0

## How far out the coastal search will walk from wherever the world put the player.
const WEATHER_SEARCH := 16

## How far the player paces, in tiles, and therefore how much clear walkable ground the stand
## needs on either side of it.
const WEATHER_STEP := 2

## The fraction of the visible frame that should be open sea.
##
## About a third: enough that the water is plainly a second thing being lit rather than a
## strip at the edge, and not so much that the player is standing on a spit with the island he
## lives on out of shot. It is a target rather than a maximum on purpose — ranking on "most
## sea" walks the stand out onto the narrowest finger of land the search can find.
const WEATHER_SEA_TARGET := 0.34

## Below this the frame has no sea worth calling sea, and the clip refuses to shoot rather
## than filming a screen that merely gets darker. Reachable in a real world: on a maxed island
## the coastline is 30-odd tiles from the middle, well past WEATHER_SEARCH.
const WEATHER_SEA_MIN := 0.10

## Beat lengths in seconds. Everything the clip's pacing depends on is here so it can be
## retimed without reading the choreography. The two walks are not in it — `_walk_to` runs
## until it arrives, so they add about 0.65s each — which puts the whole performance at
## roughly 25 seconds between the two marks.
const WEATHER_BEAT := {
	"settle": 0.8,
	"day_hold": 1.6,
	"nightfall": 3.8,
	"night_hold": 1.8,
	"storm_hold": 2.4,
	"bolt_gap": 2.4,
	"last_bolt_hold": 1.8,
	"storm_clearing": 0.9,
	"predawn": 1.3,
	"daybreak": 3.8,
	"dawn_hold": 1.4,
	"tail": 0.8,
}


func _run_weather_clip() -> void:
	var handler := _handler()
	var player := _player()
	var clock := _clock()
	if handler == null or player == null:
		_fail("no TileMapHandler or player in the scene")
		return
	if clock == null:
		_fail("no WorldClock in the scene, so there is no weather to film")
		return

	var shot = _stage_weather_shot(handler, player, clock)
	if shot == null:
		_fail("no coastal stand with at least %d%% sea in frame within %d tiles of the player" % [
			int(WEATHER_SEA_MIN * 100.0), WEATHER_SEARCH,
		])
		return

	# Everything above this line is setup and is expected to be trimmed off the front of the
	# recording; everything below it is the clip.
	await _wait(WEATHER_BEAT["settle"])
	_mark("show_start")

	await _beat_daylight(handler, player, shot)
	await _beat_nightfall(clock)
	await _beat_storm(handler, player, clock, shot)
	await _beat_lightning(clock)
	await _beat_daybreak(clock)

	_mark("show_end")
	await _wait(WEATHER_BEAT["tail"])

	_release_all()
	_beat = "done"
	_running = false


## Beat A — the baseline. Full afternoon light on the water, and the player walking a couple
## of tiles along his own shoreline so the shot opens on someone rather than on a diorama.
##
## The walk runs ALONG the coast rather than towards or away from it, which is what keeps the
## sea fraction the stand was chosen for from changing under the camera: the camera is a child
## of the player, so two tiles seaward is two tiles of extra water in every later frame and the
## staging search's answer would be stale by the time the storm arrived.
func _beat_daylight(handler: TileMapHandler, player: Player, shot: Dictionary) -> void:
	_beat = "daylight"
	_mark("daylight")

	await _walk_to(handler, player, shot["cell"] + shot["axis"] * WEATHER_STEP)
	await _wait(WEATHER_BEAT["day_hold"])


## Beat B — the day runs out. Dusk, then night: the world cools through the warm twilight, the
## sea follows it down, and the lantern comes up.
##
## The player stands still through it on purpose. This is the beat where the only thing moving
## is the light, and something walking about in it gives the eye somewhere else to be.
func _beat_nightfall(clock: WorldClock) -> void:
	_beat = "nightfall"
	_mark("nightfall")

	await _sweep_clock(clock, WEATHER_NIGHT_T, WEATHER_BEAT["nightfall"])
	await _wait(WEATHER_BEAT["night_hold"])


## Beat C — weather arrives. The rain starts, the tint drops towards the storm floor, and the
## player steps back off the water's edge.
##
## The rain is started BEFORE the walk so the walk reads as a reaction to it. Ordered the other
## way it is a man wandering back up the beach who is then rained on, which is the same two
## events and none of the causality.
func _beat_storm(handler: TileMapHandler, player: Player, clock: WorldClock,
		shot: Dictionary) -> void:
	_beat = "storm"
	_mark("storm")

	clock.set_weather(WorldClock.Weather.RAIN, WEATHER_STORM_SECONDS)
	# set_weather arms a fresh 5-20s countdown, which would fire inside this beat. See
	# WEATHER_BOLT_HOLD_OFF: the bolts in this clip are chosen, not rolled.
	clock.lightning_time_left = WEATHER_BOLT_HOLD_OFF

	await _walk_to(handler, player, shot["cell"])
	await _wait(WEATHER_BEAT["storm_hold"])


## Beat D — the bolts. Three of them, far to near, each given room to flash and rumble out
## before the next.
##
## Fired through `WorldClock.force_lightning`, which is the same entry point the devtools verb
## and the debug panel use, so the storm-first rule and the arm-before-emit ordering cannot
## drift from them. The sky is already raining by the time this runs, so nothing here starts a
## storm — but going through the function that would is what keeps that true if the beats above
## are ever reordered.
func _beat_lightning(clock: WorldClock) -> void:
	_beat = "lightning"
	_mark("lightning")

	for index in WEATHER_BOLTS.size():
		clock.force_lightning(WEATHER_BOLTS[index])
		# Re-parked after every strike, because force_lightning re-arms a real gap on its way
		# out and a 5-second one lands inside the pause below.
		clock.lightning_time_left = WEATHER_BOLT_HOLD_OFF

		# No sky.apply() here, deliberately, and the contrast with devtools_ext/commands.gd is
		# the reason to say so: `strike_lightning` repaints before replying because its caller
		# may screenshot without ever yielding a frame. A coroutine always yields, and
		# SkyLighting repaints from _process, so the flash is on screen either way.
		var last := index == WEATHER_BOLTS.size() - 1
		await _wait(WEATHER_BEAT["last_bolt_hold"] if last else WEATHER_BEAT["bolt_gap"])


## Beat E — the loop closes. The storm blows over in the dark, the clock runs on past midnight,
## and the sun comes up on the coast the clip opened on.
##
## The storm is cleared while it is still fully night, not at sunrise, and the ordering is
## visual rather than incidental: clearing rain is an instantaneous tint change (`tint_for`
## simply stops multiplying by RAIN_TINT), and against a dark screen that lands as the cloud
## breaking, where against a lit one it is a hard pop in the middle of the prettiest frames.
func _beat_daybreak(clock: WorldClock) -> void:
	_beat = "daybreak"
	_mark("daybreak")

	clock.set_weather(WorldClock.Weather.CLEAR, 0.0)
	await _wait(WEATHER_BEAT["storm_clearing"])

	# This sweep crosses midnight, and a day boundary is where WorldClock rolls fresh weather —
	# RAIN_CHANCE is 0.25, so one take in four would otherwise close on a storm arriving over
	# the sunrise. The clip declines exactly that one roll and hands the sky straight back
	# afterwards. Re-entrancy is fine: the cancel below emits weather_changed(CLEAR), which this
	# same handler ignores.
	var decline := func(weather: WorldClock.Weather) -> void:
		if weather == WorldClock.Weather.RAIN:
			clock.set_weather(WorldClock.Weather.CLEAR, 0.0)
	clock.weather_changed.connect(decline)

	await _sweep_clock(clock, WEATHER_PREDAWN_T, WEATHER_BEAT["predawn"])
	await _sweep_clock(clock, WEATHER_DAWN_T, WEATHER_BEAT["daybreak"])

	clock.weather_changed.disconnect(decline)
	await _wait(WEATHER_BEAT["dawn_hold"])


# --- weather staging ------------------------------------------------------------------

## Puts the world into the state the clip opens on, and returns `{cell, axis}` — where the
## player stands and which way he paces — or null when nothing near him has sea in frame.
func _stage_weather_shot(handler: TileMapHandler, player: Player, clock: WorldClock):
	_beat = "staging"

	var shot = _find_coast_stand(handler, player)
	if shot == null:
		return null

	_freeze_ambient()
	_clear_enemies()

	player.position = handler.tileMap.map_to_local(shot["cell"])
	player.velocity = Vector2.ZERO

	# No `player.invulnerable` here, unlike the turret clip. Nothing in this clip attacks him:
	# the spawner is frozen, the standing enemies are cleared, and lightning only reaches the
	# combat loop through a skeleton it can charge, of which there are now none.

	# The shipped zoom, not a wider one, and that is a choice rather than an oversight. Pulling
	# back would put more sea in frame, which this clip wants — but it would also shrink the
	# lantern, and the lantern coming up is the single clearest signal on screen that night has
	# arrived rather than that someone turned the brightness down.
	_set_zoom(player, CLOSE_ZOOM)
	_hide_fps()

	# The FPS counter goes and nothing else does. The HP and XP bars stay because they are the
	# third canvas write: they are inside the CanvasModulate and hold their daylight colour at
	# midnight only because _apply_hud cancels it. Hiding the HUD for tidiness would hide a
	# third of the feature.

	# Both set before the mark, so the jump is not in the footage. The weather is cleared as
	# well as the hour: the clip's first beat is the baseline everything after it is read
	# against, and a world that happened to be raining at the top would have nothing to arrive.
	clock.set_weather(WorldClock.Weather.CLEAR, 0.0)
	clock.set_time_of_day(WEATHER_OPEN_T)

	var sky := _sky()
	if sky != null:
		sky.apply()
	return shot


## The stand: the cell nearest the player with a clear lane to pace along and about
## WEATHER_SEA_TARGET of its frame open water, plus the axis to pace along.
##
## Ranked on the frame first and nearness second, so the search crosses the island to reach a
## coast rather than settling for the nearest patch of walkable grass — which on any island is
## the one the player is already standing in the middle of.
func _find_coast_stand(handler: TileMapHandler, player: Player):
	var origin: Vector2i = handler.tileMap.local_to_map(player.global_position)
	var best = null
	var best_key := [-1.0, -(1 << 30)]
	var best_sea := 0.0

	for dy in range(-WEATHER_SEARCH, WEATHER_SEARCH + 1):
		for dx in range(-WEATHER_SEARCH, WEATHER_SEARCH + 1):
			var candidate := origin + Vector2i(dx, dy)
			var frame := _frame_sea(handler, candidate)

			# Perpendicular to the water, so pacing runs along the shoreline instead of into or
			# away from it. `axis` is a direction, not a side; the beats step +STEP and back.
			var sea_dir: Vector2i = frame["dir"]
			var axis := Vector2i(sea_dir.y, -sea_dir.x)
			if not _lane_clear(handler, candidate, axis):
				continue

			var sea: float = frame["fraction"]
			var key := [-absf(sea - WEATHER_SEA_TARGET), -(dx * dx + dy * dy)]
			if key > best_key:
				best = {"cell": candidate, "axis": axis}
				best_key = key
				best_sea = sea

	if best == null:
		_note("no cell within %d tiles has a clear %d-tile lane to pace along"
			% [WEATHER_SEARCH, WEATHER_STEP * 2 + 1])
		return null
	if best_sea < WEATHER_SEA_MIN:
		# Refusing rather than shooting it. Without the sea in frame this is a clip of a screen
		# getting darker, which is what the day/night work looks like when it is BROKEN.
		_note("the best stand at %s has only %.0f%% sea in frame, wanted at least %.0f%%"
			% [best["cell"], best_sea * 100.0, WEATHER_SEA_MIN * 100.0])
		return null
	return best


## How much of the frame around `centre` is open water, and which way most of it lies.
##
## One pass for both answers, over the same VIEW_HALF the other clips reason about framing
## with. Open water is the ABSENCE of a ground tile — the sea is a ColorRect in its own
## CanvasLayer behind everything, not a tile of its own, which is the same fact
## `_spawn_enemy`'s land check turns on.
func _frame_sea(handler: TileMapHandler, centre: Vector2i) -> Dictionary:
	var total := 0
	var sea := 0
	var west := 0
	var east := 0
	var north := 0
	var south := 0

	for y in range(centre.y - VIEW_HALF.y, centre.y + VIEW_HALF.y + 1):
		for x in range(centre.x - VIEW_HALF.x, centre.x + VIEW_HALF.x + 1):
			total += 1
			if handler.tileMap.get_cell_source_id(0, Vector2i(x, y)) != -1:
				continue
			sea += 1
			if x < centre.x:
				west += 1
			elif x > centre.x:
				east += 1
			if y < centre.y:
				north += 1
			elif y > centre.y:
				south += 1

	var dir := Vector2i.RIGHT
	var most := east
	if west > most:
		dir = Vector2i.LEFT
		most = west
	if north > most:
		dir = Vector2i.UP
		most = north
	if south > most:
		dir = Vector2i.DOWN

	return {"fraction": float(sea) / float(maxi(total, 1)), "dir": dir}


## Whether the player can actually pace the lane this stand is chosen for.
##
## `is_occupied(cell, true)` is the game's own test and it is the right one here even though
## nothing gets built: it is true for any layer-0 tile that is not GRASS_ATLAS, and plain grass
## is what "walkable land" means everywhere in this project (main.gd:748). That rules out the
## shore-transition tiles `set_cells_terrain_connect` paints along the water's edge — which is
## correct, and does not push the stand inland, because the sea is scored over the whole frame
## rather than under the player's feet.
func _lane_clear(handler: TileMapHandler, centre: Vector2i, axis: Vector2i) -> bool:
	# One tile of margin past where the walks actually stop, so the player is never pressed
	# against a tree at the end of a walk.
	for step in range(-(WEATHER_STEP + 1), WEATHER_STEP + 2):
		if handler.is_occupied(centre + axis * step, true):
			return false
	return true


## Runs the clock from where it is to `target_t` over `seconds` of recording, smoothly.
##
## Through `tick()` with a larger delta — the same call `_process` makes, so every phase
## change, day boundary and weather expiry the sweep passes through fires exactly as it would
## have if the player had waited ten real minutes for it. Teleporting with `set_time_of_day`
## would be one frame of work and would read as a cut: the tint curve is smoothstepped and
## continuous by construction (WorldClock._ramp), and a sweep is the only thing that shows it.
##
## Driven off a precomputed schedule rather than off the distance still to go. The clock is
## ALSO ticking on its own in `_process` while this runs, so a feedback loop that re-read the
## remaining distance every frame would eventually find itself a hair past the target and
## sweep an entire further day to get back to it. This adds its own fraction on top of whatever
## the world does underneath, which is both monotonic and the honest arithmetic.
##
## No `sky.apply()`: SkyLighting polls the clock every frame and repaints itself, which is why
## it polls rather than listening for phase changes.
func _sweep_clock(clock: WorldClock, target_t: float, seconds: float) -> void:
	if clock == null or seconds <= 0.0:
		return

	var span := fposmod(target_t - clock.time_of_day, 1.0)
	var elapsed := 0.0
	var applied := 0.0

	while elapsed < seconds:
		await _dev.get_tree().process_frame
		elapsed = minf(elapsed + _dev.get_process_delta_time(), seconds)
		var want := span * (elapsed / seconds)
		var step := want - applied
		applied = want
		if step > 0.0:
			clock.tick(step * WorldClock.DAY_LENGTH_SECONDS)


func _clock() -> WorldClock:
	for node in _dev.get_tree().get_nodes_in_group("WorldClock"):
		if node is WorldClock:
			return node
	return null


func _sky() -> SkyLighting:
	for node in _dev.get_tree().get_nodes_in_group("SkyLighting"):
		if node is SkyLighting:
			return node
	return null


# --- staging --------------------------------------------------------------------------

## Puts the world into the state the clip opens on, and returns the arena centre.
##
## Returns null when the search never found a rectangle of solid land, which is a real
## outcome: `land_cells_for_radius` thresholds noise, so a maxed home island is routinely a
## lopsided crescent with no clear 15x9 patch anywhere near the spawn.
func _stage(handler: TileMapHandler, player: Player):
	_beat = "staging"

	var centre = _find_arena(handler, player)
	if centre == null:
		return null

	_freeze_ambient()
	_clear_enemies()
	_clear_arena(handler, centre)

	player.position = handler.tileMap.map_to_local(centre)
	player.velocity = Vector2.ZERO

	# The clip must not end on a respawn: the wave walks straight into the player, and a
	# death would teleport him out of frame and take the camera with him. This is a
	# recording-only lie and the only one in the file.
	player.invulnerable = true

	_set_zoom(player, CLOSE_ZOOM)
	_hide_fps()

	_stock(player)
	return centre


## The arena centre: the cell nearest the player whose BATTLE_HALF rectangle is entirely
## land. Ties break toward the player, so the camera moves as little as possible from
## wherever the world actually put him.
## Ranked on three keys in order: land under the battle rect, then land across the visible
## frame, then nearness to where the world put the player.
##
## The middle key is the one worth keeping. With only the first, every centre whose 9x7 was
## solid ground scored identically and the nearest won — which on the first take was a spot
## one tile inland, and the finished clip had the coastline running diagonally through it
## with a third of the frame open sea. The fight was on land the whole time; the shot was
## still wrong, and no assertion about the fight could have said so.
func _find_arena(handler: TileMapHandler, player: Player):
	var origin: Vector2i = handler.tileMap.local_to_map(player.global_position)
	var best = null
	var best_key := [-1, -1, -(1 << 30)]

	for dy in range(-ARENA_SEARCH, ARENA_SEARCH + 1):
		for dx in range(-ARENA_SEARCH, ARENA_SEARCH + 1):
			var candidate := origin + Vector2i(dx, dy)
			var key := [
				_land_score(handler, candidate, BATTLE_HALF),
				_land_score(handler, candidate, VIEW_HALF),
				-(dx * dx + dy * dy),
			]
			if key > best_key:
				best = candidate
				best_key = key

	var needed := (BATTLE_HALF.x * 2 + 1) * (BATTLE_HALF.y * 2 + 1)
	if best_key[0] < needed:
		_note("best battle rect at %s was %s/%s land" % [best, best_key[0], needed])
		# A cell or two of coast at a corner costs at most one lane; a third of the rect
		# missing means the fight would happen in the sea.
		if best_key[0] < needed - 3:
			return null
	return best


func _land_score(handler: TileMapHandler, centre: Vector2i, half: Vector2i) -> int:
	var land := 0
	for y in range(centre.y - half.y, centre.y + half.y + 1):
		for x in range(centre.x - half.x, centre.x + half.x + 1):
			if handler.tileMap.get_cell_source_id(0, Vector2i(x, y)) != -1:
				land += 1
	return land


## Clears the object and floor layers inside the arena, and the scene-tile resources that
## live as TileMap children rather than as cells — resources are two representations and
## code that walks only one leaves half the trees standing.
func _clear_arena(handler: TileMapHandler, centre: Vector2i) -> void:
	for y in range(centre.y - ARENA_HALF.y, centre.y + ARENA_HALF.y + 1):
		for x in range(centre.x - ARENA_HALF.x, centre.x + ARENA_HALF.x + 1):
			handler.tileMap.set_cell(1, Vector2i(x, y), -1)
			handler.tileMap.set_cell(2, Vector2i(x, y), -1)
			handler.tileMap.set_cell(3, Vector2i(x, y), -1)

	for child in handler.tileMap.get_children():
		if not (child is GameSceneResource):
			continue
		var cell: Vector2i = handler.tileMap.local_to_map(child.position)
		if absi(cell.x - centre.x) <= ARENA_HALF.x and absi(cell.y - centre.y) <= ARENA_HALF.y:
			child.queue_free()


func _stock(player: Player) -> void:
	# Emptied first so the beats can count on finding their item inside the six hotbar
	# slots. `pick_up_slot_data` fills the first free slot, and the starting kit is enough
	# to push the net out of reach of `select_slot`.
	var slots: Array = player.inventory_data.inventory_slot_datas
	for index in mini(6, slots.size()):
		slots[index] = null

	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(Types.Item.BoneTurret), 1))
	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(Types.Item.Net), 1))
	player.inventory_data.inv_updated()


## Stops the world advancing on its own for the length of the take: an ambient skeleton
## strolling into the net beat, or a tree regrowing inside the cleared arena, is a reshoot.
func _freeze_ambient() -> void:
	var spawner := _spawner()
	if spawner != null and spawner.timer != null:
		spawner.timer.paused = true

	var respawn := _dev.get_tree().root.get_node_or_null("Main/World/ResourceTimer")
	if respawn is Timer:
		respawn.paused = true


func _clear_enemies() -> void:
	var spawner := _spawner()
	if spawner == null:
		return
	for child in spawner.get_children():
		if child is Enemy:
			child.queue_free()


func _hide_fps() -> void:
	var player := _player()
	if player == null:
		return
	var fps := player.get_node_or_null("Camera2D/HUD/FpsLabel")
	if fps != null:
		fps.visible = false


## Camera zoom plus the HUD resize that has to follow it. The diegetic HUD sizes itself to
## `viewport_size / zoom` on `_ready` and on `size_changed` only, so a zoom written without
## this leaves a full-screen HUD laid out for the old view.
func _set_zoom(player: Player, zoom: Vector2) -> void:
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.zoom = zoom

	var hud := camera.get_node_or_null("HUD")
	if hud != null and hud.has_method("_resize_to_view"):
		hud._resize_to_view()


# --- world pokes ----------------------------------------------------------------------

func _place_turret(handler: TileMapHandler, cell: Vector2i) -> void:
	var item: GameItem = GameItems.get_item(Types.Item.BoneTurret)
	handler.set_tile(cell, item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)


## Spawns a bone skeleton on `cell`, or nowhere if that cell is open water.
##
## The land check is not defensive tidying. The starting island is roughly 20x13 tiles and
## the first take put half the wave into the sea, where the skeletons bobbed about
## unreachable by any turret — and nothing anywhere reports that, because ocean is the
## absence of a ground tile rather than a tile of its own.
func _spawn_enemy(handler: TileMapHandler, cell: Vector2i) -> Enemy:
	var spawner := _spawner()
	if spawner == null:
		return null
	if handler.tileMap.get_cell_source_id(0, cell) == -1:
		_note("skipped a spawn at %s: no ground there" % cell)
		return null

	var enemy := BONE_ENEMY.instantiate() as Enemy
	enemy.position = handler.tileMap.map_to_local(cell)
	spawner.add_child(enemy)
	return enemy


## Shows the spawner's `X` on each cell, then swaps it for a skeleton — the same two steps
## `EnemySpawner._timeout` takes, so the wave arrives the way the game announces a spawn
## instead of popping into the middle of the shot.
func _telegraph_wave(handler: TileMapHandler, cells: Array) -> void:
	var x: GameItem = GameItems.get_item(Types.Item.X)
	var live := []
	for cell in cells:
		if handler.tileMap.get_cell_source_id(0, cell) == -1:
			continue
		live.append(cell)
		handler.tileMap.set_cell(x.layer, cell, x.tile_source_id, x.atlas_location)

	await _wait(TELEGRAPH)

	for cell in live:
		handler.tileMap.set_cell(x.layer, cell, -1)
		_spawn_enemy(handler, cell)


func _offset_cells(origin: Vector2i, offsets: Array) -> Array:
	var cells := []
	for offset in offsets:
		cells.append(origin + offset)
	return cells


func _nearest_turret(player: Player):
	var closest = null
	var closest_distance := INF
	for turret in _turrets():
		var distance: float = player.global_position.distance_to(turret.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = turret
	return closest


func _turrets() -> Array:
	var found := []
	for node in _dev.get_tree().get_nodes_in_group("SaveChunks"):
		if node is BoneTurret:
			found.append(node)
	return found


func _loaded_turrets() -> int:
	var count := 0
	for turret in _turrets():
		if turret.loaded:
			count += 1
	return count


# --- input ----------------------------------------------------------------------------

## `Input.action_press` only moves the polled state, which is enough for movement (the
## InputManager polls it) and useless for the use press (the InputManager reads that one off
## the event). Both are driven, so both paths see the same input a key would produce.
func _press(action: String) -> void:
	Input.action_press(action)
	_dispatch(action, true)
	if action not in _held:
		_held.append(action)


func _release(action: String) -> void:
	Input.action_release(action)
	_dispatch(action, false)
	_held.erase(action)


func _dispatch(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _release_all() -> void:
	for action in _held.duplicate():
		_release(action)


func _hold(action: String, seconds: float) -> void:
	_press(action)
	await _wait(seconds)
	_release(action)


## One hotbar use press, held for `seconds` before release.
##
## The hold is load-bearing and cost a debugging session to find. Releasing `gather` runs
## `Player._gather_input_release`, which calls `animation_player.stop()` — so a two-frame
## tap killed the 0.2s net swing about fifteen milliseconds in, before the net had swept
## anywhere near the skeleton. Nothing reported it: `stop()` does not emit
## `animation_finished`, so `PlayerNet` never exited either, and the only trace was a
## second swing complaining that `body_entered` was already connected. A held key is also
## simply what a person does, which is why the game never had this problem.
func _use(seconds: float = 0.3) -> void:
	_press("gather")
	await _wait(seconds)
	_release("gather")


## Selects the hotbar slot holding `type`, moving the stack into the hotbar if the
## inventory put it out of reach. False when the player is not carrying one at all.
func _select(type: Types.Item) -> bool:
	# Plain `var`: _hot_bar() has an untyped return because the hotbar has no class_name,
	# and `:=` cannot infer from that.
	var hot_bar = _hot_bar()
	var player := _player()
	if hot_bar == null or player == null:
		return false

	var slots: Array = player.inventory_data.inventory_slot_datas
	var index := -1
	for i in slots.size():
		if slots[i] != null and slots[i].item != null and slots[i].item.type == type:
			index = i
			break
	if index == -1:
		return false

	if index >= 6:
		for i in 6:
			if slots[i] == null:
				slots[i] = slots[index]
				slots[index] = null
				index = i
				break
		player.inventory_data.inv_updated()
	if index >= 6:
		return false

	hot_bar.select_slot(index)
	return true


func _has(player: Player, type: Types.Item) -> bool:
	return player.inventory_data.count_of_type(type) > 0


# --- lookups and plumbing -------------------------------------------------------------

func _player() -> Player:
	for node in _dev.get_tree().get_nodes_in_group("Player"):
		if node is Player:
			return node
	return null


func _handler() -> TileMapHandler:
	for node in _dev.get_tree().get_nodes_in_group("TileMapHandler"):
		if node is TileMapHandler:
			return node
	return null


func _spawner() -> EnemySpawner:
	for node in _dev.get_tree().get_nodes_in_group("SaveLoad"):
		if node is EnemySpawner:
			return node
	return null


## Untyped: hot_bar_inventory.gd declares no `class_name`, and the player's own `@onready`
## reach into `UI/HotBarInventory` is the single place the path is written down.
func _hot_bar():
	var player := _player()
	return player.hot_bar_inventory if player != null else null


func _front_cell(handler: TileMapHandler, player: Player) -> Vector2i:
	var cell: Vector2i = handler.tileMap.local_to_map(player.global_position)
	return cell + (Vector2i(-1, 0) if player.is_facing_left() else Vector2i(1, 0))


func _wait(seconds: float) -> void:
	await _dev.get_tree().create_timer(seconds).timeout


func _frames(count: int) -> void:
	for _i in count:
		await _dev.get_tree().process_frame


## Polls `condition` once a frame until it holds or `timeout` game-seconds pass, and
## reports which. Timed off the frame clock rather than a wall clock because the whole
## point of the movie writer is that those two are not the same thing during a recording.
func _until(condition: Callable, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if condition.call():
			return true
		await _dev.get_tree().process_frame
		waited += _dev.get_process_delta_time()
	return condition.call()


## The output frame number this moment lands on. Under the movie writer `frames_drawn` is
## the frame index in the file, which is the whole reason the trim can be exact.
func _mark(label: String) -> void:
	_marks[label] = Engine.get_frames_drawn()


func _note(text: String) -> void:
	_notes.append(text)
	push_warning("DemoDirector: %s" % text)


func _fail(message: String) -> void:
	_note(message)
	_beat = "failed"
	_running = false
	_release_all()
