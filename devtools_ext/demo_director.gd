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

## How close the player is walked before swinging a SWORD, as opposed to the net's NET_REACH
## above. Both fight beats — the raid and the boss — use it, and the gap between the two numbers
## is what both of their first takes got wrong.
##
## NET_REACH is 13 and is a real measurement, of `Net_Right`, against a skeleton the player can
## walk right up to. Neither half of that transfers:
##
##  - **The bodies stop you.** An enemy's hurtbox IS its CharacterBody2D — collision_layer
##    3145729 carries bit 21, which is exactly what the player's Attack area masks — and that
##    body is solid to the player's. So the two physically cannot get closer than the sum of
##    their half-widths. On the elite, which is `bone_enemy.tscn` at 1.7x, that floor is about
##    14px; on an ordinary raider mid-attack it was measured at 16 to 18. `_chase` asking for 13
##    is asking for a distance the physics refuses, so it returned false every time and the beat
##    never swung once — with the boss standing still for a full forty-second ceiling, and with
##    the last raider of a raid sitting 16px away and simply not dying.
##  - **The sword reaches further anyway.** The Attack hitbox is a 9x5 rect whose centre sits
##    about 12px ahead of the player and which the swing animation sweeps, so its far edge passes
##    roughly 17px out — and the thing it has to touch is a hurtbox that extends 5.5px from the
##    enemy's own centre (9.4 on the elite).
##
## 19 is therefore above every collision floor measured and comfortably inside the swing. Both
## failures were silent and looked identical to a damage problem: the sword was equipped, `damage`
## read 13, and the only symptom either clip could report was that the enemy was still standing.
const SWORD_REACH := 19.0

## How close the target has to be for a sword beat to swing at all, whatever `_chase` reported.
##
## 19 was not enough either, and finding that out cost a full ten-minute recording: three clean
## dry runs in a row all ended with a cleared raid, and the take itself came back with the last
## raider resting 22px out and the raid unfinished. The resting distance is not a constant — it is
## wherever the hard bodies, the SoftCollision push and the enemy's current state happen to settle,
## and under `--fixed-fps 30` the player moves in 1.7px steps rather than the sub-pixel ones an
## uncapped dry run takes.
##
## So the reach stopped being a *gate*. `_chase` still aims for SWORD_REACH and gets as close as
## the physics allows, and the beat then swings if the target is inside this envelope — which is
## about where the hitbox stops reaching (a swing sweeping ~17px out against a hurtbox 5.5px from
## the enemy's centre). A swing that misses costs one second and the loop takes another; an
## approach that is never granted used to cost the entire fight, silently. The evidence that this
## is the right way round is that the swings were always landing: every raid that cleared, cleared
## on the same reach that left the last raider standing.
const SWORD_SWING_ENVELOPE := 26.0

## Chase stall detection: how much closer counts as progress, and how long without it before
## `_chase` accepts that this is as close as it is going to get.
const CHASE_PROGRESS := 0.5
const CHASE_STALL := 0.6

## How level with the target the player has to be before a sword swing can reach it.
##
## The sword is a horizontal weapon and the chase did not know that. `Attack` is a 9x5 rect the
## animation sweeps out to one SIDE — which side is `flip_h`, and `flip_h` only ever answers left
## or right — so an enemy standing directly above the player is inside SWORD_SWING_ENVELOPE and
## cannot be hit at all. `_chase` aims at the target's centre and stops on the straight-line
## distance, so it is perfectly happy to park the player underneath something and report success.
##
## That is what was left after the swing gate was fixed: a raid whose last raider sat 18px away,
## comfortably inside the envelope, being swung at and missed. `_close_for_swing` lines up on the
## target's row first and closes second, which is both what makes the swing land and what a person
## does with a sword.
##
## The band is centred on SWING_OFFSET_Y rather than on zero, because the hitbox is not centred on
## the player either: `Attack` rides at (3, 3) with its 9x5 rect a further (6.5, 4.5) out, and the
## swing animation sweeps it *downward* — the right-facing one from (-1, 1) to (3, 3), the
## left-facing one from (-4, -3) to (-1, 9). So the sweep passes through a region below the
## player's centre, and an enemy standing level with him is nearer the top edge of it than the
## middle. Aiming to have the target four pixels low is aiming at the middle of the actual sweep.
const SWING_OFFSET_Y := 4.0
const SWING_BAND_Y := 8.0

## What the approach does when it cannot line up, and how many times it will try.
##
## The case this exists for is an enemy standing directly above or below the player and touching
## him. The two bodies are solid to each other, so the vertical press that would put them on the
## same row is pressing into the thing it is trying to get level with: the approach stalls, gives
## up, is called again by the beat, and stalls again — sixty times in a forty-second fight, with
## the target twelve pixels away and not one swing thrown.
##
## Backing off ALONG the row is what breaks it, and it works because of what the enemy is: a
## raider hunts, so the moment the player steps aside it walks after him — onto his row, which is
## exactly where he needs it. The player does not have to solve the geometry; he has to stop
## standing under it. That is also `EnemyFollow.SIDESTEP_TIME` doing the same thing from the other
## side of the fight, which is a fair sign it is the right move.
const SWING_SIDESTEP_TIME := 0.5
const SWING_SIDESTEPS := 3

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
	return ["turrets", "workers", "weather", "charged", "raid", "boss", "quests"]


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
		"charged":
			_run_charged_clip()
		"raid":
			_run_raid_clip()
		"boss":
			_run_boss_clip()
		"quests":
			_run_quest_clip()
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

## How close the player has to get to the chest before the bag will stay open, in pixels.
##
## `InventoryInterface._physics_process` force-closes an open container the moment its owner
## is further than 15px from the player — load-bearing, because a bag left open across the
## map would keep a remote chest live and writable. A tile is 16px, so a player standing on
## the *centre* of the cell beside the chest is 16.0px out and the panel shuts itself on the
## next physics frame. The bag opened and closed inside two frames and the beat could only
## report that the press had not worked, which sent the first investigation into the input
## path — `_tap_key_for` was already correct and had nothing to do with it.
##
## So the last step of the beat is a lean into the chest rather than a stop on the mark,
## which is also what a person does. 13.0 rather than 14.9 because the workers deliver to
## this same chest and the SoftCollision nudge one gives the player in passing is about a
## pixel; a threshold set at the cliff edge would pass the check and still lose the panel.
const REVEAL_REACH := 13.0

## Ceiling on that lean, in seconds. The player walks 50px/s and has under 4px to cover, so
## anything reached here means he is wedged on something rather than walking slowly.
const REVEAL_CLOSE_TIMEOUT := 3.0

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

	var chest = _chest_at(handler, centre + WORKER_SET["chest"])
	if chest == null:
		_note("no chest at %s to open" % [centre + WORKER_SET["chest"]])
		return

	# Not a stop on the mark: see REVEAL_REACH. The mark is exactly one tile out, which is
	# one pixel further than the panel will stay open from.
	await _close_in(player, chest)
	await _wait(WORKER_BEAT["before_reveal"])

	if player.nearest_chest == null:
		_note("standing at %s the player has no chest in interact range"
			% [centre + WORKER_SET["stand_reveal"]])

	await _tap_key_for("action")
	await _frames(2)

	if not _bag_open():
		_note("the action press did not open the chest")
	await _wait(WORKER_BEAT["reveal_hold"])


## Walks the player up against `target` until he is inside REVEAL_REACH of it, and releases.
##
## Held until the *distance* says so rather than for a fixed time. The gap is under 4px and a
## timed nudge that overshot would push the player through the gap and out the far side, so
## the thing being waited on is the only thing that can be measured from here.
func _close_in(player: Player, target: Node2D) -> void:
	var action := "move_left" if target.global_position.x < player.global_position.x \
		else "move_right"
	_press(action)
	var arrived := await _until(
		func(): return player.global_position.distance_to(target.global_position) <= REVEAL_REACH,
		REVEAL_CLOSE_TIMEOUT)
	_release(action)
	if not arrived:
		_note("could not get within %.0fpx of the chest; the bag will close itself"
			% REVEAL_REACH)
	await _frames(2)


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
	return _built_around(handler, centre + WORKER_SET["mark"])


## How many cells of the frame centred on `mark` already have something on them — walls, floors,
## stations, turrets, ore. The "is the base in shot" proxy, counted over the same VIEW_HALF the
## turret clip uses to reason about framing.
##
## Split out of `_built_in_frame` when the raid clip wanted the same question asked about a mark
## of its own. The two clips are staged in the same save and want the same thing from it — the
## house behind the action — and a second copy of this loop would be a second thing to keep in
## step with what counts as built.
func _built_around(handler: TileMapHandler, mark: Vector2i) -> int:
	var built := 0
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


# --- the charged clip -----------------------------------------------------------------
#
# The one thing the weather does to the combat loop (gather-8ft), end to end: a grey skeleton
# wandering in a night storm, a bolt that lands ON it, the blue thing that gets up, the net,
# and the skull dropped into a turret which then visibly outshoots the ordinary one standing
# beside it.
#
# Shot on a fresh world like the turret clip and unlike the worker one. Nothing here needs a
# base — the whole subject is a storm and two skeletons — and a homestead save would only put
# somebody's walls behind it.
#
# ## Why the last beat is one shot and not two
#
# A fire rate is a rate, and a rate cannot be read off a single stream of bullets: "0.55s" only
# means anything against the 1.0s it replaced. So the clip never cuts from a slow turret to a
# fast one and asks the viewer to remember what the first one looked like. It ends on ONE frame
# holding both, each with its own lane of skeletons, and lets them be counted against each
# other. That requirement is what sets every offset in CHARGED_SET below — the two turrets have
# to be far enough apart to have separate lanes and close enough to share a frame, and the
# player has to end up standing somewhere that keeps both turrets and both lanes in it.
#
# ## The three things this clip fakes, all of them flagged again at their call sites
#
#  - `player.invulnerable`, exactly as the turret clip does it. A charged skeleton hits for 5
#    rather than 3, and the last beat then walks eight more skeletons in across two volleys
#    while the player stands still watching; the clip must not end on a respawn that teleports
#    the camera out of the shot.
#  - The charge itself is FORCED rather than rolled. EnemySpawner.CHARGE_CHANCE is 0.08 on near
#    bolts only, which is what makes the blue skeleton worth hunting and what makes it
#    unfilmable — a take would have to stand in a storm for minutes and might still come back
#    with nothing. See _beat_bolt for what is skipped and what is emphatically not.
#  - `WorldClock.running` is switched off for the length of the take. The clock's own countdown
#    would otherwise land a second, unaimed bolt somewhere in the middle of the performance —
#    LIGHTNING_MIN_GAP is 5 seconds against a ~26 second clip, so that is not a risk but a
#    near-certainty — and an 8% roll on THAT bolt could quietly turn one of the wave skeletons
#    blue in the final shot, which is the one frame where a second blue thing would read as the
#    upgrade having spread. `running` is the clock's own documented hook for being driven by
#    hand, so this is not a lie about the model so much as a pause on it.

## Where the bolt lands, 0.0 overhead to 1.0 on the horizon.
##
## Zero, and for three separate reasons that happen to agree. It is the brightest flash
## (SkyLighting.FLASH_PEAK_NEAR), it is the shortest delay before the thunder — so the crack
## arrives while the blue skeleton is still the newest thing on screen rather than a beat after
## it — and it is inside EnemySpawner.CHARGE_MAX_DISTANCE, which is the gate a real charging
## bolt has to pass. A clip that forced the charge from a horizon bolt would be showing an
## event the game cannot produce.
const CHARGED_BOLT_DISTANCE := 0.0

## How many times the net beat will close on the skeleton and swing before giving up.
##
## Three, matching the turret clip's swing count — but each attempt here re-walks rather than
## re-swinging on the spot, which is what makes three enough. See `_beat_net_charged`.
const CHARGED_NET_ATTEMPTS := 3

## Ceiling on one of those approaches, in seconds. Four tiles at the player's 50px/s is 1.3s, so
## this is generous for the first approach and is really sized for the later ones, where the
## skeleton is circling the player rather than standing where it was hit.
const CHARGED_CHASE_TIMEOUT := 5.0

