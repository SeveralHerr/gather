extends Node2D
class_name InteractPrompt

## The floating "F / Workbench" bubble drawn over the nearest interactable.
##
## Standing next to a crafting station or a chest used to stamp one flat highlight tile on
## tilemap layer 3 and nothing else, so a bench read as scenery: nothing on screen said the
## thing could be opened, and nothing said which button opened it. This is the missing half
## of that feedback — a key cap and the target's own name, floating over whatever is nearest.
##
## Structured after `ui/gather_progress.gd`, which is the house pattern for a world-space
## indicator: `top_level` so it is positioned in world coordinates rather than in its
## parent's, a high `z_index`, `visible = false` and `set_process(false)` while there is
## nothing to point at. Nothing here runs on a frame where the player is not standing next
## to something.
##
## ## What is *not* stored here
##
## Nothing about this survives a save. Every field below is derived from a node the player is
## currently standing next to and from the InputMap — a load that restores the player next to
## a furnace rebuilds the prompt on the first `_process` after the Interact area re-reports
## the body. There is deliberately no `saveObject()`; adding one would persist a *view*, which
## is the thing `WorldClock` / `SkyLighting` and `RunStats` are split apart to prevent.
##
## ## Why the key is read from the InputMap and not typed here
##
## `action` is bound to physical keycode 70, i.e. F. Typing "F" into a label would make this
## the one thing in the game that goes stale when a binding moves, and a prompt that names the
## wrong key is worse than no prompt at all — it teaches the player something false. So the
## cap renders whatever `InputMap.action_get_events("action")` currently holds. On a touch
## device there is no key to name, so the cap borrows the *face of the button that actually
## sends the action* out of `MobileControls.BUTTON_SPECS` (currently "USE"). Reading that
## table rather than repeating its text is what stops the two drifting: the phone is the
## device the web build is played on, and a prompt naming a button that says something else
## is a prompt that sends a child hunting.
##
## ## Why the caption asks the target for its own name
##
## `interact_prompt_label()` is duck-typed, exactly like the `player_interact()` predicate
## this prompt is gated on (`is_interactable`). A `match` on the target's class here would
## have to be edited every time an interactable is added, and would be edited *late* — the
## symptom of forgetting is a bubble that says "Interact" over a perfectly good machine, which
## nothing tests and nobody reports. The stations get their text from the item registry rather
## than from a literal, so renaming one in `items/items.gd` renames the prompt with it.
##
## ## Why it is drawn like the gather selector
##
## The first version of this was a small gold-bordered cap with a 14px caption, sized to about a
## third of a tile on the theory that a prompt must not cover the thing it points at. On screen
## it was unreadable, and the reason is visible the moment it is put next to the selector: the
## selector is a full 16px tile of bold white corner brackets, which at the camera's zoom of 8
## is **128 screen pixels** across, while the cap was under 30. The two were not in the same
## visual language and the eye went to the brackets every time.
##
## So the cap now borrows that language outright — white corner brackets of the same stroke
## weight over a dark plate, hard-edged, at a size comparable to the tile it sits above. The
## rule it replaces ("stay small so you do not cover the station") was answered by moving *up*
## rather than by shrinking: the bubble clears the selector instead of competing with it.
##
## Concretely, the constants below are SCREEN pixels multiplied through `_pixel_scale` exactly
## once, in `_cap_size()` and `_draw()`. Reading a size here as world pixels is the mistake to
## watch for — it is off by a factor of 8.
##
## The two Labels are scaled to exactly `1.0 / camera.zoom` (`SplashText.pixel_scale`) so their
## glyphs rasterize 1:1 and `font_size` *is* the on-screen pixel height — the same rule, and
## for the same reason, as `ui/damage_number.gd` and `ui/splash_text.gd`. The pop, the breathe
## and the press squash are transform writes on this node, and are therefore fractional and
## briefly soft; that is motion, not blur, and it is confined to the moments something is
## actually moving.
##
## No viewport rectangle is read anywhere in this file. The bubble is positioned relative to
## its target in world space, which is what keeps it clear of the absolute-pixel trap
## `gather-6fx` fixed for the screen-space UI.

## The InputMap action that opens a chest or a station, and the only one this prompt names.
const ACTION := "action"

