extends RefCounted

## Guards for the shared UI kit — `UiTheme`'s sizing arithmetic and `PanelFrame`'s
## chrome.
##
## The point of the kit is that every panel gets a close button and a legible size
## *by construction* rather than by each author remembering. That only holds if the
## construction itself is guarded, so these tests assert the two properties the
## panels are now allowed to assume: a control sized through `scaled_touch()` is
## never below the touch floor at any viewport, and a `PanelFrame` always has a
## working way out.

var _T  # assertion helper injected by run_tests.gd


# --- UiTheme sizing ----------------------------------------------------------

func test_scale_is_clamped_at_both_ends() -> String:
	# A phone far below the reference edge and a 4K window far above it both have
	# to land inside the clamp — unbounded, the first shrinks the chrome into
	# illegibility and the second inflates it into a cartoon.
	var tiny := UiTheme.scale_for(Vector2(320, 480))
	var huge := UiTheme.scale_for(Vector2(3840, 2160))

	var a: String = _T.assert_float_eq(tiny, UiTheme.SCALE_MIN, 0.001,
		"a 320x480 phone should clamp to SCALE_MIN")
	if a != "":
		return a

	return _T.assert_float_eq(huge, UiTheme.SCALE_MAX, 0.001,
		"a 3840x2160 window should clamp to SCALE_MAX")


func test_the_reference_edge_scales_to_exactly_one() -> String:
	# The base sizes in UiTheme were chosen against this viewport, so it is the one
	# input that must pass through unchanged. If this drifts, every hardcoded base
	# size in every panel silently means something different.
	var factor := UiTheme.scale_for(Vector2(1280, UiTheme.REFERENCE_EDGE))
	return _T.assert_float_eq(factor, 1.0, 0.001, "the reference edge should scale to 1.0")


func test_a_degenerate_viewport_does_not_produce_a_zero_scale() -> String:
	# Headless pumps no frames, so a Control that has not been through
	# instantiate_ui() reports size (0, 0). Returning 0.0 there would collapse every
	# font size to FONT_MIN and every panel to nothing, which looks like a layout
	# bug rather than a missing frame.
	var factor := UiTheme.scale_for(Vector2.ZERO)
	return _T.assert_float_eq(factor, 1.0, 0.001, "a zero viewport should fall back to 1.0")


func test_touch_targets_never_fall_below_the_floor() -> String:
	# The whole point of scaled_touch over scaled: on the smallest viewport the
	# clamp still multiplies by 0.85, so a 34px base would come out at 28.9px — well
	# under a fingertip. This is the guard for the user-visible "too small on
	# mobile" complaint.
	var small := UiTheme.scaled_touch(34.0, UiTheme.scale_for(Vector2(320, 480)))
	var a: String = _T.assert_gte(small, UiTheme.TOUCH_MIN,
		"a small base on a small viewport must still clear TOUCH_MIN")
	if a != "":
		return a

	# And it must not clamp *down* something already comfortably large.
	var large := UiTheme.scaled_touch(120.0, UiTheme.scale_for(Vector2(1280, 720)))
	return _T.assert_float_eq(large, 120.0, 0.001,
		"a base already above the floor should scale, not clamp")


func test_font_sizes_never_fall_below_the_legibility_floor() -> String:
	var small := UiTheme.scaled_font(4, UiTheme.scale_for(Vector2(320, 480)))
	return _T.assert_gte(small, UiTheme.FONT_MIN,
		"even an absurdly small base must clamp up to FONT_MIN")