## Deadbands for the chase, in pixels: closer than this on an axis and that axis stops being
## pushed on.
##
## Two numbers rather than one because the swing is not symmetric. The net sweeps roughly ten
## pixels ahead of the player and about seven to either side of him vertically, so horizontal
## alignment is what the catch is bought with and vertical alignment only has to be roughly
## right. A single tight band on both axes makes the player jitter on the spot between two
## opposing presses and never commit to the facing the swing is read from.
const CHASE_BAND_X := 4.0
const CHASE_BAND_Y := 5.0

## The hour the clip is shot at: the middle of night, the same value the devtools
## `set_time_of_day {"phase": "night"}` verb resolves to.
##
## Night rather than an overcast afternoon, and that is a lighting decision rather than a mood
## one. FLASH_PEAK_NEAR is tuned against a stormy night on purpose (see its comment) — 1.85 over
## that sky is bright and still blue, where the same gain at noon clips every channel and the
## flash reads as a dropped frame. It is also the only sky in which the charged skeleton's
## over-bright blue and the sparks off the charged turret are the brightest things in shot.
## Readability is not the risk it looks like: WorldClock.STORM_FLOOR exists precisely to stop a
## night storm going under the point where 16px art stops being identifiable.
const CHARGED_HOUR := (WorldClock.DUSK_END + 1.0) * 0.5

## The set, as offsets in tiles from the arena centre.
##
## The bounding box is x -4..4 and y -3..3, which is exactly BATTLE_HALF — so this clip can use
## the turret clip's `_find_arena` unchanged and gets its "all of this is dry land" guarantee
## for free. Growing the set past that box means the search starts refusing worlds it could
## have filmed, for the reason BATTLE_HALF's own comment gives.
##
## The two turrets sit four tiles apart vertically so each owns a lane the other cannot see:
## LineOfSight is a 40px circle (2.5 tiles) and the shortest cross distance from either turret
## to the other's lane is 4.1 tiles, so a skeleton in the charged lane is not also a target the
## ordinary turret is failing to shoot. Everything still fits the ±7 by ±4 tiles the camera
## shows at zoom 8 from `stand_watch`.
const CHARGED_SET := {
	# Centre of frame for the opening: the grey skeleton is four tiles to the player's left and
	# both turrets are two to his right, so the baseline and the payoff are in the first frame.
	"mark": Vector2i(0, 0),
	# Four tiles out, matching the turret clip's net beat and for its reason: outside the 30px
	# AGGRO_RANGE, so it wanders rather than charging before the bolt has landed, and close
	# enough that the walk which follows crosses into aggro on its last stretch.
	"skeleton": Vector2i(-4, 0),
	# Loaded before the clip starts and never touched again. This is the control, and it is
	# deliberately not placed on camera: the place-and-load beat is what the turret clip is
	# about, and doing it twice here would spend eight seconds establishing something this clip
	# only needs as a yardstick.
	"control_turret": Vector2i(2, -2),
	"charged_turret": Vector2i(2, 2),
	# One tile from the charged turret, which is well inside the 40px area
	# `GameItemChargedBoneEnemy.find_closest_loadable()` searches, and 4.1 tiles from the
	# control turret, which is well outside it. The skull could not go into the wrong machine
	# from here even if the control turret were empty — and it is not, which is the other half:
	# find_closest_loadable skips anything already `loaded`.
	"stand_load": Vector2i(1, 2),
	# The vantage for the last beat, and it is x=1 rather than x=2 for a mechanical reason. A
	# walk from `stand_load` runs its horizontal leg first, so ending at x=2 would send the
	# player straight into the charged turret's StaticBody2D and stall the walk against it.
	# Sharing stand_load's column makes that leg zero-length.
	"stand_watch": Vector2i(1, 0),
}

## The two volleys of the contrast beat, two skeletons per turret each time.
##
## Two per turret rather than one, because a turret holds a single target and re-acquires only
## when that one dies: with one each, the charged turret kills its skeleton in about two seconds
## and then stands idle through the rest of the shot, which is the opposite of the point. A
## spare in the lane keeps both turrets firing continuously, and a continuous stream is the only
## form in which a fire rate can actually be counted.
##
## Every cell is within 2.3 tiles of its own turret and at least 4.1 from the other. The second
## volley lands a tile closer in rather than on the first volley's marks, so reinforcements
## arrive on ground the survivors have already left instead of inside them.
const CHARGED_VOLLEY_ONE := [Vector2i(4, -2), Vector2i(4, -3), Vector2i(4, 2), Vector2i(4, 3)]
const CHARGED_VOLLEY_TWO := [Vector2i(3, -2), Vector2i(3, -3), Vector2i(3, 2), Vector2i(3, 3)]

## Beat lengths in seconds. The whole performance is about 26 seconds between the marks.
##
## Nothing here shortens a gameplay duration, which is worth stating because the worker clip's
## WORKER_CHOP does and the reader may be looking for its counterpart. The two numbers this clip
## exists to show — a 1.0s ordinary fire interval against a charged 0.55s — are the shipped ones,
## and they are legible unaltered: a bullet crosses the 40px LineOfSight in about a second, so
## the charged turret simply has two in the air whenever the ordinary one has one.
const CHARGED_BEAT := {
	# Longer than the other clips' settle because the rain has to be established before the
	# first kept frame. RainVfx starts emitting the instant the weather changes, but its
	# ambience tweens up over AUDIO_FADE, and a clip that opens on visible rain and silence
	# reads as the sound being broken rather than as a storm arriving.
	"settle": 1.5,
	# The grey baseline. Long enough to register the skeleton as an ordinary one, and no longer:
	# nothing is happening yet and the viewer knows it.
	"storm_hold": 3.0,
	# The money shot. The flash itself is over in SkyLighting.FLASH_DURATION (0.55s), so almost
	# all of this is the blue skeleton standing in the spot the grey one was, throwing sparks —
	# which is the comparison the beat exists to make and needs a still moment to be made in.
	"after_bolt": 2.8,
	"before_swing": 0.35,
	"after_capture": 1.2,
	"after_select": 0.45,
	# The charged turret goes blue and starts sparking on this frame and does nothing else until
	# the wave arrives, so this is the only chance to see the machine change.
	"after_load": 1.8,
	"before_wave": 0.6,
	# Set by how long one ORDINARY kill takes: four 3-damage bullets against 10 health, fired a
	# second apart and each about a second in flight, so ~4.1s. With the second volley's own
	# 1.0s telegraph on top of this, reinforcements land at ~4.5s — just after the ordinary lane
	# has finally dropped its first skeleton and well after the charged lane has cleared both of
	# its own, which is the moment the gap between the two is widest and most readable.
	"between_volleys": 3.5,
	"wave_hold": 5.0,
	"tail": 0.8,
}


func _run_charged_clip() -> void:
	var handler := _handler()
	var player := _player()
	if handler == null or player == null:
		_fail("no TileMapHandler or player in the scene")
		return

	var centre = _stage_storm(handler, player)
	if centre == null:
		_fail("found no all-land %sx%s battle rect within %s tiles of the player" % [
			BATTLE_HALF.x * 2 + 1, BATTLE_HALF.y * 2 + 1, ARENA_SEARCH,
		])
		return

	# A scene tile is instanced by the TileMap, not by the code that wrote the cell, so neither
	# turret exists as a node until the frames after `_place_turret` returns. Everything below
	# looks them up by cell rather than holding anything from staging.
	await _frames(2)
	_light_control_turret(handler, centre)

	await _wait(CHARGED_BEAT["settle"])
	_mark("show_start")

	await _beat_charged_storm()
	var charged: Enemy = await _beat_bolt()
	await _beat_net_charged(player, charged)
	await _beat_load_charged(handler, player, centre)
	await _beat_contrast(handler, player, centre)

	_mark("show_end")
	await _wait(CHARGED_BEAT["tail"])

	_restore_storm(player)
	_release_all()
	_beat = "done"
	_running = false


## Beat A — a night storm, and one ordinary grey skeleton in it.
##
## Nothing happens here and that is the beat. Without the grey baseline in shot first, the blue
## skeleton in beat B is just an enemy that happens to be blue; with it, the replacement is the
## event. The turrets are already in frame for the same reason — the one that will be upgraded
## is standing beside the one that will not, from the first kept frame.
func _beat_charged_storm() -> void:
	_beat = "storm"
	_mark("storm")
	await _wait(CHARGED_BEAT["storm_hold"])


## Beat B — the bolt lands on the skeleton and what gets up is a different enemy.
##
## Three calls, and every one of them is the game's own: `charge_random_skeleton` is what
## EnemySpawner._on_lightning_struck calls, `force_lightning` is what the storm's countdown
## calls, and `strike_bolt_at` is the line the spawner runs immediately afterwards to re-aim the
## arc onto the skeleton it picked. The only things skipped are the 0.08 roll and the distance
## gate — the same two `_cmd_charge_skeleton` skips, and for the same reason: they are what make
## this rare in play, which is exactly what makes it unfilmable by waiting.
##
## The order is load-bearing. Charging FIRST and firing second looks backwards and is not: the
## spawner's own handler runs on the `force_lightning` emit and would, 8% of the time, charge the
## skeleton itself — leaving the explicit call below with no plain skeleton to find and the beat
## reporting a failure on the one take in twelve where the game did the work. There is no `await`
## between the three, so all of it lands in a single frame and the screen shows one event.
##
## `strike_bolt_at` after `force_lightning` rather than instead of it. The first is what makes
## the bolt land on the skeleton; the second is what makes it a real strike — the flash, the
## thunder at the right volume and delay, and a storm that is genuinely mid-countdown rather than
## one frame of weather painted over a clear sky.
func _beat_bolt() -> Enemy:
	_beat = "bolt"
	_mark("bolt")

	var spawner := _spawner()
	if spawner == null:
		_note("no EnemySpawner to strike")
		return null

	# Deterministic despite the name: staging cleared every other enemy and spawned exactly one
	# skeleton, so the random pick has one candidate. Using the real function rather than
	# reaching for the node the director already holds is what keeps this clip honest about
	# which code path a charged skeleton comes out of.
	var struck: Enemy = spawner.charge_random_skeleton()
	if struck == null:
		_note("no plain skeleton alive to strike")
		return null

	var clock := _world_clock()
	if clock != null:
		clock.force_lightning(CHARGED_BOLT_DISTANCE)

	var sky := _sky_lighting()
	if sky != null:
		sky.strike_bolt_at(CHARGED_BOLT_DISTANCE, struck.global_position)
		# Repaint before the wait, for the reason every devtools setter here repaints before
		# replying: SkyLighting folds the flash into the tint from _process, and the frame this
		# runs in has already been through its own.
		sky.apply()

	await _wait(CHARGED_BEAT["after_bolt"])
	return struck


## Beat C — the player walks into it and takes it with the net.
##
## Netted, never killed, and the clip would be wrong if it were: EnemyRegistry gives the charged
## type a loot table barely better than a plain skeleton's precisely so that killing one is a
## loss. The capture IS the reward, so the capture is what gets filmed.
##
## Closing on the enemy rather than swinging on a timer, exactly as the turret clip does — it
## wanders while idle and charges once inside AGGRO_RANGE, so where it is at any given second is
## not knowable from here. Walking LEFT means the swing plays `Net_Left`; NET_REACH was measured
## against the mirrored animation and holds either way.
## Walks the player at `target` until it is inside NET_REACH, re-choosing the direction every
## frame, and reports whether he got there.
##
## Every frame rather than once, because the thing being walked at is an Enemy: it wanders while
## idle, charges once inside AGGRO_RANGE and circles the player once it is attacking, so a
## direction chosen when the beat began is stale by the time the walk arrives — and a player
## holding a direction the enemy is no longer in walks away from it for the whole timeout with
## nothing reporting anything wrong.
##
## The horizontal press is what sets `flip_h`, and `flip_h` is what PlayerNet reads to pick
## `Net_Left` over `Net_Right`. So the horizontal leg is deliberately the one that runs closest
## to the end: arriving on a purely vertical approach would leave the player swinging the net
## out of his back.
## `reach` defaults to NET_REACH and is a parameter because of the sword (see SWORD_REACH): the
## two bodies are solid to each other and stop at the sum of their half-widths, so the distance a
## net can be swung from is not one a sword beat can ask for.
##
## ## Why it also gives up when it stops closing
##
## `reach` is a request, and the physics does not have to grant it — how close two bodies actually
## come to rest is decided by their hard shapes, their SoftCollision, and which state the enemy is
## in while it happens. Measured against a raider it was 16px, then 18, then 22 on the recording
## itself. So the loop cannot be allowed to spend its whole `timeout` pressing into a target it is
## already touching: at eight seconds an approach and five approaches to the ceiling, that is the
## entire fight spent walking on the spot.
##
## Stalling is measured as "the smallest gap seen has not improved in CHASE_STALL", which is
## `EnemyFollow`'s own rule (measure displacement, never the velocity you wrote) applied to the
## player. Returning early is what lets the caller swing at what it is standing on rather than
## keep asking for a distance that is not available.
func _chase(player: Player, target: Enemy, timeout: float, reach: float = NET_REACH) -> bool:
	var waited := 0.0
	var held: Array = []
	var closest := INF
	var stalled := 0.0

	while waited < timeout:
		if not is_instance_valid(target):
			break
		var gap: Vector2 = target.global_position - player.global_position
		if gap.length() < reach:
			break

		if gap.length() < closest - CHASE_PROGRESS:
			closest = gap.length()
			stalled = 0.0
		else:
			stalled += _dev.get_process_delta_time()
			if stalled >= CHASE_STALL:
				break

		var want: Array = []
		if absf(gap.x) > CHASE_BAND_X:
			want.append("move_left" if gap.x < 0.0 else "move_right")
		if absf(gap.y) > CHASE_BAND_Y:
			want.append("move_up" if gap.y < 0.0 else "move_down")

		for action in held:
			if action not in want:
				_release(action)
		for action in want:
			if action not in held:
				_press(action)
		held = want

		await _dev.get_tree().process_frame
		waited += _dev.get_process_delta_time()

	for action in held:
		_release(action)
	return is_instance_valid(target) \
		and player.global_position.distance_to(target.global_position) < reach


