extends Control
class_name MobileControls

## Virtual touch controls for phone play (the itch.io web build): a virtual
## joystick on the left driving move_left / move_right / move_up / move_down, and
## a cluster of action buttons on the right driving gather's own InputMap actions.
##
## The right thumb gets **one** big contextual button, not a menu of verbs. It used
## to get five — MINE, HIT, USE, BREAK and ITEM, all the same shape, all the same
## size — and watching a small child play made the problem obvious: they could not
## tell MINE from HIT, and choosing wrong produces no feedback whatsoever, so the
## game reads as broken rather than as mis-aimed. The primary button now resolves to
## `gather` or `attack` from what is in the player's hand and what is standing next
## to them (resolve_primary()), and its face changes to say which. BREAK moved to the
## opposite corner, ITEM is gone. See BUTTON_SPECS for the full accounting.
##
## No gameplay lives here. Every button synthesises the *same* InputMap action the
## keyboard sends, with Input.parse_input_event(InputEventAction), so the existing
## InputManager -> Player -> HotBarInventory -> ResourceManager2 chain runs
## completely unchanged. parse_input_event is deliberate rather than
## Input.action_press: InputManager reads gather / attack / destroy from _input(),
## which only runs when an actual event is dispatched. Input.action_press updates
## the action state without dispatching anything, so the press would sit there
## unnoticed until some unrelated event happened to arrive.
##
## `gather` is a *hold*: press starts ResourceManager2's hold timer and release is
## what calls stop_removing_resource() (via Player._gather_input_release). So the
## gather button sends press on finger-down and release on finger-up. A one-shot
## tap would leave the mining timer running forever. The same is true of `destroy`.
## A contextual button makes that trap sharper, not softer — the answer can change
## between the press and the release — which is what `_latched_action` is for.
##
## Buttons are hit-tested from _input() on InputEventScreenTouch rather than being
## real Button nodes, so a second finger works while the first one is holding the
## joystick — mouse emulation only ever tracks one touch index, so Button.pressed
## alone would silently drop those.
##
## Mounted in the UI CanvasLayer, never under Player/Camera2D/HUD: that Control is
## world-space at 0.23 scale for the diegetic HUD (see CLAUDE.md).

## Emitted alongside every synthesised action, so a test can assert that a hold
## button really produced both halves without depending on frame timing. The
## primary button emits the action it *resolved to* (`gather` / `attack`), never
## its PRIMARY_ACTION sentinel.
signal action_sent(action: String, pressed: bool)

## Emitted whenever the primary button's face changes, so anything watching the
## overlay can react without polling it in turn. Carries the resolved action and
## the label now painted on the button.
signal primary_changed(action: String, label: String)

## Sentinel "action" for the one contextual button. It is not an InputMap action:
## `_action_for()` resolves it to `gather` or `attack` at the moment a finger lands.
const PRIMARY_ACTION := "@primary"

## The InputMap actions PRIMARY_ACTION can resolve to. `get_actions()` expands the
## sentinel into these, so callers that ask "what can this overlay send" still get
## real action names.
const PRIMARY_ACTIONS := ["gather", "attack"]

## How often the overlay re-checks for a touchscreen. DisplayServer exposes no
## signal for it, and the self-test harness's `set-feature --touchscreen true`
## flips it mid-run, so it has to be polled — but once a second is imperceptible
## to a human and costs nothing next to a per-frame query that runs for the whole
## life of the game on every platform.
const TOUCH_POLL_INTERVAL := 1.0

## How often the primary button re-reads the world to decide what it will do. The
## things it reads — the hotbar's selected slot and whether an enemy has walked up
## — change from gameplay, not from an event this node can subscribe to, so this is
## polled for the same reason TOUCH_POLL_INTERVAL is. Much faster than that one
## because it drives what the button *says*: a label that lags a second behind is a
## label that lies, and the whole point of merging MINE and HIT into one button is
## that the face is now the only thing telling the player which they are about to
## get. The poll only runs while the overlay is visible, i.e. never on desktop.
const CONTEXT_POLL_INTERVAL := 0.15

## How close an enemy has to be, in world pixels, before the primary button flips to
## `attack`. A tile is 16px and `enemy.gd`'s own `lunge_distance` is 18, so this is a
## little past the range at which the enemy is already committing to hit you — the
## button changes just before the first blow lands, not after. Deliberately far
## short of `detection_range` (100): a skeleton that has merely noticed you across
## the clearing must not take the pickaxe out of the player's hands.
const ENEMY_REACH := 28.0

## The addon joystick scene is authored at 300x300 with a 200px base centred in it.
## Both numbers are baked into its own layout, so the overlay scales the control
## rather than resizing it.
const JOYSTICK_SIZE := Vector2(300.0, 300.0)
const JOYSTICK_CLAMPZONE := 75.0
const JOYSTICK_DEADZONE := 10.0

