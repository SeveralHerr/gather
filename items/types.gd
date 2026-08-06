class_name Types

enum Item {
	StoneResource,
	CoalResource,
	IronResource,
	Tree,
	
	Stone,
	Wood,
	Plank,
	# Renamed from Sawmill (gather-mhwy). Renamed IN PLACE, on purpose: the identifier is
	# not the save key, the ordinal is, and this is still 7 — the same 7 written into every
	# existing saveFile and into crafting/workbench.tscn's `type`. Moving it to the append
	# block below to "keep the order tidy" would change that integer and rename this station
	# to something else in every save ever written.
	Workbench,
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
	Berry,

	# The charged skeleton caught in the net (gather-8ft). This is the sibling of BoneEnemy
	# above and reads as one next to it: BoneEnemy is a netted skeleton, ChargedBoneEnemy is a
	# netted CHARGED skeleton, and both are capture items that load a worker or a turret. The
	# name says which enemy was caught rather than what the drop looks like, which is why it is
	# not "ChargedSkull" — the player-facing string still is. Appended, like everything above:
	# the enum's ordinals are the ids in every save file, so inserting rather than appending
	# renames every item after the insertion point in every existing save.
	ChargedBoneEnemy
}