func test_scaling_a_viewport_derived_factor_matches_the_viewport() -> String:
	# The regression guard for `gather-snn`. Six panels used to rebuild a synthetic
	# viewport size out of a factor — `Vector2.ONE * REFERENCE_EDGE * factor` — purely
	# to feed helpers that reduced it straight back to that float. The helpers take the
	# factor now, and this pins the equivalence the old round trip was relying on: a
	# factor obtained from a viewport must size exactly as that viewport did.
	var vp := Vector2(1440, 900)
	var factor := UiTheme.scale_for(vp)

	var a: String = _T.assert_float_eq(
		UiTheme.scale_for(Vector2.ONE * UiTheme.REFERENCE_EDGE * factor), factor, 0.001,
		"re-deriving a factor from its own synthetic viewport must be a no-op")
	if a != "":
		return a

	return _T.assert_float_eq(UiTheme.scaled(UiTheme.PAD_PANEL, factor),
		UiTheme.PAD_PANEL * factor, 0.001,
		"scaled() must be a plain multiply by the factor it is handed")


func test_typography_is_applied_and_survives_a_freed_control() -> String:
	# The four panels that keep a `_typography` list rebuild their rows, which leaves
	# freed controls in it. The walk used to be inline in each panel and unguarded; a
	# stale entry would raise on the next resize — weeks later, and nowhere near the
	# rebuild that caused it.
	var live := Label.new()
	var stale := Label.new()
	var entries: Array = [[live, UiTheme.FONT_BODY], [stale, UiTheme.FONT_SMALL]]
	stale.free()

	UiTheme.apply_typography(entries, 2.0)

	var got := live.get_theme_font_size("font_size")
	live.free()

	return _T.assert_eq(got, UiTheme.scaled_font(UiTheme.FONT_BODY, 2.0),
		"the live entry should be scaled even with a freed one beside it")


func test_connect_resize_does_not_stack_handlers() -> String:
	# The `is_connected` guard is the load-bearing half: `_ready()` is not the only
	# caller, and a second connection means every size gets applied twice.
	var node := Control.new()
	await _T.instantiate_ui(node, Vector2i(640, 480))

	var handler := func() -> void: pass
	UiTheme.connect_resize(node, handler)
	UiTheme.connect_resize(node, handler)

	# Counting only *our* callable: the shared test viewport already carries whatever
	# other UI in the tree has connected, so a bare connection count is not ours to
	# assert on.
	var count := 0
	for connection in node.get_viewport().size_changed.get_connections():
		if connection["callable"] == handler:
			count += 1
	_T.free_ui(node)

	return _T.assert_eq(count, 1, "connecting twice should leave exactly one handler")


# --- PanelFrame chrome -------------------------------------------------------

func test_a_panel_frame_is_built_closed_with_content_ready() -> String:
	# setup() constructs eagerly rather than waiting for _ready(), so an owner can
	# fill `content` before parenting. If that regressed, every panel would silently
	# add its children to a null container.
	var frame := PanelFrame.new()
	frame.setup("TEST PANEL", Vector2(400, 200))

	var a: String = _T.assert_false(frame.visible, "a panel should be built closed")
	if a != "":
		frame.free()
		return a

	var b: String = _T.assert_true(frame.content != null,
		"content should be a valid container immediately after setup()")
	frame.free()
	return b


func test_every_panel_frame_has_a_close_button() -> String:
	# The regression this whole class exists to prevent: before the kit, no panel
	# had a close button, and on a phone there is no Escape key to fall back on.
	var frame := PanelFrame.new()
	frame.setup("TEST PANEL")

	var button := frame.find_child("CloseButton", true, false) as Button
	var a: String = _T.assert_true(button != null,
		"a PanelFrame must carry a CloseButton, found by name")
	frame.free()
	return a


func test_the_close_button_asks_the_owner_to_close() -> String:
	# It emits close_requested rather than hiding itself, deliberately: the owners
	# have to run their disable_input / mouse-mode handshake on the way out, and a
	# frame that just hid itself would leave the player soft-locked.
	var frame := PanelFrame.new()
	frame.setup("TEST PANEL")

	var fired := [false]
	frame.close_requested.connect(func(): fired[0] = true)

	var button := frame.find_child("CloseButton", true, false) as Button
	if button == null:
		frame.free()
		return "no CloseButton to press"

	button.pressed.emit()

	var a: String = _T.assert_true(fired[0], "pressing the close button should emit close_requested")
	frame.free()
	return a


