extends Control
class_name HudToolbar

## The always-on-screen buttons that open the game's four panels: the bag, the
## skill tree, the land purchase panel and the save slots.
##
## ## Why this exists
##
## Until this node the panels had no on-screen affordance at all on desktop. They
## opened on `I` / `K` / `B` and nothing said so. `mobile_controls.gd` does carry a
## BAG / SKILL / LAND cluster, but it hides itself for the whole session unless
## DisplayServer reports a touchscreen, so a mouse-and-keyboard player saw nothing —
## the skill tree and the land economy, which are most of the game's progression,
## were effectively undiscoverable.
##
## Adding buttons was only half of it. The game used to play with
## `Input.mouse_mode == MOUSE_MODE_CAPTURED`, which locks the pointer to the middle
## of the window and stops Godot picking any Control at all, so a HUD button could
## not have been clicked even if one had been drawn — `hot_bar_inventory.gd` says as
## much about its own `<` / `>` buttons, which it calls "decoration" for exactly that
## reason. The cursor is free during play now (`player/player.gd`), and that is what
## makes this node, the hotbar's arrows and its clickable slots all work.
##
## ## What it does not do
##
## No gameplay and no panel logic. Each button synthesises the same InputMap action
## the keyboard sends, with `Input.parse_input_event`, so the press lands in
## `InputManager` and travels the existing path to whichever panel owns that toggle.
## That is the same choice `mobile_controls.gd` made and for the same reason: one
## route in means the button cannot drift away from the key.
##
## Lives in the UI CanvasLayer (screen space). Never parent it under
## `Player/Camera2D/HUD` — that Control is world space at 0.23 scale for the diegetic
## HUD (see CLAUDE.md).

## Emitted alongside every synthesised action, so a test can assert a button really
## produced both halves of the press without depending on frame timing.
signal action_sent(action: String, pressed: bool)

## Emitted whenever the strip's size or visibility changes, so anything parked under
## it can move. `skill_tree_ui.gd`'s points badge is the one consumer: it shares this
## corner and would otherwise be drawn straight through the buttons.
signal layout_changed

## The buttons, left to right. `action` is an InputMap action and `key` is only the
## hint printed on the face — the binding itself lives in `project.godot`, and these
## two agreeing is checked by `test_hud_toolbar.gd` rather than by eye.
##
## Which panels earn a button, and why these four:
##   inventory  the bag. Also the only screen that shows what the player is carrying
##              beyond the six hotbar slots.
##   skills     the skill tree. Every stat the player will ever gain is behind it and
##              points bank silently, so a button here is what turns a banked point
##              into something the player can act on.
##   land       buying land is the only way to reach the three islands, and nothing
##              else in the game hints that it is possible.
##   saves      the save-slot panel. The strongest case of the four: `[` and `]` are
##              keyboard-only, the Save / Load Controls this node's comments used to
##              point at are gone (`Systems/SaveLoad` is an empty invisible Control
##              now), and nothing else on screen says a save exists. Every other entry
##              here makes a feature discoverable; this one is the only affordance the
##              feature has.
##
## NOT sufficient on a phone on its own. This strip hides itself the moment
## DisplayServer reports a touchscreen (see `_touch_active()`), and `mobile_controls.gd`
## carries the thumb-reachable cluster instead — its own BUTTON_SPECS and its
## MENU_ACTIONS list both need an entry before a touch device can open the panel at all.
## Adding one here does not do that, and the two files do not share a table.
##
## `quests` is the button that proved the warning: it was added here and nowhere else, so the
## board had a key and a desktop button while being unreachable on a phone — no error, no missing
## button, just a panel that did not exist for a touch player. `test_mobile_controls.gd` now
## asserts that every panel this strip opens is reachable from the overlay too, so the next entry
## added here cannot go missing there in silence.
##
## Deliberately absent: crafting (opened by walking up to a station and pressing the
## `action` key — it is a *place* in the world, not a menu). The bare `[` / `]`
## quick-save and quick-load keys stay as they are; this button opens the slot panel,
## which is the same state by a route a mouse can take.
##
## Width: buttons are not free. The row grows leftwards from the top-right corner, so one too
## many used to walk the first button off the LEFT edge rather than wrapping or clipping, with
## nothing on screen to say a button was missing. `_apply_scale()` now divides the space it
## actually has, and drops the key hint from the faces when that space runs short — so the
## budget is enforced rather than merely documented, and adding a sixth entry here is a layout
## question rather than a silent regression. `test_hud_toolbar.gd` holds the line at 390x844.
##
## `quests` is the fifth (`gather-dj2`): the board is the only thing in the game that tells the
## player what to do next, and — like the skill tree — it banks something silently, so a button
## that carries the ready count is what turns a finished quest into something they act on.
const BUTTON_SPECS := [
	{"name": "BagButton", "action": "inventory", "label": "BAG", "key": "I"},
	{"name": "QuestsButton", "action": "quests", "label": "QUESTS", "key": "J"},
	{"name": "SkillsButton", "action": "skills", "label": "SKILLS", "key": "K"},
	{"name": "LandButton", "action": "land", "label": "LAND", "key": "B"},
	{"name": "SavesButton", "action": "saves", "label": "SAVES", "key": "O"},
]