## Button sizing, all derived from the viewport's shortest edge so the cluster is
## thumb-sized on a phone and not absurd on a desktop window. The reference edge
## that ratio is taken against is `UiTheme.REFERENCE_EDGE`; this file used to
## declare its own byte-identical 720.0, which is one more thing that could drift
## away from the panels. Nothing here may be a viewport *position* (see CLAUDE.md).
const BUTTON_BIG_FRACTION := 0.20
const BUTTON_BIG_MIN := 52.0
const BUTTON_BIG_MAX := 148.0
const BUTTON_SMALL_RATIO := 0.68
const BUTTON_PAD_RATIO := 0.16
const MARGIN_FRACTION := 0.035
const MARGIN_MIN := 10.0
const MARGIN_MAX := 40.0
const LABEL_SIZE_RATIO := 0.22
const LABEL_SIZE_MIN := 9
const JOYSTICK_SCALE_MIN := 0.45
const JOYSTICK_SCALE_MAX := 1.25

# Colours come from `UiTheme` — the overlay's own near-duplicate palette was the
# fourth copy of the same five values and the one that had already drifted (its
# background was a shade more transparent than the panels'). `overlay_style()` is
# the variant meant for chrome sitting directly over the world with no backdrop,
# which is exactly what these buttons and the hotbar are.

## The button cluster, laid out in rows measured from a screen corner. Rows count
## away from the corner, and within a row buttons are placed right-to-left in the
## order this table declares them. Adding a button is a one-line edit here: _layout
## derives the set of (corner, row) groups from the table itself.
##
## Which of gather's actions earn a button, and why:
##   PRIMARY   one big contextual button in the bottom-right corner, under the
##             thumb. It resolves to `gather` or `attack` from what the player is
##             holding and what is standing next to them — see resolve_primary().
##             This replaced two same-sized neighbours labelled MINE and HIT, which
##             is the change this whole file was reshaped for: a small child cannot
##             tell those two apart, and picking the wrong one does nothing visible
##             at all, so the game reads as broken rather than as mis-aimed.
##   action    open a chest / crafting station; without it the crafting half of the
##             game is unreachable on a phone. One row up from the primary so a
##             thumb reaching for the big button cannot clip it.
##   destroy   removes a misplaced building. Held, same as gather. Moved out of the
##             thumb cluster and up to the top-right corner (see below).
##   inventory / quests / skills / land   the panels. They are the progression UI, and
##             on a phone this cluster is the only way *into* them. It used to be
##             the only way back out too, which is why the overlay was mounted on
##             top of everything; every panel now closes from its own PanelFrame X,
##             a tap on the backdrop, or Escape, so that constraint is gone and the
##             overlay sits *beneath* the panels instead. handle_touch_event()
##             declines presses while one is open so the two cannot both answer the
##             same tap.
##
## `destroy` kept its button but not its place. It is the only *destructive* verb on
## the overlay — a mis-tap deletes a building the player meant to keep — and it is
## also the rarest, so it was the worst possible neighbour for the button a thumb
## is aiming at forty times a minute. Deleting it outright was the other option and
## was rejected: nothing else on a phone can undo a misplaced wall, and "you can
## build but never unbuild" is a dead end a child reaches within a minute of getting
## walls. Top-right, one row below the panel buttons, is deliberately awkward: it
## costs a reach across the screen, which is exactly right for an action you want on
## purpose and never by accident.
##
## The ITEM button is gone. It cycled the hotbar selection forward by one, and it was
## the single button on this overlay whose effect happened *somewhere else on the
## screen* — the same "I pressed it and nothing happened" failure that MINE-vs-HIT
## produced. The hotbar now has its own < and > arrows and every slot is directly
## tappable (hot_bar_inventory.gd), and tapping the picture of the thing you want is
## strictly more legible than cycling blind. Removing it also deleted the only place
## in the project that forged raw InputEventKey KEY_1..KEY_6 to drive the hotbar,
## which is what gather-shz was filed to fix.
##
## Left off deliberately: `save` and `load` (debug bindings — they quicksave and
## quickload the current slot, and `saves` below opens the panel that picks one) and
## the mouse buttons (touch already emulates a left click).
##
## `saves` and `quests` sit in row 1 rather than beside SKILL/BAG/LAND: the `tr` row 0
## already carries three, and this strip is the *only* way to reach a panel on a touch
## device — `hud_toolbar.gd` hides its whole cluster whenever DisplayServer reports a
## touchscreen (`_apply_visibility` / `_touch_active`), so a panel missing from here is
## unreachable on a phone rather than merely inconvenient. `quests` was exactly that: the
## board shipped with a key, a desktop toolbar button and no way in at all on a phone, and
## nothing said so — the panel simply did not exist for a touch player. This table and
## `hud_toolbar.gd`'s do not share a row, so adding a button there does not add one here.
##
## The face reads QUEST rather than QUESTS for the same reason SKILL and SAVE are clipped:
## these buttons are square and sized from the screen's shortest edge, so the label is
## fitted to the button rather than the other way round.
const BUTTON_SPECS := [
	{"name": "PrimaryButton", "action": PRIMARY_ACTION, "label": "MINE", "big": true, "primary": true, "corner": "br", "row": 0},
	{"name": "ActionButton", "action": "action", "label": "USE", "big": false, "primary": false, "corner": "br", "row": 1},
	{"name": "SkillsButton", "action": "skills", "label": "SKILL", "big": false, "primary": false, "corner": "tr", "row": 0},
	{"name": "InventoryButton", "action": "inventory", "label": "BAG", "big": false, "primary": false, "corner": "tr", "row": 0},
	{"name": "LandButton", "action": "land", "label": "LAND", "big": false, "primary": false, "corner": "tr", "row": 0},
	{"name": "DestroyButton", "action": "destroy", "label": "BREAK", "big": false, "primary": false, "corner": "tr", "row": 1},
	{"name": "SavesButton", "action": "saves", "label": "SAVE", "big": false, "primary": false, "corner": "tr", "row": 1},
	{"name": "QuestsButton", "action": "quests", "label": "QUEST", "big": false, "primary": false, "corner": "tr", "row": 1},
]

