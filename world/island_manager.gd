extends Node
class_name IslandManager

## The pregenerated islands: a forest grove, an ore island, and a boss arena.
##
## They are drawn at world generation and are visible across the water from the first
## frame. There is no boat and no bridge - the way to reach them is to keep buying land,
## because a bought parcel grows the home island's coastline outward until it meets them.
## That is why every island's DISTANCE is the interesting number: it decides where in the
## progression the island opens up, and the three are spaced so they arrive in order.
##
## Placement is deliberately split into a fixed distance and a chosen angle. See
## _choose_angle for why a fixed angle would sometimes strand an island in open water
## forever.

## Which island sits where, and what grows on it.
##
## `distance` is from the home island's centre, in tiles, and is bounded by the maximum
## radius the home island can ever reach - LandManager.radius_for(MAX_PARCELS), which is
## 34 today. An island further out than that plus its own radius can never be reached.
##
## The weights override GameResource.spawn_weight for that island only. A type left out
## keeps its global weight; a type at 0.0 never spawns there. Iron and gold need no
## special handling to stay gated: the roll only ever considers resources that have been
## unlocked, so listing them here simply means they start appearing on the ore island the
## moment their skill is bought, and nowhere else. The flip side of that is that these two
## weights do NOTHING before the skill - which is why the island also carries a fixed
## handful placed outside the roll. See SEEDED_VEINS.
##
## The numbers are lopsided on purpose. An island is worth crossing the water for only if
## it is somewhere the mainland is not, and "somewhere else" is judged by what the player
## can see on it, not by a ratio. The first pass at these weights left the ore island
## rolling stone the clear majority of the time - stone being the mainland's most common
## node - so it played as an ordinary island that happened to also have coal. Ore now
## outweighs stone there roughly seven to one, and the grove is trees with a stone or two
## for texture. See ISLAND_THEME_SHARE, which is the floor a test holds these to.
const ISLANDS := [
	{
		"id": "forest",
		"distance": 20,
		"radius": 6,
		"weights": {
			Types.Item.Tree: 24.0,
			Types.Item.StoneResource: 0.75,
			Types.Item.StoneResourceTest: 0.75,
			Types.Item.CoalResource: 0.0,
			Types.Item.IronResource: 0.0,
			Types.Item.CopperResource: 0.0,
			Types.Item.GoldResource: 0.0,
		},
		"ambient_resources": true,
		"ambient_enemies": true,
	},
	{
		"id": "ore",
		"distance": 27,
		"radius": 6,
		"weights": {
			Types.Item.Tree: 0.0,
			Types.Item.StoneResource: 0.75,
			Types.Item.StoneResourceTest: 0.75,
			Types.Item.CoalResource: 6.0,
			# Copper carries the island's theming alongside coal because those two are the
			# ores that exist before any Industry skill - the island has to read as an ore
			# island on the first visit, not once `smelting` is bought.
			Types.Item.CopperResource: 5.0,
			# Gold is deliberately the one ore that is NOT scaled up much here. It is the
			# only node that pays coins and coins are what land costs, so its weight is a
			# lever on the land economy rather than on the island's flavour.
			Types.Item.IronResource: 2.5,
			Types.Item.GoldResource: 1.0,
		},
		"ambient_resources": true,
		"ambient_enemies": true,
	},
	{
		"id": "boss",
		"distance": 36,
		"radius": 5,
		"weights": {},
		# The arena stays the boss's. Nothing grows and nothing wanders in - and because
		# both flags also remove its grass from the ceilings those systems scale against,
		# it does not quietly buy extra resources and enemies for everywhere else.
		"ambient_resources": false,
		"ambient_enemies": false,
	},
]

## What each themed island is supposed to be made of, and the share of its rolls that has
## to come up that way.
##
## Stated next to the weights rather than inside the test, because the thing worth
## protecting is the intent - "the ore island is ore" - and the weights are only today's
## way of expressing it. The share is checked against both the starting unlocked set and
## the fully unlocked one: the roll only ever considers unlocked resources, so a weight
## table can look themed on paper and play as something else for the whole stretch before
## the mining skills are bought. That is precisely what happened here - the ore island's
## two stone types outweighed everything a player could actually see there until copper
## and gold were unlocked, by which point the island had already made its impression.
const ISLAND_THEME_SHARE := 0.85
const ISLAND_THEMES := {
	"forest": [Types.Item.Tree],
	"ore": [
		Types.Item.CoalResource,
		Types.Item.IronResource,
		Types.Item.CopperResource,
		Types.Item.GoldResource,
	],
}


