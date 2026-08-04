extends GameSceneResource
class_name BerryBush

## The one resource in the game that a gather does not destroy.
##
## Every other node is a single event: you hold the pickaxe on it, it pays out, the cell is
## cleared. A berry bush has two states and two different gathers:
##
##   fruiting  -> picking it yields Berries, the bush STAYS and starts a REGROW_SECONDS timer
##   picked    -> gathering it again uproots the whole bush into a placeable BerryBush item
##
## That split is what makes a bush farm possible: the player clears a plot, uproots wild
## bushes, replants them in rows, and harvests the row every fifteen minutes. It is also why
## this is a scene tile rather than a pair of tilemap cells — a cell has nowhere to keep a
## timer, and "how far through regrowing is this particular bush" is exactly the kind of
## in-progress state CLAUDE.md's save-fidelity section is about.
##
## ResourceManager2 owns the routing between the two gathers (see _pick_berries there); this
## class owns the state and the clock.

## How long a picked bush takes to refruit. Fifteen minutes of REAL time, deliberately not
## game-clock hours: WorldClock runs a full day in a few minutes, so an in-world "morning"
## would make this a handful of seconds and the plot would never read as something you come
## back to.
const REGROW_SECONDS := 900.0

## Animation names on the scene's AnimatedSprite2D. "Default" is the fruiting frame because
## GameSceneResource's autoplay and rest state both assume that name, and "Destroy" because
## break_react() looks for exactly that one.
const ANIM_FRUITING := "Default"
const ANIM_PICKED := "Picked"

## Cells the player has just planted a bush on, so the node that appears there next frame can
## start picked instead of fruiting.
##
## Without this, uproot-and-replant is an infinite berry faucet: a bush can only be uprooted
## once it has already been picked, so a replant that came back in leaf would hand the berries
## straight back. The item marks the cell (GameItemBerryBush.use), the node claims the mark
## (_ready), and the mark is consumed either way — see _claim_planted.
##
## Static rather than a signal or a manager because the two halves are a frame apart and have
## no reference to each other: the item is a RefCounted with no place in the tree, and the node
## does not exist yet when the item runs.
static var _planted_cells: Dictionary = {}

## How long a mark stays claimable. The node is instantiated the frame after the cell is
## written, so this is generous by two orders of magnitude and exists only so that a placement
## that never instantiates anything cannot leak an entry for the rest of the session.
const PLANT_MARK_TTL_MSEC := 2000


## Whether this bush is currently carrying fruit. A bush spawned by world generation starts
## in leaf; a bush the player plants does not (see _planted_cells).
var is_fruiting := true

## Whether the player put this bush here. Set once, in _ready(), from the planting mark; saved,
## because it is provenance rather than state and nothing can ever re-derive it from the world.
##
## It exists to answer awards_gather_xp() — see there for why a planted bush pays no xp.
var was_planted := false

var _regrow: Timer


## Records that a bush was just planted at `cell`, in tilemap coordinates.
static func mark_planted(cell: Vector2i) -> void:
	var now := Time.get_ticks_msec()

	# Pruned on write rather than on a timer: this is a static Dictionary with no node to
	# own a timer, and a placement is a rare enough event that walking a handful of keys
	# costs nothing.
	for key in _planted_cells.keys():
		if now - int(_planted_cells[key]) > PLANT_MARK_TTL_MSEC:
			_planted_cells.erase(key)

	_planted_cells[cell] = now


## Consumes the mark for `cell`, returning whether there was a live one.
static func _claim_planted(cell: Vector2i) -> bool:
	if not _planted_cells.has(cell):
		return false

	var planted_at := int(_planted_cells[cell])
	_planted_cells.erase(cell)
	return Time.get_ticks_msec() - planted_at <= PLANT_MARK_TTL_MSEC


