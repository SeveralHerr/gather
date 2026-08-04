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

## The tier-2 crafting set (gather-cte). Bone is the warm off-white of the skeleton tiles so a
## bone sword reads as kin to the bone pickaxe; iron keeps the blue-grey the hand-drawn iron
## tiles already use, so the sword ladder is legible against the pickaxe ladder at a glance.
## Gold reuses GOLD above rather than a second yellow, for the same reason.
const BONE := Color(0.90, 0.88, 0.76)
const IRON := Color(0.60, 0.67, 0.78)

## Bandage is near-white with the faintest warm cast, so it does not read as ice; cooked food
## is a deeper brown than raw so the two are distinguishable in a hotbar slot at 16px; brick
## is the red-brown that says "fired" against the grey of plain stone.
const BANDAGE := Color(0.95, 0.94, 0.90)
const COOKED := Color(0.78, 0.47, 0.26)
const BRICK := Color(0.70, 0.42, 0.34)

## The charged skull (gather-8ft). A cold electric blue, chosen to sit as far from BONE above
## as the sheet allows: the charged skull and the ordinary bone drop are the same silhouette,
## so colour is the ONLY thing distinguishing them in a hotbar slot, and "slightly bluer bone"
## would not survive being seen at 16px through a night tint.
const CHARGED := Color(0.35, 0.72, 1.0)

## The arc colours drawn over that skull. The core is near-white because electricity reads as
## white-hot with a coloured halo, not as a bright version of its own colour — an arc drawn in
## CHARGED alone disappears into the skull it is supposed to be crackling over.
const ARC_CORE := Color(0.88, 0.97, 1.0)
const ARC_GLOW := Color(0.40, 0.78, 1.0)

## Recolours are luminance-driven, so the original tile's shading survives. The
## gain lifts midtones back up after the tint multiply, which otherwise reads as
## a uniformly muddy silhouette.
const TINT_GAIN := 1.45

## Rows 3 and 4 hold the ore tiers. Row 1 holds the tier-2 crafting set added by gather-cte;
## rows 0 and 2 are still free.
##
## Those rows used to be reserved deliberately: several lookups in main.gd matched a resource
## by atlas coordinate ALONE, ignoring the source id, so a generated cell reusing a coordinate
## already held by tree (1,0) or stone (2,1) would have been gathered as that resource. That
## is fixed — main.gd now keys on source + coordinate together (gather-54s, see
## TileMapHandler.resource_key) — so the rows are usable and row 1 is used.
##
## The rule that remains, and it is a weaker one: a few coordinate-only comparisons survive in
## tile_path_finder.gd and bone_worker.gd, all of them scanning TILEMAP cells for water, door
## or tree. Nothing on row 1 is placeable, so none of them can ever see these cells. Put a
## PLACEABLE tile on this sheet and that constraint comes back — check those call sites first.
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

	# --- the tier-2 crafting set (gather-cte), all on row 1.
	# Each is a recolour of the hand-drawn tile it is a variant OF, so the silhouettes stay
	# consistent with what the player already knows: the swords come off the starting sword,
	# the bandage off string, cooked food off food, and the brick off plain stone.
	{"from": Vector2i(6, 0), "to": Vector2i(0, 1), "tint": BONE, "what": "bone sword"},
	{"from": Vector2i(6, 0), "to": Vector2i(1, 1), "tint": IRON, "what": "iron sword"},
	{"from": Vector2i(6, 0), "to": Vector2i(2, 1), "tint": GOLD, "what": "gold sword"},
	{"from": Vector2i(16, 1), "to": Vector2i(3, 1), "tint": BANDAGE, "what": "bandage"},
	{"from": Vector2i(15, 0), "to": Vector2i(4, 1), "tint": COOKED, "what": "cooked food"},
	{"from": Vector2i(1, 2), "to": Vector2i(5, 1), "tint": BRICK, "what": "stone brick"},

	# The charged skull (gather-8ft), on the free row 0. Recoloured from the captured
	# bone-enemy icon rather than the plain Bone drop, because that cell is a SKULL and the
	# item is a skull - the player should recognise what fell out of the skeleton.
	{"from": Vector2i(14, 0), "to": Vector2i(0, 0), "tint": CHARGED, "what": "charged skull"},
]

## Where the charged skull lands, and where the arcs are drawn over it.
const CHARGED_SKULL_CELL := Vector2i(0, 0)