## Walks the player onto the target's ROW and up beside it, and reports whether a swing thrown now
## would reach. The sword's counterpart to `_chase`; see SWING_BAND_Y for why the two differ.
##
## Vertical is pressed on a tighter band than horizontal because vertical is the axis the hit
## depends on: being a pixel too far along the row costs nothing, being half a tile above the
## target costs the whole swing. The horizontal press stops at SWORD_REACH rather than at zero so
## the player walks *beside* the enemy rather than into it — pressing into a body he cannot pass
## through is what `_chase`'s stall detection exists to cut short, and not doing it at all is
## better.
##
## Ends on alignment rather than on distance, and on the same stall rule as `_chase`: how close two
## bodies come to rest is not something this side of the loop gets to choose.
func _close_for_swing(player: Player, target: Enemy, timeout: float) -> bool:
	var waited := 0.0
	var held: Array = []
	var closest := INF
	var stalled := 0.0
	var sidestep := 0.0
	var sidesteps := 0

	while waited < timeout:
		if not is_instance_valid(target):
			break
		var gap: Vector2 = target.global_position - player.global_position
		var off_row := absf(gap.y - SWING_OFFSET_Y)
		if off_row <= SWING_BAND_Y and absf(gap.x) <= SWORD_REACH:
			break

		# Progress is measured on the thing being optimised — how far the player still is from
		# standing beside the target — so drifting sideways along a wall does not read as progress.
		var togo := off_row + maxf(0.0, absf(gap.x) - SWORD_REACH)
		if togo < closest - CHASE_PROGRESS:
			closest = togo
			stalled = 0.0
		elif sidestep <= 0.0:
			stalled += _dev.get_process_delta_time()
			if stalled >= CHASE_STALL:
				sidesteps += 1
				if sidesteps > SWING_SIDESTEPS:
					break
				# A fresh baseline, or the sidestep's own outward movement counts as failure to
				# make progress and the next stall fires the moment it ends.
				stalled = 0.0
				closest = INF
				sidestep = SWING_SIDESTEP_TIME

		var want: Array = []
		if sidestep > 0.0:
			sidestep -= _dev.get_process_delta_time()
			# Out from under it, and keep pressing toward its row while doing so. See
			# SWING_SIDESTEP_TIME: the raider follows, which is what produces the alignment.
			want.append("move_right" if gap.x < 0.0 else "move_left")
			if off_row > SWING_BAND_Y * 0.5:
				want.append("move_up" if gap.y < SWING_OFFSET_Y else "move_down")
			_apply_held(want, held)
			held = want
			await _dev.get_tree().process_frame
			waited += _dev.get_process_delta_time()
			continue

		if off_row > SWING_BAND_Y * 0.5:
			want.append("move_up" if gap.y < SWING_OFFSET_Y else "move_down")
		if absf(gap.x) > SWORD_REACH:
			want.append("move_left" if gap.x < 0.0 else "move_right")

		_apply_held(want, held)
		held = want

		await _dev.get_tree().process_frame
		waited += _dev.get_process_delta_time()

	for action in held:
		_release(action)
	if not is_instance_valid(target):
		return false

	var arrived: Vector2 = target.global_position - player.global_position
	return absf(arrived.y - SWING_OFFSET_Y) <= SWING_BAND_Y 		and absf(arrived.x) <= SWORD_SWING_ENVELOPE


## Throws one sword swing at `target` and reports whether it actually took health off it.
##
## This is the only honest answer to "did that swing land", and getting here took three failed
## takes' worth of reasoning about hitbox geometry that kept being *nearly* right. The swing
## animation plays identically whether it connects or not — it is `PlayerNet`'s problem in a new
## place, and NET_REACH's own comment says so — and the enemy gives no signal either, so a beat
## that swings and moves on cannot tell a fight from a mime.
##
## `health_manager.current_health` is readable from here because this runs inside the game rather
## than over the devtools bus, where a RefCounted comes back as an opaque object id. It is worth
## saying out loud that this measures the OUTCOME rather than the setup: whatever the true shape of
## the sweep is, and whichever of the four attack animations played, a swing that took health off
## the thing it was aimed at is a swing that landed.
func _swing_at(player: Player, target: Enemy, pause: float) -> bool:
	var before := _health_of(target)
	await _wait(pause)
	await _use()
	await _wait(SWING_SETTLE)

	# Dead is the strongest possible form of landed.
	if not is_instance_valid(target):
		return true
	return _health_of(target) < before


func _health_of(target: Enemy) -> int:
	if not is_instance_valid(target) or target.health_manager == null:
		return -1
	return target.health_manager.current_health


## Steps out from beside the target and over to its other side, so the next swing comes in at a
## different angle instead of repeating one that just missed.
##
## Horizontal first, and that order is what makes it work: the reason a swing misses an adjacent
## enemy is almost always that the enemy is directly above the player, and the vertical press that
## would fix that is pressing into the body it is trying to get past. Stepping aside first is what
## makes the vertical step available at all — the same insight as SWING_SIDESTEP_TIME, applied
## after a miss rather than after a stall.
func _reposition(player: Player, target: Enemy) -> void:
	if not is_instance_valid(target):
		return
	var gap: Vector2 = target.global_position - player.global_position
	await _hold("move_right" if gap.x < 0.0 else "move_left", SWING_SIDESTEP_TIME)
	if not is_instance_valid(target):
		return
	gap = target.global_position - player.global_position
	await _hold("move_up" if gap.y < SWING_OFFSET_Y else "move_down", SWING_SIDESTEP_TIME)


## Presses everything in `want` that is not already held and releases everything held that is no
## longer wanted. Split out because `_close_for_swing` drives two different sets of presses — the
## approach and the sidestep — and doing that twice inline is how one of them ends up leaking a
## held key into the other.
func _apply_held(want: Array, held: Array) -> void:
	for action in held:
		if action not in want:
			_release(action)
	for action in want:
		if action not in held:
			_press(action)


func _beat_net_charged(player: Player, charged: Enemy) -> void:
	_beat = "net_charged"
	_mark("net_charged")

	if not is_instance_valid(charged):
		_note("nothing charged to net")
		return
	if not _select(Types.Item.Net):
		_note("no net in the hotbar")
		return

	# Approach and swing are one loop, not two phases, and three dry runs are the reason. A
	# single hold of `move_left` followed by three swings on the spot failed two takes in three,
	# and it failed them differently: once the skeleton had wandered past the player before the
	# walk began, so eight seconds of holding left simply carried him away from it; once the
	# swings all met air because the thing being swung at had moved on between the arrival test
	# and the first frame of the animation. Both are the same mistake — deciding once where the
	# enemy is, against something whose whole behaviour is that it moves.
	var caught := false
	for _attempt in CHARGED_NET_ATTEMPTS:
		if not await _chase(player, charged, CHARGED_CHASE_TIMEOUT):
			break
		await _wait(CHARGED_BEAT["before_swing"])
		await _use()
		await _wait(SWING_SETTLE)
		caught = _has(player, Types.Item.ChargedBoneEnemy)
		if caught:
			break

	if not caught:
		if is_instance_valid(charged):
			_note("the net beat finished without a charged skull in the inventory")
			charged.queue_free()
		else:
			_note("the charged skeleton was gone before the net reached it")

	await _wait(CHARGED_BEAT["after_capture"])


## Beat D — the skull goes into the empty turret, which turns blue.
##
## The walk is not decoration. `GameItemChargedBoneEnemy.use()` searches the areas the player's
## own Area2D overlaps, so from anywhere else the press finds nothing, `can_use()` refuses it and
## the stack is (correctly) not spent — which on film is a player fumbling at the air.
##
## Asserted on `charged` rather than on `loaded`, and the distinction is the whole beat: a skull
## that loaded the turret without charging it would leave an ordinary turret standing where the
## payoff should be, and the last beat would then be two identical turrets firing at the same
## rate with nothing to say about it.
func _beat_load_charged(handler: TileMapHandler, player: Player, centre: Vector2i) -> void:
	_beat = "load_charged"
	_mark("load_charged")

	var cell: Vector2i = centre + CHARGED_SET["charged_turret"]
	var turret = _turret_at(handler, cell)
	if turret == null:
		_note("no turret at %s to load" % [cell])
		return

	await _walk_to(handler, player, centre + CHARGED_SET["stand_load"])

	if not _select(Types.Item.ChargedBoneEnemy):
		_note("no charged skull in the hotbar to load")
		return
	await _wait(CHARGED_BEAT["after_select"])

	await _use()
	await _frames(4)

	if not turret.charged:
		_note("the load press did not charge the turret at %s" % [cell])
	await _wait(CHARGED_BEAT["after_load"])


## Beat E — the payoff, and the only shot in the clip that holds two things at once.
##
## The player steps into the gap between the two turrets and two volleys of skeletons arrive,
## split between their lanes. From there the difference is arithmetic anyone can do by eye: over
## the nine or so seconds there is anything to shoot at, the ordinary turret fires about nine
## times and the charged one about seventeen — and each of the charged bullets takes five off a
## skeleton where the ordinary ones take three.
##
## Through `_telegraph_wave` rather than by spawning directly, so the reinforcements arrive
## behind the spawner's own `X` tile — the way the game announces a spawn, instead of popping
## into the middle of the shot.
func _beat_contrast(handler: TileMapHandler, player: Player, centre: Vector2i) -> void:
	_beat = "contrast"
	_mark("contrast")

	await _walk_to(handler, player, centre + CHARGED_SET["stand_watch"])
	await _wait(CHARGED_BEAT["before_wave"])

	await _telegraph_wave(handler, _offset_cells(centre, CHARGED_VOLLEY_ONE))
	await _wait(CHARGED_BEAT["between_volleys"])
	await _telegraph_wave(handler, _offset_cells(centre, CHARGED_VOLLEY_TWO))
	await _wait(CHARGED_BEAT["wave_hold"])


# --- charged staging ------------------------------------------------------------------

## Puts the world into the state the clip opens on, and returns the arena centre — or null when
## the world has no rectangle of solid land big enough, which `_find_arena` documents as a real
## outcome rather than a defensive check.
func _stage_storm(handler: TileMapHandler, player: Player):
	_beat = "staging"

	var centre = _find_arena(handler, player)
	if centre == null:
		return null

	_freeze_ambient()
	_clear_enemies()
	_clear_arena(handler, centre)

	player.position = handler.tileMap.map_to_local(centre + CHARGED_SET["mark"])
	player.velocity = Vector2.ZERO

	# The turret clip's lie, told again and for a stronger reason: a charged skeleton hits for 5
	# rather than 3, and beat E walks four more skeletons into the player's lap while he stands
	# still watching the turrets. A death would teleport him out of frame and take the camera
	# with him. Undone in `_restore_storm` once the recording is over.
	player.invulnerable = true

	_set_zoom(player, CLOSE_ZOOM)
	_hide_fps()
	_stock_net(player)

	# Straight onto the tilemap, which is the same end state a hotbar press reaches. The placing
	# beat belongs to the turret clip; here the turrets are the set, not the subject.
	_place_turret(handler, centre + CHARGED_SET["control_turret"])
	_place_turret(handler, centre + CHARGED_SET["charged_turret"])

	_open_storm()
	_spawn_enemy(handler, centre + CHARGED_SET["skeleton"])
	return centre