## Caption for an interactable that does not name itself. Deliberately a verb rather than a
## guess at the node's identity: "Interact" is honest about knowing nothing, where a node name
## like "@CraftingStation@31" would look like a bug on screen.
const FALLBACK_LABEL := "Interact"

## Cap text when neither the InputMap nor the touch table can answer — an unbound `action`
## still gets a bubble, because a prompt with an empty cap reads as a rendering fault.
const FALLBACK_KEY := "USE"

## World pixels above the target's origin that the key cap is centred on. A station's art fills
## its 16px cell and the selector brackets are drawn around that whole cell, so this has to clear
## the TILE, not the sprite: -16 put the cap on top of the brackets, which is exactly the
## competition described above.
const Y_OFFSET := -22.0

## Screen pixels, because the Labels are scaled by 1/zoom — see the header. Sized against the
## selector rather than against the old cap: the key is the thing the player has to read at a
## glance, and at 64 it is about half a tile tall, which is the weight the brackets carry.
const KEY_FONT_SIZE := 64
const CAPTION_FONT_SIZE := 30

## Padding inside the key cap, and the gap between the cap and the caption. Screen pixels.
const KEY_PAD_X := 22.0
const KEY_PAD_Y := 12.0
const CAPTION_GAP := 8.0

## The corner brackets, in screen pixels — the selector's motif and, deliberately, its stroke
## weight. `BRACKET_ARM` is how far each arm runs from its corner; it is clamped in `_draw` so a
## wide cap ("USE") gets the same corners rather than four arms that meet in the middle.
const BRACKET_WIDTH := 8.0
const BRACKET_ARM := 22.0

## Text outline, so the caption survives over a bright grass tile without a plate behind it.
## Scaled up with the font: a 4px outline that read as a solid edge under a 14px caption is a
## hairline under a 30px one, and the caption sits directly on grass.
const OUTLINE_SIZE := 10
const OUTLINE_COLOR := Color(0.05, 0.03, 0.05, 1.0)

## The plate behind the cap. Darker and more opaque than COLOR_OVERLAY_BG, because this one is
## over grass in daylight rather than over a dimmed screen, and the white brackets need something
## to be white *against*.
const PLATE_COLOR := Color(0.04, 0.05, 0.07, 0.92)

## Label boxes, in screen pixels. A Label lays out inside its rect even with `clip_text` off,
## so these are generous; the labels are centred on their pivots and `mouse_filter` is IGNORE,
## so surplus box costs nothing. Grown with the fonts above — a box that no longer fits its text
## does not error, it just lays the glyphs out somewhere slightly wrong.
const KEY_BOX := Vector2(260.0, 110.0)
const CAPTION_BOX := Vector2(640.0, 60.0)

## Above the world (enemies sit at 1) and below the gather bar at 100, the damage numbers at
## 100 and the xp splashes at 110. A prompt is *ambient* — it is on screen for as long as the
## player stands there — so it must never be the thing covering a number that appears for
## three quarters of a second.
const Z_INDEX := 95

## The cap text currently rendered ("F", "USE"). Read-only from outside; `_refresh()` owns it.
var key_text := ""

## The caption currently rendered ("Furnace", "Chest"). Read-only from outside.
var caption_text := ""

var _key_label: Label
var _caption_label: Label

## The interactable being pointed at, or null. Always reached through `is_instance_valid` —
## a chest freed while the player is still standing on it is the ordinary case, not an edge.
var _target: Node2D = null

## Where the bubble is being pulled toward, and where it currently sits. Separate, because the
## whole point of `_anchor` is that it *lags* `_desired`: walking past a row of stations slides
## the bubble along the row instead of teleporting it (see PROMPT_FOLLOW_SPEED).
var _desired := Vector2.ZERO
var _anchor := Vector2.ZERO

## The pop. `_pop_age` counts up to Juice.PROMPT_POP_TIME and then stops costing anything;
## `_pop_from` is the scale it grows out of, and is the *only* difference between a first
## appearance and a retarget — one bursts in, the other gives a small nod.
var _pop_age := 0.0
var _pop_from := 1.0

## The press reaction, same shape.
var _press_age := 0.0
var _press_settled := true

## The leave. A dismissed prompt shrinks, rises and fades rather than blinking out, so walking
## away from a bench reads as leaving it rather than as the bubble having failed.
var _leaving := false
var _leave_age := 0.0