## The fraction of an island's spawn rolls that comes up as its own theme, given which
## resource types are currently unlocked. Mirrors ResourceManager2.get_random's arithmetic:
## a type absent from the overrides keeps its global weight, and a negative one cannot pull
## the total down.
static func theme_share(id: String, unlocked: Array) -> float:
	var definition := _definition_for(id)
	if definition.is_empty() or not ISLAND_THEMES.has(id):
		return 0.0

	var weights: Dictionary = definition["weights"]
	var theme: Array = ISLAND_THEMES[id]
	var total := 0.0
	var themed := 0.0

	for type in unlocked:
		var weight: float = max(0.0, weights.get(type, Resources.TUNING.get(type, {}).get("spawn_weight", 0.0)))
		total += weight
		if theme.has(type):
			themed += weight

	return 0.0 if total <= 0.0 else themed / total


## Islands are denser than the mainland and far smaller, so they need their own floor -
## the home island's MIN_RESOURCE_CAP of 40 would cap a 90-tile grove as generously as
## the whole mainland.
##
## 0.3 -> 0.39 is the "30% more trees on the grove, 30% more ore on the ore island" pass,
## and it is deliberately done here rather than in the weight tables. The weights already
## put the grove at ~94% trees and the ore island at ~88-91% ore, so raising a theme weight
## further buys almost nothing - 24.0 to 31.0 moves the grove from 94% to 95%, which is not
## 30% more trees by any reading. What the player counts is NODES, and the node count is
## this number times the island's land, so scaling it scales the theme with it.
##
## It applies to every island, but only the two stocked ones feel it: the boss arena sets
## ambient_resources false and is never seeded.
const ISLAND_RESOURCE_DENSITY := 0.39
const ISLAND_MIN_RESOURCES := 8

## Island coastlines are cut from their own field at a much higher frequency than the
## home island's. At the default 0.01 the field barely changes across a 12-tile island,
## so every island would come out either solid or empty.
const ISLAND_NOISE_FREQUENCY := 0.18

## How hard the noise is allowed to bite into the disc. The distance from the centre does
## the deciding and the noise only ruffles the edge, which is what guarantees an island is
## solid in the middle - its contents get placed there.
const ISLAND_EDGE_BITE := 0.35

## Angles tried when placing an island, i.e. one every five degrees.
const ANGLE_SAMPLES := 72

## How far apart two islands must sit, in radians, so they do not overlap or read as one.
const MIN_ANGLE_SEPARATION := 0.9

## Width of a carved isthmus. Three is the minimum that leaves a walkable interior: the
## terrain solver turns the outer columns into coastline, and coastline tiles carry
## collision polygons, so a one-wide strip is a wall rather than a path.
const ISTHMUS_WIDTH := 3

## How much the corridor's width wanders, in tiles. Kept under half the width so the
## narrowest point still leaves a walkable interior column.
const ISTHMUS_WOBBLE := 0.9

## What the arena is guarding. Three stacks because TestChest has exactly three slots, and
## coins because they are the only currency in the game - land is what the player is
## saving for, and the boss island is the last thing they reach.
const BOSS_ID := "boss"
## Points at the registry rather than repeating the string, so the name of a type exists in
## exactly one place (gather-33f). Still a constant here because the boss island's guard being
## an elite is a fact about this island, not about the enemy.
const BOSS_TYPE := EnemyRegistry.ELITE
const BOSS_REWARD := [
	{"type": Types.Item.Coin, "count": 40},
	{"type": Types.Item.GoldOre, "count": 8},
	{"type": Types.Item.IronOre, "count": 12},
]

## Where the chest sits relative to the boss. Two tiles is inside every island radius the
## boss island can have, so the cell is always land whatever the seed does to the edge.
const BOSS_CHEST_OFFSET := Vector2i(0, 2)

## The ore island's seeded veins: a fixed handful of iron and gold, placed at generation
## rather than rolled.
##
## This exists because the ISLANDS weights above cannot produce them. The spawn roll only
## ever considers UNLOCKED resources (ResourceManager2.curent_resources), and iron waits on
## `smelting` while gold waits on `gold_rush` - so `IronResource: 2.5` and `GoldResource:
## 1.0` do nothing at all for the whole stretch in which the player first walks over here,
## and the ore island plays as coal and copper. These are placed straight from the resource
## registry, deliberately bypassing that gate, the same way the boss and its chest are put
## down deterministically instead of being rolled for. Nothing gates MINING them - any
## pickaxe breaks any node - so an early iron vein is a vein the player can actually take.
##
## Six nodes, and the smallness is the design. These are the reward for crossing the water,
## not a supply line; the skills are still what turn iron and gold into something renewable.
## The numbers are sized against what they buy: iron smelts 1:1 into IronBar and an iron
## pickaxe costs 5 bars (recipes.gd), so four veins leave the player one short - close
## enough to want the skill, not close enough to skip it. Gold smelts 1:1 into a Coin and
## the first parcel of land costs 12 (LandManager.BASE_COST), so two veins plus their
## secondary-drop coins are worth about a quarter of one parcel: visibly the good stuff,
## nowhere near an economy.
##
## Ambient respawn cannot multiply these - it rolls the same unlocked-only set, so it will
## never put another iron node down - and seed_ore_veins() is flag-guarded so a reload does
## not either. Once mined they stay mined until the skill makes them spawnable normally.
const SEEDED_VEIN_ISLAND := "ore"
const SEEDED_VEINS := [
	{"type": Types.Item.IronResource, "count": 4},
	{"type": Types.Item.GoldResource, "count": 2},
]