## The charged skeleton's own sprite, recoloured from the bone enemy's cell at tiles.png
## (14, 0) — the same art the enemy scene points at, so the two silhouettes are identical and
## only the colour differs.
##
## This is a real recoloured SPRITE rather than a `modulate` on the node, and the difference is
## not cosmetic. A modulate multiplies the whole cell by one colour, so the dark eye sockets and
## the bright bone move together and the result reads as a skeleton behind blue glass. Ramping
## the luminance through three colours instead lets the shadows go deep blue while the
## highlights go pale, which is what makes it read as a skeleton that IS blue.
const CHARGED_SKELETON_FROM := Vector2i(14, 0)
const CHARGED_SKELETON_CELL := Vector2i(1, 0)

## The three stops of that ramp: socket shadow, mid bone, lit edge.
##
## The darkest stop is deliberately not black. The enemy is met at night and in rain, under a
## world tint already multiplying everything down, and a skull whose sockets reach zero loses
## its shape against the ground before the player can read what it is.
const SKEL_SHADOW := Color(0.05, 0.11, 0.28)
const SKEL_MID := Color(0.20, 0.46, 0.86)
const SKEL_LIGHT := Color(0.78, 0.94, 1.0)

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

	# After the recolour loop, deliberately: the arcs are drawn ON TOP of the blue skull that
	# entry produced, so ordering here is what makes them visible at all.
	_draw_arcs(sheet, CHARGED_SKULL_CELL)
	print("  charged skull arcs  (drawn) -> %s" % CHARGED_SKULL_CELL)

	_ramp_cell(source, sheet, CHARGED_SKELETON_FROM, CHARGED_SKELETON_CELL)
	print("  charged skeleton  %s -> %s" % [CHARGED_SKELETON_FROM, CHARGED_SKELETON_CELL])

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


## Electricity crackling around the charged skull.
##
## The arcs are hand-placed pixel runs rather than a procedural bolt, and at this size that is
## not laziness. A 16x16 cell is about four pixels of clearance around the skull; a random
## walk through that space produces either a straight line or mush, and it produces a
## DIFFERENT one every time the sheet is regenerated, so a committed asset would change under
## a rerun that was meant to be a no-op.
##
## Two arcs, opposite corners, so the skull reads as being between them rather than as having
## something stuck to one side. Each is a zigzag: the core in near-white with ARC_GLOW shed
## one pixel below-left, which is the cheapest thing that reads as a glow without a blur.
const ARCS := [
	[Vector2i(2, 1), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(2, 5)],
	[Vector2i(13, 10), Vector2i(12, 11), Vector2i(13, 12), Vector2i(12, 13), Vector2i(13, 14)],
]


func _draw_arcs(sheet: Image, cell: Vector2i) -> void:
	# Both loops bind through a typed local. Iterating an untyped Array yields Variant, and
	# `var glow := point + Vector2i(...)` is a PARSE error on it rather than a runtime one —
	# the same inference trap CLAUDE.md documents for the test runner's `_T`.
	for arc in ARCS:
		for point in arc:
			# The glow goes down first so the core overwrites it wherever the two collide -
			# an arc whose own halo is drawn over its centre reads as a smudge, not a spark.
			var at: Vector2i = point
			var glow := at + Vector2i(-1, 1)
			if glow.x >= 0 and glow.y < CELL:
				sheet.set_pixel(cell.x * CELL + glow.x, cell.y * CELL + glow.y, ARC_GLOW)
	for arc in ARCS:
		for point in arc:
			var at: Vector2i = point
			sheet.set_pixel(cell.x * CELL + at.x, cell.y * CELL + at.y, ARC_CORE)


## Recolours a cell by mapping its LUMINANCE through a three-stop ramp.
##
## Different from _recolour_cell above, which multiplies a tint into the original and therefore
## preserves the source's own hue relationships. That is right for an ore or a tool, where the
## art should read as the same object in a different metal. It is wrong here: the skeleton is
## already near-white, so a multiply just darkens it uniformly and the sockets stay the same
## relative brightness they were. Remapping instead means the ramp decides the whole palette,
## which is how a white skull becomes a blue one rather than a tinted one.
func _ramp_cell(source: Image, sheet: Image, from: Vector2i, to: Vector2i) -> void:
	for y in CELL:
		for x in CELL:
			var pixel := source.get_pixel(from.x * CELL + x, from.y * CELL + y)
			if pixel.a <= 0.0:
				continue

			var l := pixel.get_luminance()
			var colour: Color
			if l < 0.5:
				colour = SKEL_SHADOW.lerp(SKEL_MID, l * 2.0)
			else:
				colour = SKEL_MID.lerp(SKEL_LIGHT, (l - 0.5) * 2.0)

			# Alpha is carried straight through, so the silhouette is EXACTLY the bone enemy's.
			# Any change here and the two stop being the same skeleton.
			sheet.set_pixel(to.x * CELL + x, to.y * CELL + y, Color(colour.r, colour.g, colour.b, pixel.a))


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
