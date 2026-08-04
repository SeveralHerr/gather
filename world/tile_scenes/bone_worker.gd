extends StaticBody2D
class_name BoneWorker

## Automated wood farmer, assembled the same way as BoneTurret: the player places the
## unassembled bone base, captures a skull enemy with the net, and uses the resulting
## Types.Item.BoneEnemy on it. GameItemBoneEnemy.use() is what calls set_loaded().
##
## The worker WALKS. It leaves its tile, routes to a tree with TilePathFinder, fells it,
## carries the wood to a chest — around walls and in through doors, which is the entire
## reason for pathing rather than measuring straight-line reach — and returns.
##
## THE PLACED CELL IS STILL THE ANCHOR. This node is a TileMap scene tile: the cell owns the
## instance, clear_tile on that cell destroys the worker, and occupancy and placement are
## decided on it. So the node moves its own `position` and nothing else — never reparented —
## and save() reports the home anchor rather than wherever the legs currently are, so a
## reload cannot strand a worker mid-errand.
##
## IT STILL DOES NOT BLOCK ANYTHING, but it is no longer invisible to physics. The root body
## sits on collision layer bit 6 (32) — a layer nothing masks except the door's Area2D — so
## the player walks straight through a worker and workers never jostle each other, exactly as
## when this was authored on layer 0. A machine that can body-block the player in a doorway
## is a nuisance rather than a helper, and that has not changed: build occupancy is decided by
## main.gd:is_occupied on the tilemap cell rather than by physics, and nothing else in the
## project masks bit 6.
##
## Layer 0 had to go because a body on no layer cannot be detected by anything, and the door
## has to see a worker coming: TilePathFinder routes workers through door cells on purpose so
## they can reach a chest indoors, and the door stayed shut while they walked through it.
##
## The root is an AnimatableBody2D rather than a StaticBody2D for the same reason, and this is
## the part that is easy to undo by "tidying" it back. A StaticBody2D moved by assigning
## `position` — which is exactly how this walks, see _physics_process — never re-enters an
## Area2D's broadphase, because static bodies are assumed not to move. With the worker parked
## dead centre on the door tile, `Area2D.get_overlapping_bodies()` returned only the player.
## AnimatableBody2D is the same body that reports its motion, which is what this needs.
##
## Its `sync_to_physics` is authored FALSE, and that is not a default left alone — it is a
## default overridden. With it on (AnimatableBody2D's own default) the node's transform is
## driven from the physics body, so a direct `position = ...` is quietly discarded: the write
## in _physics_process is how this thing moves at all, and save() reports `_home()`, which is
## that same position. Turning it on cost nothing at runtime and broke the save round trip
## instead, where the worker's x came back 0 instead of the 112 it had just been given.
## Detection works either way; only the writes do not.
##
## Two sprites and only one visible, exactly the turret's idiom. UnloadedSprite is the
## headless base (tiles.png cell (20,2)); LoadedSprite is the four-frame chop animation
## drawn from the cells sitting next to it, (21,2)..(24,2). The animation runs only while
## the worker is actually swinging — never while walking — so a worker in transit reads as
## in transit. There are only those four frames, so there is no walk cycle and none is
## faked: a distinct walking look needs new art, not new code.

## What this worker harvests. The blue machine takes Tree, the grey one StoneResource; the
## behaviour is identical either way, so the difference is an exported value and two sprite
## regions rather than a second script. Anything registered in resources.gd works, which is
## what makes a third variant a scene file and no code at all.
@export var harvest_type: Types.Item = Types.Item.Tree

## Set by GameItemBoneEnemy once a captured skull has been dropped on the base. Nothing
## else may write it -- go through set_loaded(), which owns the sprite swap.
var loaded: bool = false

## Seconds per completed chop, and deliberately NOT the wait_time authored on WorkTimer --
## start() below overrides it, so this constant is the only number that matters and the
## reasoning can live beside it.
##
## 20s: the 4.0s this shipped with, made 400% slower — i.e. five times the duration, reading
## "400% slower" as "the old time plus 400% of it". If four times was meant, this is the one
## number to change.
##
## For scale, the wooden pickaxe (the slowest tier in items.gd) clears a node in 2.0s, and
## the worker rolls yield with a flat 0.0 bonus chance where even that first pickaxe can
## carry one. So a player swinging the worst tool in the game out-earns a worker ten to one
## per second spent. Automation pays for the time you are not there; it is emphatically not
## the better way to clear a node.
const CHOP_SECONDS := 20.0

## What a charged skull does to that cadence (gather-8ft).
##
## 0.5 halves the 20s chop to 10s. The multiplier is deliberately large enough to be worth
## crossing a stormy island for: CHOP_SECONDS is set high on purpose (see the comment above -
## hand-gathering is meant to beat automation), so a 10% nudge would be a reward the player
## could not detect without a stopwatch, which is the same dead-content failure the Cooked
## Food repricing fixed.
##
## It stays a multiplier rather than a second absolute number so the two cannot drift: retune
## CHOP_SECONDS and the charged worker moves with it.
const CHARGED_CHOP_MULTIPLIER := 0.5

## The blue a charged machine wears. Shared in spirit with Enemy.CHARGED_TINT and kept above
## 1.0 on blue for the same reason: this is read at night, in rain, under a tint that is
## already multiplying everything down.
const CHARGED_TINT := Color(0.28, 0.58, 1.85)

