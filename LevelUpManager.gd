extends Control
class_name LevelUpManager

signal added_xp(amount: int)

@onready var xp_bar: ProgressBar = $"../PlayerInfo/XpBar"


var xp = 0
var next_level = 10

# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("LevelUpManager")
	add_to_group("SaveLoad")
	#visible = false
	$BonePickaxeButton.pressed.connect(_on_bone_pickaxe) ##("pressed", Callable)
	$BoneSwordButton.pressed.connect(_on_bone_sword)
	$BoneSwordButton.disabled = true
	$IronButton.disabled = true
	$BoneTurretButton.disabled = true
	$WoodDecorButton.disabled = true
	
	xp_bar.max_value = next_level
	xp_bar.value = xp
	pass # Replace with function body.

func add_xp(amount: int):
	xp += amount
	xp_bar.max_value = next_level
	xp_bar.value = xp
	added_xp.emit(amount)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if xp >= next_level:
		visible = true
		next_level *= 1.5
		xp_bar.max_value = next_level
		xp_bar.value = xp
	pass


func _on_bone_pickaxe():
	Recipes.add_recipe(Types.Item.BonePickaxe, Types.Item.Sawmill)
	
	$BonePickaxeButton.disabled = true
	$BoneSwordButton.disabled = false
	visible = false
	pass
func _on_bone_sword():

	
	$BonePickaxeButton.disabled = true
	$BoneSwordButton.disabled = false
	visible = false
	pass


func saveObject() -> Dictionary:
	
	var dict := {
		"filepath": get_path(),
		"visible": visible,
		"bone_sword_button": $BoneSwordButton.disabled,
		"iron_button": $IronButton.disabled,
		"bone_turret_button": $BoneTurretButton.disabled,
		"wood_decor_button": $WoodDecorButton.disabled,
		"xp": xp,
		"next_level": next_level
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	visible = loadedDict["visible"]
	$BoneSwordButton.disabled = loadedDict["bone_sword_button"]
	$IronButton.disabled = loadedDict["iron_button"]
	$BoneTurretButton.disabled = loadedDict["bone_turret_button"]
	$WoodDecorButton.disabled = loadedDict["wood_decor_button"]
	xp = loadedDict["xp"]
	next_level = loadedDict["next_level"]
	xp_bar.max_value = next_level
	xp_bar.value = xp
	pass
