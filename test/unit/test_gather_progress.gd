extends RefCounted

## Covers the GatherProgress indicator's state machine. The drawing itself is not
## unit-testable, but the progress value feeding it is, and a bar that reports a
## stale or out-of-range value is exactly how this kind of indicator goes wrong.

var _T

var bar: GatherProgress


func setup() -> void:
	bar = GatherProgress.new()
	# _ready is not called automatically for a node outside the tree.
	bar._ready()


func teardown() -> void:
	if bar:
		bar.free()
		bar = null


func test_starts_hidden_and_empty() -> String:
	var err: String = _T.assert_false(bar.visible, "the bar is hidden until a gather starts")
	if err != "":
		return err

	return _T.assert_eq(bar.progress, 0.0, "the bar starts empty")


func test_begin_shows_the_bar_above_the_node() -> String:
	bar.begin(Vector2(100.0, 200.0))

	var err: String = _T.assert_true(bar.visible, "beginning a gather shows the bar")
	if err != "":
		return err

	err = _T.assert_eq(bar.progress, 0.0, "a fresh gather starts from empty")
	if err != "":
		return err

	# Positioned above the node so it does not sit on top of the tile art.
	err = _T.assert_eq(bar.global_position.x, 100.0, "the bar is centred on the node")
	if err != "":
		return err

	return _T.assert_true(bar.global_position.y < 200.0, "the bar sits above the node")


func test_progress_is_clamped_to_unit_range() -> String:
	bar.set_progress(-5.0)
	var err: String = _T.assert_eq(bar.progress, 0.0, "negative progress clamps to empty")
	if err != "":
		return err

	bar.set_progress(37.0)
	return _T.assert_eq(bar.progress, 1.0, "overshooting progress clamps to full")


func test_progress_tracks_intermediate_values() -> String:
	bar.set_progress(0.25)
	var err: String = _T.assert_float_eq(bar.progress, 0.25, 0.001, "a quarter through")
	if err != "":
		return err

	bar.set_progress(0.8)
	return _T.assert_float_eq(bar.progress, 0.8, 0.001, "most of the way through")


func test_finish_hides_and_resets() -> String:
	bar.begin(Vector2.ZERO)
	bar.set_progress(0.9)
	bar.finish()

	var err: String = _T.assert_false(bar.visible, "finishing hides the bar")
	if err != "":
		return err

	# Resetting matters: an interrupted gather must not leave a partly filled bar
	# that reappears mid-way through the next one.
	return _T.assert_eq(bar.progress, 0.0, "finishing empties the bar")


func test_reuse_after_an_interrupted_gather_starts_clean() -> String:
	bar.begin(Vector2.ZERO)
	bar.set_progress(0.7)
	bar.finish()
	bar.begin(Vector2(50.0, 50.0))

	return _T.assert_eq(bar.progress, 0.0, "the next gather starts from empty")