## Free-running clock for the idle bob and breathe. Never reset — a retarget that restarted it
## would make the bubble jump to the top of the sine every time the nearest station changed.
var _bob_age := 0.0

## Exactly 1/camera.zoom, so glyphs land on whole screen pixels. Re-read whenever the bubble
## appears rather than cached once: `SplashText.pixel_scale` exists because this number went
## stale the last time the camera's zoom moved.
var _pixel_scale := SplashText.WORLD_SCALE


# --- the three predicates, all pure and all testable without a game -----------------------

## Whether `node` is something the player can press `action` on.
##
## Duck-typed, and this is the fix at the centre of `gather-rlf3`. `player.gd` used to name
## `TestChest` and `CraftingStation` explicitly at the press site, so "every interactable"
## was false by construction: anything else that wandered into the Interact area got a
## highlight tile and a prompt and then did nothing when pressed, and a new interactable had
## to remember to add itself to an if/elif in a file about the player. The prompt, the
## highlight and the press are now gated on this one answer, so they cannot disagree.
##
## `Variant` rather than `Object`, and that is not tidiness. `player.gd`'s `chests` array
## genuinely holds FREED objects — a chest broken while the player is standing on it never
## fires `body_exited` (gather-3zg.6) — and handing a freed instance to a parameter typed
## `Object` raises at the call boundary itself ("the Object-derived class of argument 1
## (previously freed) is not a subclass of the expected argument class"), before a single line
## of this function runs. `typeof()` and `is_instance_valid()` are what can be asked about one
## safely. Pinned by `test_a_freed_body_is_not_interactable`.
static func is_interactable(node: Variant) -> bool:
	if typeof(node) != TYPE_OBJECT:
		return false
	if not is_instance_valid(node):
		return false
	return node.has_method("player_interact")


## The caption for a target: whatever it calls itself, else FALLBACK_LABEL.
static func label_for(target: Variant) -> String:
	if typeof(target) != TYPE_OBJECT or not is_instance_valid(target):
		return ""
	if target.has_method("interact_prompt_label"):
		var named := str(target.call("interact_prompt_label"))
		if named != "":
			return named
	return FALLBACK_LABEL


## The name of the first keyboard key bound to `action`, or "" when nothing is.
##
## Prefers the layout-dependent keycode where the binding carries one and falls back to the
## physical key otherwise, which is the shape every binding in `project.godot` actually has
## (they store `physical_keycode` and leave `keycode` at 0).
##
## `keyboard_get_keycode_from_physical` is what turns a physical position into the label
## printed on *this* player's keyboard, so an AZERTY player is not told to press a letter that
## is somewhere else. The physical code is the fallback when there is no layout to ask.
static func key_label_for_action(action: String) -> String:
	if action == "" or not InputMap.has_action(action):
		return ""

	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue

		var code: int = key.keycode
		if code == KEY_NONE and key.physical_keycode != KEY_NONE:
			code = key.physical_keycode
			# Guarded on there being a keyboard layout to translate through at all. The headless
			# display server has none and answers `keyboard_get_keycode_from_physical` with a
			# pushed engine error — which would then be printed by every headless run of a test
			# that touches this, i.e. noise in the one log that carries this project's real
			# failure signal. `keyboard_get_layout_count()` is answerable everywhere (0 headless)
			# and asks the same question honestly.
			if DisplayServer.keyboard_get_layout_count() > 0:
				var mapped := DisplayServer.keyboard_get_keycode_from_physical(code)
				if mapped != KEY_NONE:
					code = mapped
		if code == KEY_NONE:
			continue

		var named := OS.get_keycode_string(code)
		if named != "":
			return named
	return ""


## The face of the touch button that sends `action`, read out of the table that draws it.
##
## `ui/mobile_controls.gd` is the ONLY route into a chest or a station on a phone, and the web
## build is played on one. Copying its "USE" into this file would create a second copy of a
## string whose whole job is to match the button under the player's thumb; reading the table
## means renaming the button renames the prompt.
static func touch_key_label() -> String:
	for spec in MobileControls.BUTTON_SPECS:
		if str(spec.get("action", "")) == ACTION:
			var label := str(spec.get("label", ""))
			if label != "":
				return label
	return FALLBACK_KEY


