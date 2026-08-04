@tool
extends SceneTree

# Berry bush art generator: the two bush states, the berry item icon, and the two
# frames the bush breaks over when it is uprooted.
#
#   godot --headless --path . --script res://tools/generate_berry_bush_art.gd
#   godot --headless --path . --import          # re-imports the edited PNG
#
# Unlike tools/generate_placeholder_art.gd and generate_stone_build_art.gd, which write
# their own sheets, this one stamps cells into the HAND-DRAWN sheet (tiles.png). That is
# deliberate: GameItem.get_atlas() picks the icon sheet off the tile source id, so anything
# registered against source 4 has to have its icon on that sheet, and the bush is a source-4
# resource. Stamping is idempotent — every run writes the same pixels into the same five
# cells and touches nothing else — so a rerun is safe, but it IS an edit to a committed
# hand-drawn asset and the output is committed with it.
#
# The palette is the TREE's, sampled from tiles.png (1,0) rather than invented, which is the
# whole reason the bush reads as the same forest: same four-step green ramp, same navy
# outline, same translucent shadow ellipse. Berries are the only colours that are new.
#
# Exit codes: 0 wrote the sheet, 2 could not run (sheet unreadable or a cell out of range).

const SHEET := "res://assets/art/tiles.png"
const CELL := 16

## Where each sprite lands. Row 23 is empty across its whole width and no registered atlas
## coordinate points into it — checked before choosing it, because Resources.get_resource_by_data
## matches on atlas position ALONE, across every source, so a collision here would silently
## make two different things resolve to the same registry entry.
const FRUITING_CELL := Vector2i(0, 23)
const PICKED_CELL := Vector2i(1, 23)
const BERRY_ICON_CELL := Vector2i(2, 23)
const BREAK_1_CELL := Vector2i(3, 23)
const BREAK_2_CELL := Vector2i(4, 23)

## The tree's ten colours, plus three for the fruit. Keyed by the character used in the
## pixel maps below.
##  h/l/m/d/k  the green ramp, lightest to darkest
##  o          the navy outline the whole sheet shares
##  s          the soft shadow ellipse every node sits on
##  r/R/B      berry highlight / body / shade
const PALETTE := {
	"h": Color8(153, 230, 95),
	"l": Color8(90, 197, 79),
	"m": Color8(51, 152, 75),
	"d": Color8(30, 111, 80),
	"k": Color8(19, 76, 76),
	"o": Color8(12, 46, 68),
	"s": Color8(19, 19, 19, 116),
	"r": Color8(245, 85, 93),
	"R": Color8(196, 36, 48),
	"B": Color8(137, 30, 43),
	".": Color8(0, 0, 0, 0),
}

## The bush in leaf. `l` is deliberately scarce in the lower two thirds: it is the exact
## colour of the grass tile (90,197,79), so a bush that uses much of it below the highlight
## loses its edge against the ground it stands on.
const BUSH := [
	"................",
	"................",
	"......kkkk......",
	"....kkmhhmkk....",
	"..kkmhhllhhmkk..",
	"..kmllmllmmlmk..",
	".ommmmdmmmmmmmo.",
	".oddmmddmmddmdo.",
	".oddddmdddddddo.",
	".odkdddkddkdddo.",
	".okkdodkdkkdkko.",
	"..okkooookkkko..",
	"...oooooooooo...",
	"..ssssssssssss..",
	"..ssssssssssss..",
	"....ssssssss....",
]

## Top-left of each 2x2 berry stamped onto the bush above. Only pixels that are already
## opaque are overwritten, so a berry can sit on the silhouette edge without growing it.
const BUSH_BERRIES := [
	Vector2i(3, 6),
	Vector2i(10, 5),
	Vector2i(7, 9),
	Vector2i(12, 8),
]

## The 2x2 berry itself: highlight top-left, shade bottom-right.
const BERRY_STAMP := ["rR", "RB"]

