extends Node
class_name SkyLighting

## Paints the world with whatever colour the WorldClock says the sky is.
##
## Created at runtime by main.gd, like LandManager and IslandManager, because it has to
## reach three things that live in three different canvases and none of them is a natural
## parent for it.
##
## ## Why this is three writes and not one
##
## A CanvasModulate tints exactly ONE canvas — the one it is a child of. The game has
## three, and a single CanvasModulate under `World` reaches only the first of them:
##
##   root canvas (no CanvasLayer)   World, TileMap, Player, Camera2D, and the diegetic HUD
##   Ocean CanvasLayer, layer -100  the sea (main.gd:_setup_ocean_backdrop)
##   UI CanvasLayer, layer 1        hotbar, panels, screen flash
##
## So:
##
##  - **The world** gets the CanvasModulate. This is the one that does the actual work.
##  - **The sea does not.** Left alone it stays daylight blue at midnight while the land it
##    surrounds goes dark, which looks less like night than like a rendering bug. main.gd
##    owns OCEAN_COLOR; this multiplies the same tint into it by hand.
##  - **The HUD is tinted when it should not be.** It hangs off Camera2D, so it is in the
##    root canvas and the CanvasModulate catches it — the HP bar and the XP bar dim exactly
##    when the player most needs to read them. The fix is to cancel it: `modulate` is a
##    per-canvas-item multiply and CanvasModulate is a whole-canvas multiply, so the
##    reciprocal restores the HUD to what it would have been. One line, and it does not
##    require moving the HUD out of the camera — which is world-space by design and which
##    camera_hud.gd, the save paths and half the layout comments all depend on.
##
## The UI CanvasLayer is untouched on purpose: screen-space UI is not in the world and
## should not take the world's weather.

## Where the sea's ColorRect lives, relative to Main. Kept as a constant next to the code
## that depends on it rather than reached for inline, because it is a promise about
## main.gd:_setup_ocean_backdrop that nothing else enforces.
const OCEAN_WATER_PATH := "Ocean/Water"

## The diegetic HUD, relative to Main. Absent in any scene that is not the full game, and
## absent for the first frames of one — resolved lazily for the same reason
## LevelUpManager resolves its xp bar lazily.
const HUD_PATH := "World/Player/Camera2D/HUD"

const PLAYER_PATH := "World/Player"

## The radial falloff the lantern is drawn with. This is the texture the disabled
## `World/PointLight2D` in main.tscn used to carry — that node was an unfinished experiment
## sitting at the world origin with `visible = false`, and this is what it was for.
const LIGHT_TEXTURE := preload("res://assets/art/light.png")

## Lantern brightness at full night, and the scale that sets its radius.
##
## Both are much lower than they started, and the screenshot is why. light.png is 256px, so
## the scale the dead scene node carried (0.365) put the lantern 93 world units across —
## nearly six tiles, 748 screen pixels at the camera's 8 zoom — and at 0.9 energy a Light2D
## blends additively, so the middle of it saturated to a pale green blob covering a third of
## the view. Every property read said the night tint was correct, and it was; the world was
## simply lit back up on top of it. This is the one thing in the change that only a
## screenshot could have caught.
##
## 0.16 is about two and a half tiles, which reaches roughly as far as the player can
## interact, and 0.40 leaves the ground under it readable without erasing the tint.
const LANTERN_ENERGY := 0.40
const LANTERN_SCALE := 0.16

## The lantern is off in daylight and full at night, ramped across the twilights so it does
## not switch on in a single frame. `1.0 - brightness` drives it, where brightness is how
## light the sky currently is — so it tracks the same curve the tint does instead of
## re-deriving the phase boundaries and drifting from them.
const LANTERN_DAY_BRIGHTNESS := 0.95
const LANTERN_NIGHT_BRIGHTNESS := 0.55

var clock: WorldClock

## The Main node everything above is resolved against.
var main: Node

var _modulate: CanvasModulate
var _water: ColorRect
var _hud: CanvasItem
var _lantern: PointLight2D

## The base colour of the sea, captured once so every pass multiplies the tint into the
## ORIGINAL rather than into the already-tinted result. Compounding a multiply frame over
## frame drives the sea to black in about a second — the same mistake PlayerStats documents
## for stat deltas and camera_hud.gd documents for its base transforms.
var _base_water_color := Color.WHITE
var _has_base_water := false


func _ready() -> void:
	add_to_group("SkyLighting")

	if main == null:
		main = get_parent()

	_modulate = CanvasModulate.new()
	_modulate.name = "SkyModulate"

	# Into the World subtree, so it tints the root canvas. Anywhere inside that canvas would
	# work identically — it is a canvas-wide effect, not a subtree one — but putting it under
	# World is what makes that intent legible to the next reader.
	var world := main.get_node_or_null("World")
	if world == null:
		push_warning("SkyLighting: no World node, the day/night tint has nowhere to live")
		return
	world.add_child(_modulate)
	apply()