## What the cap should say on this device.
static func prompt_key(touchscreen: bool) -> String:
	if touchscreen:
		return touch_key_label()
	var named := key_label_for_action(ACTION)
	return named if named != "" else touch_key_label()


## An item's display name out of a registry, with a fallback for every way the lookup can come
## back empty.
##
## Takes the registry rather than naming the `GameItems` autoload so the resolution is
## exercisable headless: the autoload node exists under the test runner but its `_ready()`
## never runs, so `item_list` is empty there and every lookup answers null (see
## `test/unit/test_equipped_sprite.gd`). A helper that could only ever be tested in its
## fallback branch would be a helper nobody had tested.
static func item_name(registry: Variant, type: int, fallback: String) -> String:
	if typeof(registry) != TYPE_OBJECT or not is_instance_valid(registry):
		return fallback
	if not registry.has_method("get_item"):
		return fallback
	var item: Variant = registry.get_item(type)
	if item == null:
		return fallback
	var named := str(item.name)
	return named if named != "" else fallback


# --- lifecycle ----------------------------------------------------------------------------

func _ready() -> void:
	# Positioned in world space, so it does not inherit the tilemap's transform.
	top_level = true
	z_index = Z_INDEX
	# NEAREST, not the project-default LINEAR: the pop is a fractional transform and linear
	# filtering turns that into a smear. Both Labels inherit through TEXTURE_FILTER_PARENT_NODE.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	set_process(false)

	# Both white, and the caption is no longer gold. The selector is white; a gold caption under
	# white brackets read as two different systems stacked on each other rather than as one
	# indicator.
	_key_label = _make_label(KEY_FONT_SIZE, UiTheme.COLOR_TEXT, KEY_BOX)
	_caption_label = _make_label(CAPTION_FONT_SIZE, UiTheme.COLOR_TEXT, CAPTION_BOX)


func _make_label(font_size: int, colour: Color, box: Vector2) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = false
	label.size = box
	# Scale is applied about the pivot in UNSCALED units, so centring a label on a local point
	# is `position = point - pivot_offset` whatever the scale is. Same arithmetic as
	# `ui/damage_number.gd`.
	label.pivot_offset = box * 0.5
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	add_child(label)
	return label


# --- the API player.gd drives --------------------------------------------------------------

## Points the bubble at `target`, or dismisses it when there is none.
##
## Safe and cheap to call every frame with the same target — that is how `player.gd` uses it,
## because the nearest interactable is recomputed per frame anyway. Only a *change* of target
## costs anything.
##
## `Variant` for the reason `is_interactable` is: the caller's nearest-interactable field is
## untyped and can hold a freed object.
func point_at(target: Variant) -> void:
	if not is_interactable(target):
		dismiss()
		return

	var node := target as Node2D
	if node == null:
		# Interactable but not a Node2D — nothing to hang a world position off.
		dismiss()
		return

	if node == _target and visible and not _leaving:
		return

	var arriving := _target == null or not visible or _leaving
	_target = node
	_leaving = false
	_leave_age = 0.0
	_refresh()

	_desired = node.global_position + Vector2(0.0, Y_OFFSET)
	if arriving:
		# Snap, and write the transform through rather than leaving it for the first `_process`:
		# a bubble that slid in from wherever the last one died would read as an object flying
		# across the world, and one that is made visible a frame before it is placed draws that
		# frame over the previous station.
		_anchor = _desired
		global_position = _anchor
		_pop_from = Juice.PROMPT_POP_FROM
	else:
		_pop_from = Juice.PROMPT_RETARGET_FROM

	_pop_age = 0.0
	modulate.a = 1.0
	visible = true
	set_process(true)


## Begins the leave animation. Idempotent, and does nothing at all when already hidden — which
## is the common case, since `player.gd` calls this on every frame the player is not standing
## next to anything.
func dismiss() -> void:
	_target = null
	if not visible or _leaving:
		return
	_leaving = true
	_leave_age = 0.0
	set_process(true)


## The reaction to the press actually landing. Distinct from the pop on purpose: the pop says
## "this can be opened" and this says "that worked", and a player who cannot tell them apart
## cannot tell a press that registered from one that missed.
func react() -> void:
	if not visible or _leaving:
		return
	_press_age = 0.0
	_press_settled = false
	queue_redraw()