## Whether a charged skull has been fitted. Persisted - it is a permanent upgrade the player
## paid a rare drop for, and a reload that quietly returned the machine to stock would be
## exactly the "load succeeds and hands back less" failure the save-fidelity section names.
var charged := false


## Seconds for one chop, given whether a skull is fitted.
##
## A method rather than a variable because work_timer.start() is called from two places, and
## a stored value would have to be recomputed at both of them. Static so the arithmetic is
## testable without a worker, a tree or a timer.
static func chop_seconds_for(is_charged: bool) -> float:
	return CHOP_SECONDS * CHARGED_CHOP_MULTIPLIER if is_charged else CHOP_SECONDS


## Fits a skull. Idempotent, like set_loaded above and for the same reason: the item is
## consumed by the inventory around this call, so charging twice would spend two skulls for
## one upgrade.
func make_charged() -> void:
	if charged:
		return
	charged = true
	_apply_charged_look()

	# The cadence has to be re-armed, not just recorded. work_timer is already counting down
	# from the SLOW interval; leaving it be means the upgrade the player just paid for does
	# not take effect until the current chop finishes, which at 20s is long enough to read as
	# the skull having done nothing.
	work_timer.start(chop_seconds_for(charged))


## The blue, plus the crackle. Split out because the load path needs it without the guard in
## make_charged - a restored worker already has `charged` set and would early-out.
func _apply_charged_look() -> void:
	for sprite in [unloaded_sprite, loaded_sprite]:
		if sprite != null:
			sprite.modulate = CHARGED_TINT
	_set_spark_emitting(true)

## Only used if the scene's WorkArea ever loses its CircleShape2D. The authored shape is the
## source of truth for reach, so the collision shape and the search radius cannot drift.
const DEFAULT_REACH := 40.0

## Pixels per second while walking, against the player's own speed in player/player.gd.
## Deliberately slower than the player: a worker that kept pace would read as a rival, and
## one that outran them would look like a bug.
const WALK_SPEED := 25.0

## How far, in cells, the worker will look for a tree or a chest — measured from its home
## tile, not from wherever it is standing, so a worker cannot wander its search window
## across the map one errand at a time and end up arbitrarily far from where it was placed.
## That anchor is the load-bearing half of this constant; the radius below is the tuning.
##
## Twenty-four cells is 384px, and it was ten. Ten was picked so an errand starts and ends
## inside roughly what the player sees standing at the worker — the camera runs at zoom 8 on
## a 1920x1080 window, so the visible world is about 240x135px, or 15x8 cells. That reads
## well and starves the machine. A developed homestead sits in an apron the player cleared by
## hand and then built on, so by the time there is a worker to place there is nothing within
## ten cells of it left to harvest. In the slot-3 save the two bone workers' nearest trees
## were 19.4 and 20.6 cells out and the loaded stone worker's nearest stone 13.5, and all
## three wandered indefinitely while the player could see trees from where they stood
## (gather-dvw). Legibility is worth less than the machine doing its job.
##
## Twenty-four rather than "just enough for that save", because a radius fitted to one
## measurement puts the boundary somewhere arbitrary: at twenty, those two bone workers sit
## two cells apart with one working and the other starving on a 0.6-cell margin, which reads
## as a broken worker rather than as a range limit. TilePathFinder.HALF_EXTENT is the same
## 24 — the padding A* gets around an errand to route past walls — so matching it means the
## furthest target this will ever ask for still has a full detour margin behind it. Past that
## the scan starts handing the pathfinder routes it was not sized to plan.
##
## The other bound is the clock, and it is why not to go further even where A* could. At
## WALK_SPEED the round trip to the edge of the window is about 31s against a 20s chop, so
## out there a worker already spends more of its cycle walking than working. Being a poor
## earner is on theme — see CHOP_SECONDS on why hand-gathering is meant to beat automation —
## but a worker that only walks is not a worker.
##
## The cost is the cell scan: 49x49 probes per cycle rather than 21x21, still fixed however
## much land has been bought, and still once per CHOP_SECONDS rather than per frame.
const SEARCH_CELLS := 24

## How many candidate targets, nearest first, get an actual A* query per cycle. The cell scan
## is cheap; pathing is not, and a worker walled off from a dense grove would otherwise run
## one search per tree every cycle forever.
const MAX_PATH_PROBES := 6

## How far from home an idle worker will drift, in cells. Deliberately much smaller than
## SEARCH_CELLS: wandering is there so a worker with nothing to do reads as alive rather than
## broken, not so it explores. Three cells keeps it visibly attached to its own tile, and
## keeps it inside the window it searches for trees, so it never wanders somewhere it would
## then have to walk back from to reach a tree that spawned next to home.
const WANDER_CELLS := 3

## How many random cells to try before giving up on a wander this cycle. A worker boxed in by
## walls has no free neighbour at all, and it must not spin looking for one.
const WANDER_TRIES := 8