## Deliberately polls rather than listening to the clock's signals.
##
## The tint changes on every frame of a twilight — that gradual ramp is the entire point of
## the curve — so `phase_changed` fires four times a day and would leave the sky frozen at
## whatever colour the last boundary set. The signals exist for systems that react to a
## *change* of phase (the spawner); a system that draws the current value has to read the
## current value.
func _process(_delta: float) -> void:
	apply()


## Pushes the clock's current tint into all three places. Public and idempotent so devtools
## and the load path can force a repaint without waiting for a frame — a setter that changes
## the model and leaves the screen showing the old world is exactly the half-applied state
## CLAUDE.md warns a devtools verb must never leave behind.
func apply() -> void:
	if clock == null:
		return

	var tint := clock.tint()

	if _modulate != null:
		_modulate.color = tint

	_apply_ocean(tint)
	_apply_hud(tint)
	_apply_lantern(tint)


func _apply_ocean(tint: Color) -> void:
	if not is_instance_valid(_water):
		_water = main.get_node_or_null(OCEAN_WATER_PATH) as ColorRect
		if _water == null:
			return
		_base_water_color = _water.color
		_has_base_water = true

	if not _has_base_water:
		return

	# Alpha is left alone: the sea is opaque and the tint has no business changing that.
	_water.color = Color(
		_base_water_color.r * tint.r,
		_base_water_color.g * tint.g,
		_base_water_color.b * tint.b,
		_base_water_color.a
	)


## Cancels the CanvasModulate over the HUD subtree, so the bars read the same at midnight
## as at noon.
##
## The reciprocal is exact rather than approximate: CanvasModulate multiplies the canvas by
## `tint` and `modulate` multiplies this item by `1/tint`, so the product is 1 and the HUD
## renders at its authored colours. Channels clamp at 1.0 on the way out, which is why this
## restores rather than over-brightens — and why the guard below matters, since a tint
## channel at zero would be a division by zero the clamp could not save.
func _apply_hud(tint: Color) -> void:
	if not is_instance_valid(_hud):
		_hud = main.get_node_or_null(HUD_PATH) as CanvasItem
		if _hud == null:
			return

	_hud.modulate = Color(
		1.0 / maxf(tint.r, 0.001),
		1.0 / maxf(tint.g, 0.001),
		1.0 / maxf(tint.b, 0.001)
	)


## Brings the player's lantern up as the sky goes down.
##
## Driven off the tint's own brightness rather than off the phase, so it follows the same
## smoothstepped twilight ramp the sky does and cannot drift from it — deriving the
## boundaries a second time here is how the light ends up switching on a few seconds before
## or after the sky agrees that it is dark. It also means rain, which darkens the sky
## without changing the hour, brings the lantern up a little on its own. That is the
## correct behaviour and it costs nothing.
##
## The renderer matters here. project.godot runs `gl_compatibility` on mobile, where
## Light2D count per canvas item is limited, so this is deliberately ONE light rather than
## a lantern plus a rim plus a glow. Anything added later (a torch, a campfire) needs to be
## distance-culled against the same budget.
func _apply_lantern(tint: Color) -> void:
	if not is_instance_valid(_lantern):
		var player := main.get_node_or_null(PLAYER_PATH)
		if player == null:
			return

		_lantern = PointLight2D.new()
		_lantern.name = "Lantern"
		_lantern.texture = LIGHT_TEXTURE
		_lantern.scale = Vector2(LANTERN_SCALE, LANTERN_SCALE)
		_lantern.shadow_enabled = true
		player.add_child(_lantern)

	# The perceived brightness of the sky, as one number. An unweighted mean is fine: the
	# tints here are all near-neutral, and the alternative (a luminance weighting) would
	# imply a precision the two constants below do not have.
	var brightness := (tint.r + tint.g + tint.b) / 3.0

	# inverse_lerp, then clamped: full off at or above LANTERN_DAY_BRIGHTNESS, full on at or
	# below LANTERN_NIGHT_BRIGHTNESS, and a smooth ramp between the two.
	var span := LANTERN_DAY_BRIGHTNESS - LANTERN_NIGHT_BRIGHTNESS
	var darkness := 0.0 if span <= 0.0 else clampf((LANTERN_DAY_BRIGHTNESS - brightness) / span, 0.0, 1.0)

	_lantern.energy = darkness * LANTERN_ENERGY
	# Free the renderer from a light that contributes nothing, rather than drawing a
	# zero-energy one every frame all day.
	_lantern.visible = darkness > 0.0
