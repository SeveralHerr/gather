extends RefCounted

## Covers SplashText: the pure text/colour helpers, the label configuration, where the
## splash gets parented, and - the one that actually matters for a game that spawns these
## constantly - that every splash frees itself. A leaked splash per gather would show up
## as steady orphan growth long before it showed up on screen.

var _T

## Stand-in for main.tscn's "Main/World": SplashText resolves its container by that path
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
	world.name = "World"
	host.add_child(world)
	tree.root.add_child(host)

	source = Node2D.new()
	source.name = "Source"
	world.add_child(source)

	# `SplashText._sparkle` is a static var that deliberately outlives any one splash, and
	# teardown() hard-free()s the world it parents itself to. Reset it here rather than
	# relying on that free, so the sparkle assertions below never depend on which test ran
	# first (the runner does not promise an order).
	if SplashText._sparkle != null and is_instance_valid(SplashText._sparkle):
		var stale_parent := SplashText._sparkle.get_parent()
		if stale_parent != null:
			stale_parent.remove_child(SplashText._sparkle)
		SplashText._sparkle.free()
	SplashText._sparkle = null


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


## How many shared sparkle emitters are parked on the world host. Matched by prefix, not by
## equality: Godot silently renames a second child that wants a name already in use
## ("SplashSparkle2"), so an exact-name count is exactly the count that would fail to notice
## the leak this asserts against.
func _sparkle_children() -> int:
	var found := 0
	for child in world.get_children():
		if String(child.name).begins_with(SplashText.SPARKLE_NAME):
			found += 1
	return found


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


func test_tier_for_xp_marks_the_band_edges() -> String:
	# tier_for_xp is the single definition of the thresholds and color_for_xp is written in
	# terms of it, so the two can never disagree - which is exactly the thing worth pinning,
	# because the tier-up sparkle fires off the tier while the player judges it by the colour.
	var cases := [
		[SplashText.XP_MEDIUM_AT - 1, 0, SplashText.COLOR_XP_SMALL],
		[SplashText.XP_MEDIUM_AT, 1, SplashText.COLOR_XP_MEDIUM],
		[SplashText.XP_LARGE_AT - 1, 1, SplashText.COLOR_XP_MEDIUM],
		[SplashText.XP_LARGE_AT, 2, SplashText.COLOR_XP_LARGE],
	]

	for case in cases:
		var amount: int = case[0]
		var err: String = _T.assert_eq(
			SplashText.tier_for_xp(amount), case[1], "the tier at %d xp" % amount
		)
		if err != "":
			return err

		err = _T.assert_eq(
			SplashText.color_for_xp(amount), case[2], "the colour agrees with the tier at %d xp" % amount
		)
		if err != "":
			return err

	return ""


# --- pixel scale ---

func test_pixel_scale_falls_back_when_there_is_no_camera() -> String:
	var err: String = _T.assert_float_eq(
		SplashText.pixel_scale(null), SplashText.WORLD_SCALE, 0.0001, "a null source"
	)
	if err != "":
		return err

	var orphan := Node2D.new()
	err = _T.assert_float_eq(
		SplashText.pixel_scale(orphan), SplashText.WORLD_SCALE, 0.0001, "a source outside the tree"
	)
	orphan.free()
	if err != "":
		return err

	# The test world has no Camera2D, which is the case every other test in this file runs in.
	return _T.assert_float_eq(
		SplashText.pixel_scale(source), SplashText.WORLD_SCALE, 0.0001, "in the tree, but no camera"
	)


