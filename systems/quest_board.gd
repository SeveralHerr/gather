class_name QuestBoard
# RefCounted so tests can build the whole board with QuestBoard.new() without a SceneTree, and so
# nothing can accidentally add it to the tree. QuestLog owns the one instance the game uses.
extends RefCounted

## Every quest in the game, built imperatively the way `SkillTree` and `items.gd` are.
##
## ## Why the game had to grow one
##
## Nothing in this game ever asked the player for anything. The skill tree offers, the land panel
## sells, the crafting stations accept — but nothing says "bring me twenty planks", so a new
## player has no idea what the game wants from them and an experienced one has no short-term
## goal between the long ones. The board is both: a reward drip, and the closest thing the game
## has to a tutorial.
##
## ## Every quest is a question about state something else already owns
##
## This is the load-bearing decision and it is what keeps the whole feature small. A quest does
## not subscribe to anything, does not accumulate its own counter, and is not "accepted". Its
## progress is *derived*, every time it is asked for, from whoever already owns the fact:
##
##   HAVE    the player's inventory          KILL    RunStats.enemies_killed
##   RAID    RaidDirector.raids_cleared      DAY     WorldClock.day
##   LEVEL   LevelUpManager.level            PARCEL  LandManager.parcels_bought
##
## So `QuestLog` persists exactly one thing — the set of ids already claimed — and there is no
## per-quest progress to save, to migrate, or to lose on a load. The alternative (a counter per
## quest, incremented from a signal) is the same shape as the raid's "how many raiders are left"
## problem: the counter is right until the first quicksave and silently wrong afterwards.
##
## It also means a quest added later works retroactively, which is the correct behaviour and
## would otherwise take a migration: a player who has already killed 200 enemies opens a new
## build and finds "Exterminator" ready to claim, rather than being asked to kill 50 more.
##
## ## Why rewards are only coins and xp
##
## `Skill` can also unlock recipes and resources; a quest deliberately cannot. Unlocks must be
## applied exactly once and never on load, because `Recipes` and `ResourceManager2` persist their
## own lists — replaying them appends every recipe twice (see the skill-tree note in CLAUDE.md).
## Coins and xp are paid into the world once and saved like anything else, so they carry no such
## rule. A quest that unlocked something would need the claimed set to become a *replay* log, and
## that is a save-format decision worth making deliberately rather than in passing.

var quests: Dictionary = {}

## Insertion order, so the UI and the tests walk the board deterministically rather than in
## Dictionary hash order.
var order: Array[String] = []


func _init():
	_build()


func _add(quest: Quest) -> void:
	quests[quest.id] = quest
	order.append(quest.id)