## The corners the layout walks, in the order rows stack away from each.
const CORNERS := ["br", "tr"]

## The buttons that open a panel rather than acting on the world. They stay live
## while `disable_input` is raised for death and respawn, matching the keyboard
## bindings in input_manager.gd. See _press_blocked_for().
const MENU_ACTIONS := ["inventory", "quests", "skills", "land", "saves"]

var _joystick: Control

## The generated button Controls, in BUTTON_SPECS order, and their metadata.
var _buttons: Array[Control] = []
var _button_action: Dictionary = {}

## touch index -> the button that finger is currently holding.
var _held: Dictionary = {}

## button -> the action its current press resolved to.
##
## This is the whole reason the merged button is safe. `gather` and `destroy` are
## holds: the press starts ResourceManager2's timer and the *release* is what calls
## stop_removing_resource(). The primary button's meaning is read from the world, and
## the world moves while a finger is down — mine a node to nothing, or let a skeleton
## wander into reach, and a re-resolution at release time would answer `attack` for a
## press that had sent `gather`. The engine would then never see the gather release
## and the mining timer would run forever: gather-3zg again, arrived at from a new
## direction. So the resolution is latched on finger-down and every later read of that
## press — including the release, including _release_all() on focus loss — returns the
## latched answer. Entries live exactly as long as the press does.
var _latched_action: Dictionary = {}

## Test seam: a Callable returning the same {action, label} Dictionary
## resolve_primary() does. Left invalid in the game, where the real world is the
## input. A unit test has no player, no hotbar and no enemies, so without this the
## resolution would only ever be exercised in its default branch — and the case
## worth asserting is precisely the one where the answer *changes* between the two
## halves of a press.
var primary_resolver: Callable = Callable()

## The project's InputManager, resolved by relative path because main.tscn's root
## belongs to every group and get_first_node_in_group() therefore returns the root
## (see CLAUDE.md). Null in a test that instantiates this scene on its own, which
## reads as "no panel is open" — the right answer there.
var _input_manager: InputManager

## Last value read from DisplayServer, so _process only reacts to changes.
var _touch_available := false
var _force_visible := false

## The context poll, started and stopped with visibility so a desktop session never
## walks the enemy list at all.
var _context_poll: Timer

## What the primary button's face currently says, so a poll that resolves to the same
## answer costs nothing.
var _primary_action := ""
var _primary_label := ""


func _ready() -> void:
	add_to_group("UI")

	# The overlay must never swallow a click aimed at the world; every hit test it
	# does is manual, from _input().
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_joystick = get_node_or_null("VirtualJoystick") as Control
	if _joystick == null:
		push_error("MobileControls: no VirtualJoystick child; movement will have no touch input")

	# UI/MobileControls -> Main/Systems/InputManager. The same relative hop the rest of the
	# UI nodes make.
	_input_manager = get_node_or_null("../../Systems/InputManager") as InputManager

	_build_buttons()
	_layout()

	UiTheme.connect_resize(self, _layout)

	_touch_available = DisplayServer.is_touchscreen_available()
	_apply_visibility()

	# DisplayServer.is_touchscreen_available() is a query, not a signal, so the only
	# way to notice `set-feature --touchscreen true` (which drives
	# Input.set_emulate_touch_from_mouse) is to ask again. Reading it once here would
	# mean the overlay never appears for a desktop test run.
	var poll := Timer.new()
	poll.name = "TouchPoll"
	poll.wait_time = TOUCH_POLL_INTERVAL
	poll.timeout.connect(_poll_touch_available)
	add_child(poll)
	poll.start()

	# Same reasoning, different question and a much shorter period — see
	# CONTEXT_POLL_INTERVAL. Created stopped; _apply_visibility() owns whether it runs.
	_context_poll = Timer.new()
	_context_poll.name = "ContextPoll"
	_context_poll.wait_time = CONTEXT_POLL_INTERVAL
	_context_poll.timeout.connect(refresh_primary)
	add_child(_context_poll)

	refresh_primary()
	_apply_context_poll()