## The errand, as an explicit enum-and-match in this one file. Deliberately not either of the
## project's node-based state machines: player/states/state_machine.gd transitions by name
## and enemies/states/enemy_state_machine.gd by signal, they are mutually incompatible, and
## CLAUDE.md warns against carrying either outward. Five states with no per-state data do not
## need five scripts and a node each.
##   WANDER     no tree anywhere in range; drifting near home until one spawns
##
## WANDER is appended rather than inserted: devtools reads _state as a raw int, so the
## existing values have to keep meaning what they meant.
enum State { IDLE, TO_TREE, CHOPPING, TO_CHEST, RETURNING, WANDER }

@onready var unloaded_sprite: Sprite2D = $UnloadedSprite
@onready var loaded_sprite: AnimatedSprite2D = $LoadedSprite
@onready var work_timer: Timer = $WorkTimer
@onready var work_area: Area2D = $WorkArea
@onready var gather_sprite: Sprite2D = $Gather
@onready var carried_sprite: Sprite2D = $Carried
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## How far this worker reaches for both trees and delivery chests, read off WorkArea.
var _reach := DEFAULT_REACH

## Whether the chop animation is currently running. Distinct from `loaded`: a loaded worker
## standing in cleared grass has nothing to chop and must read as idle.
var _working := false

var _handler: TileMapHandler

## Where the worker was placed, in the TileMap's own space. Captured lazily, the first time
## the worker actually leaves — NOT in _ready(). A scene tile's transform is assigned by the
## TileMap around the time it enters the tree, so reading position in _ready() is a race, and
## a worker that has never moved is by definition standing on its own anchor anyway. Until it
## walks, _home() is simply where it is.
var _home_position := Vector2.ZERO
var _has_home := false

var _state: int = State.IDLE

## Remaining waypoints in local space, consumed front to back as the worker walks.
var _path: Array[Vector2] = []

## The tree cell being walked to; meaningful in TO_TREE and CHOPPING only.
var _target_cell := Vector2i.ZERO

## Wood in hand, waiting for a chest. Non-zero only between felling and depositing.
var _carry := 0

## One finder held for this worker's life rather than one per query: for_world() builds a
## fresh object and a fresh object rebuilds its grid, so per-probe construction would pay
## for the grid up to MAX_PATH_PROBES times a cycle. Its own cache expires well inside the
## chop cadence, so a held instance never plans two errands off one read of the world.
var _finder: TilePathFinder = null

## Seconds accumulated toward the next visible blow while CHOPPING.
var _swing_accum := 0.0


func _ready() -> void:
	add_to_group("SaveChunks")
	add_to_group("BoneWorker")
	_reach = _work_reach()
	work_timer.timeout.connect(_on_work_timeout)
	# WorkTimer is authored with neither autostart nor a wait_time, so this is the only place
	# the cadence is set. It used to carry 3.0 and autostart, which start() silently overrode
	# — two numbers for one thing, and the one you would find first was the dead one.
	work_timer.start(chop_seconds_for(charged))
	_refresh_sprites()
	_build_sparks()
	if charged:
		_apply_charged_look()


## Swap to the assembled unit. Idempotent: loading an already-loaded worker is a no-op
## rather than a second skull consumed, because GameItemBoneEnemy removes the stack
## itself and cannot see whether the target was already full.
func set_loaded() -> void:
	if loaded:
		return
	loaded = true
	_refresh_sprites()
	# Settle the idle/working look now instead of leaving a freshly assembled worker
	# looking wrong for the whole CHOP_SECONDS until its first timeout.
	_set_working(not _find_tree_cell().is_empty())


## The anchor: the placed cell while the worker has never left it, the remembered one after.
func _home() -> Vector2:
	return _home_position if _has_home else position


## Freeze the anchor. Called once, immediately before the first step of the first errand.
func _anchor_home() -> void:
	if not _has_home:
		_home_position = position
		_has_home = true


func _refresh_sprites() -> void:
	unloaded_sprite.visible = not loaded
	loaded_sprite.visible = loaded
	_update_carry_visual()
	if not loaded:
		_set_working(false)


## The crackle over a charged worker.
##
## CPUParticles2D rather than GPUParticles2D on purpose: project.godot runs gl_compatibility
## on mobile, and the same renderer note that caps Light2D counts (see SkyLighting) makes GPU
## particles the less portable of the two for something this small. Sixteen sparks is not
## work worth moving to the GPU anyway.
##
## Built once in _ready and left emitting=false, rather than created when the skull is
## fitted: a node added mid-frame to a StaticBody2D that the tilemap may be re-parenting is
## how the worker ends up with two of them after a load.
var _sparks: CPUParticles2D


func _build_sparks() -> void:
	if is_instance_valid(_sparks):
		return

	_sparks = CPUParticles2D.new()
	_sparks.name = "Sparks"
	_sparks.emitting = false
	_sparks.amount = 16
	_sparks.lifetime = 0.45
	_sparks.explosiveness = 0.0
	# A small box around the body rather than a point, so the sparks look like they are coming
	# off the whole machine instead of leaking from its centre.
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparks.emission_rect_extents = Vector2(5, 7)
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 180.0
	_sparks.gravity = Vector2.ZERO
	_sparks.initial_velocity_min = 4.0
	_sparks.initial_velocity_max = 14.0
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	# Near-white core fading to the blue, the same reasoning as the item icon's arcs: an
	# electric spark reads as white-hot with a coloured halo, not as a bright blue dot.
	_sparks.color = Color(0.88, 0.97, 1.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.88, 0.97, 1.0, 1.0))
	ramp.set_color(1, Color(0.35, 0.72, 1.0, 0.0))
	_sparks.color_ramp = ramp
	add_child(_sparks)


