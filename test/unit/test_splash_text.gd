extends RefCounted

## Covers SplashText: the pure text/colour helpers, the label configuration, where the
## splash gets parented, and - the one that actually matters for a game that spawns these
## constantly - that every splash frees itself. A leaked splash per gather would show up
## as steady orphan growth long before it showed up on screen.

var _T

## Stand-in for main.tscn's "Main/Node2D": SplashText resolves its container by that path
## from the scene-tree root, and a --script run has no main scene, so the test builds one.
var host: Node
var world: Node2D
## Node the splash is spawned "from". Freeing it must not affect the splash.
var source: Node2D


func setup() -> void:
	var tree := Engine.get_main_loop() as SceneTree

	# The suite runs from _initialize(), i.e. before the first frame, and until the main
	# loop has ticked once nothing added to root reports is_inside_tree(). SplashText
	# refuses to spawn from a source outside the tree, so the very first test would
	# otherwise get a null splash and every "did it free itself?" assertion would pass
	# vacuously. setup() is awaited by the runner, so one frame here fixes all of them.
	await tree.process_frame

	host = Node.new()
	host.name = "Main"
	world = Node2D.new()
	world.name = "Node2D"
	host.add_child(world)
	tree.root.add_child(host)

	source = Node2D.new()
	source.name = "Source"
	world.add_child(source)


func teardown() -> void:
	if host and is_instance_valid(host):
		var parent := host.get_parent()
		if parent:
			parent.remove_child(host)
		# free(), not queue_free(): the orphan gate watches deferred deletions too.
		host.free()
	host = null
	world = null
	source = null


## Pumps frames until `node` is gone, or the deadline passes. Returns true if it went.
## Bounded by wall clock because the splash's own tween runs on real elapsed time.
func _await_free(node: Node, timeout_ms: int) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if not is_instance_valid(node):
			return true
		await tree.process_frame
	return not is_instance_valid(node)


func _settle() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await tree.process_frame


# --- pure helpers ---

func test_splash_format_xp_reads_as_a_gain() -> String:
	var err: String = _T.assert_eq(SplashText.format_xp(1), "+1 XP", "a single point")
	if err != "":
		return err

	return _T.assert_eq(SplashText.format_xp(12), "+12 XP", "a double-digit gain")


func test_splash_format_xp_refuses_non_positive() -> String:
	# An event that granted nothing must not pop a "+0 XP".
	var err: String = _T.assert_eq(SplashText.format_xp(0), "", "zero formats to nothing")
	if err != "":
		return err

	return _T.assert_eq(SplashText.format_xp(-4), "", "a negative amount formats to nothing")


func test_splash_colour_ramp_warms_up() -> String:
	var err: String = _T.assert_eq(
		SplashText.color_for_xp(1), SplashText.COLOR_XP_SMALL, "a pickup tick stays cool"
	)
	if err != "":
		return err

	err = _T.assert_eq(
		SplashText.color_for_xp(SplashText.XP_MEDIUM_AT),
		SplashText.COLOR_XP_MEDIUM,
		"the medium threshold is inclusive"
	)
	if err != "":
		return err

	err = _T.assert_eq(
		SplashText.color_for_xp(SplashText.XP_LARGE_AT - 1),
		SplashText.COLOR_XP_MEDIUM,
		"one short of large is still medium"
	)
	if err != "":
		return err

	return _T.assert_eq(
		SplashText.color_for_xp(SplashText.XP_LARGE_AT + 5),
		SplashText.COLOR_XP_LARGE,
		"a gold vein burns hot"
	)


# --- configuration ---

func test_splash_spawn_configures_the_label() -> String:
	var colour := Color(0.2, 0.4, 0.8)
	var splash := SplashText.spawn(source, Vector2(64.0, 32.0), "+7 XP", colour)

	var err: String = _T.assert_true(splash != null, "spawning inside a tree returns a splash")
	if err != "":
		return err

	err = _T.assert_eq(splash.text, "+7 XP", "the text is what was asked for")
	if err != "":
		return err

	err = _T.assert_eq(splash.get_theme_color("font_color"), colour, "the colour is applied")
	if err != "":
		return err

	err = _T.assert_eq(
		splash.get_theme_font_size("font_size"), SplashText.FONT_SIZE, "font size is overridden"
	)
	if err != "":
		return err

	# The outline is what keeps the number legible over 16px tile art.
	err = _T.assert_eq(
		splash.get_theme_constant("outline_size"), SplashText.OUTLINE_SIZE, "the outline is on"
	)
	if err != "":
		return err

	# A splash must never eat a click meant for the world underneath it.
	err = _T.assert_eq(
		splash.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the splash ignores the mouse"
	)
	if err != "":
		return err

	return _T.assert_float_eq(
		splash.scale.x, SplashText.WORLD_SCALE, 0.001, "scaled down for the zoomed-in camera"
	)


func test_splash_empty_text_spawns_nothing() -> String:
	var splash := SplashText.spawn(source, Vector2.ZERO, "")
	return _T.assert_true(splash == null, "an empty splash is not worth a node")


func test_splash_xp_skips_non_positive() -> String:
	var before := world.get_child_count()

	var splash := SplashText.spawn_xp(source, Vector2.ZERO, 0)
	var err: String = _T.assert_true(splash == null, "zero xp spawns no splash")
	if err != "":
		return err

	return _T.assert_eq(world.get_child_count(), before, "and creates no container either")