## Three berries on a sprig. Item icons on this sheet are small, centred and unoutlined
## (compare Food at (15,0), Wood at (2,2)) — the heavy navy ring the world tiles carry
## reads as a blob at inventory size, so this does not use one.
const BERRY_ICON := [
	"................",
	"................",
	"........kmhk....",
	".......kmhhmk...",
	".......dmhmk....",
	"...rR..dk.......",
	"..rRRB.d.rR.....",
	"..RRBBd.rRRB....",
	"...RB.d.RRBB....",
	"......d..RB.....",
	"....rR..........",
	"...rRRB.........",
	"...RRBB.........",
	"....RB..........",
	"................",
	"................",
]

## Uprooting frames. The bush is pulled out rather than smashed, so it collapses to a
## flattened clump and then to scattered leaves, instead of the stone node's shatter.
const BREAK_1 := [
	"................",
	"................",
	"................",
	"................",
	"................",
	"................",
	"...k.......k....",
	"..kmk.....kmk...",
	".kmhhmkkmhhmmk..",
	".ommmdmmmdmmmo..",
	".oddmddmddmddo..",
	".okddoodkddkko..",
	"..oooooooooo....",
	"..ssssssssss....",
	"....ssssss......",
	"................",
]

const BREAK_2 := [
	"................",
	"................",
	"................",
	"...k........k...",
	"..km........mk..",
	"................",
	".k...m....d...k.",
	"................",
	"...d.......m....",
	"..k...ddm....k..",
	".....okkdo......",
	"......ooo.......",
	"....ssssss......",
	"................",
	"................",
	"................",
]


func _init() -> void:
	var path := ProjectSettings.globalize_path(SHEET)
	var image := Image.load_from_file(path)
	if image == null:
		push_error("generate_berry_bush_art: could not read %s" % SHEET)
		quit(2)
		return

	# Every write goes through here, so an out-of-range cell is caught once rather than
	# clipped silently by set_pixel().
	if not _fits(image, BREAK_2_CELL):
		push_error("generate_berry_bush_art: %s is too small for the target cells" % SHEET)
		quit(2)
		return

	_stamp(image, FRUITING_CELL, BUSH, BUSH_BERRIES)
	_stamp(image, PICKED_CELL, BUSH, [])
	_stamp(image, BERRY_ICON_CELL, BERRY_ICON, [])
	_stamp(image, BREAK_1_CELL, BREAK_1, [])
	_stamp(image, BREAK_2_CELL, BREAK_2, [])

	var err := image.save_png(path)
	if err != OK:
		push_error("generate_berry_bush_art: could not write %s (error %d)" % [SHEET, err])
		quit(2)
		return

	print("generate_berry_bush_art: stamped 5 cells into %s" % SHEET)
	quit(0)


func _fits(image: Image, cell: Vector2i) -> bool:
	return (cell.x + 1) * CELL <= image.get_width() and (cell.y + 1) * CELL <= image.get_height()


## Paints one 16x16 map at `cell`, then stamps the berries over it.
##
## The whole cell is written every time, transparent pixels included, so a rerun after the
## art shrinks does not leave the old sprite's overhang behind.
func _stamp(image: Image, cell: Vector2i, rows: Array, berries: Array) -> void:
	var origin := cell * CELL

	for y in CELL:
		var row: String = rows[y]
		for x in CELL:
			image.set_pixelv(origin + Vector2i(x, y), PALETTE[row[x]])

	for berry in berries:
		for dy in BERRY_STAMP.size():
			var stamp: String = BERRY_STAMP[dy]
			for dx in stamp.length():
				var at: Vector2i = origin + berry + Vector2i(dx, dy)
				# Opaque-only, so a berry never adds to the silhouette — see BUSH_BERRIES.
				if image.get_pixelv(at).a > 0.0:
					image.set_pixelv(at, PALETTE[stamp[dx]])