func _set_spark_emitting(on: bool) -> void:
	if is_instance_valid(_sparks):
		_sparks.emitting = on


## The think tick. Movement happens every frame in _physics_process; this only ever decides
## what to do next, so a worker walking a long path costs one decision per CHOP_SECONDS
## rather than one per frame.
func _on_work_timeout() -> void:
	if not loaded:
		return

	match _state:
		State.IDLE, State.WANDER:
			# WANDER belongs here and not below. A stroll is what the worker does INSTEAD of
			# work, so a tick that arrives mid-stroll is exactly when to look again — and
			# _start_wander()'s own docstring has always promised that ("a tree spawning
			# mid-wander is picked up on the next cycle rather than after the walk
			# completes"). It used to fall through to _revalidate_errand(), which only
			# handles TO_TREE, so the promise was never kept: a wandering worker skipped the
			# tick entirely and only re-scanned once it happened to arrive back in IDLE,
			# which cost it roughly every other cycle (gather-dvw).
			_look_for_work()
		State.CHOPPING:
			# The walk is over and a full CHOP_SECONDS has elapsed standing beside the tree.
			_finish_chop()
		_:
			# TO_TREE / TO_CHEST / RETURNING are driven by arrival, not by the clock. The tick
			# still re-checks that the errand is still worth walking: a player may have felled
			# the target tree while the worker was on its way to it.
			_revalidate_errand()


## Walk the remaining path. Deliberately _physics_process and not _process: the worker shares
## the world with physics bodies, and moving it on the render frame would let it visibly
## stutter against them at a different cadence.
func _physics_process(delta: float) -> void:
	if loaded and _state == State.CHOPPING:
		_swing(delta)

	if not loaded or _path.is_empty():
		return

	var step := WALK_SPEED * delta
	while step > 0.0 and not _path.is_empty():
		var waypoint: Vector2 = _path[0]
		var to_go := waypoint - position
		var distance := to_go.length()
		if distance <= step:
			position = waypoint
			step -= distance
			_path.remove_at(0)
		else:
			position += to_go / distance * step
			step = 0.0

	if _path.is_empty():
		_on_arrived()


## Chips off the tree on the same cadence the player's own swings use.
##
## Juice.GATHER_SWING_INTERVAL, not the 0.2s animation loop: the animation is how fast the
## tool moves and the interval is how often a blow lands, and ResourceManager2._swing() keys
## the player's chips off the latter. Sharing the constant is what keeps the two reading as
## the same act rather than merely similar ones.
##
## The tree itself does not react, and cannot: an ordinary layer-1 tilemap cell has no
## transform, modulate or material, which is why ResourceManager2._swing() only calls
## hit_react() on a GameSceneResource. Trees are plain cells, so the player gets no wiggle
## out of one either — the chips ARE the feedback. Making a tree flinch means making Tree a
## scene tile, which is a tileset and save-format change, not a code one.
func _swing(delta: float) -> void:
	_swing_accum += delta
	if _swing_accum < Juice.GATHER_SWING_INTERVAL:
		return
	_swing_accum = 0.0

	var handler := _tile_map_handler()
	if handler == null or handler.tileMap == null or handler.resource_manager == null:
		return
	if not _is_tree_at(_target_cell):
		return
	var tile_map: TileMap = handler.tileMap
	handler.resource_manager.emit_gather_chips(tile_map.to_global(tile_map.map_to_local(_target_cell)))


## What to do on reaching the end of a path, which depends only on why we set out.
func _on_arrived() -> void:
	match _state:
		State.TO_TREE:
			# Standing beside the tree. Start the swing; the timer tick finishes it, so a chop
			# always costs a full CHOP_SECONDS rather than whatever was left on the clock.
			_state = State.CHOPPING
			_swing_accum = 0.0
			_set_working(true)
			work_timer.start(chop_seconds_for(charged))
		State.TO_CHEST:
			_deposit_carry()
		State.RETURNING, State.WANDER:
			_state = State.IDLE


## Look for a tree, then a chest if already carrying. Nothing else starts an errand.
func _look_for_work() -> void:
	if _carry > 0:
		_start_delivery()
		return

	var targets := _find_tree_cells(MAX_PATH_PROBES)
	if targets.is_empty():
		# No tree anywhere in range. Drift rather than freeze: a worker standing perfectly
		# still is indistinguishable from a broken one, and trees respawn on the global timer,
		# so this is a wait, not an end state.
		_set_working(false)
		_start_wander()
		return

	# Nearest first, and the first one that actually plans wins. Walking past a closer tree
	# only happens when that closer tree cannot be reached at all.
	for cell in targets:
		var path := _path_to_adjacent(cell)
		if path.is_empty():
			continue
		_anchor_home()
		_target_cell = cell
		_state = State.TO_TREE
		_path = path
		_set_working(false)
		return

	# Every candidate seen but none reachable — walled off, or on an island across water.
	# Not an error; just nothing to do this cycle.
	_set_working(false)


