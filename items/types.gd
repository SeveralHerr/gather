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
	StoneWorker,

	# The tier-2 crafting set (gather-cte). Appended, like everything above the line: iron and
	# gold bars each had exactly one buyer, and Combat had no craftable of its own at all.
	BoneSword,
	IronSword,
	GoldSword,
	Bandage,
	CookedFood,
	StoneBrick,

	# The berry bush and its fruit (gather-j2n). Two ids for one thing on purpose: BerryBush
	# is the node standing in the world AND the item an uprooted one becomes, so a bush can be
	# carried and replanted; Berry is what picking it yields. Appended, like everything above.
	BerryBush,
	Berry
}