## Drops every outstanding mark. World generation and a save load both write a great many
## cells without going through the item, so nothing should be left over from a previous
## session to be claimed by a bush that was not planted at all.
static func clear_planted_marks() -> void:
	_planted_cells.clear()


func _ready() -> void:
	super()

	add_to_group("SaveChunks")
	add_to_group("BerryBush")

	# one_shot: the bush refruits once and then waits to be picked again. A repeating timer
	# would keep firing against an already-fruiting bush forever.
	_regrow = Timer.new()
	_regrow.name = "RegrowTimer"
	_regrow.one_shot = true
	_regrow.wait_time = REGROW_SECONDS
	_regrow.timeout.connect(_on_regrow_finished)
	add_child(_regrow)

	if _claim_planted(cell()):
		was_planted = true
		pick()
	else:
		_show_state()


## Where this bush stands, in its parent's space.
##
## GameSceneResource is declared `extends Node` even though every scene that uses it has a
## Node2D root (a StaticBody2D) — pre-existing, and left alone because narrowing it is a change
## to every scene rather than to this one. The consequence is that `position` is invisible to
## the compiler here: a plain `position` does not parse, and `self as Node2D` does not either,
## because GDScript rejects a cast it can prove impossible from the declared type. Object.get()
## is the way through, and the type check on the result is what makes the fallback honest
## rather than a null propagating into a Vector2 field.
func world_offset() -> Vector2:
	var at: Variant = get("position")
	if at is Vector2:
		return at
	return Vector2.ZERO


## This bush's tilemap cell. Scene tiles are children of the TileMap, so the position above is
## already in tilemap-local space and only needs converting — but the parent is looked up
## rather than assumed, because a bush held in a test has no TileMap over it at all.
func cell() -> Vector2i:
	var at := world_offset()
	var parent := get_parent()
	if parent != null and parent.has_method("local_to_map"):
		return parent.call("local_to_map", at)
	return Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))


## Strips the fruit and starts the clock. Idempotent: picking an already-picked bush restarts
## nothing, so a double-fire cannot extend the wait.
func pick() -> void:
	if not is_fruiting:
		return

	is_fruiting = false
	_show_state()
	_restart_regrow(REGROW_SECONDS)


## Whether harvesting this bush should pay xp. False for anything the player planted.
##
## A bush is the one resource that can be picked up and put back down, and both of its gathers
## used to pay `xp`, so replanting one minted xp out of nothing: a replanted bush comes up
## already picked (see _planted_cells) and is therefore immediately uprootable, which made
## uproot-replant-uproot a zero-material loop paying 1 xp a cycle forever. That is the same
## faucet shape as the pickup award and the build award, both of which were deleted outright —
## see LevelUpManager's award table.
##
## Provenance rather than a per-cell ledger, because a bush moves and a cell does not: the
## exploit is one bush being harvested over and over, so the flag belongs on the bush. It also
## covers the slow half of the loop — a planted bush pays nothing for its 15-minute refruit
## either, so a bush farm is a food supply and not a second xp economy. Berries are the point
## of a farm; the xp was paid when the wild bush was found.
func awards_gather_xp() -> bool:
	return not was_planted


## Puts the fruit back immediately, cancelling any regrow in flight. Used by the load path and
## by the devtools verb; nothing in normal play calls it.
func refruit() -> void:
	is_fruiting = true
	if _regrow != null:
		_regrow.stop()
	_show_state()


## Seconds until this bush fruits again, or 0.0 when it already has fruit.
##
## `time_left`, not `wait_time`: the first is how far through THIS regrow the bush is, the
## second is how long a regrow takes and never moves. Saving the second and calling it
## progress is the exact failure the furnace hit in gather-9x0.
func regrow_remaining() -> float:
	if is_fruiting or _regrow == null or _regrow.is_stopped():
		return 0.0
	return _regrow.time_left


func _on_regrow_finished() -> void:
	is_fruiting = true
	_show_state()


