extends RefCounted
class_name LandRegion

## A named stretch of land with its own spawn rules.
##
## Every system that stocks the world - the resource seeder, the ambient respawn
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
##
## These state the region's INTENT and never change. Whether it is stockable *today* is
## `connected` below, and the two are deliberately separate: the boss arena refuses ambient
## spawning forever, while the grove merely has not been reached yet.
var ambient_resources: bool = true
var ambient_enemies: bool = true

## Whether the player can walk here from the home island right now.
##
## Islands are drawn at world generation and are visible across the water for most of the
## early game. What that means for what lives on them is split, and the split is the point:
##
##   - **Resources grow there from the first frame.** An island is a place, and a place the
##     player can see across the water has to look like one - the ore island reads as an ore
##     island because there is visibly ore on it, which is the thing that makes crossing the
##     water worth saving up for. This gate used to cover resources too, and a bare green
##     disc is not a promise of anything.
##   - **Enemies wait for the coastline to arrive.** Nothing may wander onto ground the
##     player cannot reach, so an island stays quiet until it opens and then fills up. The
##     boss is gated the same way, by IslandManager, and for the stronger version of the same
##     reason: an elite parked across the water threatens nobody and is on screen from the
##     first frame.
##
## The enemy ceiling scales with the land its regions own, so a closed island holds no share
## of it either - see EnemySpawner. The resource ceiling deliberately does now, because those
## nodes exist.
##
## Defaults true, so the home region and anything that never sets it behave as before.
## IslandManager clears it at generation and sets it from a flood fill; see
## IslandManager.refresh_connections.
var connected: bool = true


## Whether the respawn timer may put a node down here as things stand.
##
## Not gated on `connected`: resources are what an island is made of, and it is made of them
## before anyone can walk there. `ambient_resources` is still absolute - the boss arena stays
## bare forever.
func accepts_ambient_resources() -> bool:
	return ambient_resources


## Whether the enemy spawner may pick a cell here as things stand. Gated on `connected`, so
## an island the player cannot reach yet stays empty of enemies.
func accepts_ambient_enemies() -> bool:
	return connected and ambient_enemies


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
