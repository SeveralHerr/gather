extends Control

@onready var level_up_ui: LevelUpManager = $"../LevelUpUI"


# Called when the node enters the scene tree for the first time.
func _ready():
	level_up_ui.added_xp.connect(_on_xp_add)
	pass # Replace with function body.

	
func _on_xp_add(amount: int):
	$XpLabel.text = str(amount) + " xp"
	await get_tree().create_timer(0.3).timeout
	$XpLabel.text = ""
	pass
