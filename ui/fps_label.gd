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
## appearance to sit alongside. The size is large because the HUD is scaled down
## to 0.275 before it reaches the screen: an outline of 1 would be a quarter of a
## pixel and would not survive the downscale.


## Outline width in the HUD's own unscaled space. See the note above on why it is
## not a small number.
const OUTLINE_SIZE := 12


func _ready() -> void:
	add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	add_theme_color_override("font_outline_color", UiTheme.COLOR_INK)
	add_theme_constant_override("outline_size", OUTLINE_SIZE)


func _process(_delta: float) -> void:
	text = "FPS " + str(Engine.get_frames_per_second())