## Night, rain, and a clock that has stopped ticking.
##
## `set_weather` rather than a raw write to `weather`, so every consumer that reacts to the
## signal reacts: RainVfx starts its drops and its ambience, SkyLighting takes the storm tint,
## and the lightning countdown is armed. A whole storm's worth of seconds rather than a sliver,
## so that when `running` goes back on at the end the sky is still one the game could be in.
##
## `running = false` is the clock's own documented hook for being driven by hand, and it is set
## AFTER the weather so the storm is fully established first. Without it the countdown keeps
## running underneath the performance — LIGHTNING_MIN_GAP is 5 seconds against a 26 second clip
## — and every bolt it fired would land somewhere the camera is not looking, with an 8% chance
## of turning one of the wave skeletons blue in the final shot. Two blue things in that frame
## would read as the upgrade spreading, which is not a thing the game does.
func _open_storm() -> void:
	var clock := _world_clock()
	if clock == null:
		_note("no WorldClock: the clip would be shot in whatever weather the world was already in")
		return

	clock.set_time_of_day(CHARGED_HOUR)
	clock.set_weather(
		WorldClock.Weather.RAIN,
		WorldClock.RAIN_MAX_FRACTION * WorldClock.DAY_LENGTH_SECONDS
	)
	clock.running = false

	# Repaint immediately rather than waiting for SkyLighting's next _process, so the settle
	# beat is spent on a sky that has already gone dark instead of one that darkens during it.
	var sky := _sky_lighting()
	if sky != null:
		sky.apply()


## Hands the world back in a state it could have reached on its own.
##
## Both halves matter and neither is tidiness. An invulnerable player is not a state the game
## has, and a clock that never ticks is a world where the storm never ends and the sun never
## comes up — either one left behind would make the next thing to use this instance (a second
## clip, a devtools session, someone poking at the game after a take) quietly wrong in a way
## nothing reports. The storm itself is deliberately NOT cleared: rain is perfectly reachable,
## and `force_lightning` left a full fresh gap on the countdown, so restarting the clock simply
## resumes a storm that will expire when it was always going to.
func _restore_storm(player: Player) -> void:
	player.invulnerable = false

	var clock := _world_clock()
	if clock != null:
		clock.running = true


## The net, and nothing else, in the first hotbar slot.
##
## Deliberately a bag with one thing in it. The catch drops a Charged Skull into the slot beside
## it and spends the net out of the first, so the hotbar itself shows the trade happening — which
## is the clearest statement anywhere in the clip that this is caught rather than killed. A full
## starting kit would bury both changes among five other icons.
func _stock_net(player: Player) -> void:
	var slots: Array = player.inventory_data.inventory_slot_datas
	for index in mini(6, slots.size()):
		slots[index] = null

	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(Types.Item.Net), 1))
	player.inventory_data.inv_updated()


## Assembles the control turret, so the last beat compares two working turrets rather than a
## working one and a prop.
func _light_control_turret(handler: TileMapHandler, centre: Vector2i) -> void:
	var cell: Vector2i = centre + CHARGED_SET["control_turret"]
	var control = _turret_at(handler, cell)
	if control == null:
		_note("no control turret at %s to assemble" % [cell])
		return
	control.set_loaded()


## The turret standing on `cell`, or null. Matched on the cell rather than held from the
## placement call, because a scene tile is instanced by the TileMap and the placing code never
## sees the node it created — the same reason `_worker_at` exists.
func _turret_at(handler: TileMapHandler, cell: Vector2i):
	for turret in _turrets():
		if handler.tileMap.local_to_map(turret.position) == cell:
			return turret
	return null


## The clock and the lighting, both by group.
##
## Neither has a path this file can rely on: main.gd creates SkyLighting at runtime as a direct
## child of Main, and WorldClock lives under `Systems`, which is declared last. The clock
## registers its group in `_enter_tree` precisely so a lookup like this one works regardless of
## tree order.
func _world_clock() -> WorldClock:
	for node in _dev.get_tree().get_nodes_in_group("WorldClock"):
		if node is WorldClock:
			return node
	return null


func _sky_lighting() -> SkyLighting:
	for node in _dev.get_tree().get_nodes_in_group("SkyLighting"):
		if node is SkyLighting:
			return node
	return null


# --- the raid clip --------------------------------------------------------------------
#
# From night three the dark comes to you (gather-0ez): the horn and the banner, a sized wave
# walking in out of the black, the fight at the wall, and the clear that pays for it.
#
# Shot on the demo homestead save, like the worker clip and unlike the other three. A raid is
# the answer to a question only a built base asks — the whole feature exists so that walls,
# doors and turrets have something to stand between the player and — and staged on empty
# starting grass it would be five skeletons walking at a man in a field, which is what night
# looked like BEFORE this shipped. The base has to be in shot or the clip argues the opposite
# of its subject.
#
# ## The one number this clip changes, and the arithmetic that forces it
#
# See RAID_SPEED. Every other number below is the shipped one, including the two the clip is
# actually about: the night's size curve and the per-raider clear bonus.

## Which save slot the raid clip loads. Slot 3, the demo homestead — the same world and the same
## one-word change as WORKER_SLOT, whose comment explains why the slot rather than the fixture
## path is what is written down here.
const RAID_SLOT := 3

## The night the clip declares a raid for, chosen off `RaidDirector.size_for_day`: night 6 sends
## five raiders at 1.24x health.
##
## Five rather than three. Night 3's raid is deliberately the small one a new player can lose to
## and still learn from, and three skeletons at a walled house with turrets on it is a scuffle
## rather than a raid — the clip would be showing the feature at its least like itself. Five is
## the first size where the stagger reads as a *wave* (they arrive in twos rather than in
## sequence) and is still inside what one player with one sword can clear on camera. Twelve, the
# cap, is a different clip and a much longer one.
const RAID_NIGHT := 6

## What raiders' `EnemyFollow.move_speed` is raised to for the recording, against the 10 a bone
## skeleton ships with.
##
## **This is the clip's one lie about a number**, in the WORKER_CHOP tradition, and the
## arithmetic is what forces it. `RaidDirector._pick_spawn_cell` puts a raider at least
## MIN_SPAWN_DISTANCE (200px) from the player — that is the whole point of it, raiders are *seen
## arriving* rather than seen appearing — and on a maxed island the cell it finds is routinely
## 200 to 500px out. At the shipped 10px/s that is twenty to fifty seconds of empty grass between
## the banner and the first raider, in a clip with about thirty seconds in total. The game can
## afford that wait because a night is three minutes long and the player spends it preparing;
## the clip cannot, because here the wait IS the footage.
##
## 45 rather than something larger: it is within half a tile per second of the shipped raider
## SPIDER speed (30) and of the elite's (32), so a hastened raider still moves like something in
## this game rather than like a bug. It also keeps the arrival staggered — five raiders spawned
## 1.6s apart at 45px/s still reach the player in twos, which is the shape the stagger exists to
## produce and the thing a faster number would flatten into a single clump.
##
## Applied every frame rather than once, for `_compress_work`'s reason: raiders arrive over about
## nine seconds, so a single sweep at the top of the beat would only reach the ones already out.
const RAID_SPEED := 45

## How close the nearest raider has to get before the arrival beat hands over to the fight.
##
## Seven tiles, which is VIEW_HALF.x — so the beat ends on the frame the first raider is actually
## in shot, rather than after a number of seconds guessed from a walking speed and a spawn
## distance that are both different every take.
const RAID_ARRIVAL_REACH := 112.0

## Ceiling on that walk. Five hundred pixels at RAID_SPEED is eleven seconds, and `EnemyFollow`'s
## sidestep costs a stuck raider up to SIDESTEP_TIME per obstacle on the way — a homestead has
## walls in it. Twenty is generous rather than tight on purpose: this timeout expiring means the
## raid is not coming, which is a note worth trusting.
const RAID_ARRIVAL_TIMEOUT := 20.0

## Ceiling on the whole fight, and on one approach inside it.
##
## The fight is five one-hit kills with a walk between each, so about twelve seconds; the rest is
## slack for a raider that goes around the house rather than through the gap, and for the turrets
## taking one down at the far end of their own LineOfSight while the player is busy elsewhere.
## Both are sized by the straggler rather than by the fight, and the fight is not the expensive
## part: five raiders that all arrive are dealt with in about twelve seconds. What costs is the one
## raider that wedges on the far side of the base — measured at 319px in one dry run and 344px in a
## recording, both at full health, meaning it had never reached the player at all. There is no
## baked navigation in this game (see CLAUDE.md), so neither the raider nor the player can route
## around a house; what actually resolves it is `EnemyFollow`'s sidestep freeing the raider while
## the player walks toward it, and that needs room to happen in. Twenty-one tiles at the player's
## 50px/s is seven seconds of walking before a swing is even possible.
const RAID_FIGHT_TIMEOUT := 55.0
const RAID_CHASE_TIMEOUT := 16.0

## How close a raider has to be before the player goes to meet it, and how long the field has to
## stay quiet before he goes looking anyway.
##
## The first cut chased the nearest raider from wherever it was, and it failed one dry run in
## three — twice the raid ran out its forty seconds with two raiders left, and the same forty
## seconds produced takes of 28 and 66 wall-clock seconds. The cause is that a raider has
## obstacle logic and the player does not: `EnemyFollow` measures actual displacement and
## sidesteps along whatever it is pressed against, while `_chase` is a held direction, so a
## player sent across his own homestead at something behind a wall pushes into that wall for the
## whole approach timeout and then does it again.
##
## So the player holds his ground and lets them come, which is more robust for the same reason it
## is better footage: raiders hunt from `hunt_range` 4000, so every one of them is already walking
## at him, and standing at the wall you built while they arrive is the decision this entire
## feature exists to create. RAID_PATIENCE is the escape hatch for the genuinely wedged one — if
## nothing has been in reach for that long, the field really has gone quiet and it is worth
## walking out.
const RAID_HOLD_RANGE := 40.0
const RAID_PATIENCE := 2.5

## Half-extents of the apron the fight needs: land, unbuilt, and walkable.
##
## Deliberately small. Scoring a big clearing beside a house asks for something a finished base
## does not have — its owner built on the flat ground — and BATTLE_HALF's comment records what
## that costs: a search that refuses worlds it could have filmed. Three by two is room for the
## player to back up and swing without the chase wedging him on his own wall, and no more.
const RAID_FIGHT_HALF := Vector2i(3, 2)

## The hour the clip is shot at: the middle of night, the same value `set_time_of_day
## {"phase": "night"}` resolves to and the same constant the charged clip is framed on.
##
## Night rather than dusk, and it is not only mood. `RaidDirector._process` ends any raid it finds
## running outside `WorldClock.is_night()`, so a clip staged in the twilight would be racing the
## clock to finish before dawn cancelled the thing it is filming — which is the same trap the
## `start_raid` devtools verb moves the clock for.
const RAID_HOUR := (WorldClock.DUSK_END + 1.0) * 0.5

## Beat lengths in seconds. The performance runs about thirty between the marks, most of it the
## arrival and the fight — both of which end on a condition rather than on a clock, so those two
## are ceilings above rather than entries here.
const RAID_BEAT := {
	"settle": 0.8,
	# The quiet before. Long enough to read the base and the dark as the state of things, which
	# is what the announcement then interrupts — an announcement over an establishing shot that
	# has not landed yet is just the first thing that happens.
	"dark_hold": 2.6,
	# Covers RaidDirector.TELEGRAPH_SECONDS (3.0) and a little: the splash, the flash, the shake
	# and the horn all land on the first frame of this and nothing is on the map until the end of
	# it, which is exactly the beat the telegraph exists to buy the player.
	"announce": 3.4,
	"before_swing": 0.3,
	# After the last raider goes down: the RAID REPELLED splash, the coin purse landing and
	# vacuuming in, and the xp. All three are the payout, and the clip has no other reason to
	# still be running.
	"cleared_hold": 3.6,
	"tail": 0.8,
}


