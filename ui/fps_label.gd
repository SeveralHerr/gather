extends Label

## The frame-rate readout in the diegetic HUD.
##
## It lives under `Player/Camera2D/HUD`, which is world space — so this text is
## drawn straight onto the tilemap with nothing behind it, and the world it is
## drawn onto is bright green grass in one direction and bright blue ocean in the
## other. Plain white glyphs disappear into the water.
##
## The ink outline is what the whole UI uses to separate itself from the world
## (see `ui/ui_theme.gd`'s note on COLOR_INK), and it is applied here in code
## rather than in `main.tscn` because this Control has no other authored
## appearance to sit alongside.
##
## ## Why the size and the node's scale are a matched pair
##
## This label is scaled down inside a camera zoomed to 8, so the number of screen
## pixels one font pixel covers is `font_size / 10 * scale * 8`. The bitmap face
## only stays crisp when that product is a whole number, and the node's authored
## scale used to be `0.275` — which multiplied to 2.2 and could not be made whole
## by *any* font size below 50. The scale is `0.25` in `main.tscn` now, so the
## product is exactly 2.0 and a FONT_SIZE of 20 puts each font pixel on four
## screen pixels.
##
## Change either number and the other has to move with it, or the readout goes
## soft — which does not look like a font bug, it looks like a blurry screenshot.


## Both on the pixel grid described above. OUTLINE_SIZE is expressed against
## FONT_SIZE, so 2 of 20 is exactly one font pixel of ink.
const FONT_SIZE := 20
const OUTLINE_SIZE := 2


func _ready() -> void:
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	add_theme_color_override("font_outline_color", UiTheme.COLOR_INK)
	add_theme_constant_override("outline_size", OUTLINE_SIZE)


func _process(_delta: float) -> void:
	text = "FPS " + str(Engine.get_frames_per_second())
