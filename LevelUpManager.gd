extends Control
class_name LevelUpManager

signal added_xp(amount: int)

@onready var xp_bar: ProgressBar = $"../PlayerInfo/XpBar"
@onready var resource_manager: ResourceManager2 = $"../../../../../ResourceManager"

# Each upgrade is a button in this scene plus the name of the upgrade that has to
# be taken before it unlocks. An empty requirement means it is offered from the start.
const UPGRADES = {
	"bone_pickaxe": {"button": "BonePickaxeButton", "requires": ""},
	"bone_sword": {"button": "BoneSwordButton", "requires": "bone_pickaxe"},
	"iron": {"button": "IronButton", "requires": "bone_sword"},
	"bone_turret": {"button": "BoneTurretButton", "requires": ""},
	"wood_decor": {"button": "WoodDecorButton", "requires": ""},
}

var xp = 0
var next_level = 10

# Levels earned but not yet spent. Banking them means a burst of xp that crosses
# two thresholds still hands out two upgrades instead of silently eating one.
var pending_levels = 0

var taken: Dictionary = {}


func _ready():
	add_to_group("LevelUpManager")
	add_to_group("SaveLoad")

	for upgrade_name in UPGRADES:
		_button(upgrade_name).pressed.connect(_on_upgrade_chosen.bind(upgrade_name))

	visible = false
	_refresh_buttons()

	xp_bar.max_value = next_level
	xp_bar.value = xp


func _button(upgrade_name: String) -> Button:
	return get_node(UPGRADES[upgrade_name]["button"]) as Button


func is_available(upgrade_name: String) -> bool:
	if taken.has(upgrade_name):
		return false
	var requires: String = UPGRADES[upgrade_name]["requires"]
	return requires == "" or taken.has(requires)


func has_available_upgrade() -> bool:
	for upgrade_name in UPGRADES:
		if is_available(upgrade_name):
			return true
	return false


func _refresh_buttons() -> void:
	for upgrade_name in UPGRADES:
		_button(upgrade_name).disabled = not is_available(upgrade_name)


func add_xp(amount: int):
	xp += amount
	added_xp.emit(amount)

	while xp >= next_level:
		next_level *= 2
		pending_levels += 1

	xp_bar.max_value = next_level
	xp_bar.value = xp

	_offer_upgrade()


# Only take over the screen when there is actually something to pick. Otherwise the
# player is left staring at a panel of dead buttons with no way to dismiss it.
func _offer_upgrade() -> void:
	if pending_levels <= 0 or not has_available_upgrade():
		return

	_refresh_buttons()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_upgrade_chosen(upgrade_name: String) -> void:
	if not is_available(upgrade_name):
		return

	taken[upgrade_name] = true
	pending_levels = max(0, pending_levels - 1)

	call("_apply_" + upgrade_name)

	_refresh_buttons()

	# A banked level with something left to spend it on keeps the panel up.
	if pending_levels > 0 and has_available_upgrade():
		return

	close()


func _apply_bone_pickaxe() -> void:
	Recipes.add_recipe(Types.Item.BonePickaxe, Types.Item.Sawmill)


func _apply_bone_sword() -> void:
	pass


func _apply_iron() -> void:
	resource_manager.add_resource(Types.Item.CoalResource)
	resource_manager.add_resource(Types.Item.IronResource)
	Recipes.add_recipe(Types.Item.Furnace, Types.Item.Sawmill)
	Recipes.add_recipe(Types.Item.IronBar, Types.Item.Furnace)
	Recipes.add_recipe(Types.Item.IronPickaxe, Types.Item.Sawmill)


func _apply_bone_turret() -> void:
	Recipes.add_recipe(Types.Item.BoneTurret, Types.Item.Sawmill)
	Recipes.add_recipe(Types.Item.Net, Types.Item.Sawmill)


func _apply_wood_decor() -> void:
	Recipes.add_recipe(Types.Item.WoodDoor, Types.Item.Sawmill)
	Recipes.add_recipe(Types.Item.WoodFloor, Types.Item.Sawmill)
	Recipes.add_recipe(Types.Item.WoodWall, Types.Item.Sawmill)


func close():
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func saveObject() -> Dictionary:
	var dict := {
		"filepath": get_path(),
		"visible": visible,
		"taken": taken.keys(),
		"pending_levels": pending_levels,
		"xp": xp,
		"next_level": next_level,
		# Kept so that older builds reading this save still see sane button states.
		"bone_sword_button": _button("bone_sword").disabled,
		"iron_button": _button("iron").disabled,
		"bone_turret_button": _button("bone_turret").disabled,
		"wood_decor_button": _button("wood_decor").disabled,
	}
	return dict


func loadObject(loadedDict: Dictionary) -> void:
	xp = loadedDict["xp"]
	next_level = loadedDict["next_level"]
	pending_levels = loadedDict.get("pending_levels", 0)

	taken = {}
	if loadedDict.has("taken"):
		for upgrade_name in loadedDict["taken"]:
			taken[upgrade_name] = true
	else:
		# Saves written before upgrades were tracked by name: recover what we can from
		# the button states. A disabled button meant either taken or not yet unlocked.
		if loadedDict.get("bone_sword_button", true) == false:
			taken["bone_pickaxe"] = true
		if loadedDict.get("iron_button", true) == false:
			taken["bone_pickaxe"] = true
			taken["bone_sword"] = true
		if loadedDict.get("bone_turret_button", true) == true:
			taken["bone_turret"] = true
		if loadedDict.get("wood_decor_button", true) == true:
			taken["wood_decor"] = true

	_refresh_buttons()
	xp_bar.max_value = next_level
	xp_bar.value = xp

	visible = loadedDict["visible"] and has_available_upgrade()