func _run_raid_clip() -> void:
	if not _load_slot(RAID_SLOT):
		_fail("could not load save slot %d" % RAID_SLOT)
		return
	# A load rebuilds most of the world, and the scene tiles it re-instances are not in the tree
	# — so not in their groups, and not findable — until the frames after it returns.
	await _frames(4)

	var handler := _handler()
	var player := _player()
	if handler == null or player == null:
		_fail("no TileMapHandler or player after loading slot %d" % RAID_SLOT)
		return

	var director := _raid_director()
	if director == null:
		_fail("no RaidDirector in the scene, so there is no raid to film")
		return

	var centre = _stage_raid(handler, player, director)
	if centre == null:
		_fail("no clear %sx%s apron with a base in frame within %s tiles of where slot %d put the player" % [
			RAID_FIGHT_HALF.x * 2 + 1, RAID_FIGHT_HALF.y * 2 + 1, ARENA_SEARCH, RAID_SLOT,
		])
		return

	# Everything above this line is setup and is expected to be trimmed off the front of the
	# recording; everything below it is the clip.
	await _wait(RAID_BEAT["settle"])
	_mark("show_start")

	await _beat_raid_watch()
	await _beat_raid_call(director)
	await _beat_raid_arrival(player, director)
	await _beat_raid_fight(player, director)
	await _beat_raid_cleared(director)

	_mark("show_end")
	await _wait(RAID_BEAT["tail"])

	_release_all()
	_beat = "done"
	_running = false


## Beat A — night at the homestead, and nothing happening.
##
## The same job as the charged clip's grey skeleton: without the quiet first, the banner is the
## opening title rather than an interruption. What the frame holds — the walls, the turrets, the
## chests — is also the argument the rest of the clip makes, so it is established before anything
## is asked of it.
func _beat_raid_watch() -> void:
	_beat = "raid_watch"
	_mark("raid_watch")
	await _wait(RAID_BEAT["dark_hold"])


## Beat B — the horn. `NIGHT 6 — RAID` in three registers at once and a banner counting five.
##
## Through `RaidDirector.start_raid`, which is the game's own entry point and what the clock calls
## at nightfall — so the splash, the screen flash, the shake, the thunder, the telegraph and the
## banner all come from the code that would have run anyway. The clip chooses the *night*, not
## the announcement.
##
## The size is asserted rather than assumed. `start_raid` returns 0 for a night that does not
## raid, and a clip that filmed a quiet night would run to completion showing an empty base with
## a banner that never appeared — success, and nothing on screen.
func _beat_raid_call(director: RaidDirector) -> void:
	_beat = "raid_call"
	_mark("raid_call")

	var size := director.start_raid(RAID_NIGHT)
	if size <= 0:
		_note("night %d declared no raiders" % RAID_NIGHT)
		return

	await _wait(RAID_BEAT["announce"])

	var banner := _raid_banner()
	if banner != null and not banner.is_showing():
		_note("the raid started but the banner never came on screen")


## Beat C — they arrive. The wave crosses the island in the dark and the first of it walks into
## frame.
##
## Ends on the first raider being inside RAID_ARRIVAL_REACH rather than after a fixed wait, and
## that is the same rule the worker clip's delivery beat follows: where a walking thing has got to
## is not knowable from here, and the only honest thing to wait on is the arrival itself.
##
## `_hasten_raiders` runs every frame of it. See RAID_SPEED for what it changes and why the clip
## cannot be shot without it.
func _beat_raid_arrival(player: Player, director: RaidDirector) -> void:
	_beat = "raid_arrival"
	_mark("raid_arrival")

	var arrived := await _until(func() -> bool:
		_hasten_raiders()
		var nearest := _nearest_raider(player)
		return nearest != null \
			and player.global_position.distance_to(nearest.global_position) <= RAID_ARRIVAL_REACH,
		RAID_ARRIVAL_TIMEOUT)

	if not arrived:
		_note("no raider came within %.0fpx in %.0fs; %d were still owed" % [
			RAID_ARRIVAL_REACH, RAID_ARRIVAL_TIMEOUT, director.remaining()])


## Beat D — the fight. The player takes them as they come and the turrets take what he does not.
##
## One loop that re-chooses its target every pass rather than a list decided up front, which is
## the `charged` clip's lesson applied to five moving things instead of one: raiders are still
## arriving while this runs, the turrets are killing them in an order nobody chose, and a target
## picked when the beat opened may be dead or across the base by the time the swing lands.
##
## The exit condition is the director's own `remaining()` — standing plus still to arrive — and
## not "no raiders on screen". Those differ for the whole middle of the beat, and stopping on the
## second would cut away from a raid the banner still says is running.
func _beat_raid_fight(player: Player, director: RaidDirector) -> void:
	_beat = "raid_fight"
	_mark("raid_fight")

	if not _select(Types.Item.GoldSword):
		_note("no sword in the hotbar to meet the raid with")
		return

	# A SceneTreeTimer rather than an accumulator, because the loop below spends most of its time
	# inside `_chase` and `_use`, neither of which reports how long it took — summing what this
	# level of the loop can see would undercount the beat by most of its length. The timer counts
	# process time, which is game time, which under the movie writer is exactly frames/fps.
	var deadline := _dev.get_tree().create_timer(RAID_FIGHT_TIMEOUT)
	var quiet := 0.0

	while deadline.time_left > 0.0 and director.raid_active:
		_hasten_raiders()

		var target := _nearest_raider(player)
		if target == null:
			# Nothing standing, but the raid is still open: the stagger has more to send. Waiting a
			# frame keeps `_hasten_raiders` running over the ones still walking in.
			await _dev.get_tree().process_frame
			continue

		var gap := player.global_position.distance_to(target.global_position)
		if gap > RAID_HOLD_RANGE and quiet < RAID_PATIENCE:
			# Hold the line. See RAID_HOLD_RANGE — they are all already coming.
			await _dev.get_tree().process_frame
			quiet += _dev.get_process_delta_time()
			continue

		quiet = 0.0
		# `_close_for_swing`, not `_chase`: this is a sword, and lining up on the target's row is
		# what makes the difference between a swing and a swing at air. See SWING_BAND_Y.
		if await _close_for_swing(player, target, RAID_CHASE_TIMEOUT):
			# And the swing is checked rather than assumed. Two dry runs ended with the last raider
			# nine pixels from the player, being swung at and not dying — see `_swing_at`.
			if not await _swing_at(player, target, RAID_BEAT["before_swing"]):
				await _reposition(player, target)

	if director.raid_active:
		# The survivor's distance, because "two left" has two causes that want opposite fixes: two
		# raiders still walking in (the arrival was slower than the fight ceiling) and two wedged
		# on terrain a dozen tiles away (they are never arriving). The number tells them apart.
		var survivor := _nearest_raider(player)
		var away := player.global_position.distance_to(survivor.global_position) \
			if survivor != null else -1.0
		_note("the raid was still running after %.0fs with %d left, nearest %.0fpx away on %d health" % [
			RAID_FIGHT_TIMEOUT, director.remaining(), away, _health_of(survivor)])


## Beat E — RAID REPELLED, and the purse.
##
## `raids_cleared` is what gets asserted, not `raid_active`, and the difference is the whole
## feature: dawn also ends a raid, pays nothing and leaves the survivors alive. A clip that
## checked only "is it over" would happily film a night the player *survived* while the README
## line under it said cleared.
func _beat_raid_cleared(director: RaidDirector) -> void:
	_beat = "raid_cleared"
	_mark("raid_cleared")

	if director.raids_cleared <= 0:
		_note("the raid ended without being cleared")
	await _wait(RAID_BEAT["cleared_hold"])


# --- raid staging ---------------------------------------------------------------------

## Puts the loaded save into the night the clip opens on, and returns the rampart cell — or null
## when the save has nowhere to fight that still has the base in shot.
func _stage_raid(handler: TileMapHandler, player: Player, director: RaidDirector):
	_beat = "staging"

	var centre = _find_rampart(handler, player)
	if centre == null:
		return null

	_freeze_ambient()
	_clear_enemies()
	# Every worker in the save belongs to the save, not to the clip; see `_still_existing_workers`.
	# It matters more here than in the worker clip, because a wandering skeleton in a shot whose
	# whole subject is *incoming skeletons* is not merely a distraction, it is a wrong answer.
	_still_existing_workers()

	player.position = handler.tileMap.map_to_local(centre)
	player.velocity = Vector2.ZERO
	# The turret clip's lie, for the turret clip's reason: five raiders at three damage a hit will
	# kill this player, and a death teleports him to the respawn point with the camera attached.
	player.invulnerable = true

	_set_zoom(player, CLOSE_ZOOM)
	_hide_fps()
	_stock_raid_kit(player)

	# The raid the clip runs is the one it declares, on the night it chose. `running = false` stops
	# the clock opening a *second* one underneath it when the hour below crosses into darkness —
	# `_on_night_started` fires on that crossing, and the day the demo save is on is not the night
	# this clip is about. It gates only that handler: `_process` still spawns, still counts and
	# still pays, so everything the clip films is the real thing.
	director.running = false

	var clock := _world_clock()
	if clock != null:
		# Clear rather than whatever the save was under. A raid IS the weather in this clip, and a
		# storm over it would put lightning, rain and a second set of tint writes on top of the one
		# event the frame is meant to be about.
		clock.set_weather(WorldClock.Weather.CLEAR, 0.0)
		clock.set_time_of_day(RAID_HOUR)

	var sky := _sky()
	if sky != null:
		sky.apply()
	return centre


## The rampart: a cell with a clear apron to fight in and as much of the player's own base in
## frame as the search can find.
##
## Ranked on built cells in view, then nearness — `_find_pocket`'s scoring, and for exactly its
## reason. Clear ground is abundant on a maxed island and the nearest clear apron is out in a
## field, which would film a raid against grass and quietly make the opposite of this feature's
## argument. What differs from the pocket is the requirement: this one wants ground to *fight* on
## rather than ground to build on, so it tests a rectangle around the stand rather than a set of
## named cells.
func _find_rampart(handler: TileMapHandler, player: Player):
	var origin: Vector2i = handler.tileMap.local_to_map(player.global_position)
	var best = null
	var best_key := [-1, -(1 << 30)]

	for dy in range(-ARENA_SEARCH, ARENA_SEARCH + 1):
		for dx in range(-ARENA_SEARCH, ARENA_SEARCH + 1):
			var candidate := origin + Vector2i(dx, dy)
			if not _apron_clear(handler, candidate):
				continue
			var key := [_built_around(handler, candidate), -(dx * dx + dy * dy)]
			if key > best_key:
				best = candidate
				best_key = key
	return best


## Whether the fight apron around `centre` is land and unbuilt.
##
## `is_occupied(cell, true)` is the game's own build test and answers both halves at once: it is
## false for open water (no ground tile) and false for anything already standing there. A raid
## fought half in the sea is the `_spawn_enemy` bug in another place, and a chase through the
## player's own wall is `EnemyFollow`'s sidestep spending the whole beat.
func _apron_clear(handler: TileMapHandler, centre: Vector2i) -> bool:
	for y in range(-RAID_FIGHT_HALF.y, RAID_FIGHT_HALF.y + 1):
		for x in range(-RAID_FIGHT_HALF.x, RAID_FIGHT_HALF.x + 1):
			if handler.is_occupied(centre + Vector2i(x, y), true):
				return false
	return true


## The kit: one gold sword, into the first slot.
##
## A gold sword rather than the starting one, and it is a pacing decision with a number behind it.
## A night-6 raider is 12 health; the starting Sword is 4 damage, so it is three swings and a
## re-approach each — about forty seconds of the same animation for five raiders, in a clip with
## thirty. Gold is 13, so each raider is one committed swing, which is also what a player who has
## reached night 6 with a furnace in their base is actually holding.
##
## Only the first two slots are cleared, not all six — `_stock_worker_kit`'s reason: the save's own
## wood and stone stay visible in the hotbar, and a defended base whose owner is carrying nothing
## reads as a diorama.
func _stock_raid_kit(player: Player) -> void:
	var slots: Array = player.inventory_data.inventory_slot_datas
	for index in mini(2, slots.size()):
		slots[index] = null

	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(Types.Item.GoldSword), 1))
	player.inventory_data.inv_updated()