## Unscaled metrics. Height goes through `UiTheme.scaled_touch()` — these are the
## buttons a finger would hit if the overlay ever showed on a touch device — and the
## inset from the screen corner is a *size*, applied as an offset from the anchor,
## never computed from a viewport dimension (the gather-6fx trap).
const BUTTON_HEIGHT := 30.0
const BUTTON_MIN_WIDTH := 78.0

## The narrowest a button may be squeezed to before the row is allowed to overflow again.
##
## A floor rather than unbounded division, because a button narrower than its own label is not a
## smaller button, it is an unreadable one — and at that point running off the edge is at least
## an honest failure. 46px at SCALE_MIN still fits the widest plain face in the table ("QUESTS" /
## "SKILLS") at FONT_SMALL; it is reached only by a viewport far narrower than any phone reports.
const BUTTON_FLOOR_WIDTH := 46.0

const MARGIN := 12.0

var _row: HFlowContainer

## Whether the faces are currently drawn without their key hints. See `_apply_scale`.
var _compact := false

## action -> its Button, so `press()` and the point-count accent can find one by name
## rather than by index.
var _buttons: Dictionary = {}

## Every text control paired with the unscaled font size it was authored at, the same
## `[control, base_size]` list the panels keep, so a control added later cannot be
## forgotten by the resize handler.
var _typography: Array[Array] = []

## Resolved in `_ready()`. Null in a unit test that builds this node on its own, which
## every read below treats as "nothing to hide behind".
var _mobile_controls: Control
var _level_up_manager: LevelUpManager


func _ready() -> void:
	add_to_group("UI")

	# The root spans the screen only so the strip can be anchored to a corner of it;
	# it must never be the node that swallows a click aimed at the world.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_row()

	_mobile_controls = get_parent().get_node_or_null("MobileControls") as Control
	if _mobile_controls != null and not _mobile_controls.visibility_changed.is_connected(_apply_visibility):
		_mobile_controls.visibility_changed.connect(_apply_visibility)

	_level_up_manager = LevelUpManager.find(self)
	if _level_up_manager != null:
		_level_up_manager.points_changed.connect(_on_points_changed)

	# The log polls rather than being driven by six signals (see QuestLog.POLL_SECONDS), so this
	# is a connection to that poll's "something moved" rather than to any one source.
	var quest_log := QuestLog.find(self)
	if quest_log != null:
		quest_log.progress_changed.connect(_refresh_quests)
		quest_log.quest_claimed.connect(_on_quest_claimed)

	watch_panels()

	UiTheme.connect_resize(self, _apply_scale)

	# _apply_scale() refreshes both badges itself, so they are not repeated here.
	_apply_scale()
	_apply_visibility()

	# Again once the whole tree is up. MobileControls decides whether it is visible in
	# its own `_ready()`, and this node is created from `main.gd`'s `_ready()`, which
	# runs after its children's — but a panel built later still has to be picked up.
	watch_panels.call_deferred()
	_apply_visibility.call_deferred()


# --- construction ------------------------------------------------------------

