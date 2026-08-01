extends Node
class_name LandManager

## The land economy. In Forager the map grows because the player *buys* the next
## parcel, and that is what this owns: how big the island currently is, how many
## parcels have been paid for, and what the next one costs in gold coins.
##
## It deliberately does not know how to draw anything. Growing the island is one
## call into TileMapHandler.expand_island(), which only writes the newly revealed
## ring, so everything already standing on the old island survives a purchase.

## Emitted after the island has actually grown. `tiles_added` is the number of
## land cells the new ring revealed, not the change in visible grass.
signal land_purchased(new_radius: int, tiles_added: int)

## Emitted whenever the price, the parcel count or the radius moves. The purchase
## panel redraws off this; it is separate from land_purchased so a load can
## refresh the UI without pretending a parcel was just bought.
signal state_changed

## The island main.gd generates in _ready(). Parcel 1 grows it to BASE_RADIUS +
## RADIUS_STEP, and so on.
const BASE_RADIUS := 10

## How much further out each parcel pushes the coastline. Two rings is roughly a
## 40% area increase on the starting island and shrinks as a proportion from
## there, which is what keeps late parcels from doubling the map in one payment.
const RADIUS_STEP := 2

## Price of the first parcel, and the factor each subsequent parcel multiplies by.
## Gold is the scarcest drop in the game (gold veins have the lowest spawn weight
## and pay a coin only half the time), so the opening price is deliberately small
## — the first parcel should be reachable in one mining session, and the fifth
## should not.
const BASE_COST := 12
const COST_GROWTH := 1.6

## Beyond this the ring is bigger than the noise field is interesting and the
## price has run away regardless. It exists so the curve has a defined end rather
## than overflowing an int somewhere past parcel 40.
const MAX_PARCELS := 12

## Set by TileMapHandler when it creates this node. The only thing that can
## actually grow the world.
var tile_map_handler: TileMapHandler

## Test seam. When valid this is called instead of tile_map_handler.expand_island,
## so the purchase path can be exercised without a TileMap. It must take the new
## radius and return the number of tiles added.
var expand_callable: Callable

## Both default to the live player and exist so a unit test can supply its own.
var inventory: InventoryData
var stats: PlayerStats

var parcels_bought := 0
var radius := BASE_RADIUS


func _ready():
	add_to_group("SaveLoad")
	add_to_group("LandManager")

	if tile_map_handler == null:
		tile_map_handler = get_parent() as TileMapHandler

	radius = radius_for(parcels_bought)


# --- the price curve ---------------------------------------------------------
#
# Static and free of any node state, so the arithmetic the game charges is the
# same arithmetic a unit test can check without standing up a SceneTree.

## What the next parcel costs when `parcels_already_bought` are owned, after the
## Land Deeds style discount. Never returns less than one coin: a multiplier at
## or near zero must still cost *something* or the purchase loop is free.
static func cost_for_parcel(parcels_already_bought: int, cost_mult: float) -> int:
	var raw: float = BASE_COST * pow(COST_GROWTH, max(0, parcels_already_bought)) * maxf(cost_mult, 0.0)
	return maxi(1, int(round(raw)))


## The island radius once `parcels` have been bought.
static func radius_for(parcels: int) -> int:
	return BASE_RADIUS + max(0, parcels) * RADIUS_STEP


# --- state -------------------------------------------------------------------

func current_cost() -> int:
	return cost_for_parcel(parcels_bought, cost_mult())


## The discount from the skill tree. 1.0 when there is no player yet, so a UI
## built before the Player's _ready() still shows a sane price.
func cost_mult() -> float:
	if stats != null:
		return stats.land_cost_mult

	var player = PlayerManager.player
	if player == null or player.stats == null:
		return 1.0
	return player.stats.land_cost_mult


## The purse land is paid out of. Public because the panel watches it for changes
## and should not have to reach past this node to find the player.
func inventory_data() -> InventoryData:
	if inventory != null:
		return inventory

	var player = PlayerManager.player
	if player == null:
		return null
	return player.inventory_data


## Coins on hand, summed across every stack — currency spills into more than one
## slot as soon as a stack fills.
func gold() -> int:
	var inv := inventory_data()
	if inv == null:
		return 0
	return inv.count_of_type(Types.Item.Coin)


func is_maxed() -> bool:
	return parcels_bought >= MAX_PARCELS


func can_afford() -> bool:
	return not is_maxed() and gold() >= current_cost()


## Buys the next parcel: spends the coins, then grows the island. Returns false
## and changes nothing if the player cannot pay, the map is maxed out, or there
## is nothing able to grow the world — the affordability and expansion checks
## both run *before* the payment so a failed purchase never eats coins.
func purchase() -> bool:
	if is_maxed():
		return false

	if not expand_callable.is_valid() and tile_map_handler == null:
		push_warning("LandManager: no TileMapHandler, refusing to charge for land it cannot create")
		return false

	var inv := inventory_data()
	if inv == null:
		return false

	var cost := current_cost()
	if not inv.spend_type(Types.Item.Coin, cost):
		return false

	parcels_bought += 1
	radius = radius_for(parcels_bought)

	var tiles_added := _expand(radius)
	_award_purchase_xp()

	land_purchased.emit(radius, tiles_added)
	state_changed.emit()
	return true


## Buying land is the single biggest thing a player does, so it pays accordingly —
## more than any node, less than clearing a level. Guarded rather than assumed: this
## node is also driven by unit tests with no LevelUpManager and no player in the tree.
const XP_LAND_PURCHASE := 15

func _award_purchase_xp() -> void:
	if not is_inside_tree():
		return

	var level_up := LevelUpManager.find(self)
	if level_up == null:
		return

	var player := PlayerManager.player
	if player == null:
		level_up.add_xp(XP_LAND_PURCHASE)
	else:
		level_up.add_xp(XP_LAND_PURCHASE, player.global_position)


func _expand(target_radius: int) -> int:
	if expand_callable.is_valid():
		return int(expand_callable.call(target_radius))
	if tile_map_handler != null:
		return tile_map_handler.expand_island(target_radius)
	return 0


# --- persistence -------------------------------------------------------------

func saveObject() -> Dictionary:
	var dict := {
		# The scene path is the key SaveLoad reunites this dictionary with the node
		# by. Guarded because get_path() pushes an error on a detached node, and a
		# unit test exercising the roundtrip has no tree to attach it to.
		"filepath": get_path() if is_inside_tree() else NodePath(),
		"parcels_bought": parcels_bought,
		"radius": radius,
	}

	if tile_map_handler != null:
		dict["noise_seed"] = tile_map_handler.island_seed()

	return dict


func loadObject(loadedDict: Dictionary) -> void:
	parcels_bought = int(loadedDict.get("parcels_bought", 0))
	radius = int(loadedDict.get("radius", radius_for(parcels_bought)))

	# The seed goes back first. main.gd randomizes it every session, so expanding
	# against the live one would grow a coastline unrelated to the saved island —
	# grass where the save has open water, and the reverse.
	if tile_map_handler != null and loadedDict.has("noise_seed"):
		tile_map_handler.set_island_seed(int(loadedDict["noise_seed"]))

	# main.gd's _ready() always builds the *base* island, so a save with parcels
	# on it has to re-grow the map here or the player loads back onto a smaller
	# island than the one they paid for. With the seed restored, expand_island()
	# is idempotent: it writes the same deterministic land set either way, so it
	# does not matter whether main.gd's own loadObject ran before or after this.
	_expand(radius)

	state_changed.emit()
