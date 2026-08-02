@tool
extends SceneTree

# Stone building-set art generator: the stone wall blob and the stone floor.
#
# Same approach as tools/generate_placeholder_art.gd - recolour existing hand-drawn
# tiles rather than author new ones - but this one copies a whole autotiling blob
# instead of single cells, so the terrain topology of the stone wall is identical to
# the wood wall's by construction rather than by hand-transcription.
#
#   godot --headless --path . --script res://tools/generate_stone_build_art.gd
#   godot --headless --path . --import          # imports the new PNG
#
# The output is committed; the game never runs this at runtime. Rerun it only when
# the stone set should change, or when real art replaces one of these cells.
#
# The tileset side (atlas source 11 in assets/tilesets/world_tile_set.tres) is
# hand-written for the same reason the placeholder one is: ResourceSaver.save() on
# that TileSet rewrites all 1900 lines of terrain and scene-collection data.
#
# Exit codes: 0 wrote the sheet, 2 could not run (source sheet unreadable).

const SOURCE_SHEET := "res://assets/art/tiles.png"
const OUTPUT_SHEET := "res://assets/art/stone_build_tiles.png"

const CELL := 16
const SHEET_CELLS := Vector2i(12, 7)

## The wood wall's 47-tile blob on tiles.png, in cells. Rows 7-10 hold the tile
## origins; rows 11-12 hold the lower halves of the tiles that are 1x2 in the atlas
## (see size_in_atlas in world_tile_set.tres), so the copied rect has to run to row
## 12 or those walls lose their top-of-wall overhang.
const WALL_BLOB_FROM := Rect2i(0, 7, 12, 6)

## Where that blob lands on the generated sheet. Kept at column 0 and shifted up by
## exactly WALL_BLOB_FROM.position.y so every cell's offset within the blob survives:
## the tileset block for source 11 is the source-4 block with 7 subtracted from every
## row, which is only true while this stays a pure translation.
const WALL_BLOB_TO := Vector2i(0, 0)

## The wood floor, and where its stone twin goes. Row 6 rather than row 5: rows 0-4
## are wall tile origins and row 5 is the overflow of the 1x2 tiles on row 4, and
## main.gd classifies a wall by an atlas rect, so anything inside (0,0)-(11,4) would
## be picked up as a wall tile.
const FLOOR_FROM := Vector2i(4, 2)
const FLOOR_TO := Vector2i(0, 6)

## The same desaturated blue-grey the placeholder generator tints the stone pickaxe
## with, so the stone tier reads as one material across tools and buildings.
const STONE := Color(0.62, 0.64, 0.70)

## Recolours are luminance-driven, so the original tile's shading, mortar lines and
## outline all survive the tint. The gain lifts midtones back up after the multiply,
## which otherwise reads as a uniformly muddy silhouette. Higher than the placeholder
## generator's 1.45 because the wood wall is a much darker source than the ore nodes
## are, and at 1.45 the wall came out nearly black.
const TINT_GAIN := 1.9


func _init() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_SHEET))
	if source == null:
		printerr("[generate_stone_build_art] could not read %s" % SOURCE_SHEET)
		quit(2)
		return

	source.convert(Image.FORMAT_RGBA8)

	var sheet := Image.create_empty(
		SHEET_CELLS.x * CELL, SHEET_CELLS.y * CELL, false, Image.FORMAT_RGBA8
	)

	_recolour_rect(source, sheet, WALL_BLOB_FROM, WALL_BLOB_TO)
	print("  stone wall blob  %s -> %s" % [WALL_BLOB_FROM, WALL_BLOB_TO])

	_recolour_rect(source, sheet, Rect2i(FLOOR_FROM.x, FLOOR_FROM.y, 1, 1), FLOOR_TO)
	print("  stone floor  %s -> %s" % [FLOOR_FROM, FLOOR_TO])

	var error := sheet.save_png(ProjectSettings.globalize_path(OUTPUT_SHEET))
	if error != OK:
		printerr("[generate_stone_build_art] save_png failed: %d" % error)
		quit(2)
		return

	print("[generate_stone_build_art] wrote %s (%dx%d)" % [
		OUTPUT_SHEET, sheet.get_width(), sheet.get_height()
	])
	print("[generate_stone_build_art] now run: godot --headless --path . --import")
	quit(0)


## Copies a rect of cells, tinting every opaque pixel by its own luminance. Fully
## transparent pixels are skipped rather than written black, which is what keeps the
## gaps inside the blob (the empty cell at 10:8, the notches around each wall cap)
## transparent instead of turning the sheet into a solid grey square.
func _recolour_rect(source: Image, sheet: Image, from: Rect2i, to: Vector2i) -> void:
	for y in from.size.y * CELL:
		for x in from.size.x * CELL:
			var pixel := source.get_pixel(from.position.x * CELL + x, from.position.y * CELL + y)
			if pixel.a <= 0.0:
				continue
			var luminance := pixel.get_luminance() * TINT_GAIN
			sheet.set_pixel(to.x * CELL + x, to.y * CELL + y, Color(
				minf(STONE.r * luminance, 1.0),
				minf(STONE.g * luminance, 1.0),
				minf(STONE.b * luminance, 1.0),
				pixel.a
			))
