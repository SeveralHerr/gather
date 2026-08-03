extends AnimatedSprite2D

## The door in a player-built wall run. It opens for anything that walks through it under its
## own steam — the player, and the workers, who go through it constantly: TilePathFinder
## treats a door cell as the one walkable hole in a wall (world/tile_path_finder.gd:_is_door)
## precisely so a worker can reach a chest indoors, and a house whose chests were unreachable
## is the case that whole class was written for.
##
## Workers had to be given a collision layer before this could see them at all. The root body
## of bone_worker.tscn was authored on `collision_layer = 0` so the player walks through a
## worker and workers never jostle each other, and a body on no layer is invisible to every
## Area2D including this one. It is now on bit 6 (32), a layer nothing else masks: this Area2D
## is the only thing that looks for it, so the pass-through behaviour is unchanged — a worker
## still blocks nothing and is blocked by nothing, because it moves by assigning `position`
## rather than through physics.
##
## Enemies are deliberately still excluded. They sit on layers 1/21/22 and this Area2D masks
## layer 1, so they DO trip body_entered; _opens_door is what keeps a skeleton from strolling
## in. That filter is load-bearing, not defensive.

@onready var collider = $Area2D
var sound_manager: SoundManager

## How many door-opening bodies are standing in the doorway right now.
##
## Counted rather than latched because there is more than one opener now. With a bare
## open-on-enter / close-on-exit pair, a worker stepping out through a door the player is
## still standing in slams it shut in their face — and plays the sound doing it. The door is
## open while anyone is in it and shut when the last one leaves.
var _occupants := 0


func _ready():
	collider.connect("body_entered", Callable(self, "_door_open"))
	collider.connect("body_exited", Callable(self, "_door_close"))

	var nodes = get_tree().get_nodes_in_group("SoundManager")
	for node in nodes:
		if node is SoundManager:
			sound_manager = node


## Who this door answers to. BoneWorker covers the stone worker too — stone_worker.tscn is a
## separate scene running the same script, so the class is the right test and the scene file
## is not.
func _opens_door(body) -> bool:
	return body is Player or body is BoneWorker


func _door_open(body):
	if not _opens_door(body):
		return
	_occupants += 1
	# Already standing open for someone else. Replaying the animation and the sound per
	# arrival would make a doorway with a worker cycling through it click continuously.
	if _occupants > 1:
		return
	play("Open")
	_play_action_sound()


func _door_close(body):
	if not _opens_door(body):
		return
	# Floored: an exit with no matching entry would otherwise drive the count negative and
	# leave the door permanently stuck open. body_exited also fires when a body is freed,
	# and a worker's cell can be cleared out from under it while it stands in the doorway.
	_occupants = maxi(0, _occupants - 1)
	if _occupants > 0:
		return
	play("Closed")
	_play_action_sound()


## Null-guarded because the lookup above finds nothing when no SoundManager is in the tree,
## and an unguarded call raises inside a signal handler — which aborts the handler after the
## animation has already been swapped, so the door would silently stop counting occupants.
func _play_action_sound() -> void:
	if sound_manager != null:
		sound_manager.play_sound(sound_manager.SoundType.DOOR_ACTION)