## Builds the strip.
##
## An `HFlowContainer`, not an `HBoxContainer`, and that is the fix for a hazard the old comment
## only described: the row used to be anchored top-right and grown leftwards, so a row wider than
## the screen did not wrap or clip — the leftmost button simply ended up off the edge, reachable
## by nothing and announced by nothing.
##
## Four buttons fitted a 390px portrait phone with 2px to spare, which was never a budget so much
## as a coincidence; the fifth blew it. And it cannot be fixed by making the buttons narrower,
## because what sets a Button's minimum width is its *text* plus `style_button`'s content
## margins — the widest face in the game is "SKILLS +99  [K]", which no `custom_minimum_size`
## can shrink below.
##
## A flow container wraps to a second line instead. The strip is a little taller on a narrow
## screen and every button is still on it, which is the correct trade and the one the previous
## layout could not make. `occupied_top_height()` reports the wrapped height, so the skill tree's
## points badge still parks clear of it.
func _build_row() -> void:
	_row = HFlowContainer.new()
	_row.name = "Row"
	# Spans the width so the container knows where to wrap, and right-aligned within it so the
	# strip still reads as a top-right cluster rather than drifting to the left edge.
	_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_row.alignment = FlowContainer.ALIGNMENT_END
	_row.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_row)

	for spec in BUTTON_SPECS:
		var button := Button.new()
		button.name = str(spec["name"])
		button.text = _face(str(spec["label"]), str(spec["key"]))
		button.tooltip_text = "%s  (%s)" % [str(spec["label"]).capitalize(), str(spec["key"])]
		# The player is steering with the keyboard; a focused button would eat the
		# next Space or Enter and press itself again.
		button.focus_mode = Control.FOCUS_NONE
		UiTheme.style_button(button)
		button.pressed.connect(_on_button_pressed.bind(str(spec["action"])))
		_typography.append([button, UiTheme.FONT_SMALL])
		_row.add_child(button)
		_buttons[str(spec["action"])] = button


## The text on a button. Split out because the skills and quests buttons rewrite their own faces
## when something is banked and have to rebuild the rest of it identically.
##
## Drops the key hint when the row has been squeezed — see `_apply_scale`. The binding is
## untouched; this is only what is printed on the face.
func _face(label: String, key: String) -> String:
	return label if _compact else "%s  [%s]" % [label, key]


## The horizontal space the row may occupy: the viewport, less the margin at each end. Zero
## outside a tree, where the caller keeps the unclamped width — the same fallback
## `PanelFrame._clamp_to_viewport` makes for a headless build.
func _row_space(margin: float) -> float:
	if not is_inside_tree() or get_viewport() == null:
		return 0.0
	return maxf(0.0, get_viewport().get_visible_rect().size.x - margin * 2.0)


# --- sizing ------------------------------------------------------------------

