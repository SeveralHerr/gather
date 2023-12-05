extends Control
class_name LevelUpManager

signal added_xp(amount: int)

@onready var xp_bar: ProgressBar = $"../PlayerInfo/XpBar"
@onready var resource_manager: ResourceManager2 = $"../../../../../ResourceManager"



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
	
	$WoodDecorButton.pressed.connect(_on_wood_decor)
	$WoodDecorButton.disabled = false
	
	$BoneTurretButton.pressed.connect(_on_bone_turret)
	$BoneTurretButton.disabled = false
	
	$IronButton.pressed.connect(_on_iron)
	$IronButton.disabled = false
	
	xp_bar.max_value = next_level
	xp_bar.value = xp
	pass # Replace with function body.

func add_xp(amount: int):
	xp += amount
	xp_bar.max_value = next_level
	xp_bar.value = xp
	added_xp.emit(amount)

func _on_iron():
	$IronButton.disabled = true
	resource_manager.add_resource(Types.Item.CoalResource)
	resource_manager.add_resource(Types.Item.IronResource)
	Recipes.add_recipe(Types.Item.Furnace, Types.Item.Sawmill)
	Recipes.add_recipe(Types.Item.IronBar, Types.Item.Furnace)
	Recipes.add_recipe(Types.Item.IronPickaxe, Types.Item.Furnace)
	visible = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if xp >= next_level:
		visible = true
		next_level *= 2
		xp_bar.max_value = next_level
		xp_bar.value = xp
		print(xp, next_level)
	pass

func _on_bone_turret():
	$BoneTurretButton.disabled = true
	Recipes.add_recipe(Types.Item.BoneTurret, Types.Item.Sawmill)
	Recipes.add_recipe(Types.Item.Net, Types.Item.Sawmill)
	visible = false

func _on_wood_decor():
	$WoodDecorButton.disabled = true;
	Recipes.add_recipe(Types.Item.WoodDoor, Types.Item.Sawmill)
	Recipes.add_recipe(Types.Item.WoodFloor, Types.Item.Sawmill)
	Recipes.add_recipe(Types.Item.WoodWall, Types.Item.Sawmill)
	visible = false

func _on_bone_pickaxe():
	Recipes.add_recipe(Types.Item.BonePickaxe, Types.Item.Sawmill)
	
	$BonePickaxeButton.disabled = true
	$BoneSwordButton.disabled = false
	visible = false
	pass
func _on_bone_sword():
	$BonePickaxeButton.disabled = true
	$BoneSwordButton.disabled = true
	$IronButton.disabled = false
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