func _poll_touch_available() -> void:
	var now := DisplayServer.is_touchscreen_available()
	if now != _touch_available:
		_touch_available = now
		_apply_visibility()


## Shows the overlay regardless of whether a touchscreen is reported. For tests and
## for eyeballing the layout on desktop.
func set_forced_visible(on: bool) -> void:
	_force_visible = on
	_apply_visibility()


## The generated Control for an InputMap action, or null. `gather` and `attack` both
## answer with the primary button, since that is the button which sends them — asking
## for either by name is how the devtools bridge and the tests address it, and neither
## should have to know about the PRIMARY_ACTION sentinel.
func get_button_for(action: String) -> Control:
	for i in mini(BUTTON_SPECS.size(), _buttons.size()):
		if str(BUTTON_SPECS[i]["action"]) == action:
			return _buttons[i]

	if PRIMARY_ACTIONS.has(action):
		return get_button_for(PRIMARY_ACTION)
	return null


## Every InputMap action this overlay can send. The primary button's sentinel is
## expanded into the two real actions it resolves to, so every entry here is a name
## InputMap actually knows.
func get_actions() -> Array[String]:
	var out: Array[String] = []
	for spec in BUTTON_SPECS:
		var action := str(spec["action"])
		if action == PRIMARY_ACTION:
			for real in PRIMARY_ACTIONS:
				out.append(str(real))
		else:
			out.append(action)
	return out


func _apply_visibility() -> void:
	var want := _force_visible or _touch_available

	# On desktop the overlay is hidden for the entire session. Without this, every
	# mouse-motion event in the game would still make the trip into _input() just to
	# be turned away by the `not visible` guard.
	set_process_input(want)

	if want == visible:
		return

	visible = want
	if not want:
		_release_all()
	else:
		refresh_primary()
	_apply_context_poll()


## The context poll runs only while the overlay is on screen. On desktop that is
## never, so a keyboard session pays nothing for a button it cannot see.
func _apply_context_poll() -> void:
	if _context_poll == null:
		return
	if visible:
		if _context_poll.is_stopped():
			_context_poll.start()
	else:
		_context_poll.stop()


func _input(event: InputEvent) -> void:
	if handle_touch_event(event):
		get_viewport().set_input_as_handled()


## The whole touch routing, split out from _input() so it can be driven directly
## without a live viewport. Returns true when the event was consumed.
##
## Presses are declined while a modal panel is open; releases never are. See
## `_presses_blocked()` for why the two halves are not treated alike.
func handle_touch_event(event: InputEvent) -> bool:
	if not visible:
		return false

	var blocked := _presses_blocked()

	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			var button := _button_at(touch.position)
			if button != null and not _press_blocked_for(button, blocked):
				_press(touch.index, button)
				return true
		elif _held.has(touch.index):
			_release(touch.index)
			return true
		return false

	var drag := event as InputEventScreenDrag
	if drag != null and _held.has(drag.index):
		# Sliding off a button releases it; sliding onto another takes that one over.
		var over := _button_at(drag.position)
		if over != _held[drag.index]:
			_release(drag.index)
			# ...unless a panel opened mid-drag, in which case letting go is all that
			# is left to do.
			if over != null and not _press_blocked_for(over, blocked):
				_press(drag.index, over)
			return true

	return false


## True while a modal panel owns the screen.
##
## The overlay hit-tests its own rects from `_input()`, which runs before the
## viewport picks a Control, and marks the event handled. So a touch on the BAG /
## SKILL / LAND cluster used to fire its action even with a panel painted over the
## top of it: the player tapped what looked like the panel and something else
## happened underneath. Declining the event (rather than consuming it) lets it fall
## through to the panel's own GUI handling, which is what a tap there should hit.
##
## `InputManager.disable_input` is the signal because every panel already sets it
## true on open and false on close through its `set_open()` handshake — there is no
## second source of truth to keep in step.
##
## **Presses only.** A release for a finger already in `_held` is always processed,
## even mid-panel. `gather` and `destroy` are holds: press starts
## ResourceManager2's timer and the release is what calls
## stop_removing_resource(). Swallow that release — because a panel opened under
## the other thumb — and the action latches down forever with the tile stuck on its
## animated mid-gather frame. That is gather-3zg, and it is why input_manager.gd's
## own releases are ungated too.
func _presses_blocked() -> bool:
	if _input_manager == null:
		return false
	return bool(_input_manager.disable_input)