## Raises every live raider's follow speed. See RAID_SPEED.
##
## Guarded on the current value rather than assigned unconditionally, which costs nothing and
## makes the function safe to call every frame — the same shape as `_compress_work`, and for the
## same reason: the things it acts on arrive after it first runs.
func _hasten_raiders() -> void:
	for node in _dev.get_tree().get_nodes_in_group("Enemy"):
		if not (node is Enemy) or not EnemyRegistry.is_raider(node.type):
			continue
		var follow := node.get_node_or_null("StateMachine/EnemyFollow") as EnemyFollow
		if follow != null and follow.move_speed < RAID_SPEED:
			follow.move_speed = RAID_SPEED


## The nearest live raider, or null. Raiders only — an ordinary skeleton wandering in from the
## save is not what the fight beat is counting down.
func _nearest_raider(player: Player) -> Enemy:
	var closest: Enemy = null
	var closest_distance := INF
	for node in _dev.get_tree().get_nodes_in_group("Enemy"):
		if not (node is Enemy) or not EnemyRegistry.is_raider(node.type):
			continue
		var enemy := node as Enemy
		var distance: float = player.global_position.distance_to(enemy.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = enemy
	return closest


func _raid_director() -> RaidDirector:
	for node in _dev.get_tree().get_nodes_in_group("RaidDirector"):
		if node is RaidDirector:
			return node
	return null


## By path, the way `commands.gd:_raid_banner` reaches it. The banner is authored into
## `main.tscn`'s UI layer rather than created at runtime, so unlike the clock there is a path to
## rely on and no group to look it up by.
func _raid_banner() -> RaidBanner:
	return _dev.get_tree().root.get_node_or_null("Main/UI/RaidBanner") as RaidBanner


# --- the boss clip --------------------------------------------------------------------
#
# The run has an ending now, and the ending has a number (gather-1zv): the elite guarding the
# boss arena, the fight, and the card that totals up everything the run came to.
#
# Shot on the demo homestead save, and that is a requirement rather than a preference. The boss
# is placed by `IslandManager` only once its island is `connected` — `LandRegion.connected` gates
# enemies and the boss, so on a fresh world the arena is stocked scenery across water with
# nothing standing in it. A save with all twelve parcels bought is the only world that has a boss
# to kill.
#
# ## Why the card is most of the clip
#
# The fight is the part that looks like the rest of the game; the card is the part that is new.
# `RunSummaryUi` is deliberately slow — twelve rows landing one at a time with their numbers
# counting up — because it is the only screen in this game whose job is to be looked at rather
# than played through. So the beat after the kill is the longest one here, and it is doing
# nothing except letting the tally finish, which is what it is for.
#
# ## What this clip does NOT do
#
# It never presses NEW RUN. That button is `reload_current_scene()` and it asks twice before it
# acts; filming the confirmation would be filming a dialog, and filming the reload would be
# filming a loading world. The card, and the two ways out sitting under it, is the feature.

## Which save slot the boss clip loads. Slot 3, the demo homestead — see WORKER_SLOT.
const BOSS_SLOT := 3

## How far from the boss the player is stood before the show, in tiles.
##
## Three. The elite is 1.7x scale on a 16px sprite and its `hunt_range` is the ordinary 30px, so
## from three tiles it is plainly in frame, plainly bigger than anything else in the game, and
## has not yet noticed the player — which lets the clip open on the arena rather than opening
## mid-fight.
const BOSS_STAND_OFFSET := 3

## How far the stand search will walk from the boss, and the ground it scores around each
## candidate.
##
## The scoring is the interesting part and the first cut got it wrong in a way worth recording.
## That version demanded a clear 5x5 at exactly BOSS_STAND_OFFSET in one of the four cardinal
## directions, and it refused the save outright: `island_census` puts the boss arena at radius 5
## with 45 land tiles, so a rect centred three tiles out reaches the coastline on every side, and
## that coastline is noise-thresholded and ragged. The arena is small BY DESIGN — it is the last
## island the player reaches and it is a fighting pit, not a settlement — so a search that needs
## a parade ground in it is asking the wrong question.
##
## What replaced it scores instead of demanding, in `_find_arena`'s three-key style: clear cells
## around the candidate first, then how close it sits to BOSS_STAND_OFFSET (framing), then how
## level it is with the boss (a horizontal approach is the one that leaves the player facing it,
## and facing is what the swing animation is picked from). Only the stand cell itself is a hard
## requirement, because that is the only cell the player is guaranteed to occupy.
const BOSS_SEARCH := 5
const BOSS_DUEL_HALF := Vector2i(2, 1)

## Ceilings on the duel, and on one approach inside it.
##
## The elite is 90 health against a gold sword's 13, so it is seven landed swings; it moves at 32
## px/s, which is over three times a bone skeleton's and is why the approach ceiling here is
## shorter than the raid's — a boss that is hunting the player closes most of the gap itself.
const BOSS_DUEL_TIMEOUT := 40.0
const BOSS_CHASE_TIMEOUT := 6.0

## Ceiling on the card appearing after the boss goes down.
##
## Generous for what is a signal chain and not a wait: `Enemy._on_died` records the kill, emits
## `died`, `IslandManager._on_boss_died` re-emits `boss_killed`, `RunStats._on_boss_killed` calls
## `end_run` and `RunSummaryUi` opens on `run_ended`. All of that is inside a couple of frames —
## but `_on_died` also awaits 0.2s of particles, so this is not a single-frame test either.
const BOSS_CARD_TIMEOUT := 6.0

## The hour the clip is shot at: the middle of DAY, where `WorldClock.tint_for` is flat DAY_TINT.
##
## Flat is the point. The duel and the card together run over twenty seconds, and anywhere in
## either twilight the light would be visibly moving underneath them — which the weather clip
## exists to show and this one would only be leaking.
const BOSS_HOUR := (WorldClock.DAWN_END + WorldClock.DAY_END) * 0.5

## Beat lengths in seconds. The duel ends on the boss dying rather than on a clock, so the
## performance is roughly 8 seconds of framing plus however long the fight takes — about
## twenty-eight in total.
const BOSS_BEAT := {
	"settle": 0.8,
	# The arena, the chest and the thing standing over it. Short: nothing is happening and the
	# viewer can see that the shape of what is about to happen is obvious.
	"arena_hold": 3.0,
	"before_swing": 0.3,
	# The pause on the body. The elite's death particles and its loot land here, and the card is
	# about to take the screen — cutting straight from the last swing to a full-screen panel reads
	# as the panel having interrupted the fight rather than as having concluded it.
	"after_kill": 1.2,
	# The card. Twelve rows at ROW_STAGGER (0.08) with COUNT_TIME (0.55) each finishes its tally
	# about 1.5s in; the rest is the time it takes to actually read a scoreboard, which is the
	# only thing this screen is for — and the measured duel is only about eight seconds, so this
	# is also where the clip's length comes from. The first timing came out at nineteen seconds
	# against the 25-30 the shipped four sit at.
	"card_hold": 8.5,
	"tail": 0.8,
}


func _run_boss_clip() -> void:
	if not _load_slot(BOSS_SLOT):
		_fail("could not load save slot %d" % BOSS_SLOT)
		return
	await _frames(4)

	var handler := _handler()
	var player := _player()
	if handler == null or player == null:
		_fail("no TileMapHandler or player after loading slot %d" % BOSS_SLOT)
		return

	var boss := _boss()
	if boss == null:
		_fail("slot %d has no live %s: either its boss island never opened or the run is already over"
			% [BOSS_SLOT, EnemyRegistry.ELITE])
		return

	if not _stage_boss(handler, player, boss):
		_fail("no land to stand on within %s tiles of the boss at %s" % [
			BOSS_SEARCH, handler.tileMap.local_to_map(boss.global_position),
		])
		return

	# Everything above this line is setup and is expected to be trimmed off the front of the
	# recording; everything below it is the clip.
	await _wait(BOSS_BEAT["settle"])
	_mark("show_start")

	await _beat_boss_arena()
	await _beat_boss_duel(player, boss)
	await _beat_boss_card()

	_mark("show_end")
	await _wait(BOSS_BEAT["tail"])

	_release_all()
	_beat = "done"
	_running = false


## Beat A — the arena, the guard and the chest behind it.
##
## The chest is in frame on purpose and is not decoration: it is what the boss is standing over,
## and a viewer who has not seen it has no reason to believe there was anything here worth the
## walk. `IslandManager.CHEST_OFFSET` puts it two tiles from the boss, so it comes for free from
## framing the boss at all.
func _beat_boss_arena() -> void:
	_beat = "boss_arena"
	_mark("boss_arena")
	await _wait(BOSS_BEAT["arena_hold"])


## Beat B — the duel.
##
## Seven swings with a re-approach between each, driven through the same chase-and-swing loop the
## raid uses, for the reason that loop exists at all: the elite hunts, and a direction chosen when
## the beat opened is stale by the time the walk arrives.
##
## Killed rather than netted, which is the opposite of the charged clip and is correct for the
## same registry reason: `ELITE` is `nettable: false`, and it pays out on the body and in its
## chest. The boss is the one enemy in the game the reward for is its death.
func _beat_boss_duel(player: Player, boss: Enemy) -> void:
	_beat = "boss_duel"
	_mark("boss_duel")

	if not _select(Types.Item.GoldSword):
		_note("no sword in the hotbar to fight the boss with")
		return

	# Both halves are counted, and that is not instrumentation for its own sake: "the boss is
	# still standing" has two entirely different causes — swings that never happened because the
	# approach could not close, and swings that happened and did nothing — and they live in
	# different files. The first take reported only the symptom and sent the search to the wrong
	# one of them. See SWORD_REACH.
	var swings := 0
	var missed_approaches := 0

	var deadline := _dev.get_tree().create_timer(BOSS_DUEL_TIMEOUT)
	while deadline.time_left > 0.0 and is_instance_valid(boss):
		# Lined up beside it rather than walked at it. A boss at 1.7x scale is one of the two
		# things that made the plain chase unusable here; the other is that the sword only swings
		# sideways. See SWING_BAND_Y and SWORD_SWING_ENVELOPE.
		if not await _close_for_swing(player, boss, BOSS_CHASE_TIMEOUT):
			missed_approaches += 1
			continue
		if await _swing_at(player, boss, BOSS_BEAT["before_swing"]):
			swings += 1
		else:
			await _reposition(player, boss)

	if is_instance_valid(boss):
		_note("the boss was still standing after %.0fs on %d health: %d swing(s) landed, %d approach(es) never lined up"
			% [BOSS_DUEL_TIMEOUT, _health_of(boss), swings, missed_approaches])
	await _wait(BOSS_BEAT["after_kill"])


## Beat C — the card. Every number the run came to, counting itself up.
##
## Waited on rather than timed, and asserted on the *view*: `RunStats.end_run` freezing the score
## and `RunSummaryUi` drawing it are different files, and a clip that held for six seconds on the
## strength of the model having ended would film six seconds of an ordinary game if the card never
## opened. This is the `world_clock` verb's rule — read the thing back off the node that draws it.
func _beat_boss_card() -> void:
	_beat = "boss_card"
	_mark("boss_card")

	var card := _run_summary_ui()
	if card == null:
		_note("no RunSummaryUI in the scene to show the score")
		return

	if not await _until(func() -> bool: return card.is_open(), BOSS_CARD_TIMEOUT):
		# Worded off what is actually knowable here. A duel that ran out of time leaves a live boss
		# and no card, and the first take's message ("the boss died but…") asserted the half this
		# beat cannot see — which reads as a second, independent failure rather than as a
		# consequence of the note above it.
		_note("no run summary card within %.0fs (boss alive: %s)"
			% [BOSS_CARD_TIMEOUT, _boss() != null])
		return

	await _wait(BOSS_BEAT["card_hold"])


# --- boss staging ---------------------------------------------------------------------

## Puts the loaded save into the state the boss clip opens on. Returns whether it found ground to
## fight on — the boss itself is looked up before staging, because a save with no boss is a
## different failure and deserves a different message.
func _stage_boss(handler: TileMapHandler, player: Player, boss: Enemy) -> bool:
	_beat = "staging"

	var boss_cell: Vector2i = handler.tileMap.local_to_map(boss.global_position)
	var stand = _find_duel_ground(handler, boss_cell)
	if stand == null:
		return false

	_freeze_ambient()
	# Everything except the boss. The arena itself refuses ambient enemies, so this is really about
	# the rest of the save — a skeleton that wandered in off the mainland during the load would be
	# a second thing for the swing loop to find, and `_nearest` would take it first.
	_clear_enemies_except(boss)
	_still_existing_workers()

	player.position = handler.tileMap.map_to_local(stand)
	player.velocity = Vector2.ZERO
	# The elite hits for 6 and the duel is seven swings long. The clip must not end on a respawn,
	# which would also take the camera off the island the boss is on.
	player.invulnerable = true

	_set_zoom(player, CLOSE_ZOOM)
	_hide_fps()
	_stock_raid_kit(player)

	var clock := _world_clock()
	if clock != null:
		# Daylight, and clear. The card is a full-screen panel of small text over the world, and the
		# night tint plus rain behind it costs contrast on the one screen in the game that exists
		# to be read. It is also the honest framing: nothing about the boss is nocturnal.
		clock.set_weather(WorldClock.Weather.CLEAR, 0.0)
		clock.set_time_of_day(BOSS_HOUR)

	var sky := _sky()
	if sky != null:
		sky.apply()
	return true


## Where the player stands to open the duel: land beside the boss, as much of it as the arena has
## and as close to BOSS_STAND_OFFSET as that allows. See BOSS_SEARCH for the scoring and for the
## take that made it a search.
func _find_duel_ground(handler: TileMapHandler, boss_cell: Vector2i):
	var best = null
	var best_key := [-1, -(1 << 30), -(1 << 30)]

	for dy in range(-BOSS_SEARCH, BOSS_SEARCH + 1):
		for dx in range(-BOSS_SEARCH, BOSS_SEARCH + 1):
			if dx == 0 and dy == 0:
				continue
			var candidate := boss_cell + Vector2i(dx, dy)
			# The one hard requirement: the cell the player is put on. Everything else is scored,
			# because the arena does not have enough flat ground to demand any of it.
			if handler.is_occupied(candidate, true):
				continue
			var reach := int(round(Vector2(dx, dy).length()))
			var key := [
				_duel_ground_score(handler, candidate),
				-absi(reach - BOSS_STAND_OFFSET),
				-absi(dy),
			]
			if key > best_key:
				best = candidate
				best_key = key
	return best


## How many cells of the duel rectangle around `centre` are land and unbuilt.
##
## `is_occupied(cell, true)` answers both halves at once: it is true for open water (no ground
## tile) as well as for anything already standing there. A duel fought half in the sea is the
## `_spawn_enemy` bug in another place.
func _duel_ground_score(handler: TileMapHandler, centre: Vector2i) -> int:
	var clear := 0
	for y in range(-BOSS_DUEL_HALF.y, BOSS_DUEL_HALF.y + 1):
		for x in range(-BOSS_DUEL_HALF.x, BOSS_DUEL_HALF.x + 1):
			if not handler.is_occupied(centre + Vector2i(x, y), true):
				clear += 1
	return clear


## The live boss, matched on its enemy type — the only handle a reloaded boss has, for the reason
## `IslandManager._live_boss` states: it is parented to the EnemySpawner and rebuilt by the
## ordinary enemy load path, so nothing carries which island it came from.
func _boss() -> Enemy:
	for node in _dev.get_tree().get_nodes_in_group("Enemy"):
		if node is Enemy and node.type == EnemyRegistry.ELITE:
			return node
	return null


## `_clear_enemies` with one exception. A separate function rather than an argument on that one,
## because every other clip wants the unconditional version and a defaulted parameter is how a
## clip ends up sparing something it meant to remove.
func _clear_enemies_except(keep: Enemy) -> void:
	var spawner := _spawner()
	if spawner == null:
		return
	for child in spawner.get_children():
		if child is Enemy and child != keep:
			child.queue_free()


func _run_summary_ui() -> RunSummaryUi:
	return _dev.get_tree().root.get_node_or_null("Main/UI/RunSummaryUI") as RunSummaryUi


# --- the quest clip -------------------------------------------------------------------
#
# The board asks for something and the player goes and gets it (gather-dj2): the panel with its
# live progress, one tree short of a task, the tree, and the hand-in that pays for it.
#
# Shot on a fresh world, and unlike the raid and boss clips that is a decision rather than a
# constraint. The board is what the game says to somebody who has just arrived — it is the
# closest thing here to a tutorial — so filming it in front of a finished homestead would put
# the answer behind the question.
#
# ## Why the panel is opened twice
#
# The obvious cut is one open, one hand-in. It shows the payout and none of the point: what the
# board actually changed is that there is now a reason to go and do a specific thing. So the clip
# opens on the ask (`9 of 10 wood`, a bar one notch short), closes, goes and fells the tree that
# finishes it, and opens again on a card that has turned green with HAND IN on the button. The
# middle beat is the feature; the two panels either side are what make it legible.
#
# ## What is real here and what is arranged
#
# The 9 wood in the bag is arranged, and it is the only thing that is. Everything after it — the
# gather, the derived progress, the spend, the coins, the xp — is the game running. In particular
# the quest is NOT marked complete by hand: `QuestLog` derives progress from the inventory on a
# poll, so the card turning green is the feature working rather than the clip asserting it did.

## The quest the clip hands in.
##
## `first_timber` is the board's opening ask and the right one to film for three reasons: it wants
## an item, so the button says HAND IN rather than CLAIM and the spend is visible in the hotbar; it
## is gated behind nothing, so it is offered on a world one second old; and wood is the resource a
## viewer already understands by the time they reach this clip in the README.
const QUEST_ID := "first_timber"
const QUEST_ITEM := Types.Item.Wood

## What the bag is stocked with, against the quest's ask of ten.
##
## Nine, so the bar opens one notch short. Eight would need two trees, and a second identical
## gather is not a second thing happening; ten would open on a finished quest, which is the payout
## without the ask.
const QUEST_STOCK_WOOD := 9

## And of the resource the *next* card asks for, so the panel is plainly a board rather than a
## single task. Six of Stonemason's ten: enough to read as progress under way, short enough that
## nobody expects the clip to hand that one in as well.
const QUEST_STOCK_STONE := 6

## Where the tree is planted and where the player stands to fell it, as offsets from the arena
## centre.
##
## One tile apart, because `ResourceManager2.start_removing_resource` targets
## `get_location_of_nearby_resource(player.global_position)` — the nearest resource in reach, not
## the cell in front. The arena is cleared before this is planted, so "nearest" has exactly one
## answer and the gather cannot pick up something the staging left standing.
const QUEST_SET := {
	"mark": Vector2i(0, 0),
	"stand_tree": Vector2i(0, 0),
	"tree": Vector2i(1, 0),
}

## The pickaxe the clip fells the tree with, and its shipped gather time is why: a Stone Pickaxe is
## 1.8 seconds, which `Juice.swings_for` divides into enough blows to read as work. The Wooden one
## the player starts with is 2.0 and the difference is not worth a slower beat; anything above
## Copper finishes before the chips do and the gather reads as a click.
const QUEST_PICKAXE := Types.Item.StonePickaxe

## Ceiling on the fell, in seconds. Two gather cycles' worth: `remove_resource` rolls a yield of
## one or two logs, so a single tree can leave the player on 10 or on 11 — but a roll of one on a
## bag of nine is still enough, and this timeout is really sized for a gather that never started.
const QUEST_GATHER_TIMEOUT := 8.0

## Ceiling on a panel open or close, in seconds. `PanelFrame` tweens; this is generous for it.
const QUEST_PANEL_TIMEOUT := 2.0

## Beat lengths in seconds. About twenty-four between the marks.
const QUEST_BEAT := {
	"settle": 0.8,
	# The ask. Long enough to read two cards and their bars, which is what this beat is for and the
	# only thing on screen — this is the one clip in the set whose subject is words.
	"board_hold": 5.0,
	"after_close": 0.6,
	# On the felled tree before walking back into the panel: the logs pop out and vacuum in, and
	# the hotbar count ticks over. That tick is the quest's progress changing, and it happens in
	# the hotbar rather than in the panel — so it needs a frame of its own to be seen in.
	"after_gather": 1.6,
	# On the completed card before the button goes. The border has turned green and the button says
	# HAND IN; pressing it on the frame the panel opens would show the reward and never the state
	# that earned it.
	"before_claim": 2.2,
	# After the press, with the panel still up: the card disappears out of the list and the one it
	# was gating takes its place, which is the board behaving like a board.
	"after_claim": 2.5,
	# Panel closed, standing in the world: the coin purse and the xp are dropped at the player's
	# feet by `QuestLog._pay` and vacuum in. The payout is deliberately watched from outside the
	# menu, because that is where the player is when it lands.
	"reward_hold": 3.5,
	"tail": 0.8,
}


func _run_quest_clip() -> void:
	var handler := _handler()
	var player := _player()
	if handler == null or player == null:
		_fail("no TileMapHandler or player in the scene")
		return

	# `quests` rather than `log`, which is a built-in math function and shadowing it is a warning
	# the lint gate would (correctly) hand back.
	var quests := _quest_log()
	var panel := _quest_ui()
	if quests == null or panel == null:
		_fail("no QuestLog or QuestUI in the scene, so there is no board to film")
		return

	var centre = _stage_quests(handler, player)
	if centre == null:
		_fail("no clear %s-tile clearing with land in frame within %s tiles of the player" % [
			QUEST_CLEARING, ARENA_SEARCH,
		])
		return

	# Everything above this line is setup and is expected to be trimmed off the front of the
	# recording; everything below it is the clip.
	await _wait(QUEST_BEAT["settle"])
	_mark("show_start")

	await _beat_quest_ask(quests, panel)
	await _beat_quest_errand(handler, player, quests)
	await _beat_quest_hand_in(player, quests, panel)

	_mark("show_end")
	await _wait(QUEST_BEAT["tail"])

	_release_all()
	_beat = "done"
	_running = false


## Beat A — the board, and what it wants.
##
## Opened with the real key rather than by calling `toggle()`, and it has to be `_tap_key_for`:
## `InputManager._input` reads `quests` with `is_action_released`, so an `action_press` from a
## coroutine that has already resumed inside the frame is read by nobody. That is the chest bug in
## `_beat_reveal` in a second place, and it fails the same silent way — a panel that never opens
## and a clip that carries on regardless.
##
## The progress is asserted *before* the errand, because the whole beat is the claim that the
## board knows the player has nine wood without having been told. If it opened on ten, or on zero,
## the two beats after this one would still run and the footage would show a different story than
## the README line under it.
func _beat_quest_ask(quests: QuestLog, panel: QuestUi) -> void:
	_beat = "quest_ask"
	_mark("quest_ask")

	await _tap_key_for("quests")
	if not await _until(func() -> bool: return panel.is_open(), QUEST_PANEL_TIMEOUT):
		_note("the quests key did not open the board")
		return

	var progress := quests.progress_of(QUEST_ID)
	if progress != QUEST_STOCK_WOOD:
		_note("the board opened on %d of %d for %s, expected %d" % [
			progress, _quest_amount(quests), QUEST_ID, QUEST_STOCK_WOOD])

	await _wait(QUEST_BEAT["board_hold"])


## Beat B — the errand. The panel closes, the player walks to the tree and takes it down.
##
## The gather is held rather than tapped, for `_use`'s reason twice over: releasing `gather` runs
## `Player._gather_input_release`, which stops the hold timer outright — so a tapped gather is not
## a short gather, it is no gather. This one is held until the wood actually lands in the bag,
## which is also the only evidence that matters: the swing animation plays whether or not there is
## anything in reach to swing at.
func _beat_quest_errand(handler: TileMapHandler, player: Player, quests: QuestLog) -> void:
	_beat = "quest_errand"
	_mark("quest_errand")

	await _tap_key_for("quests")
	await _wait(QUEST_BEAT["after_close"])

	if not _select(QUEST_PICKAXE):
		_note("no pickaxe in the hotbar to fell the tree with")
		return

	# Facing the tree before swinging at it. The gather targets by proximity rather than by facing,
	# so this changes nothing about what gets felled — it changes which of `Gather` / `Gather_left`
	# plays, and a player chopping with his back to the tree is the sort of thing only the finished
	# film shows you.
	var cell: Vector2i = handler.tileMap.local_to_map(player.global_position)
	await _aim(handler, player, cell + Vector2i(1, 0))

	var wanted: int = _quest_amount(quests)
	_press("gather")
	var felled := await _until(
		func() -> bool: return player.inventory_data.count_of_type(QUEST_ITEM) >= wanted,
		QUEST_GATHER_TIMEOUT)
	_release("gather")

	if not felled:
		_note("the gather left the player on %d %s after %.0fs, short of %d" % [
			player.inventory_data.count_of_type(QUEST_ITEM), QUEST_ID,
			QUEST_GATHER_TIMEOUT, wanted])

	await _wait(QUEST_BEAT["after_gather"])


## Beat C — the hand-in, and what it pays.
##
## The button is clicked rather than `pressed.emit()`-ed. An emit would run the same handler and
## prove the same thing about `QuestLog`, and it would prove nothing at all about the panel — a
## disabled button, a button laid out off-screen or a button under something else all emit
## perfectly. See `_click_button`.
##
## `is_claimed` is what the beat is judged on rather than the coins, because `claim()` refuses on
## three separate grounds — already claimed, not complete, not offered — and a clip that only
## checked for a coin drop could not tell a refusal from a payout that had not landed yet.
func _beat_quest_hand_in(player: Player, quests: QuestLog, panel: QuestUi) -> void:
	_beat = "quest_hand_in"
	_mark("quest_hand_in")

	await _tap_key_for("quests")
	if not await _until(func() -> bool: return panel.is_open(), QUEST_PANEL_TIMEOUT):
		_note("the quests key did not re-open the board")
		return

	if not quests.is_complete(QUEST_ID):
		_note("the board still does not consider %s complete" % QUEST_ID)
	await _wait(QUEST_BEAT["before_claim"])

	# `_find_claim_button` notes for itself, with the card names it actually saw — a second note
	# here would say less and say it twice.
	var button := _find_claim_button(panel, quests)
	if button == null:
		return

	await _click_button(button)
	await _frames(2)

	if not quests.is_claimed(QUEST_ID):
		_note("the press did not hand %s in" % QUEST_ID)
	await _wait(QUEST_BEAT["after_claim"])

	# Out of the menu for the payout. `_pay` drops the purse at the player's feet, and the pickup
	# flies to him — which is worth being outside a full-screen panel to see.
	await _tap_key_for("quests")
	await _wait(QUEST_BEAT["reward_hold"])

	if player.inventory_data.count_of_type(Types.Item.Coin) <= 0:
		_note("the hand-in paid no coins into the bag")


# --- quest staging --------------------------------------------------------------------

## Puts the world into the state the quest clip opens on, and returns the arena centre — or null
## when the search found no rectangle of solid land, which `_find_arena` documents as a real
## outcome rather than a defensive check.
func _stage_quests(handler: TileMapHandler, player: Player):
	_beat = "staging"

	var centre = _find_clearing(handler, player)
	if centre == null:
		return null

	_freeze_ambient()
	_clear_enemies()
	_clear_quest_clearing(handler, centre)

	# One tree, planted after the clearing rather than found in it. Two reasons, and the first is
	# the same one the worker clip gives: a cleared arena has nothing to gather. The second is that
	# the gather targets the NEAREST resource, so leaving the treeline in reach would make which
	# tree gets felled a matter of where staging happened to put the player.
	_plant(handler, centre + QUEST_SET["tree"], Types.Item.Tree)

	player.position = handler.tileMap.map_to_local(centre + QUEST_SET["mark"])
	player.velocity = Vector2.ZERO

	# No `player.invulnerable` here, unlike the raid and boss clips. Nothing in this one attacks
	# him: the spawner is frozen and the standing enemies are cleared.

	_set_zoom(player, CLOSE_ZOOM)
	_hide_fps()
	_stock_quest_kit(player)

	var clock := _world_clock()
	if clock != null:
		# Daylight and clear, for the boss clip's reason: this panel is small text, and it is the
		# thing the clip is about.
		clock.set_weather(WorldClock.Weather.CLEAR, 0.0)
		clock.set_time_of_day(BOSS_HOUR)

	var sky := _sky()
	if sky != null:
		sky.apply()
	return centre


## Where the player stands, and where nothing else may be standing.
##
## The clip's own search rather than `_find_arena`, and that is the same correction the boss clip
## needed. `_find_arena` scores a 9x7 rectangle of solid land because the turret clip fights a wave
## across one; nothing here is fought at all, and on the first take the mismatch showed up as a
## note — `best battle rect at (5, -2) was 62/63 land` — which is `_find_arena` reporting, entirely
## correctly, that a cell of coastline clipped a corner of a rectangle this clip has no use for. A
## note is the recording gate, so a clip that files one it does not care about cannot be shot.
##
## What this clip actually needs is small: a cell to stand on, a cell beside it for the tree, and
## no OTHER resource within the eight neighbours `get_location_of_nearby_resource` searches — plus
## enough land across the frame that the panel is not floating over open sea.
const QUEST_CLEARING := 2


## The clearing: land to stand on with the tree cell free, ranked on how much of the frame is land.
func _find_clearing(handler: TileMapHandler, player: Player):
	var origin: Vector2i = handler.tileMap.local_to_map(player.global_position)
	var best = null
	var best_key := [-1, -(1 << 30)]

	for dy in range(-ARENA_SEARCH, ARENA_SEARCH + 1):
		for dx in range(-ARENA_SEARCH, ARENA_SEARCH + 1):
			var candidate := origin + Vector2i(dx, dy)
			if handler.is_occupied(candidate, true):
				continue
			if handler.is_occupied(candidate + QUEST_SET["tree"], true):
				continue
			var key := [_land_score(handler, candidate, VIEW_HALF), -(dx * dx + dy * dy)]
			if key > best_key:
				best = candidate
				best_key = key
	return best


## Clears the cells the gather could otherwise pick instead of the planted tree.
##
## `main.gd:get_location_of_nearby_resource` searches the player's own cell and its eight
## neighbours and takes the nearest match, so a tree the world already put one tile the other way
## is a coin toss over which one gets felled — and the clip would show the player swinging in the
## wrong direction. QUEST_CLEARING covers that neighbourhood with a tile to spare.
##
## Both representations, for `_clear_arena`'s reason: a resource is either a cell on layer 1 or a
## `GameSceneResource` child of the TileMap, and code that walks only one leaves half the trees
## standing.
func _clear_quest_clearing(handler: TileMapHandler, centre: Vector2i) -> void:
	for y in range(-QUEST_CLEARING, QUEST_CLEARING + 1):
		for x in range(-QUEST_CLEARING, QUEST_CLEARING + 1):
			var cell := centre + Vector2i(x, y)
			handler.tileMap.set_cell(1, cell, -1)
			handler.tileMap.set_cell(2, cell, -1)
			handler.tileMap.set_cell(3, cell, -1)

	for child in handler.tileMap.get_children():
		if not (child is GameSceneResource):
			continue
		var cell: Vector2i = handler.tileMap.local_to_map(child.position)
		if absi(cell.x - centre.x) <= QUEST_CLEARING and absi(cell.y - centre.y) <= QUEST_CLEARING:
			child.queue_free()


## The kit: a pickaxe, nine wood and six stone.
##
## The wood and the stone are what the board reads, and they are put in through
## `pick_up_slot_data` rather than written into a slot so the stack, its count and its hotbar icon
## are built the way a picked-up stack is. `QuestLog` derives progress from
## `InventoryData.count_of_type`, so a hand-made slot with the wrong shape would show the right
## number in the panel and refuse the spend at the hand-in.
func _stock_quest_kit(player: Player) -> void:
	var slots: Array = player.inventory_data.inventory_slot_datas
	for index in mini(6, slots.size()):
		slots[index] = null

	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(QUEST_PICKAXE), 1))
	player.inventory_data.pick_up_slot_data(
		SlotData.new(GameItems.get_item(QUEST_ITEM), QUEST_STOCK_WOOD))
	player.inventory_data.pick_up_slot_data(
		SlotData.new(GameItems.get_item(Types.Item.Stone), QUEST_STOCK_STONE))
	player.inventory_data.inv_updated()


