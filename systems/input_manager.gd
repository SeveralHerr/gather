extends Node
class_name InputManager

signal move_right
signal move_left
signal move_down
signal move_up
signal mouse_button_right
signal mouse_button_left(isUiOpen: bool)
signal gather_input_press
signal gather_input_release
signal gather
signal destroy_input_press
signal destroy_input_release
signal attack
signal toggle_inventory
signal toggle_skills
signal toggle_land
signal toggle_saves
signal toggle_quests
signal toggle_debug

@export var isUiOpen = false
var disable_input = false

func _ready():
	add_to_group("InputManager")

func _physics_process(_delta):

	if Input.is_action_pressed(&"move_right") and not disable_input:
		move_right.emit()
	if Input.is_action_pressed(&"move_left") and not disable_input:
		move_left.emit()
	if Input.is_action_pressed(&"move_down") and not disable_input:
		move_down.emit()
	if Input.is_action_pressed(&"move_up") and not disable_input:
		move_up.emit()

## Every action test below reads the EVENT, never Input's own state.
##
## This used to poll Input.is_action_just_pressed() / is_action_just_released() from in
## here, and that is a frame-scoped question asked from a per-event callback:
## just_pressed stays true for the whole frame, while _input() runs once for every event
## that arrives in it. So each signal fired once per event in the press frame, not once
## per press.
##
## On a keyboard that was invisible — a gather press is one InputEventKey and nothing
## else lands that frame. On touch a single tap on the MINE button delivers an emulated
## mouse-down (emulate_mouse_from_touch defaults to true), the InputEventScreenTouch, and
## the InputEventAction the overlay synthesises; the virtual joystick then adds an
## InputEventScreenDrag every frame the thumb moves. Three to four events per frame, and
## a non-deterministic count because mouse emulation only follows whichever finger
## landed first.
##
## The duplicate gather_input_press re-entered PlayerGather, which restarted
## ResourceManager2 against a freshly looked-up tile and stranded the previous tile's
## layer-3 selector and its animated layer-1 mid-gather cell — the phone bug in
## gather-3zg. Reading the event makes each signal exactly 1:1 with the input that
## caused it, on every platform.
##
## is_action_pressed() also ignores echo events by default, so a held key no longer
## re-triggers on the OS repeat rate.
func _input(event):

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not disable_input:
			mouse_button_right.emit()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not disable_input:
			mouse_button_left.emit(isUiOpen)
	if event.is_action_pressed("gather") and not disable_input:
		gather_input_press.emit()
	if event.is_action_pressed("attack") and not disable_input:
		attack.emit()
	# Releases are deliberately NOT gated on disable_input, while the presses above are.
	# A release is the half that *stops* something, and swallowing it strands whatever the
	# press started: hold MINE with one thumb, open a panel with the other (the panel
	# toggles below are ungated on purpose, and they set disable_input), and the lift used
	# to be dropped — so stop_removing_resource() never ran and the tile stayed on its
	# animated mid-gather frame with the selector on it, permanently, even after the panel
	# closed. Two-thumb play makes that the ordinary case on a phone rather than a curio.
	if event.is_action_released("gather"):
		gather_input_release.emit()
		gather.emit()
	if event.is_action_pressed("destroy") and not disable_input:
		destroy_input_press.emit()
	if event.is_action_released("destroy"):
		destroy_input_release.emit()
	if event.is_action_released("inventory"):
		toggle_inventory.emit()
	# Not gated on disable_input, matching the inventory: opening a menu while dead
	# or mid-respawn is harmless, and being locked out of it is not.
	if event.is_action_released("skills"):
		toggle_skills.emit()
	# Same reasoning as the skill panel: the land panel is a menu, and being locked
	# out of it while dead or mid-respawn is worse than opening it there.
	if event.is_action_released("land"):
		toggle_land.emit()
	# Same again for the save-slot panel, and ungated for a stronger reason than the
	# others: picking a slot and loading it is the way OUT of a wedged or dead run, so
	# it is exactly the panel that must stay reachable while disable_input is up.
	#
	# The has_action guard is not defensive style, it is load-bearing. `saves` is a
	# newer binding than the three above, and is_action_released() on an action the
	# InputMap does not know pushes an error rather than returning false — from
	# _input(), which runs several times a frame, so it floods the log and makes the
	# game unplayable rather than merely noisy. A clone that has not re-imported since
	# the binding landed is exactly that case.
	if InputMap.has_action("saves") and event.is_action_released("saves"):
		toggle_saves.emit()
	# The same `has_action` guard, and it is load-bearing for the same reason: `quests` is newer
	# still, and `is_action_released` on an action the InputMap does not know pushes an error
	# rather than returning false — from `_input()`, several times a frame, which floods the log
	# and makes the game unplayable rather than merely noisy. A clone that has not re-imported
	# since this binding landed is exactly that case.
	#
	# Ungated on disable_input like the other panels: the board is a menu, and being locked out
	# of it while dead or mid-respawn is worse than opening it there.
	if InputMap.has_action("quests") and event.is_action_released("quests"):
		toggle_quests.emit()
	# Same again, and more so: the debug panel is the thing you want when the run is
	# already wedged, so gating it on disable_input would lock it away exactly when it
	# is useful. The panel only exists in a debug build (main.gd builds it behind
	# OS.is_debug_build()), so in an export this signal has no listener.
	if event.is_action_released("debug_panel"):
		toggle_debug.emit()
