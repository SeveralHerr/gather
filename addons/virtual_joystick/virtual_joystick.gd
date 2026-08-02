class_name JoystickControl

extends Control

## A simple virtual joystick for touchscreens, with useful options.
## Github: https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot

# EXPORTED VARIABLE

## The color of the button when the joystick is pressed.
@export var pressed_color := Color.GRAY

## If the input is inside this range, the output is zero.
@export_range(0, 200, 1) var deadzone_size : float = 10

## The max distance the tip can reach.
@export_range(0, 500, 1) var clampzone_size : float = 75

enum Joystick_mode {
	FIXED, ## The joystick doesn't move.
	DYNAMIC, ## Every time the joystick area is pressed, the joystick position is set on the touched position.
	FOLLOWING ## When the finger moves outside the joystick area, the joystick will follow it.
}

## If the joystick stays in the same position or appears on the touched position when touch is started
@export var joystick_mode := Joystick_mode.FIXED

enum Visibility_mode {
	ALWAYS, ## Always visible
	TOUCHSCREEN_ONLY, ## Visible on touch screens only
	WHEN_TOUCHED ## Visible only when touched
}

## If the joystick is always visible, or is shown only if there is a touchscreen
@export var visibility_mode := Visibility_mode.ALWAYS

## If true, the joystick uses Input Actions (Project -> Project Settings -> Input Map)
@export var use_input_actions := true

@export var action_left := "ui_left"
@export var action_right := "ui_right"
@export var action_up := "ui_up"
@export var action_down := "ui_down"

# PUBLIC VARIABLES

## If the joystick is receiving inputs.
var is_pressed := false

# The joystick output.
var output := Vector2.ZERO

# PRIVATE VARIABLES

var _touch_index : int = -1

@onready var _base := $Base
@onready var _tip := $Base/Tip

@onready var _base_default_position : Vector2 = _base.position
@onready var _tip_default_position : Vector2 = _tip.position

@onready var _default_color : Color = _tip.modulate

# FUNCTIONS

func _ready() -> void:
	# LOCAL PATCH (gather): upstream printerr's here when
	# `emulate_mouse_from_touch` is true or `emulate_touch_from_mouse` is false.
	# Both of those recommendations are wrong for this project and we keep the
	# engine defaults on purpose:
	#   * emulate_mouse_from_touch must stay TRUE — the inventory drag/drop and
	#     crafting UI read `get_global_mouse_position()`, and InputManager's
	#     mouse_button_left/right only fire from real mouse events. Turning it
	#     off makes the inventory unusable on a phone.
	#   * emulate_touch_from_mouse must stay FALSE — turning it on makes
	#     `DisplayServer.is_touchscreen_available()` return true forever, so the
	#     touch overlay would render for every desktop player. It is also the
	#     exact lever the harness's `set-feature --touchscreen true` pulls.
	# The advice is therefore permanently inapplicable, and it printed 12+ lines
	# of stderr per test run. Since stderr is this project's only real failure
	# signal for the test runner (see CLAUDE.md, gather-1t9), the noise is
	# actively harmful, so the two checks are dropped rather than silenced
	# conditionally. Restore from upstream if the addon is ever updated.
	if not DisplayServer.is_touchscreen_available() and visibility_mode == Visibility_mode.TOUCHSCREEN_ONLY :
		hide()
	
	if visibility_mode == Visibility_mode.WHEN_TOUCHED:
		hide()
	