## The rings the veins are spread over, in tiles from the island's centre. Small, because
## island_cells only promises the middle of the island is solid; alternating two radii
## rather than one so six veins do not come out as a ring of dots.
const VEIN_RING_RADII := [2, 3]

var tile_map_handler: TileMapHandler
var resource_manager: ResourceManager2

## Saved, so a killed boss stays killed. Without it the post-load re-assert cannot tell a
## player who has already cleared the arena from one who has never seen it, and resurrects
## the boss on every load.
var boss_defeated := false

## Saved, for exactly the same reason as boss_defeated and against exactly the same bug.
## The seeded veins are ordinary layer-1 tiles, so main.gd's tile save carries them and the
## replay puts them back; a vein the player has already mined is simply absent from that
## replay. Without this flag the post-load pass could not tell that from an island that
## never had veins, and would hand them back on every single load.
var ore_veins_seeded := false

## Per-island seed. Saved, because the coastlines have to come back the shape the player
## learned, exactly as LandManager saves the home island's.
var islands_seed: int = 0

## The generated islands, keyed by id: {centre: Vector2i, radius: int, region: LandRegion}.
var islands := {}


func _ready() -> void:
	add_to_group("SaveLoad")


## Draws every island and stocks it. Called once, after the home island exists - the
## placement reads the home island's shape.
func generate(new_seed: int = 0) -> void:
	if tile_map_handler == null:
		return

	islands_seed = new_seed if new_seed != 0 else randi()
	islands.clear()

	var home_reach := _home_land_at_max_radius()
	var taken_angles := []

	for definition in placement_order():
		var angle := _choose_angle(definition["distance"], taken_angles, home_reach)
		taken_angles.append(angle)
		_build(definition, angle, home_reach)


## The order islands claim their directions in: furthest out first.
##
## Each island takes the best remaining angle, so whichever picks last is left with the
## direction the home island reaches least far in - and the cost of a bad angle is paid in
## isthmus length, which grows with distance. Letting the boss island pick last put a
## twenty-tile causeway across the map. Furthest-first hands the scarce good directions to
## the islands that cannot afford a bad one.
static func placement_order() -> Array:
	var ordered := ISLANDS.duplicate()
	ordered.sort_custom(func(a, b): return a["distance"] > b["distance"])
	return ordered


## The land the home island will have once every parcel is bought, as a lookup. Placement
## is judged against the FINAL coastline rather than today's, because the whole point is
## where the island will connect, not whether it is reachable now.
func _home_land_at_max_radius() -> Dictionary:
	var lookup := {}
	if tile_map_handler == null:
		return lookup
	for cell in tile_map_handler.land_cells_for_radius(LandManager.radius_for(LandManager.MAX_PARCELS)):
		lookup[cell] = true
	return main_body(lookup)