func test_open_and_close_drive_visibility_and_signals() -> String:
	var frame := PanelFrame.new()
	frame.setup("TEST PANEL")

	var opened := [0]
	var closed := [0]
	frame.opened.connect(func(): opened[0] += 1)
	frame.closed.connect(func(): closed[0] += 1)

	frame.open()
	# Opening twice must stay idempotent — the crafting panel's own test drives
	# set_open(true) twice for exactly this reason.
	frame.open()

	var a: String = _T.assert_true(frame.is_open(), "the frame should report open")
	if a != "":
		frame.free()
		return a

	var b: String = _T.assert_eq(opened[0], 1, "opened should fire once, not per call")
	if b != "":
		frame.free()
		return b

	frame.close()
	frame.close()

	var c: String = _T.assert_false(frame.is_open(), "the frame should report closed")
	if c != "":
		frame.free()
		return c

	var d: String = _T.assert_eq(closed[0], 1, "closed should fire once, not per call")
	frame.free()
	return d


func test_the_panel_fits_and_centres_inside_a_phone_viewport() -> String:
	# The failure this guards is the one CLAUDE.md calls the gather-6fx class of
	# bug: a panel whose size was tuned for the old 1152x648 window and which
	# overflows or drifts off-centre the moment the viewport is a phone's.
	var frame := PanelFrame.new()
	frame.setup("TEST PANEL", Vector2(400, 200))
	# Open it *before* measuring. Godot does not sort containers underneath a hidden
	# Control, so a closed panel keeps whatever rect it was constructed with and
	# every geometry assertion below would be reading a stale number rather than a
	# laid-out one — it reported position (0, 0), which is the CenterContainer
	# having never run at all.
	frame.open()

	var viewport := Vector2i(390, 844)
	var node: Node = await _T.instantiate_ui(frame, viewport)
	if node == null:
		return "instantiate_ui returned null"

	var inner := node.find_child("Frame", true, false) as PanelContainer
	if inner == null:
		_T.free_ui(node)
		return "no inner Frame PanelContainer"

	var rect := inner.get_global_rect()
	var view := Vector2(viewport)

	var a: String = _T.assert_gte(rect.position.x, 0.0, "the panel should not overflow the left edge")
	if a != "":
		_T.free_ui(node)
		return a

	var b: String = _T.assert_gte(view.x - (rect.position.x + rect.size.x), 0.0,
		"the panel should not overflow the right edge")
	if b != "":
		_T.free_ui(node)
		return b

	# Centred, not pinned: the left and right gaps should match.
	var left := rect.position.x
	var right := view.x - (rect.position.x + rect.size.x)
	var c: String = _T.assert_float_eq(left, right, 1.5, "the panel should be horizontally centred")

	_T.free_ui(node)
	return c


func test_the_close_button_clears_the_touch_floor_on_a_phone() -> String:
	# A close button too small to hit is the same bug as no close button.
	var frame := PanelFrame.new()
	frame.setup("TEST PANEL", Vector2(400, 200))
	# Open before measuring — see the note in the centring test above.
	frame.open()

	var node: Node = await _T.instantiate_ui(frame, Vector2i(390, 844))
	if node == null:
		return "instantiate_ui returned null"

	var button := node.find_child("CloseButton", true, false) as Button
	if button == null:
		_T.free_ui(node)
		return "no CloseButton"

	var side := button.get_global_rect().size
	var a: String = _T.assert_gte(side.x, UiTheme.TOUCH_MIN,
		"the close button should be at least TOUCH_MIN wide")
	if a != "":
		_T.free_ui(node)
		return a

	var b: String = _T.assert_gte(side.y, UiTheme.TOUCH_MIN,
		"the close button should be at least TOUCH_MIN tall")
	_T.free_ui(node)
	return b