func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event is InputEventScreenTouch:
		if event.pressed:
			if _is_point_inside_joystick_area(event.position) and _touch_index == -1:
				if joystick_mode == Joystick_mode.DYNAMIC or joystick_mode == Joystick_mode.FOLLOWING or (joystick_mode == Joystick_mode.FIXED and _is_point_inside_base(event.position)):
					if joystick_mode == Joystick_mode.DYNAMIC or joystick_mode == Joystick_mode.FOLLOWING:
						_move_base(event.position)
					if visibility_mode == Visibility_mode.WHEN_TOUCHED:
						show()
					_touch_index = event.index
					_tip.modulate = pressed_color
					_update_joystick(event.position)
					get_viewport().set_input_as_handled()
		elif event.index == _touch_index and _touch_index != -1:
			# LOCAL PATCH (gather): the `_touch_index != -1` half.
			# This branch is index-gated only — unlike the press above it does not check
			# that the touch is anywhere near the joystick — and it consumes the event.
			# So while _touch_index is stale the joystick eats the touch-up of whichever
			# *other* finger holds that index, MobileControls never sees the lift, and a
			# gather started on the MINE button stays latched down forever. -1 is the one
			# index that is never a real finger and is what _reset() leaves behind, so
			# guarding it closes the window between a reset and the next grab. The other
			# half of this fix is the reset() call in mobile_controls.gd:_release_all().
			_reset()
			if visibility_mode == Visibility_mode.WHEN_TOUCHED:
				hide()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			_update_joystick(event.position)
			get_viewport().set_input_as_handled()

func _move_base(new_position: Vector2) -> void:
	_base.global_position = new_position - _base.pivot_offset * get_global_transform_with_canvas().get_scale()

func _move_tip(new_position: Vector2) -> void:
	_tip.global_position = new_position - _tip.pivot_offset * _base.get_global_transform_with_canvas().get_scale()

func _is_point_inside_joystick_area(point: Vector2) -> bool:
	var x: bool = point.x >= global_position.x and point.x <= global_position.x + (size.x * get_global_transform_with_canvas().get_scale().x)
	var y: bool = point.y >= global_position.y and point.y <= global_position.y + (size.y * get_global_transform_with_canvas().get_scale().y)
	return x and y

func _get_base_radius() -> Vector2:
	return _base.size * _base.get_global_transform_with_canvas().get_scale() / 2

func _is_point_inside_base(point: Vector2) -> bool:
	var _base_radius = _get_base_radius()
	var center : Vector2 = _base.global_position + _base_radius
	var vector : Vector2 = point - center
	if vector.length_squared() <= _base_radius.x * _base_radius.x:
		return true
	else:
		return false

func _update_joystick(touch_position: Vector2) -> void:
	var _base_radius = _get_base_radius()
	var center : Vector2 = _base.global_position + _base_radius
	var vector : Vector2 = touch_position - center
	vector = vector.limit_length(clampzone_size)
	
	if joystick_mode == Joystick_mode.FOLLOWING and touch_position.distance_to(center) > clampzone_size:
		_move_base(touch_position - vector)
	
	_move_tip(center + vector)
	
	if vector.length_squared() > deadzone_size * deadzone_size:
		is_pressed = true
		output = (vector - (vector.normalized() * deadzone_size)) / (clampzone_size - deadzone_size)
	else:
		is_pressed = false
		output = Vector2.ZERO
	
	if use_input_actions:
		if output.x > 0:
			Input.action_release(action_left)
			Input.action_press(action_right, output.x)
		else:
			Input.action_release(action_right)
			Input.action_press(action_left, -output.x)

		if output.y > 0:
			Input.action_release(action_up)
			Input.action_press(action_down, output.y)
		else:
			Input.action_release(action_down)
			Input.action_press(action_up, -output.y)
## LOCAL PATCH (gather): public entry point for _reset().
## The browser never delivers the touch-up for a finger that was down when the tab lost
## focus, so without an outside-in reset the joystick keeps _touch_index, is_pressed and
## the latched move_* actions forever — the player walks off on their own and the stale
## index then starts eating other fingers' releases (see _input above).
func reset() -> void:
	_reset()


func _reset():
	is_pressed = false
	output = Vector2.ZERO
	_touch_index = -1
	_tip.modulate = _default_color
	_base.position = _base_default_position
	_tip.position = _tip_default_position
	# Release actions
	if use_input_actions:
		for action in [action_left, action_right, action_down, action_up]:
			if Input.is_action_pressed(action):
				Input.action_release(action)