## Re-derives every size from the current viewport. The project runs with
## `window/stretch/mode = "disabled"`, so nothing here scales on its own and a
## resize has to re-run the whole derivation.
func _apply_scale() -> void:
	if _row == null:
		return

	# The same factor the panels this strip opens are built at, so they grow in step.
	var factor := UiTheme.scale_for_node(self)

	UiTheme.apply_typography(_typography, factor)

	var gap := int(round(UiTheme.scaled(UiTheme.GAP, factor)))
	_row.add_theme_constant_override("separation", gap)

	var height := UiTheme.scaled_touch(BUTTON_HEIGHT, factor)
	var margin := UiTheme.scaled(MARGIN, factor)

	# `UiTheme.scale_for()` clamps at SCALE_MIN, so a 390px portrait phone and a 720px window
	# produce the same factor and therefore the same buttons — but one of them has 390px to put
	# them in. The flow container wraps rather than overflowing (see `_build_row`), so the width
	# below decides how many lines the strip takes rather than whether a button is reachable.
	#
	# Squeezing the buttons is still worth doing, because one line is better than two: at the
	# full width five buttons want ~530px, and dropping the key hints and the padding gets a
	# 720px window down to one line where it would otherwise wrap for no reason.
	var available := _row_space(margin)
	var count := maxi(1, _buttons.size())
	var wanted := UiTheme.scaled(BUTTON_MIN_WIDTH, factor)
	var width := wanted
	if available > 0.0:
		width = minf(wanted, (available - gap * (count - 1)) / float(count))
		width = maxf(width, UiTheme.scaled(BUTTON_FLOOR_WIDTH, factor))

	# Below the full width the key hint is the first thing to go: "SKILLS" alone still says what
	# the button does, and "[K]" without a legible "SKILLS" says nothing at all. The keys keep
	# working either way — this is the face, not the binding.
	_compact = width < wanted - 0.5
	for spec in BUTTON_SPECS:
		var button: Button = _buttons.get(str(spec["action"]))
		if button == null:
			continue
		button.custom_minimum_size = Vector2(width, height)
		button.text = _face(str(spec["label"]), str(spec["key"]))

	# The two buttons that carry a count have just had their faces reset to the plain form by the
	# loop above, so they are rebuilt here. Doing it in this order rather than teaching the loop
	# about badges keeps one place that knows what a face looks like.
	_refresh_points()
	_refresh_quests()

	# The row spans the width between the margins; the flow container right-aligns its buttons
	# inside that and wraps when they do not fit. Both offsets are insets from an anchor, never a
	# position computed from a viewport dimension — the `gather-6fx` trap.
	_row.offset_left = margin
	_row.offset_right = -margin
	_row.offset_top = margin

	# Tall enough for however many lines the buttons wrapped onto. `get_combined_minimum_size()`
	# on a flow container is width-dependent, so this has to be asked AFTER the offsets above set
	# that width — reading it first gives the single-line answer for every layout.
	_row.offset_bottom = margin + maxf(height, _row.get_combined_minimum_size().y)

	layout_changed.emit()


## How much of the top of the screen this strip is covering, so anything anchored to
## the same corner can sit clear of it. Zero while it is hidden, which is the whole
## session on a touch device.
##
## `skill_tree_ui.gd`'s banked-points badge is the reason this is public: it is
## anchored top-right too, and the two drew on top of each other.
## Measured from the BUTTONS, not only from the container.
##
## `HFlowContainer.get_combined_minimum_size()` is width-dependent, so it answers for whatever
## width the row had when it was asked — and a `_apply_scale()` that has just changed the row's
## offsets is asking before the layout pass has applied them. Reading the container alone
## therefore returns the one-line height for a strip that will wrap on the next frame, and the
## skill tree's points badge parks itself straight through the second row of buttons.
##
## The buttons' own rects have no such lag once they are laid out, and taking the max of both
## readings is right whichever of them is currently stale.
func occupied_top_height() -> float:
	if not visible or _row == null:
		return 0.0

	var bottom := _row.offset_top + maxf(_row.size.y, _row.get_combined_minimum_size().y)
	for action in _buttons:
		var button: Button = _buttons[action]
		if is_instance_valid(button):
			bottom = maxf(bottom, button.get_global_rect().end.y)
	return bottom


# --- visibility --------------------------------------------------------------

## Hidden in the two cases where these buttons are wrong rather than merely unused:
## a touch device, where `mobile_controls.gd` puts the same three actions under the
## player's thumb; and while a panel is open, where the strip would float over the
## backdrop and offer to re-toggle the panel the player is looking at.
##
## Draw order cannot settle the second case. A CanvasLayer paints in tree order and
## this node is added from `main.gd` after every panel, so it is *above* all of them.
func _apply_visibility() -> void:
	var want := not _touch_active() and not _panel_open()
	if want == visible:
		return

	visible = want
	layout_changed.emit()


func _touch_active() -> bool:
	return _mobile_controls != null and _mobile_controls.visible


## Whether a PanelFrame is on screen anywhere in this CanvasLayer. Asks the frames
## themselves rather than `InputManager.disable_input`, because that flag also goes up
## for the half-second death-and-respawn window, and a strip of buttons vanishing
## every time the player dies is worse than one that stays.
func _panel_open() -> bool:
	for frame in _panel_frames():
		if frame.visible:
			return true
	return false