## Whether the bubble is up and pointing at something. False from the instant it is dismissed,
## even though it is still on screen finishing its fade.
func is_showing() -> bool:
	return visible and not _leaving


## Re-resolves everything the bubble draws. Called on every appear and every retarget, which is
## also when the device question is re-asked: `DisplayServer.is_touchscreen_available()` is a
## query rather than a signal (see `mobile_controls.gd`'s TOUCH_POLL_INTERVAL), and walking up
## to a station is a natural place to ask. Nothing polls it here — a prompt already up when the
## flag flips keeps its cap until the player walks to the next station, which is a devtools-only
## situation and not worth a timer.
func _refresh() -> void:
	_pixel_scale = SplashText.pixel_scale(self)
	key_text = prompt_key(DisplayServer.is_touchscreen_available())
	caption_text = label_for(_target)

	if _key_label != null:
		_key_label.text = key_text
		_key_label.scale = Vector2.ONE * _pixel_scale
	if _caption_label != null:
		_caption_label.text = caption_text
		_caption_label.scale = Vector2.ONE * _pixel_scale

	_layout()
	queue_redraw()


## Places the two labels around the cap. World pixels, so every screen-pixel constant above is
## multiplied through `_pixel_scale` exactly once, here.
func _layout() -> void:
	var cap := _cap_size()
	if _key_label != null:
		_key_label.position = -_key_label.pivot_offset
	if _caption_label != null:
		var y := cap.y * 0.5 + (CAPTION_GAP + CAPTION_FONT_SIZE * 0.5) * _pixel_scale
		_caption_label.position = Vector2(0.0, y) - _caption_label.pivot_offset


## The key cap, in world pixels, measured from the text it has to hold — a one-character "F"
## and a three-character "USE" must not be given the same box.
func _cap_size() -> Vector2:
	var width := float(KEY_FONT_SIZE) * 0.62 * float(maxi(key_text.length(), 1))
	var font: Font = null
	if _key_label != null and _key_label.is_inside_tree():
		font = _key_label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	if font != null and key_text != "":
		width = font.get_string_size(
			key_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, KEY_FONT_SIZE
		).x

	return Vector2(
		width + KEY_PAD_X * 2.0,
		float(KEY_FONT_SIZE) + KEY_PAD_Y * 2.0
	) * _pixel_scale


# --- animation -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _leaving:
		_process_leave(delta)
		return

	# Follow. An exponential approach rather than a fixed step, so the bubble catches up at a
	# rate that does not depend on the frame rate and never overshoots the station it is
	# sliding toward.
	if is_instance_valid(_target):
		_desired = _target.global_position + Vector2(0.0, Y_OFFSET)
	else:
		# The target was freed under us — a chest broken while standing on it. Nothing to point
		# at, so leave rather than hang over the empty cell.
		dismiss()
		return
	_anchor = _anchor.lerp(_desired, 1.0 - exp(-Juice.PROMPT_FOLLOW_SPEED * delta))

	# Idle bob and breathe, driven off one sine so the rise and the swell are in phase and read
	# as one motion. This is the whole reason the node keeps processing while visible.
	_bob_age += delta
	var bob := sin(_bob_age * TAU * Juice.PROMPT_BOB_HZ)
	var offset := Vector2(0.0, bob * Juice.PROMPT_BOB_PIXELS)
	var scaling := Vector2.ONE * (1.0 + Juice.PROMPT_BREATHE * bob)

	# The pop, on appear and (gentler) on retarget. Overshoots through ease_out_back and
	# settles; once past PROMPT_POP_TIME it costs one float compare a frame.
	if _pop_age < Juice.PROMPT_POP_TIME:
		_pop_age += delta
		var p := Juice.ease_out_back(clampf(_pop_age / Juice.PROMPT_POP_TIME, 0.0, 1.0))
		scaling *= lerpf(_pop_from, 1.0, p)

	# The press: squash wide and flat, kick upward, and flash the cap. The flash is drawn, so
	# this is also what keeps `_draw` running for exactly as long as it has something to say.
	if not _press_settled:
		_press_age += delta
		if _press_age >= Juice.PROMPT_PRESS_TIME:
			_press_settled = true
			queue_redraw()
		else:
			var q := Juice.ease_out_back(clampf(_press_age / Juice.PROMPT_PRESS_TIME, 0.0, 1.0))
			scaling *= Juice.PROMPT_PRESS_SQUASH.lerp(Vector2.ONE, q)
			offset.y -= Juice.PROMPT_PRESS_RISE * (1.0 - q)
			queue_redraw()

	scale = scaling
	global_position = _anchor + offset