## Whether this particular button declines the press, given the blanket
## `_presses_blocked()` verdict.
##
## `disable_input` alone is very slightly too broad: `player.gd:respawn()` also
## raises it for the half-second death-and-respawn window, and input_manager.gd is
## explicit that the three menu toggles must *not* be gated on it — "opening a menu
## while dead or mid-respawn is harmless, and being locked out of it is not". A flat
## gate would have locked a phone player out of their own inventory every time they
## died, which is precisely the complaint the keyboard build already fixed.
##
## So the two reasons to decline are separated:
##   * a panel is genuinely on screen — decline everything, the cluster is buried
##     under it and the panel carries its own close button now;
##   * input is merely disabled (dead, mid-respawn) — decline the gameplay actions
##     but let the menu buttons through, matching the keyboard.
func _press_blocked_for(button: Control, blocked: bool) -> bool:
	if _modal_panel_open():
		return true
	if not blocked:
		return false
	return not MENU_ACTIONS.has(str(_button_action.get(button, "")))


## Whether a PanelFrame is currently on screen anywhere in this CanvasLayer.
##
## Asks the frames themselves rather than trusting `disable_input`, because that
## flag answers "can the player act", not "is something covering the buttons", and
## only the second question is the one draw order cannot settle.
func _modal_panel_open() -> bool:
	var parent := get_parent()
	if parent == null:
		return false

	for sibling in parent.get_children():
		if sibling == self:
			continue
		# owned = false: every panel builds its PanelFrame in code, so none of them
		# are owned by a scene and an owned-only search finds nothing.
		for frame in sibling.find_children("*", "PanelFrame", true, false):
			if frame.visible:
				return true
	return false


func _notification(what: int) -> void:
	# Losing focus (app backgrounded, browser tab switched) drops the matching touch
	# release, which would leave `gather` latched down and the mining timer running.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _button_at(point: Vector2) -> Control:
	for button in _buttons:
		if button.visible and button.get_global_rect().has_point(point):
			return button
	return null


func _press(index: int, button: Control) -> void:
	# A dropped touch-up (a browser gesture, an itch.io iframe scroll, a touch that began
	# while the overlay was hidden) leaves the old binding in _held. The browser then
	# reuses that identifier for the next finger, and without this the old button's action
	# — `gather`, typically — would be overwritten and never released.
	if _held.has(index):
		_release(index)

	_held[index] = button
	_set_pressed_look(button, true)
	send_action(_action_for(button), true)


func _release(index: int) -> void:
	var button: Control = _held[index]
	_held.erase(index)

	# A second finger may still be on the same button — and if it is, the latch has to
	# survive, because that finger's press is still outstanding.
	if _held.values().has(button):
		return

	_set_pressed_look(button, false)
	send_action(_action_for(button), false)
	_latched_action.erase(button)

	# The world has almost certainly moved on during the hold; repaint the face now
	# rather than up to CONTEXT_POLL_INTERVAL later.
	refresh_primary()


## The InputMap action a press on `button` sends.
##
## For everything except the primary button this is just the table lookup. For the
## primary button it resolves the context *once*, on the first finger down, and
## returns that same answer for every subsequent read until the last finger lifts.
## See `_latched_action` for what goes wrong without the latch.
func _action_for(button: Control) -> String:
	var declared := str(_button_action.get(button, ""))
	if declared != PRIMARY_ACTION:
		return declared

	if _latched_action.has(button):
		return str(_latched_action[button])

	var resolved := str(_resolve_primary().get("action", "gather"))
	_latched_action[button] = resolved
	return resolved


func _release_all() -> void:
	# keys() is a fresh array, so erasing inside the loop is safe.
	for index in _held.keys():
		_release(index)

	# Belt and braces. _release() drops each latch as its last finger lifts, so this is
	# already empty — but a latch that outlived its press would freeze the primary
	# button's face permanently, and this is the one place that can say for certain
	# that no finger is down.
	_latched_action.clear()

	# The joystick keeps its own _touch_index and its own latched move_* actions, and
	# nothing here ever touched them: after a tab switch with a thumb on the stick the
	# player kept walking, and — worse — the stale index made the joystick swallow the
	# touch-up of whichever finger next held it, which latches `gather` down for good
	# (see the guard in virtual_joystick.gd:_input).
	if _joystick != null and _joystick.has_method("reset"):
		_joystick.reset()


func _set_pressed_look(button: Control, down: bool) -> void:
	button.modulate = UiTheme.PRESSED_MODULATE if down else Color.WHITE


## Feeds one half of an action into the engine, exactly as the keyboard would. The
## single place that turns a resolved action name into an event, so the primary
## button costs one lookup in _action_for() rather than a branch in each of _press()
## and _release(). Public because the gather/destroy holds are the part most worth
## driving from a test or a devtools verb.
func send_action(action: String, pressed: bool) -> void:
	if action == "":
		return

	if not InputMap.has_action(action):
		push_error("MobileControls: no InputMap action named '%s'" % action)
		return

	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

	action_sent.emit(action, pressed)


# --- the contextual primary button -------------------------------------------