## The quest panel's claim button for QUEST_ID, found by walking the cards.
##
## The fallback for the `%Card_.../Row/ClaimButton` path, which depends on `_build_card`'s node
## names staying what they are. Names are not an API and this file is not the place to pin them,
## but a walk that matched only on class would take whichever button came first — so this matches
## on the card name and reads the button out of it.
## The quest panel's claim button for QUEST_ID, identified by the card's TITLE rather than by its
## node name.
##
## The obvious lookup is `Card_first_timber`, which is the name `QuestUi._build_card` assigns, and
## it does not survive the second open. Three takes went into finding out why, and the mechanism is
## worth writing down because it will catch the next person who walks a rebuilt panel:
##
##  - `_refresh` rebuilds every card on each open, freeing the old ones and adding the new ones
##    **in the same frame** — and a `queue_free`d node is still a child until the end of it. So on
##    the second open the panel briefly holds two cards per quest.
##  - `add_child` without `force_readable_name` does not disambiguate the collision by decorating
##    the wanted name. It DISCARDS it: the new card comes in as `@PanelContainer@426`, with no
##    trace of `Card_first_timber` anywhere in it. An exact match, a prefix match and a containment
##    match all fail identically, and all three fail *silently* — the walk sees the node and does
##    not recognise it.
##
## The first take reported only "no claim button" while the panel was open, populated and entirely
## correct — `get_child_count` on the Cards container answered 7 at the moment the clip claimed 0.
## Dumping the descendant names into the note is what ended it, which is why the note still carries
## the titles it found.
##
## So the card is found by the one thing about it that is stable and is also the thing the player
## reads: its title Label. `Row` and `ClaimButton` keep their names because neither ever collides —
## each is unique inside its own card.
func _find_claim_button(panel: QuestUi, quests: QuestLog) -> Button:
	var quest: Quest = quests.board.get_quest(QUEST_ID)
	if quest == null:
		_note("%s is not a quest on the board" % QUEST_ID)
		return null

	var titles: Array = []
	for node in _all_descendants(panel):
		if node.is_queued_for_deletion() or str(node.name) != "Row":
			continue
		var title := node.get_node_or_null("Text/Title") as Label
		if title == null:
			continue
		titles.append(title.text)
		if title.text != quest.display_name:
			continue
		var claim := node.get_node_or_null("ClaimButton") as Button
		if claim != null and not claim.is_queued_for_deletion():
			return claim

	_note("no live claim button titled '%s'; the panel was offering %s"
		% [quest.display_name, titles])
	return null


