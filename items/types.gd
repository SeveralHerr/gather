class_name Types

enum Item {
	StoneResource,
	CoalResource,
	IronResource,
	Tree,
	
	Stone,
	Wood,
	Plank,
	Sawmill,
	WoodFloor,
	CoalOre,
	IronOre,
	IronBar,
	Furnace,
	WoodWall,
	WoodDoor,
	Grass,
	Chest,
	Bone,
	BoneTurret,
	String,
	Net,
	BoneEnemy,
	WoodPickaxe,
	IronPickaxe,
	BonePickaxe,
	Food,
	Sword,
	Ground,
	Water,
	X,
	StoneResourceTest,

	# Appended, never inserted: the integer value of every entry is what saveFile
	# stores for each tile and inventory slot, so reordering this enum silently
	# rewrites every existing save.
	Coin,
	CopperResource,
	CopperOre,
	CopperBar,
	GoldResource,
	GoldOre,
	GoldBar,
	GoldPickaxe,
	CopperPickaxe,
	StonePickaxe,
	StoneWall,
	StoneFloor,
	BoneWorker,
	StoneWorker
}