## Starts the regrow with `seconds` remaining, then puts the interval back.
##
## Timer.start(t) ASSIGNS wait_time = t. Restoring a part-finished regrow with it and walking
## away would leave that bush on a shorter cycle for the rest of the session — a bush that
## refruits every ninety seconds because it happened to be saved at ninety seconds left.
func _restart_regrow(seconds: float) -> void:
	if _regrow == null:
		return

	_regrow.start(maxf(seconds, 0.01))
	_regrow.wait_time = REGROW_SECONDS


func _show_state() -> void:
	if animated_sprite_2d == null:
		return

	var wanted := ANIM_FRUITING if is_fruiting else ANIM_PICKED
	if animated_sprite_2d.sprite_frames != null and animated_sprite_2d.sprite_frames.has_animation(wanted):
		animated_sprite_2d.play(wanted)


# --- SaveChunks contract -----------------------------------------------------------------
#
# Position-keyed, like every other scene tile: SaveLoad.late_load matches a payload onto a
# node by comparing x/y, and CHUNK_KIND stops a bush's payload being handed to a chest that
# happens to stand where a bush used to. "filepath" is the dummy every chunk carries so that
# is_node_entry() accepts the line.

func save() -> Dictionary:
	var at := world_offset()
	return {
		"x": at.x,
		"y": at.y,
		# Both halves, not just the flag. `fruiting` alone would reload every picked bush on
		# the map with a full fifteen minutes to go, which is a real loss of progress and one
		# that no error would report — the world would simply look like it always does a
		# moment after a harvest.
		"data": {
			"fruiting": is_fruiting,
			"regrow_left": regrow_remaining(),
			# Provenance, and the one field here that cannot be recovered by looking at the
			# world: _planted_cells is a session-lifetime static with a two-second TTL, and
			# main.gd clears it before a load replays. Drop it and every planted bush reloads
			# as a wild one, which reopens the xp faucet awards_gather_xp() closes — silently,
			# and only for players who saved.
			"planted": was_planted,
		},
		SaveLoad.CHUNK_KIND: SaveLoad.chunk_kind_of(self),
		"filepath": "343",
	}


## Every value here has been through JSON, so nothing about its shape is guaranteed. Each
## level is type-checked before it is read, and `fruiting` is checked with typeof rather than
## `== true` because comparing a String to a bool RAISES — and a raise inside a `-> void`
## aborts the method silently, leaving the bush on whatever state it happened to start in.
func load(dict) -> void:
	if typeof(dict) != TYPE_DICTIONARY:
		return

	var data = dict.get("data")
	if typeof(data) != TYPE_DICTIONARY:
		return

	# Read before the `fruiting` guard below, which returns rather than falls through: a payload
	# this build cannot fully parse must still not hand back a bush that pays xp. Absent in every
	# save written before the flag existed, and `false` is the right default there — those saves
	# predate a planted bush being distinguishable at all, and defaulting the other way would
	# strip the xp from every wild bush on the map instead.
	if typeof(data.get("planted")) == TYPE_BOOL:
		was_planted = data["planted"]

	# An unreadable flag is left alone rather than defaulted. Defaulting it to `true` would
	# mean a payload this build cannot parse quietly puts fruit back on every bush in the
	# world — a corrupt save reading as a free harvest, which is exactly the kind of silent
	# gain the save-fidelity rules are about. Doing nothing leaves the bush as the world
	# generated it, which is also what a save written before this field existed wants.
	if typeof(data.get("fruiting")) != TYPE_BOOL:
		return

	if data["fruiting"]:
		refruit()
		return

	is_fruiting = false
	_show_state()

	var left := REGROW_SECONDS
	var saved = data.get("regrow_left")
	if typeof(saved) == TYPE_FLOAT or typeof(saved) == TYPE_INT:
		left = clampf(float(saved), 0.0, REGROW_SECONDS)

	_restart_regrow(left)