## Mid-errand sanity check. The world changes under a walking worker.
func _revalidate_errand() -> void:
	if _state == State.TO_TREE and not _is_tree_at(_target_cell):
		# The player felled it first. Drop the errand rather than walking to bare grass and
		# swinging at nothing.
		_path.clear()
		_state = State.IDLE
		_set_working(false)


func _finish_chop() -> void:
	_set_working(false)
	if _is_tree_at(_target_cell):
		_fell(_target_cell)
	if _carry > 0:
		_start_delivery()
	else:
		# Nothing to carry means the tree was gone by the time the swing landed. Look for
		# another rather than standing still for a cycle.
		_look_for_work()


## Drift to a random reachable cell near home. Not pathed to a chosen destination so much as
## given somewhere to be: the next think tick re-checks for trees regardless of whether the
## stroll finished, so a tree spawning mid-wander is picked up on the next cycle rather than
## after the walk completes.
func _start_wander() -> void:
	# Both bail-outs below clear the path as well as the state, and that matters now that the
	# think tick reaches a worker mid-stroll: this can be entered from WANDER with a stroll
	# already in flight, and dropping to IDLE while _path still held waypoints would leave a
	# worker walking in a state that says it is standing still. Everywhere else that settles
	# to IDLE clears the path too (_revalidate_errand, _go_home); IDLE means not walking.
	var finder := _path_finder()
	var handler := _tile_map_handler()
	if finder == null or handler == null or handler.tileMap == null:
		_state = State.IDLE
		_path.clear()
		return

	var tile_map: TileMap = handler.tileMap
	var home_cell: Vector2i = tile_map.local_to_map(_home())
	var here: Vector2i = tile_map.local_to_map(position)

	for _i in WANDER_TRIES:
		var cell := home_cell + Vector2i(
			randi_range(-WANDER_CELLS, WANDER_CELLS),
			randi_range(-WANDER_CELLS, WANDER_CELLS))
		if cell == here or not finder.is_walkable(cell):
			continue
		var cells := finder.find_path(here, cell)
		if cells.is_empty():
			continue
		_anchor_home()
		_state = State.WANDER
		_path = _waypoints(tile_map, cells)
		return

	# Nowhere to go — walled in, or every roll landed on something solid. Standing still for
	# one cycle is correct; the next tick tries again.
	_state = State.IDLE
	_path.clear()


## Head for the nearest reachable chest that will take wood, else drop it where we stand.
func _start_delivery() -> void:
	# Plain `var`: _find_chest_cell has an untyped return so that null can mean "no chest",
	# and GDScript cannot infer a type from that.
	var chest_cell = _find_chest_cell()
	if chest_cell == null:
		_drop_carry()
		return

	var path := _path_to_adjacent(chest_cell)
	if path.is_empty():
		# Every chest is walled off. Dropping beats standing still holding wood forever.
		_drop_carry()
		return

	_anchor_home()
	_state = State.TO_CHEST
	_path = path


func _deposit_carry() -> void:
	var wood := _wood_item()
	if wood == null:
		_state = State.IDLE
		return

	for chest in _chests_in_reach():
		if chest.inventory_data == null:
			continue
		while _carry > 0 and chest.inventory_data.pick_up_slot_data(SlotData.new(wood, 1)):
			_carry -= 1
		_update_carry_visual()
		if _carry == 0:
			break

	# The chest filled up while we walked to it, or was full on arrival. The wood still has to
	# go somewhere, and the ground is the fallback the stationary worker already used.
	if _carry > 0:
		_drop_carry()
		return

	# Straight on to the next tree instead of trailing back to the tile between every log.
	# Going home was never the job; it is only what to do when there is nothing else.
	_look_for_work()


func _drop_carry() -> void:
	var wood := _wood_item()
	if wood != null:
		while _carry > 0:
			PickUpManager.create_pickup(wood, position)
			_carry -= 1
	_carry = 0
	_update_carry_visual()
	_look_for_work()


func _go_home() -> void:
	if position.is_equal_approx(_home()):
		_state = State.IDLE
		_path.clear()
		return

	var finder := _path_finder()
	var handler := _tile_map_handler()
	if finder == null or handler == null or handler.tileMap == null:
		# No way to plan a route home. Snapping back beats stranding the worker somewhere it
		# can never leave — the home cell is the anchor everything else is keyed on.
		position = _home()
		_state = State.IDLE
		return

	var tile_map: TileMap = handler.tileMap
	var cells := finder.find_path(
		tile_map.local_to_map(position), tile_map.local_to_map(_home()))
	if cells.is_empty():
		position = _home()
		_state = State.IDLE
		return

	_state = State.RETURNING
	_path = _waypoints(tile_map, cells)
	_path.append(_home())


## The tree this worker would chop next as {"cell": Vector2i}, or {} when nothing is in
## reach. A Dictionary rather than a Vector2i because every Vector2i is a legal cell, so
## there is no value left over to mean "none".
##
## Kept as the one-target read for callers that only need "is there anything to do at all"
## — set_loaded()'s sprite settle, and the tests. The errand itself goes through
## _find_tree_cells(), because the nearest tree is not always the reachable one.
func _find_tree_cell() -> Dictionary:
	var nearest := _find_tree_cells(1)
	return {} if nearest.is_empty() else {"cell": nearest[0]}