## The board, in the order it is drawn.
##
## Pacing: the first four are things a player will do in their first few minutes anyway, so the
## board pays out early and often enough to be worth opening again. The chains then point at the
## two crafting stations, at combat, at the raid, and finally at land — which is the real spine
## of the game and the thing nothing else signposts.
##
## Rewards are priced against `LandManager`'s curve (20 * 1.45^n, ~3795 coins for all twelve
## parcels). The whole board pays 1385 coins, which is a bit over a THIRD of the land economy.
##
## It was a fifth of it when COST_GROWTH was 1.55 and ~6955 coins bought the map; the curve came
## down and these rewards did not follow, so the board's share rose without anyone editing it.
## That is the figure to argue with if the board starts feeling like a replacement for mining
## rather than a leg-up: a fifth of today's curve would be ~760 coins across all fourteen
## quests. Nothing here is changed yet — the share is a deliberate open question, and it is
## these `reward_coins` arguments that would move, never the land curve.
func _build() -> void:
	# --- the opening: things you were going to do anyway ---------------------------
	_add(Quest.new(
		"first_timber", Quest.Kind.HAVE, 10,
		"First Timber",
		"Every building in this game starts as a tree. Bring ten wood.",
		20, 10, Types.Item.Wood
	))
	_add(Quest.new(
		"stonemason", Quest.Kind.HAVE, 10,
		"Stonemason",
		"Wood burns. Bring ten stone and you can build something that does not.",
		20, 10, Types.Item.Stone
	))
	_add(Quest.new(
		"kindling", Quest.Kind.HAVE, 5,
		"Kindling",
		"Coal is what makes a furnace more than an ornament. Bring five.",
		30, 15, Types.Item.CoalOre, ["stonemason"]
	))

	# --- the stations: the board is the only thing that says these exist -----------
	_add(Quest.new(
		"sawdust", Quest.Kind.HAVE, 10,
		"Sawdust",
		"A workbench turns wood into planks while you walk away. Bring ten planks.",
		45, 25, Types.Item.Plank, ["first_timber"]
	))
	_add(Quest.new(
		"first_smelt", Quest.Kind.HAVE, 3,
		"First Smelt",
		"Ore is rock until a furnace has had it. Bring three copper bars.",
		70, 40, Types.Item.CopperBar, ["kindling"]
	))

	# --- combat --------------------------------------------------------------------
	_add(Quest.new(
		"pest_control", Quest.Kind.KILL, 10,
		"Pest Control",
		"Ten of them, off the island. They will not stop arriving, but you can stop them.",
		30, 20
	))
	_add(Quest.new(
		"exterminator", Quest.Kind.KILL, 60,
		"Exterminator",
		"Sixty. At this point the island is yours by right of arms.",
		120, 90, Types.Item.Wood, ["pest_control"]
	))

	# --- the nights ----------------------------------------------------------------
	_add(Quest.new(
		"hold_the_line", Quest.Kind.RAID, 1,
		"Hold the Line",
		"See off one night raid. Walls help. So does a turret and somewhere to stand.",
		80, 50
	))
	_add(Quest.new(
		"night_watch", Quest.Kind.RAID, 5,
		"Night Watch",
		"Five nights held. Whatever is out there has learned where not to come.",
		250, 150, Types.Item.Wood, ["hold_the_line"]
	))
	_add(Quest.new(
		"a_week_in", Quest.Kind.DAY, 7,
		"A Week In",
		"Still here on day seven. That is longer than it sounds.",
		60, 40
	))

	# --- the spine: levels and land ------------------------------------------------
	_add(Quest.new(
		"apprentice", Quest.Kind.LEVEL, 5,
		"Apprentice",
		"Reach level five and spend the points. An unspent skill point does nothing at all.",
		50, 0
	))
	_add(Quest.new(
		"journeyman", Quest.Kind.LEVEL, 12,
		"Journeyman",
		"Level twelve. A whole branch of the tree is within reach by now.",
		150, 0, Types.Item.Wood, ["apprentice"]
	))
	_add(Quest.new(
		"landowner", Quest.Kind.PARCEL, 3,
		"Landowner",
		"Buy three parcels. The coastline grows outward — and toward the islands.",
		60, 40
	))
	_add(Quest.new(
		"continental", Quest.Kind.PARCEL, 8,
		"Continental",
		"Eight parcels. The far islands are close enough to walk to now.",
		400, 200, Types.Item.Wood, ["landowner"]
	))


func has_quest(id: String) -> bool:
	return quests.has(id)


func get_quest(id: String) -> Quest:
	return quests.get(id)


## Whether `id` is offered, given the set of already-claimed ids. A quest whose prerequisites are
## unmet is not merely unclaimable — it is not drawn at all, so the board stays a short list
## rather than a wall.
func is_offered(id: String, claimed: Dictionary) -> bool:
	var quest: Quest = quests.get(id)
	if quest == null:
		return false
	for required in quest.requires:
		if not claimed.has(required):
			return false
	return true


## Every quest that is offered and not yet claimed, in board order.
func available(claimed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in order:
		if not claimed.has(id) and is_offered(id, claimed):
			out.append(id)
	return out