func test_pixel_scale_reads_the_live_camera_zoom() -> String:
	# THIS IS THE ASSERTION THAT WOULD HAVE CAUGHT THE ORIGINAL BLUR BUG. The splash scale was
	# a hardcoded constant tuned for a camera at zoom 4.935; main.tscn moved to zoom 8 and the
	# constant did not, so every splash was a 16px glyph atlas magnified 1.6x through a linear
	# filter. pixel_scale asks the live camera instead, and 1/zoom is the only value that draws
	# one rasterized glyph pixel on one screen pixel.
	var camera := Camera2D.new()
	camera.name = "TestCamera"
	camera.zoom = Vector2(8.0, 8.0)
	world.add_child(camera)
	camera.make_current()

	var err: String = _T.assert_float_eq(
		SplashText.pixel_scale(source),
		0.125,
		0.0001,
		"a zoom-8 camera must give exactly 1/8, or splashes are resampled and go soft"
	)
	if err != "":
		return err

	# A second zoom, because 1/8 happens to equal WORLD_SCALE: without this the test would
	# still pass if pixel_scale ignored the camera and returned the fallback constant, which
	# is precisely the failure mode above.
	camera.zoom = Vector2(4.0, 4.0)
	err = _T.assert_float_eq(
		SplashText.pixel_scale(source),
		0.25,
		0.0001,
		"the scale follows the live camera rather than a constant that can go stale"
	)
	if err != "":
		return err

	# And a splash spawned under that camera adopts it, so the wiring is not just the helper.
	var splash := SplashText.spawn(source, Vector2.ZERO, "+1 XP")
	err = _T.assert_true(splash != null, "the splash was created")
	if err != "":
		return err

	return _T.assert_float_eq(
		splash.scale.x, 0.25, 0.0001, "spawn() pins the transform to the camera's 1/zoom"
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


# --- xp coalescing ---

func test_xp_awards_in_one_place_become_a_single_label() -> String:
	# The case this exists for: one tree pays xp for the node and again for every third
	# item the vacuum sweeps up, all within a couple of tiles.
	var first := SplashText.spawn_xp(source, Vector2(40.0, 40.0), 1)
	var err: String = _T.assert_true(first != null, "the first award made a splash")
	if err != "":
		return err

	var second := SplashText.spawn_xp(source, Vector2(44.0, 38.0), 2)
	var third := SplashText.spawn_xp(source, Vector2(40.0, 46.0), 3)

	err = _T.assert_eq(second, first, "a nearby award folds into the label already in the air")
	if err != "":
		return err
	err = _T.assert_eq(third, first, "and so does the next one")
	if err != "":
		return err

	return _T.assert_eq(first.text, "+6 XP", "the label shows the running total, not the last tick")


func test_a_coalesced_label_walks_up_the_colour_ramp() -> String:
	var splash := SplashText.spawn_xp(source, Vector2.ZERO, 1)
	var err: String = _T.assert_eq(
		splash.get_theme_color("font_color"), SplashText.COLOR_XP_SMALL, "one tick is cool"
	)
	if err != "":
		return err

	SplashText.spawn_xp(source, Vector2.ZERO, SplashText.XP_LARGE_AT)

	return _T.assert_eq(
		splash.get_theme_color("font_color"),
		SplashText.COLOR_XP_LARGE,
		"the total, not the tick, decides the colour"
	)


func test_a_coalesced_label_swells() -> String:
	# This asserts FONT SIZE and not transform scale, on purpose, and it also asserts that the
	# transform scale does NOT move. A Label rasterizes its glyphs once at `font_size` and the
	# GPU resamples that atlas through the transform, so growing a splash by growing `scale`
	# is magnifying a bitmap - that was the "the xp text looks soft" bug. The scale is now
	# pinned to 1/zoom so glyphs draw 1:1, and every size change re-rasterizes instead.
	# If a future reader is tempted to point these assertions back at `_base_scale`: that is
	# the regression, not the fix.
	var splash := SplashText.spawn_xp(source, Vector2.ZERO, 1)
	var before_px: int = splash.get_theme_font_size("font_size")
	var before_scale: float = splash._base_scale

	SplashText.spawn_xp(source, Vector2.ZERO, 1)

	var err: String = _T.assert_gt(
		splash.get_theme_font_size("font_size"), before_px, "each tick re-rasterizes larger"
	)
	if err != "":
		return err

	err = _T.assert_float_eq(
		splash._base_scale,
		before_scale,
		0.0001,
		"absorbing must leave the transform scale pinned at 1/zoom - scale-based growth is blur"
	)
	if err != "":
		return err

	# The swell is capped, or a long gather ends with a label wider than the screen.
	for i in range(60):
		SplashText.spawn_xp(source, Vector2.ZERO, 1)

	var capped := int(round(float(SplashText.FONT_SIZE) * SplashText.XP_STACK_SCALE_MAX))
	var grown: int = splash.get_theme_font_size("font_size")
	err = _T.assert_true(
		grown <= capped,
		"the growth is capped at XP_STACK_SCALE_MAX (%d px), got %d" % [capped, grown]
	)
	if err != "":
		return err

	return _T.assert_float_eq(
		splash._base_scale,
		before_scale,
		0.0001,
		"and 60 absorbs later the scale is still 1/zoom, not 1.75x of it"
	)


func test_the_swell_re_rasterizes_the_outline_too() -> String:
	# The tell that a swell is a re-rasterization and not a transform scale: a scaled label
	# keeps its 4px outline constant and lets the GPU blow it up, while a re-rasterized one
	# has to redraw a proportionally thicker halo. If the outline stopped tracking the font,
	# the glyphs are being magnified again.
	var splash := SplashText.spawn_xp(source, Vector2.ZERO, 1)
	var err: String = _T.assert_eq(
		splash.get_theme_constant("outline_size"), SplashText.OUTLINE_SIZE, "one tick is the base halo"
	)
	if err != "":
		return err

	for i in range(20):
		SplashText.spawn_xp(source, Vector2.ZERO, 1)

	err = _T.assert_gt(
		splash.get_theme_font_size("font_size"), SplashText.FONT_SIZE, "the streak swelled the glyphs"
	)
	if err != "":
		return err

	return _T.assert_gt(
		splash.get_theme_constant("outline_size"),
		SplashText.OUTLINE_SIZE,
		"and the outline grew with them rather than staying a fixed slab"
	)


func test_a_tier_up_creates_exactly_one_shared_sparkle() -> String:
	# The emitter is a static, created on first use and never freed - a node per burst is the
	# orphan-budget leak the gather emitters were fixed for. setup() resets that static, so
	# this counts from a known zero regardless of test order.
	var splash := SplashText.spawn_xp(source, Vector2.ZERO, 1)
	var err: String = _T.assert_true(splash != null, "the first award made a splash")
	if err != "":
		return err

	err = _T.assert_eq(_sparkle_children(), 0, "a lone +1 XP is not a celebration")
	if err != "":
		return err

	# Cross XP_MEDIUM_AT, then XP_LARGE_AT: two tier-ups folded into one label.
	SplashText.spawn_xp(source, Vector2.ZERO, SplashText.XP_MEDIUM_AT)
	err = _T.assert_eq(_sparkle_children(), 1, "crossing a colour band lights the emitter")
	if err != "":
		return err

	SplashText.spawn_xp(source, Vector2.ZERO, SplashText.XP_LARGE_AT)
	err = _T.assert_eq(
		_sparkle_children(), 1, "the second band restarts the same emitter instead of adding one"
	)
	if err != "":
		return err

	# It parks on the world host, NOT in the splash container: devtools reports `live_splashes`
	# as that container's child count and a permanent resident reads as a leak that never drains.
	var container := splash.get_parent()
	for child in container.get_children():
		if String(child.name).begins_with(SplashText.SPARKLE_NAME):
			return "the sparkle must not live in %s - it would read as a stuck splash" % SplashText.CONTAINER_NAME

	return ""


func test_xp_far_away_gets_its_own_label() -> String:
	# A kill across the island is a different event and must not be swallowed by the label
	# floating over the tree the player is chopping.
	var near := SplashText.spawn_xp(source, Vector2.ZERO, 1)
	var far := SplashText.spawn_xp(
		source, Vector2(SplashText.XP_STACK_RADIUS * 3.0, 0.0), 3
	)

	var err: String = _T.assert_true(far != null, "the distant award made a splash")
	if err != "":
		return err

	err = _T.assert_true(far != near, "and it is not the one already in the air")
	if err != "":
		return err

	return _T.assert_eq(near.text, "+1 XP", "the near label was left alone")


func test_a_finished_xp_label_does_not_absorb() -> String:
	# Otherwise the static reference outlives the node it points at and the next gather's
	# xp is added to a splash on its way out - or to a freed one.
	var first := SplashText.spawn_xp(source, Vector2.ZERO, 1)
	first._finish()
	await _settle()

	var second := SplashText.spawn_xp(source, Vector2.ZERO, 2)
	var err: String = _T.assert_true(second != null, "the next award still gets a splash")
	if err != "":
		return err

	return _T.assert_eq(second.text, "+2 XP", "and it starts its own total")


func test_splash_big_emphasis_is_visibly_larger() -> String:
	# Emphasis is a font-size difference, not a transform difference. Both labels sit at
	# exactly 1/zoom so their glyphs rasterize 1:1; a milestone is bigger because it is
	# rasterized bigger. The equal `scale.x` below is asserted deliberately - it is the
	# crispness invariant, so "fixing" this back to assert_gt on scale reintroduces the blur.
	var normal := SplashText.spawn(source, Vector2.ZERO, "+1 XP")
	var big := SplashText.spawn(
		source, Vector2.ZERO, "LEVEL 7!", SplashText.COLOR_LEVEL, SplashText.Emphasis.BIG
	)

	var err: String = _T.assert_gt(
		big.get_theme_font_size("font_size"),
		normal.get_theme_font_size("font_size"),
		"a level-up outsizes an ordinary gain"
	)
	if err != "":
		return err

	return _T.assert_float_eq(
		big.scale.x, normal.scale.x, 0.0001, "both draw 1:1; only the rasterized size differs"
	)


func test_a_splash_with_no_streak_never_rattles() -> String:
	# The wobble is the reward for a run of gathers. A single event must sit dead straight, or
	# every "+1 XP" in the game acquires a permanent tilt.
	var plain := SplashText.spawn(source, Vector2.ZERO, "+1 XP")
	var single := SplashText.spawn_xp(source, Vector2(200.0, 0.0), 1)

	var err: String = _T.assert_true(plain != null and single != null, "both splashes were created")
	if err != "":
		return err

	# Rotation is only written from _process, so this has to run a couple of frames.
	await _settle()

	err = _T.assert_true(
		is_instance_valid(plain) and is_instance_valid(single), "both are still in the air"
	)
	if err != "":
		return err

	err = _T.assert_float_eq(plain.rotation, 0.0, 0.0001, "an ordinary splash does not rattle")
	if err != "":
		return err

	return _T.assert_float_eq(
		single.rotation, 0.0, 0.0001, "and neither does an xp label that has absorbed nothing"
	)


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
	# spawn(), not spawn_xp(): a burst of xp deliberately collapses into one label now, so
	# this drives the twelve-live-splashes case through the general entry point. Level-ups
	# and skill points still arrive as separate splashes.
	var splashes: Array = []
	for i in range(12):
		splashes.append(SplashText.spawn(source, Vector2(i * 8.0, 0.0), "+%d XP" % (1 + i)))

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