func _panel_frames() -> Array[Node]:
	var found: Array[Node] = []
	var parent := get_parent()
	if parent == null:
		return found

	for sibling in parent.get_children():
		if sibling == self:
			continue
		# owned = false: every panel builds its PanelFrame in code, so none of them
		# are owned by a scene and an owned-only search finds nothing.
		for frame in sibling.find_children("*", "PanelFrame", true, false):
			found.append(frame)
	return found


## Connects to every panel frame's visibility so the strip can get out of the way.
##
## Idempotent, and called again deferred at build time because a panel created after
## this node has no frame yet on the first pass. Public because it is also the call
## anything adding a panel *later* has to make — in the shipped game nothing does,
## since `main.gd` builds this strip last precisely so that every frame already
## exists, but a test that stands one up afterwards needs the hook.
func watch_panels() -> void:
	for frame in _panel_frames():
		if not frame.visibility_changed.is_connected(_apply_visibility):
			frame.visibility_changed.connect(_apply_visibility)


# --- banked points -----------------------------------------------------------

func _on_points_changed(_points: int) -> void:
	_refresh_points()


func _on_quest_claimed(_quest: Quest) -> void:
	_refresh_quests()


## A banked skill point is worth nothing until it is spent, and levelling no longer
## seizes the screen, so the button that leads to the tree carries the count. The
## standalone badge `skill_tree_ui.gd` draws is the other half of the same cue; this
## is the one that is also the way in.
func _refresh_points() -> void:
	var points: int = _level_up_manager.points if _level_up_manager != null else 0
	_badge("skills", "SKILLS", "K", points, UiTheme.COLOR_GOLD)


## The quest board banks finished tasks silently, exactly as the skill tree banks points, so the
## button that leads to it carries how many are ready to hand in. Without it a player who is not
## already in the habit of opening the panel never finds out one went green.
func _refresh_quests() -> void:
	var log_node := QuestLog.find(self)
	var ready: int = log_node.ready_count() if log_node != null else 0
	# Green rather than the skill tree's gold: two counts side by side in the same colour read as
	# one number split across two buttons, and these mean different things.
	_badge("quests", "QUESTS", "J", ready, UiTheme.COLOR_GOOD)


## Draws `count` on a button's face, or the plain face when it is zero.
##
## Shared because the two badges were the same six lines with different strings, and because the
## compact form has to be handled identically by both — a badge that hardcoded "  [K]" would put
## the key hint back on a row that had just dropped it to fit.
func _badge(action: String, label: String, key: String, count: int, colour: Color) -> void:
	var button: Button = _buttons.get(action)
	if button == null:
		return

	if count > 0:
		button.text = "%s +%d" % [label, count] if _compact else "%s +%d  [%s]" % [label, count, key]
		button.add_theme_color_override("font_color", colour)
	else:
		button.text = _face(label, key)
		button.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)


# --- pressing ----------------------------------------------------------------

func _on_button_pressed(action: String) -> void:
	press(action)


## Sends both halves of `action` into the engine, exactly as the key would.
##
## Both halves and in that order: `input_manager.gd` answers the three panel toggles
## on `is_action_released`, so a press alone opens nothing, and an action left
## logically down is a trap for anything that later asks `Input.is_action_pressed`.
##
## `parse_input_event` rather than `Input.action_press`: InputManager reads from
## `_input()`, which only runs when an event is actually dispatched. `action_press`
## updates the action's state without dispatching anything, so the press would sit
## there unnoticed until some unrelated event happened to arrive. Same reasoning, and
## the same call, as `mobile_controls.gd`.
##
## Public because it is the handle a test and the devtools bridge drive the strip
## through — `run-method --method press --args '["skills"]'`.
func press(action: String) -> void:
	if not InputMap.has_action(action):
		push_error("HudToolbar: no InputMap action named '%s'" % action)
		return

	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		action_sent.emit(action, pressed)


## The generated Button for an InputMap action, or null. For tests and for the
## devtools bridge, which addresses it by node path.
func get_button_for(action: String) -> Button:
	return _buttons.get(action) as Button


## Every action this strip can send.
func get_actions() -> Array[String]:
	var out: Array[String] = []
	for spec in BUTTON_SPECS:
		out.append(str(spec["action"]))
	return out
