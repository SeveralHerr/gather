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

func _input(event):

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not disable_input:
			mouse_button_right.emit()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not disable_input:
			mouse_button_left.emit(isUiOpen)
	if Input.is_action_just_pressed("gather") and not disable_input:
		gather_input_press.emit()
	if Input.is_action_just_pressed("attack") and not disable_input:
		attack.emit()
	if Input.is_action_just_released("gather") and not disable_input:
		gather_input_release.emit()
		gather.emit()
	if Input.is_action_just_pressed("destroy") and not disable_input:
		destroy_input_press.emit()
	if Input.is_action_just_released("destroy") and not disable_input:
		destroy_input_release.emit()
	if Input.is_action_just_released("inventory"):
		toggle_inventory.emit()
	# Not gated on disable_input, matching the inventory: opening a menu while dead
	# or mid-respawn is harmless, and being locked out of it is not.
	if Input.is_action_just_released("skills"):
		toggle_skills.emit()
	# Same reasoning as the skill panel: the land panel is a menu, and being locked
	# out of it while dead or mid-respawn is worse than opening it there.
	if Input.is_action_just_released("land"):
		toggle_land.emit()
