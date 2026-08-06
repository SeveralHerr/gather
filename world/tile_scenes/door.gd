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
##
## ---------------------------------------------------------------------------------------
## THE COLLIDER (gather-au68.6). Until this existed the paragraph above was a description of
## an ANIMATION and nothing more: the scene was an AnimatedSprite2D with one detector Area2D
## and no physics body at all, so a door cell had zero collider and every raider walked
## straight through the front of every compound. Nothing errored and nothing looked wrong —
## the door still swung shut behind the player, it just no longer meant anything.
##
## `Blocker` is a StaticBody2D on `collision_layer = 65`, which is bit 0 ("World", what
## everything that walks masks) plus bit 7 ("Structure", the raycast-only layer the tileset
## now puts every wall polygon on a second time). Both bits matter and for different reasons:
## bit 0 is what physically stops a body, bit 7 is what lets line-of-sight ask "is there a
## WALL between me and the player" without the answer also being yes for a tree or the sea.
## A door in a wall run has to answer that question the same way the wall either side of it
## does, or a turret and an enemy would disagree about whether the gateway is cover.
##
## The shape is 16x16 — flush with the wall tiles it stands between, so a closed run has no
## seam in it. The DETECTOR is 24x24, i.e. deliberately larger, and that inequality is the
## whole reason the door does not shove the player. Both were 16x16 and the body that opens
## the door would reach the blocker on the same frame the area fired; `set_deferred` lands the
## disable at the END of that frame, so the player got stopped dead for a frame on every
## single doorway. The 4px of overhang is one to three physics frames of warning at walking
## speed, which is the margin that turns "the door opens as you arrive" into the truth.
##
## ---------------------------------------------------------------------------------------
## DOES IT OPEN FOR ENEMIES? No, and that is a decision rather than an omission.
##
## The two failure modes are real and they are not symmetrical. A door that opens for a
## raider is a hole with an animation on it — the player builds a wall, cuts a gate in it so
## their workers can reach the chests, and the gate is exactly where every raider walks in.
## A door that never opens for a raider leaves a skeleton standing outside it, which is
## precisely what a wall is FOR: gather-au68's whole point is that walls, doors and turrets
## should be a defense rather than scenery. The stuck raider is not a bug here, it is the
## wall working, and the answer to it is the Breaker in the destructible-structures work
## (gather-au68), which breaks the door down rather than opening it.
##
## Concretely: `_opens_door` stays a Player-or-BoneWorker type test. The detector's mask 33
## (bit 0 "World" + bit 5 "Worker") is what feeds it, and enemies DO trip body_entered
## because they are on bit 0 too — so the type test is the only thing standing between a
## skeleton and an open door. Widening it "so enemies don't get stuck" undoes this issue.

@onready var collider = $Area2D

## The physics half of the door. Held as the SHAPE rather than the body, because what gets
## toggled is `CollisionShape2D.disabled`: freeing or re-adding the body would re-run the
## broadphase and re-fire body_entered on whoever is standing in the doorway, which drives
## `_occupants` up without a matching exit and jams the door open forever.
@onready var blocker: CollisionShape2D = $Blocker/CollisionShape2D

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

	# A door is not in the SaveLoad group and persists nothing: the tilemap rebuilds it from
	# the cell, so a loaded door comes back fresh with `animation = "Closed"` and no
	# occupants. Syncing here rather than trusting the scene's authored `disabled = false`
	# is what keeps those two halves from disagreeing — the animation and the collider are
	# two representations of the same fact, and a door that LOOKS shut while letting a raider
	# through reads as the collider never having been added at all. If anyone gives the door
	# a saved open/closed state later, restore `_occupants` and call this; do not set
	# `animation` on its own.
	_sync_blocker()

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
	# Before the early return, not after: the animation is allowed to be a no-op for the
	# second arrival, the collider never is.
	_sync_blocker()
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
	_sync_blocker()
	if _occupants > 0:
		return
	play("Closed")
	_play_action_sound()


## The collider follows the occupancy count, which is the same thing the animation follows.
## Derived from `_occupants` on every call rather than toggled, for the reason the count
## exists at all: with two openers in the doorway a plain flip lets whoever leaves first put
## the wall back up inside the one still standing in it.
##
## `set_deferred` is not defensive here. Both callers are Area2D signal handlers, which Godot
## emits during the physics query flush, and a direct write to `disabled` in that window is
## silently REFUSED — no error, no warning, just a door that never opens and a player who
## cannot get into their own house. The cost is that the change lands at the end of the
## frame, which is exactly why the detector is bigger than the blocker; see the header.
func _sync_blocker() -> void:
	# Null only in the frame before _ready, and only ever reachable if someone moves the
	# signal connections above the @onready block.
	if blocker == null:
		return
	blocker.set_deferred("disabled", _occupants > 0)


## Null-guarded because the lookup above finds nothing when no SoundManager is in the tree,
## and an unguarded call raises inside a signal handler — which aborts the handler after the
## animation has already been swapped, so the door would silently stop counting occupants.
func _play_action_sound() -> void:
	if sound_manager != null:
		sound_manager.play_sound(sound_manager.SoundType.DOOR_ACTION)