func test_splash_xp_uses_the_ramp() -> String:
	var splash := SplashText.spawn_xp(source, Vector2.ZERO, SplashText.XP_LARGE_AT)

	var err: String = _T.assert_eq(splash.text, "+%d XP" % SplashText.XP_LARGE_AT, "formatted")
	if err != "":
		return err

	return _T.assert_eq(
		splash.get_theme_color("font_color"), SplashText.COLOR_XP_LARGE, "coloured by amount"
	)


func test_splash_big_emphasis_is_visibly_larger() -> String:
	var normal := SplashText.spawn(source, Vector2.ZERO, "+1 XP")
	var big := SplashText.spawn(
		source, Vector2.ZERO, "LEVEL 7!", SplashText.COLOR_LEVEL, SplashText.Emphasis.BIG
	)

	return _T.assert_gt(big.scale.x, normal.scale.x, "a level-up outsizes an ordinary gain")


func test_splash_outside_the_tree_is_a_no_op() -> String:
	var orphan := Node2D.new()
	var splash := SplashText.spawn(orphan, Vector2.ZERO, "+1 XP")
	orphan.free()

	return _T.assert_true(splash == null, "a source with no tree cannot place a splash")


# --- ownership ---

func test_splash_is_parented_to_the_world_not_the_source() -> String:
	var splash := SplashText.spawn(source, Vector2(10.0, 10.0), "+1 XP")

	var err: String = _T.assert_true(splash != null, "the splash was created")
	if err != "":
		return err

	var container := splash.get_parent()
	err = _T.assert_eq(
		container.name, StringName(SplashText.CONTAINER_NAME), "it lands in the shared container"
	)
	if err != "":
		return err

	err = _T.assert_eq(container.get_parent(), world, "the container hangs off the world host")
	if err != "":
		return err

	return _T.assert_true(
		splash.get_parent() != source, "the thing that triggered it does not own it"
	)


func test_splash_outlives_the_node_that_spawned_it() -> String:
	# The case this exists for: an enemy killed by the same hit that spawns its splash.
	var doomed := Node2D.new()
	world.add_child(doomed)

	var splash := SplashText.spawn(doomed, Vector2(5.0, 5.0), "+5 XP")
	var err: String = _T.assert_true(splash != null, "the splash was created")
	if err != "":
		return err

	doomed.queue_free()
	await _settle()

	return _T.assert_true(
		is_instance_valid(splash), "the splash survives the death of its spawner"
	)


func test_two_splashes_in_the_same_frame_do_not_overlap() -> String:
	var first := SplashText.spawn(source, Vector2(40.0, 40.0), "+1 XP")
	var second := SplashText.spawn(source, Vector2(40.0, 40.0), "+1 XP")

	return _T.assert_true(
		first.position != second.position, "the stagger separates simultaneous splashes"
	)


# --- lifetime ---

func test_splash_frees_itself_when_the_animation_ends() -> String:
	var splash := SplashText.spawn(source, Vector2.ZERO, "+1 XP")

	# Without this the whole test passes vacuously when spawn() returns null.
	var err: String = _T.assert_true(splash != null, "the splash was created")
	if err != "":
		return err

	# Generous cap: the tween runs on real elapsed time (LIFETIME is ~0.85s).
	var gone: bool = await _await_free(splash, 5000)
	return _T.assert_true(gone, "the splash frees itself rather than leaking")


func test_guard_frees_the_splash_when_the_tween_is_killed() -> String:
	var splash := SplashText.spawn(source, Vector2.ZERO, "+1 XP")

	# Simulate the tween being killed early (scene change, time-scale weirdness): the
	# SceneTreeTimer backstop is the only thing left that can free the node.
	var tree := Engine.get_main_loop() as SceneTree
	for tween in tree.get_processed_tweens():
		tween.kill()

	splash._on_guard_timeout()
	await _settle()

	return _T.assert_false(is_instance_valid(splash), "the guard frees an abandoned splash")


func test_splash_finishing_twice_is_harmless() -> String:
	# The tween callback and the guard can both fire; the second must not double-free.
	var splash := SplashText.spawn(source, Vector2.ZERO, "+1 XP")
	splash._finish()
	splash._on_guard_timeout()
	await _settle()

	return _T.assert_false(is_instance_valid(splash), "still gone, and no crash on the way")


func test_a_burst_of_splashes_leaves_nothing_behind() -> String:
	var splashes: Array = []
	for i in range(12):
		splashes.append(SplashText.spawn_xp(source, Vector2(i * 8.0, 0.0), 1 + i))

	var err: String = _T.assert_eq(splashes.size(), 12, "the burst really spawned")
	if err != "":
		return err
	err = _T.assert_true(splashes[0] != null, "and none of them came back null")
	if err != "":
		return err

	var deadline := Time.get_ticks_msec() + 6000
	var tree := Engine.get_main_loop() as SceneTree
	var live := splashes.size()
	while Time.get_ticks_msec() < deadline and live > 0:
		await tree.process_frame
		live = 0
		for splash in splashes:
			if is_instance_valid(splash):
				live += 1

	return _T.assert_eq(live, 0, "every splash in a burst cleans itself up")