func _all_descendants(root: Node) -> Array:
	var found := []
	for child in root.get_children():
		found.append(child)
		found.append_array(_all_descendants(child))
	return found


## The quest's own target amount, read off the board rather than written here twice. Zero when the
## id is not registered, which is a state `_note` can describe and an index would raise on.
func _quest_amount(quests: QuestLog) -> int:
	var quest: Quest = quests.board.get_quest(QUEST_ID)
	return quest.amount if quest != null else 0


## Clicks `button` with real mouse events at its own centre.
##
## Through the viewport's gui input rather than `pressed.emit()`, and the difference is what the
## beat is actually claiming. An emit calls the handler directly: it works on a disabled button, on
## a button laid out past the edge of the screen, and on one sitting under another Control — all
## three of which are ways this panel could be broken while the quest system underneath it was
## perfectly fine. A click has to find the button where it is drawn.
##
## The motion event first is not ceremony. A Button only takes a press it believes is over it, and
## `mouse_entered` is what puts it into its hover style — so without the motion the click can be
## dropped and, when it is not, the frame shows a button being activated without ever having been
## pointed at.
##
## The OS cursor is not drawn into a movie-writer recording, so what this looks like on film is the
## button lighting up and depressing on its own. That is the correct amount of cursor for a clip
## about a menu: the eye follows the state change rather than a pointer nobody controls.
func _click_button(button: Button) -> void:
	var at: Vector2 = button.get_global_rect().get_center()

	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await _frames(2)

	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		click.pressed = pressed
		click.position = at
		click.global_position = at
		Input.parse_input_event(click)
		await _frames(2)


func _quest_log() -> QuestLog:
	for node in _dev.get_tree().get_nodes_in_group("QuestLog"):
		if node is QuestLog:
			return node
	return null


func _quest_ui() -> QuestUi:
	return _dev.get_tree().root.get_node_or_null("Main/UI/QuestUI") as QuestUi
