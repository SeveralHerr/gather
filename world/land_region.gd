extends RefCounted
class_name LandRegion

## A named stretch of land with its own spawn rules.
##
## Every system that stocks the world - the resource seeder, the eight-second respawn
## timer, the enemy spawner - used to read `TileMapHandler.land_tiles()`, which is every
## plain-grass cell anywhere on the map. That was correct while the home island was the
## only land there was. It stops being correct the moment a second island exists: the
## resource and enemy ceilings both scale with total grass, so three new islands inflate
## both, and a global weighted roll scatters ordinary trees across an ore island and
## ordinary enemies across a boss arena. Within minutes a themed island erodes back into
## a generic one.
##
## A region fixes the roll rather than the geometry. `spawn_weights` overrides the global
## TUNING weights for this patch of ground only, and the two `ambient_*` flags let a
## region opt out of being restocked at all.
##
## Membership is by distance from `centre`, and islands are resolved before the home
## region (see TileMapHandler.region_for_cell). That ordering is deliberate: once the
## home island has been bought outward far enough to absorb an island, those cells belong
## to both, and the island keeps them. A forest grove swallowed by the mainland stays a
## forest grove.

var id: String = ""
var centre: Vector2i = Vector2i.ZERO
var radius: int = 0

## Per-type overrides of GameResource.spawn_weight, keyed by Types.Item. A type absent
## from the dictionary keeps its global weight; a type mapped to 0.0 never spawns here.
## Zeroing every unlocked type is a valid way to say "nothing grows on this island".
var spawn_weights: Dictionary = {}

## Live nodes per land tile, and the floor under that. The home island wants a floor high
## enough that a small starting island is not barren; an island a fifth its size wants a
## much lower one, or a six-tile grove is capped as generously as the mainland.
var resource_density: float = 0.25
var min_resources: int = 40

## Whether the respawn timer may restock here, and whether the enemy spawner may pick
## cells here. Separate because the boss arena wants neither but a quiet resource island
## might want only the first.
var ambient_resources: bool = true
var ambient_enemies: bool = true


## The exact cells this region owns, as a set. Empty means "judge by distance from
## `centre`", which is what the home region does - its footprint changes shape every time
## a parcel is bought, so there is nothing fixed to enumerate.
##
## An island states its cells outright because a disc is the wrong shape for one: the spit
## of land reaching back toward the mainland trails well outside the island's own radius,
## and a radius grown to cover it would swallow open water, neighbouring islands and a
## slice of home along with it. The boss arena is the case that matters - the far end of
## its isthmus falling back to the mainland's rules would quietly restock the one region
## whose whole purpose is to stay empty.
var cells := {}


func has_cell(cell: Vector2i) -> bool:
	if not cells.is_empty():
		return cells.has(cell)
	return Vector2(cell - centre).length() <= float(radius)


func set_cells(from: Array) -> void:
	cells.clear()
	for cell in from:
		cells[cell] = true