## What the primary button will do, as `{"action": String, "label": String}`.
##
## ## The rule
##
## **What you are holding decides. A nearby enemy only gets a say when the held item
## has nothing of its own to offer.**
##
##   held item          action    label    why
##   ---------------------------------------------------------------------------
##   sword              attack    HIT      a weapon is a statement of intent
##   consumable         gather    EAT      `gather` is "use the held item", and the
##                                         moment you need to eat is the moment an
##                                         enemy is next to you — proximity must not
##                                         take the food away
##   placeable          gather    BUILD    `gather` places the building through
##                                         HotBarInventory; walling a monster out is
##                                         a legitimate answer to it being there
##   net                gather    NET
##   pickaxe / empty    attack    HIT      *only if* an enemy is within ENEMY_REACH
##   pickaxe / empty    gather    MINE     otherwise
##
## `gather` is doing double duty throughout — it is really "use whatever is in the
## selected hotbar slot", which is why mining, building, eating and the net all come
## out of the same InputMap action and only the label differs.
##
## ## The trade-off, stated plainly
##
## The pickaxe row is the one that can feel like a betrayal, and it is the case worth
## being explicit about: the player is holding MINE down on a tree, a skeleton walks
## into reach, and the button's face changes to HIT. The next press swings instead of
## mining. That is a real cost and it was chosen on purpose, because the alternative
## is worse: a child holding the game's default tool who *cannot fight back* dies
## over and over with a button in front of them that keeps chopping wood. Three
## things keep the flip honest rather than surprising:
##
##   * the label changes, visibly, up to CONTEXT_POLL_INTERVAL after the enemy
##     arrives and before the player's next press;
##   * it can never happen *during* a press — `_latched_action` freezes the answer
##     for the whole hold, so a gather that started always finishes as a gather;
##   * ENEMY_REACH is tight. The flip means "this thing is close enough to be hitting
##     you", not "there is a skeleton somewhere on screen".
##
## Static and pure — every input is an argument — so a test can walk the whole table
## without a world, a player or an enemy.
static func resolve_primary(item: GameItem, enemy_in_reach: bool) -> Dictionary:
	if item != null:
		if item is GameItemSword:
			return {"action": "attack", "label": "HIT"}
		if item is GameItemConsumable:
			return {"action": "gather", "label": "EAT"}
		# `is_placeable` rather than `is GameItemPlaceable`: it is the same flag
		# hot_bar_inventory.gd's update_placed_slot() reads to decide whether to draw
		# the ghost tile in front of the player, so the button and the ghost cannot
		# disagree about whether the player is in building mode.
		if item.is_placeable:
			return {"action": "gather", "label": "BUILD"}
		if item is GameItemNet:
			return {"action": "gather", "label": "NET"}

	if enemy_in_reach:
		return {"action": "attack", "label": "HIT"}
	return {"action": "gather", "label": "MINE"}


## The live resolution, or whatever `primary_resolver` says when a test has installed
## one.
func _resolve_primary() -> Dictionary:
	if primary_resolver.is_valid():
		var out: Variant = primary_resolver.call()
		if out is Dictionary:
			return out
	return resolve_primary(_held_item(), _enemy_in_reach())


## Repaints the primary button's face from the current context.
##
## Does nothing while the button is held: the action is latched for the duration of
## the press (see `_latched_action`), so relabelling mid-hold would put a word on the
## button that contradicts the event its release is going to send.
##
## Public because it is the handle the context poll, the visibility switch and a test
## all drive this through, and because a caller that has just changed the hotbar
## selection can repaint immediately instead of waiting out the poll.
func refresh_primary() -> void:
	var button := get_button_for(PRIMARY_ACTION)
	if button == null:
		return
	if _latched_action.has(button):
		return

	var resolved := _resolve_primary()
	var action := str(resolved.get("action", "gather"))
	var label_text := str(resolved.get("label", "MINE"))
	if action == _primary_action and label_text == _primary_label:
		return

	_primary_action = action
	_primary_label = label_text

	var label := button.get_node_or_null("Label") as Label
	if label != null:
		label.text = label_text
		# Colour as well as text. The two words are the same length and a child is not
		# reading them so much as recognising them, so the face has to differ by more
		# than its letters.
		label.add_theme_color_override(
			"font_color", UiTheme.COLOR_BAD if action == "attack" else UiTheme.COLOR_TEXT)

	primary_changed.emit(action, label_text)


## What the primary button's face says right now. For tests and the devtools bridge.
func primary_label() -> String:
	return _primary_label


## The action the primary button would send if a finger landed on it now — or the one
## it has latched, if a finger is already down.
func primary_action() -> String:
	var button := get_button_for(PRIMARY_ACTION)
	if button != null and _latched_action.has(button):
		return str(_latched_action[button])
	return str(_resolve_primary().get("action", "gather"))


## The GameItem in the selected hotbar slot, or null.
##
## Read through `Object.get()` because hot_bar_inventory.gd declares no `class_name`,
## so there is no type to annotate this against; `selected_slot_data` is a property
## with a getter and `get()` runs it. An empty stack reads as no item, matching the
## hotbar's own `count <= 0` test in populate_hot_bar().
func _held_item() -> GameItem:
	var hotbar := _find_hotbar()
	if hotbar == null:
		return null

	var slot := hotbar.get("selected_slot_data") as SlotData
	if slot == null or slot.count <= 0:
		return null
	return slot.item


