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

var isUiOpen = false

func _ready():
	add_to_group("InputManager")

func _physics_process(delta):
	if Input.is_action_pressed(&"move_right"):
		move_right.emit()
	if Input.is_action_pressed(&"move_left"):
		move_left.emit()
	if Input.is_action_pressed(&"move_down"):
		move_down.emit()
	if Input.is_action_pressed(&"move_up"):
		move_up.emit()

func _input(event):

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			mouse_button_right.emit()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			mouse_button_left.emit(isUiOpen)
	if Input.is_action_just_pressed("gather"):
		gather_input_press.emit()

	if Input.is_action_just_released("gather"):
		gather_input_release.emit()