## The one connected landmass in `land` that the player can actually stand on, discarding
## detached scraps.
##
## Thresholding the noise leaves islets scattered inside the disc alongside the main body,
## and a plain lookup cannot tell the two apart. An island that anchors its isthmus to an
## islet is joined to a rock in the sea and to nothing else - and because the corridor is
## drawn, it looks connected on screen and stays connected-to-nothing however much land is
## bought. Six percent of seeds stranded at least one island this way, which no single
## playthrough would have surfaced.
static func main_body(land: Dictionary) -> Dictionary:
	var start = TileMapHandler.cell_nearest_to(land.keys(), Vector2i.ZERO)
	if start == null:
		return {}

	var seen := {start: true}
	var frontier := [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if land.has(next) and not seen.has(next):
				seen[next] = true
				frontier.append(next)
	return seen


## Picks the direction an island sits in.
##
## The distance is fixed but the angle cannot be, and this is the subtle part of the
## feature. land_cells_for_radius thresholds a FastNoiseLite field at the default 0.01
## frequency, so across the full +/-34 tiles of a maxed home island the field is sampled
## over a span of only +/-0.34. That is a smooth gradient rather than a speckled
## archipelago: the home island at maximum size is routinely a lopsided crescent with one
## whole side missing. An island anchored to a hardcoded angle lands on that missing side
## for a good fraction of seeds, never connects however much land is bought, and the
## progression dead-ends with nothing logged and nothing to see.
##
## So each island takes the direction in which the finished home island reaches furthest,
## keeping clear of the directions already taken.
func _choose_angle(distance: int, taken_angles: Array, home_reach: Dictionary) -> float:
	var best_angle := 0.0
	var best_reach := -1

	for i in ANGLE_SAMPLES:
		var angle := TAU * float(i) / float(ANGLE_SAMPLES)
		if _too_close_to_taken(angle, taken_angles):
			continue

		var reach := _reach_along(angle, distance, home_reach)
		if reach > best_reach:
			best_reach = reach
			best_angle = angle

	return best_angle


func _too_close_to_taken(angle: float, taken_angles: Array) -> bool:
	for taken in taken_angles:
		var delta: float = abs(angle - taken)
		delta = min(delta, TAU - delta)
		if delta < MIN_ANGLE_SEPARATION:
			return true
	return false


## How far out the finished home island still has land along `angle`, in tiles. The larger
## this is, the shorter the water gap left for the isthmus to close.
func _reach_along(angle: float, limit: int, home_reach: Dictionary) -> int:
	var reach := 0
	for step in range(1, limit + 1):
		if home_reach.has(_cell_along(angle, step)):
			reach = step
	return reach


static func _cell_along(angle: float, distance: int) -> Vector2i:
	return Vector2i(roundi(cos(angle) * distance), roundi(sin(angle) * distance))


func _build(definition: Dictionary, angle: float, home_reach: Dictionary) -> void:
	var centre := _cell_along(angle, definition["distance"])
	_install(definition, centre, definition["radius"], angle, home_reach)


## Draws one island and registers its region. The single place any island comes into
## existence - first generation, a reload and a post-replay re-assert all land here, so
## there is one definition of what an island's cells are rather than three that drift.
func _install(definition: Dictionary, centre: Vector2i, island_radius: int, angle: float, home_reach: Dictionary) -> LandRegion:
	var cells := island_cells(centre, island_radius, islands_seed, definition["id"])
	cells.append_array(_isthmus_cells(centre, island_radius, angle, home_reach, cells))

	tile_map_handler.tileMap.set_cells_terrain_connect(0, cells, 0, 1)

	var region := LandRegion.new()
	region.id = definition["id"]
	region.centre = centre
	region.radius = island_radius
	# Stated outright rather than left to the radius, so the isthmus belongs to the island
	# it grew from. See LandRegion.cells.
	region.set_cells(cells)
	region.spawn_weights = definition["weights"]
	region.resource_density = ISLAND_RESOURCE_DENSITY
	region.min_resources = ISLAND_MIN_RESOURCES
	region.ambient_resources = definition["ambient_resources"]
	region.ambient_enemies = definition["ambient_enemies"]
	# Islands start closed. Nothing is placed here and nothing wanders in until the home
	# coastline reaches the island; refresh_connections is what opens it. Carried over from
	# the previous region on a reload, because _install is also how a loaded island is
	# rebuilt and an island the player has already walked to must not close behind them.
	region.connected = _connected_state(definition["id"])

	tile_map_handler.register_region(region)
	islands[definition["id"]] = {
		"centre": centre,
		"radius": island_radius,
		"angle": angle,
		"region": region,
		"connected": region.connected,
	}
	return region


## What an island's `connected` should come back as when its region is rebuilt: whatever it
## was, defaulting to closed for one that has never been recorded.
func _connected_state(id: String) -> bool:
	if not islands.has(id):
		return false
	return bool(islands[id].get("connected", false))


## An island's land: a disc with a ragged edge.
##
## Deliberately not land_cells_for_radius. That thresholds a low-frequency field, which is
## right for a home island that has to grow outward as a superset of itself, and wrong for
## a small island that has to be reliably solid in the middle because a boss and a chest
## get placed there. Here the distance from the centre decides and the noise only ruffles
## the coastline, so the centre cell is land for every seed.
static func island_cells(centre: Vector2i, island_radius: int, seed_value: int, id: String) -> Array[Vector2i]:
	var field := FastNoiseLite.new()
	field.set_noise_type(FastNoiseLite.TYPE_PERLIN)
	field.set_frequency(ISLAND_NOISE_FREQUENCY)
	# Per island rather than shared, or three islands cut from one field at the same
	# radius come out the same shape wherever they sit.
	field.set_seed(seed_value + hash(id))

	var cells: Array[Vector2i] = []
	for x in range(centre.x - island_radius, centre.x + island_radius + 1):
		for y in range(centre.y - island_radius, centre.y + island_radius + 1):
			var falloff := Vector2(x - centre.x, y - centre.y).length() / float(island_radius)
			if falloff + ISLAND_EDGE_BITE * field.get_noise_2d(x, y) <= 1.0:
				cells.append(Vector2i(x, y))
	return cells


## The spit of land reaching back toward the mainland.
##
## A good angle usually leaves the finished home coastline within a tile or two of the
## island, but "usually" is not a progression guarantee - the noise can cut a channel
## anywhere. So whatever water is left along the approach is filled in, and filled in as
## part of the ISLAND rather than of home: it is drawn at generation, so the player can
## see the two reaching for each other long before they meet, and it does not change the
## shape of any parcel they paid for.
func _isthmus_cells(centre: Vector2i, _island_radius: int, angle: float, home_reach: Dictionary, cells: Array[Vector2i]) -> Array[Vector2i]:
	# The common case, and the one worth checking first: the finished home coastline
	# already runs up against the island, so there is nothing to bridge. Carving anyway
	# turned the sea into a set of straight three-wide causeways radiating out from the
	# mainland - geometry that reads as scaffolding rather than as a place.
	if _already_joined(centre, home_reach, cells):
		return []

	var distance := int(Vector2(centre).length())
	var reach := _reach_along(angle, distance, home_reach)
	if reach <= 0:
		return []

	# From the island's own centre rather than from its edge. The edge is not at
	# island_radius - the noise bites in by up to ISLAND_EDGE_BITE, so the real coastline
	# along this ray can sit well inside that, and a corridor starting at the nominal
	# radius then begins a few tiles out to sea with a channel behind it.
	return _corridor(centre, _cell_along(angle, reach), islands_seed)


## Whether the island can already be walked to once every parcel is bought, judged the
## same way the acceptance test judges it: flood from the mainland across the two landmasses
## together and see whether the island's centre comes up.
static func _already_joined(centre: Vector2i, home_reach: Dictionary, cells: Array[Vector2i]) -> bool:
	var combined := home_reach.duplicate()
	for cell in cells:
		combined[cell] = true
	return main_body(combined).has(centre)


## A contiguous corridor ISTHMUS_WIDTH tiles across, between two cells.
##
## Walked one axis at a time. Stepping along a float ray and rounding - which is what this
## used to do - produces a line whose cells touch only at their corners on any angle that
## is not near-axial. That reads as joined to the eye and to an 8-connected flood fill,
## and is not joined at all: the terrain solver sees two separate coastlines, and coastline
## tiles carry collision polygons. The player walks up to it and stops.
static func _corridor(from: Vector2i, to: Vector2i, seed_value: int) -> Array[Vector2i]:
	var field := FastNoiseLite.new()
	field.set_noise_type(FastNoiseLite.TYPE_PERLIN)
	field.set_frequency(0.25)
	field.set_seed(seed_value)

	var cells: Array[Vector2i] = []
	var half_width := int(ISTHMUS_WIDTH / 2.0)
	var cursor := from

	while true:
		# A disc of a noise-varied radius rather than a fixed square. Stamping squares
		# along a one-cell-at-a-time walk draws a perfect staircase with hard shoulders,
		# which reads as generator scaffolding laid across the sea; overlapping discs of
		# a wandering radius read as a spit of land.
		var brush := float(half_width) + 0.5 + ISTHMUS_WOBBLE * field.get_noise_2d(cursor.x, cursor.y)
		var extent := ceili(brush)
		for dx in range(-extent, extent + 1):
			for dy in range(-extent, extent + 1):
				if Vector2(dx, dy).length() <= brush:
					cells.append(cursor + Vector2i(dx, dy))

		if cursor == to:
			break

		# Whichever axis is further from the target moves, so the corridor runs as a
		# diagonal staircase rather than turning one hard right angle.
		var delta := to - cursor
		if absi(delta.x) >= absi(delta.y) and delta.x != 0:
			cursor.x += signi(delta.x)
		elif delta.y != 0:
			cursor.y += signi(delta.y)
		else:
			cursor.x += signi(delta.x)

	return cells


## Opens every island the home island can now be walked to, and stocks each one as it opens.
##
## This is the only thing that ever puts an island's contents down. Called once at world
## generation - where it normally opens nothing, the islands being twenty-odd tiles beyond a
## starting coastline of radius 8 - and again after every land purchase and after a load.
##
## An island is stocked on the tick it opens rather than trickling in afterwards, for the
## same reason a bought parcel is: the player has just walked across, and an empty grove
## does not read as arriving somewhere. Everything ambient takes over from there.
##
## Deliberately one-way. Land is only ever bought, never sold, so an open island cannot
## close again - and a re-check that could close one would strip a coastline the player is
## standing on the moment a flood fill disagreed with itself by a tile.
func refresh_connections() -> void:
	if tile_map_handler == null:
		return

	var walkable := tile_map_handler.walkable_cells_from_home()

	for id in islands:
		var region: LandRegion = islands[id]["region"]
		if region == null or region.connected:
			continue
		if not _region_is_walkable(region, walkable):
			continue

		region.connected = true
		islands[id]["connected"] = true
		_stock(id, region)


## Whether any of a region's cells can be walked to from home. Any single cell is enough:
## the island's own interior is one connected patch of grass, so reaching a tile of it is
## reaching the island.
static func _region_is_walkable(region: LandRegion, walkable: Dictionary) -> bool:
	for cell in region.cells:
		if walkable.has(cell):
			return true
	return false


## Everything that goes onto an island the moment it opens.
func _stock(id: String, region: LandRegion) -> void:
	if resource_manager == null:
		return

	# Before the ambient fill, so the veins take the cells they were placed for and the
	# fill counts them toward the island's node ceiling rather than stacking on top of it.
	if id == SEEDED_VEIN_ISLAND:
		seed_ore_veins()

	if region.ambient_resources:
		resource_manager.seed_island(region)

	if id == BOSS_ID:
		populate_boss_island()


## Puts SEEDED_VEINS on the ore island, once ever.
##
## Runs at world generation and again after a save is replayed, and only one of those may
## ever place anything - hence the flag rather than a census check. Placement is a pure
## function of the island's saved centre, radius and seed, so even a bug that ran this
## twice would rewrite the same six cells rather than double them; the flag is what stops
## a mined-out vein coming back.
func seed_ore_veins() -> void:
	if ore_veins_seeded:
		return
	if resource_manager == null or resource_manager.resources == null or tile_map_handler == null:
		return
	if not islands.has(SEEDED_VEIN_ISLAND):
		return
	# Never before the player can walk over here. The flag below is once-ever and is set even
	# when a cell is skipped, so a call made while the island is still across the water would
	# spend the whole seeding pass on ground nobody can reach and record it as done.
	if not _connected_state(SEEDED_VEIN_ISLAND):
		return

	var island: Dictionary = islands[SEEDED_VEIN_ISLAND]
	var cells := vein_cells(
		island["centre"], island["radius"], islands_seed, SEEDED_VEIN_ISLAND, seeded_vein_total()
	)

	var next := 0
	for entry in SEEDED_VEINS:
		var resource: GameResource = resource_manager.resources.Get(entry["type"])
		for _n in int(entry["count"]):
			if next >= cells.size():
				break
			var cell: Vector2i = cells[next]
			next += 1
			# Never over something already standing there. At generation the island is bare,
			# but this also runs after a replay, and a player's building outranks a teaser.
			if resource == null or tile_map_handler.is_occupied(cell, true):
				continue
			# Through the resource_added signal rather than set_tile directly, so the veins
			# arrive by the same path every other spawned node does.
			resource_manager.set_resource(cell, resource)

	# Set even if a cell was skipped: this is "the seeding pass has happened", not "six
	# nodes exist". Retrying on the next load is precisely the resurrect-on-load bug.
	ore_veins_seeded = true


static func seeded_vein_total() -> int:
	var total := 0
	for entry in SEEDED_VEINS:
		total += int(entry["count"])
	return total


## Which cells the seeded veins go on, from the island's own geometry.
##
## Spread around the centre on VEIN_RING_RADII at evenly spaced angles: taking the cells
## nearest the centre instead would fill a solid 3x3 block, which reads as generator
## scaffolding rather than as veins.
##
## Every candidate is walked inward until it lands on a cell whose eight neighbours are all
## island land. That is stricter than "is land" on purpose, and it is the reason these are
## reliably placeable: island_cells only promises the CENTRE is solid - the noise bites up
## to ISLAND_EDGE_BITE into the rest - and a cell with a water neighbour is solved into a
## coastline tile rather than plain grass, which main.gd's is_occupied refuses outright. An
## interior cell is grass, so it is placeable for every seed. Walking inward terminates at
## the centre, which is interior for any island radius the table uses.
##
## Isthmus cells are never candidates: this reads island_cells, which is the disc alone.
static func vein_cells(centre: Vector2i, island_radius: int, seed_value: int, id: String, count: int) -> Array[Vector2i]:
	var land := {}
	for cell in island_cells(centre, island_radius, seed_value, id):
		land[cell] = true

	var chosen: Array[Vector2i] = []
	var taken := {}

	for i in count:
		var angle := TAU * float(i) / float(count)
		var ring: int = VEIN_RING_RADII[i % VEIN_RING_RADII.size()]
		var cell = _vein_cell_along(centre, angle, ring, land, taken)
		if cell == null:
			# The ray ran out - its cells were bitten away or already claimed. Rare, but a
			# silently dropped vein would leave the island short of what the constant says,
			# so fall back to the nearest usable cell anywhere on the island.
			cell = _nearest_interior_cell(centre, land, taken)
		if cell == null:
			continue
		taken[cell] = true
		chosen.append(cell)

	return chosen


## The outermost cell along `angle` that is usable, searching inward from `ring` to the
## island's centre. Untyped return: null means the whole ray was unusable.
static func _vein_cell_along(centre: Vector2i, angle: float, ring: int, land: Dictionary, taken: Dictionary):
	for step in range(ring, -1, -1):
		var cell := centre + Vector2i(roundi(cos(angle) * step), roundi(sin(angle) * step))
		if not taken.has(cell) and _is_interior(cell, land):
			return cell
	return null


## Untyped return: null means the island has no usable cell left at all.
static func _nearest_interior_cell(centre: Vector2i, land: Dictionary, taken: Dictionary):
	var best = null
	var best_distance := 0.0
	for cell in land:
		if taken.has(cell) or not _is_interior(cell, land):
			continue
		var distance := Vector2(cell - centre).length()
		if best == null or distance < best_distance:
			best = cell
			best_distance = distance
	return best


## Whether every one of a cell's eight neighbours is land, i.e. whether the terrain solver
## leaves it as plain grass rather than as coastline.
static func _is_interior(cell: Vector2i, land: Dictionary) -> bool:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if not land.has(cell + Vector2i(dx, dy)):
				return false
	return true


## Puts the elite and its chest on the boss island. Idempotent: it checks for what it is
## about to place, because it runs both at world generation and again after a save is
## replayed, and only one of those should ever actually place anything.
func populate_boss_island() -> void:
	if boss_defeated or not islands.has(BOSS_ID):
		return
	# The arena is the last thing the progression opens, so the elite waits for it. Spawning
	# it at world generation put a boss on the far side of the water for the whole game: it
	# counts against nothing and threatens nobody, but it is on screen from the first frame
	# and its reward chest is sitting there filled.
	if not _connected_state(BOSS_ID):
		return

	var centre: Vector2i = islands[BOSS_ID]["centre"]
	if _live_boss() == null:
		_spawn_boss(centre)
	_place_reward_chest(centre + BOSS_CHEST_OFFSET)


func _spawner() -> EnemySpawner:
	if tile_map_handler == null:
		return null
	return tile_map_handler.get_node_or_null("World/EnemySpawner") as EnemySpawner


func _live_boss() -> Enemy:
	var spawner := _spawner()
	if spawner == null:
		return null
	for child in spawner.get_children():
		if child is Enemy and child.type == BOSS_TYPE:
			return child
	return null


## Parented to the EnemySpawner rather than to this node, which buys the entire enemy
## save/load path for nothing. It costs nothing either: the arena refuses ambient enemies,
## so the boss never has company competing for the population cap.
func _spawn_boss(centre: Vector2i) -> void:
	var spawner := _spawner()
	if spawner == null:
		return

	var boss = spawner.scene_for_type(BOSS_TYPE).instantiate()
	boss.position = tile_map_handler.tileMap.map_to_local(centre)
	spawner.add_child(boss)

	# After add_child - _ready is what builds the HealthManager this hangs off.
	if boss.health_manager:
		boss.health_manager.died.connect(_on_boss_died)


func _on_boss_died() -> void:
	boss_defeated = true


func _place_reward_chest(cell: Vector2i) -> void:
	if _chest_at(cell) != null:
		return

	var chest := GameItems.get_item(Types.Item.Chest)
	if chest == null:
		return

	tile_map_handler.set_tile(cell, chest.tile_source_id, chest.atlas_location, chest.layer, chest.is_scene_tile)
	_fill_reward_chest(cell)


func _chest_at(cell: Vector2i) -> TestChest:
	var want := tile_map_handler.tileMap.map_to_local(cell)
	for node in tile_map_handler.tileMap.get_children():
		if node is TestChest and node.position.distance_to(want) < 1.0:
			return node
	return null


## The engine instantiates a scene tile a frame after its cell is written, so the chest
## node does not exist yet - and TestChest._ready fills inventory_data with three empty
## slots, so anything written before that frame would be overwritten anyway.
func _fill_reward_chest(cell: Vector2i) -> void:
	await get_tree().process_frame

	var chest := _chest_at(cell)
	if chest == null or chest.inventory_data == null:
		return

	for i in mini(BOSS_REWARD.size(), chest.inventory_data.inventory_slot_datas.size()):
		var slot := SlotData.new()
		slot.item = GameItems.get_item(BOSS_REWARD[i]["type"])
		slot.count = BOSS_REWARD[i]["count"]
		chest.inventory_data.inventory_slot_datas[i] = slot


## Re-draws the islands after a save has been replayed over the map.
##
## Two different situations end up here. A save written since this feature existed carries
## an IslandManager entry, so loadObject has already restored the centres, and this only
## has to put the terrain back. A save written BEFORE it does not: loadObject never runs
## for a node the file has no line for, and main.gd's replay clears layer 1 across every
## cell it knows about - which strips the islands of their resources while leaving their
## ground intact. Hence the emptiness check rather than a flag.
##
## A player who clears an entire island and then saves is indistinguishable from that
## second case and gets it restocked on load. The respawn timer would have refilled it
## anyway; it just happens at once.
func reassert_after_load() -> void:
	if tile_map_handler == null:
		return

	var home_reach := _home_land_at_max_radius()
	for id in islands.keys():
		var island: Dictionary = islands[id]
		var definition := _definition_for(id)
		if definition.is_empty():
			continue

		var region := _install(definition, island["centre"], island["radius"], island["angle"], home_reach)

		# Only for an island already open. A closed one has nothing to restore - it never had
		# contents - and the emptiness check cannot tell those two apart.
		if region.connected and region.ambient_resources and tile_map_handler.count_resource_nodes_in(region) == 0:
			resource_manager.seed_island(region)

	# A no-op for any save written since the veins existed - the flag comes back true and
	# the tiles came back with the replay. It fires exactly once, for a save written before
	# them, whose ore island has no veins for the replay to restore, and only if that ore
	# island has been reached.
	seed_ore_veins()

	# Last, because it reads the terrain this method has just put back. It is also what opens
	# an island for a save written before the gating existed: those carry no `connected` and
	# come back closed, so the flood fill is what recognises the ones the player had already
	# walked to. The stocking that follows tops each up rather than doubling it - seed_island
	# counts what is already standing there, and the veins and the boss are both idempotent.
	refresh_connections()


func saveObject() -> Dictionary:
	var saved := []
	for id in islands:
		var island: Dictionary = islands[id]
		# A nested dictionary, not JSON.stringify of one: SaveLoad stringifies the whole
		# payload anyway, so the inner layer was pure overhead and one more failure point.
		# SaveLoad.decode_entries reads both shapes, so older saves still load (gather-usv).
		saved.append({
			"id": id,
			"x": island["centre"].x,
			"y": island["centre"].y,
			"radius": island["radius"],
			"angle": island["angle"],
			# Saved rather than re-derived, so a load does not re-open an island the player
			# has already walked to. Re-opening is not harmless: opening is what stocks, and
			# an island the player has half cleared would be topped back up on every load.
			"connected": island.get("connected", false),
		})

	return {
		# Guarded so the node stays constructible outside a SceneTree, which is what makes
		# the placement maths testable without standing up the whole game.
		"filepath": get_path() if is_inside_tree() else NodePath(),
		"islands_seed": islands_seed,
		"boss_defeated": boss_defeated,
		"ore_veins_seeded": ore_veins_seeded,
		"islands": saved,
	}


func loadObject(loadedDict: Dictionary) -> void:
	# Every read defaulted: a direct index on a dict written by an older version aborts
	# the method silently, because a -> void that errors looks exactly like one that ran.
	islands_seed = int(loadedDict.get("islands_seed", islands_seed))
	boss_defeated = bool(loadedDict.get("boss_defeated", false))
	# Defaults false, so a save written before the veins existed gets its one seeding pass
	# from reassert_after_load. A save written since carries true and never seeds again.
	ore_veins_seeded = bool(loadedDict.get("ore_veins_seeded", false))

	var saved: Array = loadedDict.get("islands", [])
	if saved.is_empty():
		return

	islands.clear()
	# decode_entries reads both the pre-gather-usv JSON strings and the nested dictionaries
	# written now, and drops anything unreadable rather than raising.
	for data in SaveLoad.decode_entries(saved):
		var id: String = str(data.get("id", ""))
		var definition := _definition_for(id)
		if definition.is_empty():
			continue

		islands[id] = {
			"centre": Vector2i(int(data.get("x", 0)), int(data.get("y", 0))),
			"radius": int(data.get("radius", definition["radius"])),
			"angle": float(data.get("angle", 0.0)),
			# Defaults closed, which is what a save written before the gating existed reads
			# as. reassert_after_load's flood fill re-opens whichever of those the player had
			# in fact already reached, so an old save does not lose an island it had earned.
			"connected": bool(data.get("connected", false)),
			"region": null,
		}

	# Geometry only. The terrain and the regions are put back by reassert_after_load, one
	# frame later, because main.gd's replay clears layer 1 across every cell it knows
	# about - anything re-asserted here would be stripped again immediately afterwards.
	#
	# And deliberately no seeding and no signal. The resources come back through that same
	# replay; running the stocking pass here would lay a second island's worth of nodes on
	# top of the ones the save just restored.


static func _definition_for(id: String) -> Dictionary:
	for definition in ISLANDS:
		if definition["id"] == id:
			return definition
	return {}