## Whether anything hostile is within ENEMY_REACH of the player.
##
## Enemies are not in a group of their own — `enemy.gd` only joins `SaveLoad` — so
## this filters that group by type rather than adding one, because enemies/ belongs to
## other work. The group is short (a dozen or so world systems plus the live enemies,
## which enemy_spawner.gd caps at MAX_ENEMY_CAP) and this runs once every
## CONTEXT_POLL_INTERVAL only while the overlay is visible.
func _enemy_in_reach() -> bool:
	var player := PlayerManager.player
	if player == null or not is_instance_valid(player):
		return false

	var tree := get_tree()
	if tree == null:
		return false

	var reach_squared := ENEMY_REACH * ENEMY_REACH
	for node in tree.get_nodes_in_group("Enemy"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_squared_to(player.global_position) <= reach_squared:
			return true
	return false


func _find_hotbar() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("HotBarInventory")


func _build_buttons() -> void:
	for spec in BUTTON_SPECS:
		var button := Control.new()
		button.name = str(spec["name"])
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var background := Panel.new()
		background.name = "Background"
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background.add_theme_stylebox_override("panel", _button_style(spec["primary"] == true))
		button.add_child(background)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var label := Label.new()
		label.name = "Label"
		label.text = str(spec["label"])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
		button.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		add_child(button)
		_buttons.append(button)
		_button_action[button] = str(spec["action"])


## `primary` maps onto UiTheme's `accent`: the gold, one-pixel-thicker border the
## hotbar's selected slot also wears, so "this is the important one" reads the
## same everywhere.
func _button_style(primary: bool) -> StyleBoxFlat:
	return UiTheme.overlay_style(primary)


## The four lengths the whole layout is built out of, in one place so that
## `_layout()` and anything asking how much screen the overlay covers cannot
## derive them differently. `small` takes UiTheme's touch floor: at the bottom of
## the range a secondary button worked out to 35px, well under the 48px
## accessibility minimum the rest of the UI now clears.
func _metrics(vp: Vector2) -> Dictionary:
	var shortest := minf(vp.x, vp.y)
	var big := clampf(shortest * BUTTON_BIG_FRACTION, BUTTON_BIG_MIN, BUTTON_BIG_MAX)
	return {
		"big": big,
		"small": maxf(big * BUTTON_SMALL_RATIO, UiTheme.TOUCH_MIN),
		"pad": big * BUTTON_PAD_RATIO,
		"margin": clampf(shortest * MARGIN_FRACTION, MARGIN_MIN, MARGIN_MAX),
	}


func _joystick_scale(vp: Vector2) -> float:
	return clampf(
		minf(vp.x, vp.y) / UiTheme.REFERENCE_EDGE, JOYSTICK_SCALE_MIN, JOYSTICK_SCALE_MAX)


## How many pixels up from the bottom edge this overlay is occupying **across the
## horizontal span `x_min .. x_max`**, so other bottom-anchored UI can sit clear of
## it. On a portrait phone the joystick and the thumb cluster own both bottom
## corners and the hotbar is very nearly screen-wide, so there is no bottom-centre
## gap for it to slip into — without this the hotbar renders underneath MINE and HIT
## and a tap hits both.
##
## The span is what stops that answer being wrong everywhere else. This used to
## return a single `max` over the joystick and the whole cluster no matter where
## they sat, and the joystick is by far the tallest thing here: 300px of authored
## scene at up to 1.25 scale. On a landscape phone — 844x390, which is what a hand
## holding a web build actually looks like — that reaches ~176px up the *left* edge,
## so the hotbar was shoved 45% of the way up a 390px screen while the entire bottom
## centre between the joystick and the thumb cluster sat empty. Hence the complaint
## that the hotbar "is often in the middle of the screen". Asking per-span costs the
## caller one extra pair of arguments it already knows (it has just solved for its
## own width) and leaves the portrait answer untouched, because there the hotbar
## really does overlap both corners.
##
## Defaults to the whole width, i.e. the old behaviour, for a caller that has no
## span to offer.
##
## Zero while the overlay is hidden, which is the whole desktop session.
func get_bottom_obstruction_height(x_min: float = -INF, x_max: float = INF) -> float:
	if not visible:
		return 0.0

	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return 0.0

	var tallest := 0.0
	for rect in bottom_obstructions():
		# Touching edges do not overlap: a hotbar ending exactly where the joystick
		# begins is clear of it.
		if rect.position.x >= x_max or rect.end.x <= x_min:
			continue
		tallest = maxf(tallest, vp.y - rect.position.y)
	return tallest


## Every piece of chrome this overlay draws against the bottom edge, as screen-space
## Rect2s, each one running down to the bottom of the viewport rather than stopping
## at the art — what a caller wants to know is how far up the bottom edge is spoken
## for, and the margin underneath a row is spoken for too.
##
## Derived from the same arithmetic `_layout()` uses rather than read off the live
## button rects. The hotbar asks this during its own layout pass, and both nodes
## answer `size_changed` in connection order, so a read of the node positions would
## be a frame stale exactly on the resize that made the question worth asking.
##
## Public because it is the only way a test can say *where* the overlay is heavy
## rather than merely how heavy.
func bottom_obstructions() -> Array[Rect2]:
	var out: Array[Rect2] = []

	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return out

	var metrics := _metrics(vp)
	var big: float = metrics["big"]
	var small: float = metrics["small"]
	var pad: float = metrics["pad"]
	var margin: float = metrics["margin"]

	# Same walk `_layout()` makes over the bottom-right corner, so a row added to
	# BUTTON_SPECS is accounted for by itself. The trailing `pad` is kept in the
	# reach — it is the gap the cluster's own rows are separated by, and reusing it
	# as clearance is what keeps the portrait answer identical to the one this
	# replaced.
	var inset := margin
	for indices in _rows_for("br"):
		var height := _row_height(indices, big, small)
		var width := -pad
		for i in indices:
			width += pad + (big if BUTTON_SPECS[i]["big"] == true else small)
		var reach := inset + height + pad
		out.append(Rect2(vp.x - margin - width, vp.y - reach, width, reach))
		inset += height + pad

	if _joystick != null:
		var side := JOYSTICK_SIZE.y * _joystick_scale(vp)
		out.append(Rect2(margin, vp.y - margin - side, JOYSTICK_SIZE.x * _joystick_scale(vp),
			margin + side))

	return out


## Sizes and positions everything from the current viewport, because the project
## runs with window/stretch/mode="disabled": the viewport is the device's real
## pixel size, so a phone gets a viewport a fraction of the desktop one's and any
## fixed pixel layout would come out unusable at one end or the other.
func _layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	var metrics := _metrics(vp)
	var big: float = metrics["big"]
	var small: float = metrics["small"]
	var pad: float = metrics["pad"]
	var margin: float = metrics["margin"]

	# Rows stack away from their corner, each one inset by the ones before it. The
	# groups come from BUTTON_SPECS, so a new row appears on screen the moment it is
	# added to the table — the previous form listed the three groups here by hand and
	# a fourth would have been built, hit-tested and left sitting at (0, 0).
	for corner in CORNERS:
		var inset := margin
		for indices in _rows_for(corner):
			var height := _row_height(indices, big, small)
			var top := (vp.y - inset - height) if corner == "br" else inset
			_layout_row(indices, vp.x, top, height, big, small, pad, margin)
			inset += height + pad

	if _joystick != null:
		var scale_factor := _joystick_scale(vp)
		_joystick.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_joystick.size = JOYSTICK_SIZE
		_joystick.scale = Vector2(scale_factor, scale_factor)
		_joystick.position = Vector2(margin, vp.y - margin - JOYSTICK_SIZE.y * scale_factor)
		# Both zones are compared against a screen-space vector inside the addon, so
		# they have to be scaled alongside the control or the tip stops where the art
		# does not.
		_joystick.set("clampzone_size", JOYSTICK_CLAMPZONE * scale_factor)
		_joystick.set("deadzone_size", JOYSTICK_DEADZONE * scale_factor)


## BUTTON_SPECS indices for one corner, grouped into rows and ordered by row number.
func _rows_for(corner: String) -> Array:
	var rows := {}
	for i in BUTTON_SPECS.size():
		var spec: Dictionary = BUTTON_SPECS[i]
		if str(spec["corner"]) != corner:
			continue
		var row := int(spec["row"])
		if not rows.has(row):
			rows[row] = []
		rows[row].append(i)

	var numbers := rows.keys()
	numbers.sort()

	var out := []
	for number in numbers:
		out.append(rows[number])
	return out


## A row is as tall as its tallest button, so a row of small buttons does not
## reserve the height of a big one.
func _row_height(indices: Array, big: float, small: float) -> float:
	var height := 0.0
	for i in indices:
		height = maxf(height, big if BUTTON_SPECS[i]["big"] == true else small)
	return height


## Lays one row out from the right edge, walking leftwards in table order.
func _layout_row(indices: Array, view_width: float, top: float, row_height: float,
		big: float, small: float, pad: float, margin: float) -> void:
	var right := view_width - margin
	for i in indices:
		# _build_buttons appends in BUTTON_SPECS order, so the index is the button.
		var button := _buttons[i]
		var side := big if BUTTON_SPECS[i]["big"] == true else small
		right -= side
		button.position = Vector2(right, top + (row_height - side) * 0.5)
		button.size = Vector2(side, side)
		right -= pad

		var label := button.get_node_or_null("Label") as Label
		if label != null:
			label.add_theme_font_size_override(
				"font_size", maxi(LABEL_SIZE_MIN, int(side * LABEL_SIZE_RATIO)))
