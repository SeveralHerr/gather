extends RefCounted

## The boss's reward chest, and the sequence between "the boss died" and "the chest is on the
## ground".
##
## The animation itself is decoration and is not what these assert. What they assert is that
## the sequence TERMINATES and hands the reward over: a fall that never settles, or a `landed`
## that never fires, is a chest the player killed the boss for and never receives - and it
## fails silently, because a chest that is missing looks exactly like a chest that has already
## been looted.

var _T


## How long the whole drop is allowed to take before the test calls it stuck. The fall alone
## is ~0.6s and the bounces add roughly half of that, so 4s is a wide margin around a
## sequence whose real failure mode is never finishing at all.
const TIMEOUT_SECONDS := 4.0


func _drive(chest: FallingChest, seconds: float) -> float:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var elapsed := 0.0
	while elapsed < seconds and is_instance_valid(chest) and not chest._done:
		await tree.process_frame
		elapsed += tree.root.get_process_delta_time()
	return elapsed


## The one that matters. Headless still runs _process, so this is the real integrator over
## real frames rather than a re-derivation of it.
func test_falling_chest_lands_and_hands_the_reward_over() -> String:
	var chest := FallingChest.drop(null)
	var hosted: Node = await _T.instantiate_scene(chest)
	if hosted == null:
		return "could not host the falling chest"

	var landed := [false]
	chest.landed.connect(func(): landed[0] = true)

	var elapsed: float = await _drive(chest, TIMEOUT_SECONDS)

	var finished: String = _T.assert_true(
		chest._done, "chest never finished falling (%0.2fs of a %0.1fs budget)" % [elapsed, TIMEOUT_SECONDS]
	)
	if finished != "":
		_T.free_ui(hosted)
		return finished

	var signalled: String = _T.assert_true(landed[0], "chest settled without emitting landed")
	var grounded: String = _T.assert_float_eq(chest._height, 0.0, 0.01, "chest settled off the ground")

	_T.free_ui(hosted)
	return signalled if signalled != "" else grounded


## It has to actually go up before it comes down, and it has to bounce. Both are the joke -
## a chest that teleports to the floor on frame one is not a chest falling from the sky - and
## both are the kind of thing a tuning pass silently zeroes out.
func test_falling_chest_starts_airborne_and_bounces() -> String:
	var chest := FallingChest.drop(null)
	var hosted: Node = await _T.instantiate_scene(chest)
	if hosted == null:
		return "could not host the falling chest"

	# Most of DROP_HEIGHT rather than all of it: instantiate_scene settles the tree for two
	# frames before this line runs, and the chest is already falling in them.
	var start: String = _T.assert_gt(
		chest._height,
		FallingChest.DROP_HEIGHT * 0.9,
		"chest was at %0.1fpx a couple of frames in, nowhere near its %0.0fpx drop height"
			% [chest._height, FallingChest.DROP_HEIGHT]
	)
	if start != "":
		_T.free_ui(hosted)
		return start

	await _drive(chest, TIMEOUT_SECONDS)

	var bounced: String = _T.assert_gt(chest._bounces, 0, "chest landed dead, with no bounce at all")
	_T.free_ui(hosted)
	return bounced


## The drop height has to clear the top of the screen, or the chest does not fall INTO frame,
## it appears in mid-air a few tiles up. The window is 1080 tall at the camera's zoom 8, so
## half the visible world is 67px above the player - anything less than that is on screen from
## the first frame.
func test_chest_starts_above_the_visible_world() -> String:
	var half_screen_world_height := 1080.0 / 8.0 / 2.0
	return _T.assert_gt(
		FallingChest.DROP_HEIGHT,
		half_screen_world_height,
		"a chest dropped from %0.0fpx is already on screen when it spawns" % FallingChest.DROP_HEIGHT
	)
