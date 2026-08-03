extends RefCounted

## Guards the door in a player-built wall run (world/tile_scenes/door.gd).
##
## The door used to answer to the player alone, which was fine while the player was the only
## thing that walked. Workers path through door cells on purpose — TilePathFinder treats a
## door as the one walkable hole in a wall so a worker can reach a chest indoors — so they
## now open it too, and the moment there is more than one opener the naive
## open-on-enter / close-on-exit pair becomes wrong.
##
## What is asserted here is the occupancy count, because its failure is silent and visual: a
## worker stepping out of a doorway the player is still standing in slams the door shut in
## their face, plays the sound doing it, and leaves no error behind. The physics half — that
## an Area2D can see the worker at all, which needed the body off collision layer 0 and onto
## an AnimatableBody2D — is not reachable here and was verified against the running game;
## a StaticBody2D moved by assigning `position` never re-enters an area's broadphase.

var _T

const DOOR_SCENE := "res://world/tile_scenes/door.tscn"
const WORKER_SCENE := "res://world/tile_scenes/bone_worker.tscn"

var door: AnimatedSprite2D
var bodies: Array[Node] = []


func setup() -> void:
	# instantiate_ui() is not UI-specific: it puts the node in a real SubViewport and pumps
	# frames, which is what fires _ready() and connects the Area2D signals.
	door = await _T.instantiate_ui(DOOR_SCENE, Vector2i(64, 64)) as AnimatedSprite2D


func teardown() -> void:
	_T.free_ui(door)
	door = null
	for body in bodies:
		if is_instance_valid(body):
			body.free()
	bodies.clear()


## A worker instance to hand the door's handlers. Built rather than faked: `_opens_door` is a
## type test, so a stand-in with the right shape would pass a check the real thing might not.
func _worker() -> Node:
	var made = load(WORKER_SCENE).instantiate()
	bodies.append(made)
	return made


func test_a_door_starts_closed() -> String:
	return _T.assert_eq(door.animation, "Closed", "a fresh door is shut")


## The headline: a worker is an opener now, not just the player.
func test_a_worker_opens_the_door() -> String:
	door._door_open(_worker())
	return _T.assert_eq(door.animation, "Open", "a worker at the threshold opens the door")


func test_the_door_shuts_behind_the_last_one_out() -> String:
	var worker := _worker()
	door._door_open(worker)
	door._door_close(worker)
	return _T.assert_eq(door.animation, "Closed", "the door shuts once the doorway is empty")


## The case the count exists for. Two openers in the doorway, one leaves — the door must stay
## open for the one still standing in it. With a bare open/close pair this shuts the door on
## whoever is left, which in practice is a worker slamming it on the player.
func test_one_leaving_does_not_shut_the_door_on_the_other() -> String:
	var first := _worker()
	var second := _worker()

	door._door_open(first)
	door._door_open(second)

	var both: String = _T.assert_eq(door.animation, "Open", "open with two in the doorway")
	if both != "":
		return both

	door._door_close(first)

	var still_open: String = _T.assert_eq(
		door.animation, "Open", "stays open while the second is still in it"
	)
	if still_open != "":
		return still_open

	door._door_close(second)
	return _T.assert_eq(door.animation, "Closed", "shuts once the second leaves too")


## Enemies sit on layer 1 and this Area2D masks layer 1, so they genuinely do reach these
## handlers — the type test is what keeps them out, not the collision mask. So does the
## TileMap itself, which is a physics body on the same layer.
func test_something_that_is_not_an_opener_is_ignored() -> String:
	var bystander := Node2D.new()
	bodies.append(bystander)

	door._door_open(bystander)

	var shut: String = _T.assert_eq(door.animation, "Closed", "a bystander does not open the door")
	if shut != "":
		return shut

	return _T.assert_eq(door._occupants, 0, "and does not get counted as an occupant")


## body_exited also fires when a body is freed, and a worker's cell can be cleared out from
## under it while it stands in the doorway — so an unmatched exit is reachable, and must not
## drive the count negative and wedge the door open forever.
func test_an_unmatched_exit_cannot_wedge_the_door_open() -> String:
	var worker := _worker()

	door._door_close(worker)

	var floored: String = _T.assert_eq(door._occupants, 0, "the count floors at zero")
	if floored != "":
		return floored

	door._door_open(worker)
	return _T.assert_eq(door.animation, "Open", "and the next arrival still opens it")