## Up to `limit` harvestable cells in range, nearest to the HOME anchor first.
##
## Plural, and that is the whole point. This used to return the single best cell and
## _look_for_work() gave up for the cycle if a path to it came back empty — so one tree
## across a wall or a strip of water, being permanently the nearest, stalled the worker
## forever with reachable trees standing behind it (gather-dvw). MAX_PATH_PROBES has always
## documented this ("how many candidate targets, nearest first, get an actual A* query per
## cycle"); it was simply never wired to anything.
##
## The scan is cheap and pathing is not, which is why the split lives here: collect the
## whole window, sort it, and let the caller stop probing as soon as one route plans.
func _find_tree_cells(limit: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	if limit <= 0:
		return found

	var handler := _tile_map_handler()
	if handler == null or handler.tileMap == null:
		return found

	var tree := _tree_resource(handler)
	if tree == null:
		return found

	var tile_map: TileMap = handler.tileMap
	# Measured from HOME, not from the worker's current position. Anchoring the window to the
	# tile means a worker cannot creep its search area across the map one errand at a time,
	# ending up arbitrarily far from where the player put it.
	var home := tile_map.to_global(_home())
	var limit_distance := float(SEARCH_CELLS * _tile_size(tile_map))

	# Cells paired with their distance so the sort does not re-measure. Sorted rather than
	# collected in scan order: the scan walks the window row by row, so its natural order is
	# top-left-first, which has nothing to do with which tree is closest.
	var scored := []

	# Resources exist in two representations and code that knew about only one is a repeat
	# bug in this project (see ResourceManager2 and main.gd:resource_node_census). Tree is a
	# plain layer-1 cell today -- is_scene_tile is set on StoneResourceTest alone -- but that
	# is a data flag in resources.gd, so the node branch is here rather than assumed away.
	if tree.is_scene_tile:
		for child in tile_map.get_children():
			if not (child is GameSceneResource) or child.resource_type != tree.type:
				continue
			var node_distance := home.distance_to(tile_map.to_global(child.position))
			if node_distance <= limit_distance:
				scored.append([node_distance, tile_map.local_to_map(child.position)])
	else:
		var origin: Vector2i = tile_map.local_to_map(_home())
		var span := SEARCH_CELLS
		for dx in range(-span, span + 1):
			for dy in range(-span, span + 1):
				var cell := origin + Vector2i(dx, dy)
				# Atlas AND source. main.gd treats that pair as the identity of a placed
				# tile, and matching on the atlas alone would claim whatever any other sheet
				# happens to draw at the same coordinates.
				#
				# It also means a tree the player is mid-gather on is skipped, because that
				# cell is showing gathering_atlas_location for the duration: the worker will
				# not steal a node out from under the swing that is already paying for it.
				if tile_map.get_cell_atlas_coords(1, cell) != tree.atlas_location:
					continue
				if tile_map.get_cell_source_id(1, cell) != tree.tile_source_id:
					continue
				var distance := home.distance_to(tile_map.to_global(tile_map.map_to_local(cell)))
				if distance <= limit_distance:
					scored.append([distance, cell])

	scored.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	for entry in scored:
		if found.size() >= limit:
			break
		found.append(entry[1])
	return found


## Take the tree at `cell` down and pay out its yield.
func _fell(cell: Vector2i) -> void:
	var handler := _tile_map_handler()
	if handler == null or handler.tileMap == null:
		return

	var tree := _tree_resource(handler)
	if tree == null:
		return

	# clear_tile is exactly what main.gd runs when it hears resource_removed, and it also
	# frees a scene-backed node by clearing the cell that instanced it. Going through
	# ResourceManager2.remove_resource() instead would be shorter but would award the tree's
	# xp, and automation must not reopen the xp faucet gather-5s5 just closed.
	handler.clear_tile(cell)

	# tree.drop, not a hardcoded Types.Item.Wood: what a tree yields is already stated once,
	# in the resources.gd registration, and a second copy here would be the one that goes
	# stale. This unit is a wood farmer because trees drop wood, not the other way round.
	var wood := GameItems.get_item(tree.drop)
	if wood == null:
		return

	# The world just changed under the pathfinder: the felled cell is walkable now, and the
	# cached grid still says otherwise. Without this the worker routes around a tree it took
	# down itself for up to the finder's cache window.
	if _finder != null:
		_finder.invalidate()

	# roll_yield with no bonus argument: bonus_yield_chance belongs to the pickaxe in the
	# player's hand and to the Bountiful Harvest skill, and a worker holds neither. The
	# 1..2 range itself is the tree's own, from Resources.TUNING.
	#
	# The wood goes into _carry rather than straight to a chest: the whole point of walking is
	# that the chest is somewhere else. _start_delivery decides where it ends up.
	_carry += tree.roll_yield()
	_update_carry_visual()

	# The secondary Food drop is deliberately not rolled. It is the forager's bonus for
	# working the tree by hand; a worker farm that also fed the player would make the one
	# consumable in the game free.


## Show what is in hand. The icon comes from the harvested resource's own drop, so the blue
## worker carries a log and the grey one carries a rock without either being named here —
## a third variant gets this for free, like everything else keyed off harvest_type.
##
## Driven from _carry rather than from the state: the worker is visibly holding something
## from the moment the node comes down until the moment it is put away, which includes the
## walk to the chest, the deposit itself, and the case where every chest is full and it is
## carrying the load back out to drop it.
func _update_carry_visual() -> void:
	var carrying := _carry > 0
	carried_sprite.visible = carrying
	if not carrying:
		return
	var item := _wood_item()
	if item != null:
		carried_sprite.texture = item.get_atlas()


## The item a felled tree yields, or null when the registry is not up (headless tests).
func _wood_item() -> GameItem:
	var handler := _tile_map_handler()
	if handler == null:
		return null
	var tree := _tree_resource(handler)
	if tree == null or GameItems == null:
		return null
	return GameItems.get_item(tree.drop)


## Whether the tree this worker set out for is still standing. Matched on atlas AND source,
## the same pair main.gd treats as a placed tile's identity.
func _is_tree_at(cell: Vector2i) -> bool:
	var handler := _tile_map_handler()
	if handler == null or handler.tileMap == null:
		return false
	var tree := _tree_resource(handler)
	if tree == null:
		return false
	var tile_map: TileMap = handler.tileMap
	return (tile_map.get_cell_atlas_coords(1, cell) == tree.atlas_location
		and tile_map.get_cell_source_id(1, cell) == tree.tile_source_id)


## The cell of the nearest chest that will currently take wood, or null when there is none.
## Returns a cell rather than the node because the caller paths to it, and a chest is solid:
## the worker stands beside it.
func _find_chest_cell():
	var handler := _tile_map_handler()
	if handler == null or handler.tileMap == null:
		return null
	var tile_map: TileMap = handler.tileMap
	var home := tile_map.to_global(_home())
	var limit := float(SEARCH_CELLS * _tile_size(tile_map))

	var best = null
	var best_distance := limit
	for node in get_tree().get_nodes_in_group("external_inventory"):
		# Type-checked rather than indexed: the group carries whatever else opts into an
		# external inventory later, and indexing a group is a documented past bug here.
		if not (node is TestChest):
			continue
		var chest := node as TestChest
		if not _chest_has_room(chest):
			continue
		var distance := home.distance_to(chest.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = tile_map.local_to_map(tile_map.to_local(chest.global_position))
	return best


## Whether a chest could take at least one more wood: a free slot, or a wood stack with room.
## Checked before walking rather than on arrival so a full chest does not win the "nearest"
## contest and send the worker on a pointless errand every cycle.
func _chest_has_room(chest: TestChest) -> bool:
	if chest.inventory_data == null:
		return false
	var wood := _wood_item()
	for slot in chest.inventory_data.inventory_slot_datas:
		if slot == null:
			return true
		if wood != null and slot.item != null and slot.item.type == wood.type:
			return true
	return false


## Delivery chests within reach, nearest first.
func _chests_in_reach() -> Array[TestChest]:
	var found: Array[TestChest] = []
	for node in get_tree().get_nodes_in_group("external_inventory"):
		# Type-checked rather than indexed: the group carries whatever else opts into an
		# external inventory later, and indexing a group is a documented past bug here.
		if node is TestChest and global_position.distance_to(node.global_position) <= _reach:
			found.append(node as TestChest)

	var origin := global_position
	found.sort_custom(func(a: TestChest, b: TestChest) -> bool:
		return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	return found


## The swing, and it is deliberately the PLAYER's swing rather than a flipbook of the
## worker's own. main.tscn gives the player a `Gather` Sprite2D holding the pickaxe icon and
## rotates it 0 -> 90 degrees while sliding it (0,-1) -> (5,2) on a 0.2s loop; this scene
## carries a copy of that sprite and that animation, on the same atlas region. So a worker
## felling a tree and a player felling a tree read as the same act, which is the point.
##
## LoadedSprite therefore sits on its axe-free `idle` frame and is never played — the tool in
## the four-frame chop sheet would be a second axe on screen beside the swinging one. Those
## frames are kept in the SpriteFrames rather than deleted: they are the sprite the feature
## was approved on, and nothing else has to change to go back to them.
##
## Tracks the target rather than `loaded`, because the animation is the only thing that tells
## a player whether a worker still has anything to do.
func _set_working(working: bool) -> void:
	if _working == working:
		return
	_working = working
	gather_sprite.visible = working
	if working:
		animation_player.play("Gather")
	else:
		animation_player.stop()
		# Park the tool back at its authored offset. stop() leaves rotation wherever the loop
		# happened to be, so without this a worker that stops mid-swing keeps a tilted pickaxe
		# frozen beside it for as long as it stands there.
		gather_sprite.rotation = 0.0
		gather_sprite.position = Vector2(0, -1)


## The finder, built once and kept. Dropped whenever the handler is re-resolved.
func _path_finder() -> TilePathFinder:
	var handler := _tile_map_handler()
	if handler == null:
		return null
	if _finder == null:
		_finder = TilePathFinder.for_world(handler)
	return _finder


## A walk to a cell beside `cell`, as local-space waypoints. Empty when unreachable.
func _path_to_adjacent(cell: Vector2i) -> Array[Vector2]:
	var empty: Array[Vector2] = []
	var finder := _path_finder()
	var handler := _tile_map_handler()
	if finder == null or handler == null or handler.tileMap == null:
		return empty

	var tile_map: TileMap = handler.tileMap
	var cells := finder.find_path_adjacent(tile_map.local_to_map(position), cell)
	if cells.is_empty():
		return empty
	return _waypoints(tile_map, cells)


## Cell path to walkable positions. Cell centres, not corners: map_to_local gives the centre
## in this project's tileset, and walking to corners would clip the worker into wall edges.
func _waypoints(tile_map: TileMap, cells: Array[Vector2i]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for c in cells:
		out.append(tile_map.map_to_local(c))
	return out


## The tileset's cell size, floored at one so a degenerate value cannot produce a zero-width
## search window. Read off the tileset rather than assuming 16px.
func _tile_size(tile_map: TileMap) -> int:
	if tile_map.tile_set == null:
		return 16
	return maxi(1, mini(tile_map.tile_set.tile_size.x, tile_map.tile_set.tile_size.y))


func _tile_map_handler() -> TileMapHandler:
	if _handler != null and is_instance_valid(_handler):
		return _handler
	for node in get_tree().get_nodes_in_group("TileMapHandler"):
		if node is TileMapHandler:
			_handler = node
			return _handler
	return null


## Looked up through get_item_or_resource_by_type rather than Resources.Get, which indexes
## its dictionary directly and errors on a type that is not registered yet.
func _tree_resource(handler: TileMapHandler) -> GameResource:
	if handler.resources == null:
		return null
	var entry := handler.resources.get_item_or_resource_by_type(harvest_type)
	return entry as GameResource


func _work_reach() -> float:
	var shape_node := work_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is CircleShape2D:
		return (shape_node.shape as CircleShape2D).radius
	return DEFAULT_REACH


## How many cells out the tile scan has to walk to cover _reach. Read off the tileset rather
## than assuming 16px, and floored at one so a degenerate tile size cannot produce a scan
## that looks at nothing.
func _cell_span(tile_map: TileMap) -> int:
	var tile_size := 16
	if tile_map.tile_set != null:
		tile_size = maxi(1, mini(tile_map.tile_set.tile_size.x, tile_map.tile_set.tile_size.y))
	return maxi(1, int(ceil(_reach / float(tile_size))))


## SaveChunks contract. "filepath" keys the scene the loader rebuilds this from, matching
## BoneTurret's dict shape so main.gd's chunk loader needs no special case.
## Reports the HOME anchor, never the live position. SaveLoad.late_load() matches a saved
## chunk back onto a node by comparing x/y, and the cell is what placement and occupancy are
## keyed on — so a worker saved mid-errand must still describe its tile, not its legs.
func save() -> Dictionary:
	return {
		"x": _home().x,
		"y": _home().y,
		# `carry` is what the worker is physically holding. It used to be left out, so a
		# worker walking a full load back to the chest reloaded empty and those items were
		# destroyed — material loss, not just a visual reset (gather-z3o).
		#
		# _state, _target_cell and _path are deliberately NOT saved. They describe a route
		# through a world that the replay is in the middle of rebuilding: the tree the
		# worker was walking to may not exist by the time this runs, and a restored path
		# would point through cells that have changed. Coming back IDLE and holding the
		# right amount lets the normal logic re-plan against the world that actually
		# loaded, which is both simpler and correct.
		# `charged` rides in the same data dict. It is configuration in the sense that it never
		# changes once set, but it is not derivable from anything else in the save - the skull
		# that paid for it is long gone - so it has to be written.
		"data": {"loaded": loaded, "carry": _carry, "charged": charged},
		# See SaveLoad.CHUNK_KIND (gather-34n).
		SaveLoad.CHUNK_KIND: SaveLoad.chunk_kind_of(self),
		"filepath": "343",
	}


## Every value here arrives from JSON.parse of a file on disk, so nothing about its shape is
## guaranteed — a save from an older build, or one edited by hand, can put any type in any
## slot. Each level is therefore type-checked before it is read.
##
## The `loaded` check in particular is a typeof and not `== true`: comparing a String to a
## bool raises "Invalid operands" rather than evaluating false, which would abort the load
## partway and leave the worker at the origin with its state dropped — the silent
## save-corruption failure CLAUDE.md calls out. It also would not have failed the suite,
## because a runtime error inside a `-> String` test still returns "" and counts as a pass
## (gather-1t9).
func load(dict) -> void:
	if typeof(dict) != TYPE_DICTIONARY:
		return

	var data = dict.get("data")
	if typeof(data) != TYPE_DICTIONARY:
		return

	if typeof(data.get("loaded")) == TYPE_BOOL and data["loaded"]:
		set_loaded()

	# typeof rather than `== true`, for the reason the doc comment above spells out: a String
	# here would RAISE on comparison and abort the rest of the load. A save from before
	# charged skulls existed has no key and reads as an ordinary worker.
	if typeof(data.get("charged")) == TYPE_BOOL and data["charged"]:
		make_charged()

	# Saves predating gather-z3o carry no key, which reads as 0 — the old behaviour, and
	# correct for them. Clamped because the value came off disk: a negative carry would
	# make _deposit_carry()'s `while _carry > 0` loop never run and strand the worker.
	var carried: Variant = data.get("carry", 0)
	if typeof(carried) == TYPE_FLOAT or typeof(carried) == TYPE_INT:
		_carry = maxi(0, int(carried))
		_update_carry_visual()
