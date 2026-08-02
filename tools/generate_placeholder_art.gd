@tool
extends SceneTree

# Placeholder art generator for the ore tiers that do not have real sprites yet.
#
# The game's whole tile vocabulary lives in one hand-drawn sheet (assets/art/tiles.png).
# Rather than hand-authoring copper/gold variants, this script recolours existing
# tiles into a second, generated sheet. The output is committed so the game never
# depends on this script at runtime - rerun it only when the placeholders should
# change, or when real art replaces a cell and the rest still need regenerating.
#
#   godot --headless --path . --script res://tools/generate_placeholder_art.gd
#   godot --headless --path . --import          # imports the new PNG
#
# The tileset side (atlas source 10 in assets/tilesets/world_tile_set.tres) is
# hand-written rather than produced here: ResourceSaver.save() on that TileSet
# rewrites all 1900 lines of terrain and scene-collection data, and a silent
# round-trip bug there would take the whole world with it.
#
# Exit codes: 0 wrote the sheet, 2 could not run (source sheet unreadable).

const SOURCE_SHEET := "res://assets/art/tiles.png"
const OUTPUT_SHEET := "res://assets/art/placeholder_tiles.png"

const CELL := 16
const SHEET_CELLS := Vector2i(6, 5)

## Copper reads as a warm brown-orange, gold as a bright yellow. Both are pushed
## well away from the greys of stone and the blue-grey of iron so a node's tier is
## readable at the game's 8x zoom without a legend.
const COPPER := Color(0.87, 0.47, 0.22)
const GOLD := Color(1.0, 0.81, 0.24)

## Stone reads as a desaturated blue-grey. It is tinted off the WOODEN pickaxe rather
## than the iron one so the head still looks chipped and crude next to the metal
## tiers, which is the tier it sits between.
const STONE := Color(0.62, 0.64, 0.70)

## Recolours are luminance-driven, so the original tile's shading survives. The
## gain lifts midtones back up after the tint multiply, which otherwise reads as
## a uniformly muddy silhouette.
const TINT_GAIN := 1.45

## Rows 0-2 of the generated sheet are left empty on purpose. Several lookups in
## main.gd match a resource by atlas coordinate ALONE, ignoring the source id
## (see get_location_of_nearby_resource), so a generated node that reused a
## coordinate already held by tree (1,0) or stone (2,1) would be gathered as that
## resource instead. Rows 3 and 4 are unused by every existing resource.
const RECOLOURS := [
	{"from": Vector2i(4, 1), "to": Vector2i(0, 3), "tint": COPPER, "what": "copper node"},
	{"from": Vector2i(4, 1), "to": Vector2i(1, 3), "tint": GOLD, "what": "gold node"},
	{"from": Vector2i(8, 1), "to": Vector2i(2, 3), "tint": COPPER, "what": "copper node (being mined)"},
	{"from": Vector2i(8, 1), "to": Vector2i(3, 3), "tint": GOLD, "what": "gold node (being mined)"},
	{"from": Vector2i(6, 2), "to": Vector2i(0, 4), "tint": COPPER, "what": "copper ore"},
	{"from": Vector2i(6, 2), "to": Vector2i(1, 4), "tint": GOLD, "what": "gold ore"},
	{"from": Vector2i(7, 2), "to": Vector2i(2, 4), "tint": COPPER, "what": "copper bar"},
	{"from": Vector2i(7, 2), "to": Vector2i(3, 4), "tint": GOLD, "what": "gold bar"},
	{"from": Vector2i(6, 1), "to": Vector2i(5, 4), "tint": GOLD, "what": "gold pickaxe"},
	{"from": Vector2i(6, 1), "to": Vector2i(4, 3), "tint": COPPER, "what": "copper pickaxe"},
	{"from": Vector2i(12, 0), "to": Vector2i(5, 3), "tint": STONE, "what": "stone pickaxe"},
]

## The coin has no plausible ancestor on the sheet, so it is drawn rather than
## recoloured.
const COIN_CELL := Vector2i(4, 4)


func _init() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_SHEET))
	if source == null:
		printerr("[generate_placeholder_art] could not read %s" % SOURCE_SHEET)
		quit(2)
		return

	source.convert(Image.FORMAT_RGBA8)

	var sheet := Image.create_empty(
		SHEET_CELLS.x * CELL, SHEET_CELLS.y * CELL, false, Image.FORMAT_RGBA8
	)

	for entry in RECOLOURS:
		_recolour_cell(source, sheet, entry["from"], entry["to"], entry["tint"])
		print("  %s  %s -> %s" % [entry["what"], entry["from"], entry["to"]])

	_draw_coin(sheet, COIN_CELL)
	print("  gold coin  (drawn) -> %s" % COIN_CELL)

	var error := sheet.save_png(ProjectSettings.globalize_path(OUTPUT_SHEET))
	if error != OK:
		printerr("[generate_placeholder_art] save_png failed: %d" % error)
		quit(2)
		return

	print("[generate_placeholder_art] wrote %s (%dx%d)" % [
		OUTPUT_SHEET, sheet.get_width(), sheet.get_height()
	])
	print("[generate_placeholder_art] now run: godot --headless --path . --import")
	quit(0)


func _recolour_cell(source: Image, sheet: Image, from: Vector2i, to: Vector2i, tint: Color) -> void:
	for y in CELL:
		for x in CELL:
			var pixel := source.get_pixel(from.x * CELL + x, from.y * CELL + y)
			if pixel.a <= 0.0:
				continue
			var luminance := pixel.get_luminance() * TINT_GAIN
			sheet.set_pixel(to.x * CELL + x, to.y * CELL + y, Color(
				minf(tint.r * luminance, 1.0),
				minf(tint.g * luminance, 1.0),
				minf(tint.b * luminance, 1.0),
				pixel.a
			))


## A 5px-radius disc with a darker rim and a highlight, centred in the cell.
func _draw_coin(sheet: Image, cell: Vector2i) -> void:
	var centre := Vector2(CELL * 0.5 - 0.5, CELL * 0.5 - 0.5)
	var rim := GOLD.darkened(0.45)
	var highlight := GOLD.lightened(0.45)

	for y in CELL:
		for x in CELL:
			var distance := Vector2(x, y).distance_to(centre)
			if distance > 5.2:
				continue
			var colour := GOLD
			if distance > 4.0:
				colour = rim
			elif Vector2(x, y).distance_to(centre + Vector2(-1.5, -1.5)) < 1.6:
				colour = highlight
			sheet.set_pixel(cell.x * CELL + x, cell.y * CELL + y, colour)
