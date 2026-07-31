extends Control

const DISPLAY_TIME := 0.6

@onready var level_up_ui: LevelUpManager = $"../LevelUpUI"

# One restartable timer instead of an await per event. With an await each, two gains
# inside the window left two pending clears, and the first to fire blanked the label
# while the second gain was still the current one.
var clear_timer: Timer


# Called when the node enters the scene tree for the first time.
func _ready():
	clear_timer = Timer.new()
	clear_timer.one_shot = true
	clear_timer.wait_time = DISPLAY_TIME
	clear_timer.timeout.connect(_on_clear)
	add_child(clear_timer)

	level_up_ui.added_xp.connect(_on_xp_add)
	$XpLabel.text = ""


func _on_xp_add(amount: int):
	$XpLabel.text = "+" + str(amount) + " xp"
	clear_timer.start(DISPLAY_TIME)


func _on_clear():
	$XpLabel.text = ""