func _process_leave(delta: float) -> void:
	_leave_age += delta
	var t := clampf(_leave_age / Juice.PROMPT_LEAVE_TIME, 0.0, 1.0)
	modulate.a = 1.0 - t
	scale = Vector2.ONE * lerpf(1.0, Juice.PROMPT_LEAVE_SCALE, t)
	global_position = _anchor + Vector2(0.0, -Juice.PROMPT_LEAVE_RISE * t)
	if t >= 1.0:
		_hide_now()


## Hidden rather than freed — there is exactly one of these and it is reused for every
## interactable in the game. Everything transient is put back, because a prompt left mid-pop
## would come back at the wrong size the next time a station is walked past (the trap
## `GatherProgress.finish()` documents).
func _hide_now() -> void:
	visible = false
	_leaving = false
	_leave_age = 0.0
	_pop_age = Juice.PROMPT_POP_TIME
	_press_age = Juice.PROMPT_PRESS_TIME
	_press_settled = true
	scale = Vector2.ONE
	modulate.a = 1.0
	set_process(false)


## How white the cap is flashed, 1.0 at the press and 0.0 at rest.
func _press_flash() -> float:
	if _press_settled:
		return 0.0
	return 1.0 - clampf(_press_age / Juice.PROMPT_PRESS_TIME, 0.0, 1.0)


## Draws the cap as the selector draws a highlighted cell: a dark plate with four white corner
## brackets. Deliberately NOT a full border — the open sides are what make it read as the same
## family as the brackets around the tile below, and a closed rectangle read as a UI tooltip that
## had wandered into the world.
##
## Everything is snapped to whole world pixels. This is pixel art at zoom 8, so a bracket landing
## on a fractional coordinate is drawn as a soft two-pixel smear next to a hard-edged tileset
## selector, which is precisely the mismatch this rework exists to remove. The pop and breathe
## write `scale` on the node, so they still move it smoothly between whole positions.
func _draw() -> void:
	if key_text == "":
		return

	var cap := _cap_size()
	var w := roundf(BRACKET_WIDTH * _pixel_scale)
	var arm := roundf(BRACKET_ARM * _pixel_scale)
	# A short cap ("F") must not have its four arms meet. Half the shorter side, less the corner
	# the two arms already share, is the most any arm can run without touching its neighbour.
	arm = minf(arm, minf(cap.x, cap.y) * 0.5 - w)
	arm = maxf(arm, w)

	var x0 := roundf(-cap.x * 0.5)
	var y0 := roundf(-cap.y * 0.5)
	var x1 := roundf(cap.x * 0.5)
	var y1 := roundf(cap.y * 0.5)
	var flash := _press_flash()

	draw_rect(
		Rect2(x0, y0, x1 - x0, y1 - y0),
		PLATE_COLOR.lerp(Color(1.0, 1.0, 1.0, 1.0), flash * 0.8),
		true
	)

	# White at rest, and it only gets whiter on the press — the flash is carried by the plate
	# behind it, so the brackets never lose contrast at the moment the player is looking hardest.
	var ink: Color = UiTheme.COLOR_TEXT.lerp(Color(1.0, 1.0, 1.0, 1.0), flash)
	for corner in [Vector2(x0, y0), Vector2(x1, y0), Vector2(x0, y1), Vector2(x1, y1)]:
		var sx: float = -1.0 if corner.x > 0.0 else 1.0
		var sy: float = -1.0 if corner.y > 0.0 else 1.0
		# Horizontal arm, then vertical, both growing inward from the corner. Drawn from the
		# corner rather than centred on it, so the outer edge is flush with the plate.
		var hx: float = corner.x if sx > 0.0 else corner.x - arm
		var hy: float = corner.y if sy > 0.0 else corner.y - w
		draw_rect(Rect2(hx, hy, arm, w), ink, true)
		var vx: float = corner.x if sx > 0.0 else corner.x - w
		var vy: float = corner.y if sy > 0.0 else corner.y - arm
		draw_rect(Rect2(vx, vy, w, arm), ink, true)
