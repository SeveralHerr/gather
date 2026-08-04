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

# --- lightning ---------------------------------------------------------------
#
# Why the flash is folded into the tint rather than drawn.
#
# The obvious implementation is a white ColorRect in the UI layer, faded in and out. It is
# wrong here in three ways at once, and every one of them is something this file already has
# a comment about further up:
#
#  - It would light the land and leave the sea flat dark. The sea is in its own CanvasLayer,
#    which is the fact nothing outside this class ever remembers — the same
#    daylight-blue-at-midnight failure the header describes, arriving by a new route.
#  - It would strobe the HP and XP bars. The HUD is in the root canvas, and a flash drawn
#    over it dims and brightens the two readouts the player most needs during a storm at
#    night. That is the concern NIGHT_TINT's 0.42 floor exists for, in a different form.
#  - It would put weather in the UI CanvasLayer, which is the one canvas this class
#    deliberately never touches.
#
# Brightening `tint` before apply() makes the three writes it already does carry the flash
# instead. The sea brightens because _apply_ocean multiplies the same value. The HUD holds
# perfectly still because _apply_hud takes the reciprocal of whatever it is handed, so the
# flash cancels itself there exactly, for free, and without a special case. And the lantern
# dims for the duration because _apply_lantern reads brightness back off the tint — which is
# what a lantern does when the sky lights up. None of those three is code below; they are the
# existing code being handed a brighter number.

## How long one bolt's flash lasts, in seconds.
##
## A flash the player has time to watch is a flash that reads as a screen effect. Half a
## second is about two blinks: long enough for the second strike to land as its own event,
## short enough that the world is back to its night colour before the eye settles on the new
## one.
const FLASH_DURATION := 0.55

## How much brightness the nearest and the furthest bolt add, as a gain over 1.0.
##
## Tuned against a stormy night, because that is the only sky most bolts will ever be seen
## in: night times rain is (0.30, 0.35, 0.54), and 1.85 of that is (0.56, 0.65, 1.00) — a
## sky that is briefly bright and still blue, rather than a white frame. It is not higher for
## the mirror of the reason NIGHT_TINT has a floor: once every channel clips, the flash and
## the frame after it are both flat, and the return to darkness reads as a dropped frame
## instead of as the storm passing. A bolt at noon does clip, and that is fine — an overhead
## strike in daylight is supposed to be the brightest thing on screen.
##
## The far value is deliberately small. A distant bolt should be something noticed at the
## edge of vision while gathering, not something that interrupts it: 1.18 over a stormy night
## is roughly the difference between night and late dusk.
const FLASH_PEAK_NEAR := 0.85
const FLASH_PEAK_FAR := 0.18

## The shape of the double strike, in fractions of FLASH_DURATION.
##
## Lightning is a leader stroke and then a return stroke, and the gap between them is what
## the eye actually identifies it by. A single smooth rise and fall over the same half second
## reads as a screen wipe or a damage flash — the brightness is right and the event is still
## unrecognisable. So: a spike that reaches full in about two frames, a cubic fall to near
## dark, then a second smaller spike out of that trough.
##
## The two strikes overlap slightly (STRIKE_TWO_START sits inside STRIKE_ONE_END) so the
## trough between them is a deep dip rather than a hard cut to zero and back. A literal zero
## in the middle is a black frame, which is its own artefact.
const STRIKE_ONE_PEAK_AT := 0.04
const STRIKE_ONE_END := 0.36
const STRIKE_TWO_START := 0.30
const STRIKE_TWO_PEAK_AT := 0.36
const STRIKE_TWO_HEIGHT := 0.55

## The bolt itself — the thing the player actually points at when they say they saw lightning.
##
## The flash alone was the whole effect for a while, and it reads as the screen blinking rather
## than as a strike: the sky changes brightness and nothing in the world is the cause. Drawing
## the arc is what makes the flash look like a consequence.
##
## Geometry is regenerated per strike rather than being one authored shape reused, because a
## bolt that is the same silhouette every time reads as a sprite being toggled.
const BOLT_SEGMENTS := 10
const BOLT_HEIGHT := 260.0

## Lateral wander per segment.
##
## Was 9.0, and a screenshot is the only thing that caught it: 9 units of jitter across a 260
## unit drop is under four degrees, so the arc rendered as a very slightly bent vertical line
## and read as a laser rather than as lightning. Every property on the node was correct and the
## node was plainly there — this is the class of bug only an actual frame shows.
const BOLT_JAG := 26.0
const BOLT_WIDTH := 1.6

## The flash where the bolt lands. Without it the arc simply stops in mid-air, which reads as
## the sprite being clipped rather than as a strike hitting something.
const BOLT_IMPACT_RADIUS := 7.0

## How far from the player a bolt lands, at distance 0.0 and at 1.0.
##
## The far end is deliberately well outside the ~240 world units the camera shows at its 8
## zoom, so a horizon bolt is simply not on screen and needs no special case to hide it — the
## player sees its flash and hears its thunder, which is exactly what "far away" should mean.
const BOLT_NEAR_OFFSET := 18.0
const BOLT_FAR_OFFSET := 420.0

## Above this the bolt is off screen however the jitter falls, so it is not built at all.
const BOLT_CULL_OFFSET := 240.0

const BOLT_CORE := Color(0.92, 0.97, 1.0)
const BOLT_GLOW := Color(0.45, 0.72, 1.0)

## Drawn well above the world so a bolt is never behind a tree or a wall. It is a light source
## in front of the scene, not an object in it.
const BOLT_Z := 400

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

## The World subtree, kept from _ready so a bolt has somewhere to be drawn. Bolts go in the
## world canvas rather than the UI layer on purpose: a strike happens at a PLACE, and one drawn
## in screen space would sit still while the player walked past it.
var _world: Node2D

## The live bolt, if one is on screen. At most one — a second strike replaces it rather than
## stacking, matching the single flash envelope that fades them both.
var _bolt: Node2D

## Seconds since the current bolt struck, and the gain that bolt is worth at its peak.
##
## `_flash_peak` doubles as the "is a flash running" flag, and it is what keeps an idle sky
## bit-identical to what it was before lightning existed: at zero, apply() skips the multiply
## rather than multiplying by 1.0. A day/night curve that drifts while nothing is happening
## is the kind of regression the continuity tests in test_world_clock.gd would not
## necessarily catch, because every sample would drift the same way.
var _flash_elapsed := FLASH_DURATION
var _flash_peak := 0.0


func _ready() -> void:
	add_to_group("SkyLighting")

	if main == null:
		main = get_parent()

	# Connected before the World lookup below, which can return early. A scene without a
	# World still has a clock worth listening to, and the connection is cheap.
	#
	# main.gd assigns `clock` before add_child(), so it is already here — but a SkyLighting
	# built by hand in a test or a devtools verb may have none, and apply() already tolerates
	# that, so this has to as well.
	if clock != null and not clock.lightning_struck.is_connected(_on_lightning_struck):
		clock.lightning_struck.connect(_on_lightning_struck)

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
	_world = world as Node2D
	apply()


## Deliberately polls rather than listening to the clock's signals.
##
## The tint changes on every frame of a twilight — that gradual ramp is the entire point of
## the curve — so `phase_changed` fires four times a day and would leave the sky frozen at
## whatever colour the last boundary set. The signals exist for systems that react to a
## *change* of phase (the spawner); a system that draws the current value has to read the
## current value.
func _process(delta: float) -> void:
	_advance_flash(delta)
	apply()


## Moves the current bolt's flash along, and retires it when it is spent.
##
## Kept out of apply() on purpose. apply() is called by devtools and by the load path to
## force a repaint, and if a repaint also advanced the flash then how long a bolt lasted
## would depend on how many things had asked for a redraw during it.
func _advance_flash(delta: float) -> void:
	if _flash_peak <= 0.0:
		return

	_flash_elapsed += delta
	if _flash_elapsed >= FLASH_DURATION:
		# Clamped rather than left to grow, and the peak zeroed with it, so an idle sky is
		# back to skipping the multiply entirely rather than evaluating an envelope that will
		# answer zero forever.
		_flash_elapsed = FLASH_DURATION
		_flash_peak = 0.0
		_clear_bolt()
		return

	# Driven off the SAME envelope the flash uses rather than a tween of its own. Two timers
	# for one event drift, and the way that shows up is a bolt still hanging in the air after
	# the sky has finished flashing — which reads as a stuck sprite, not as lightning.
	if is_instance_valid(_bolt):
		_bolt.modulate.a = flash_envelope(_flash_elapsed, FLASH_DURATION)


## Pushes the clock's current tint into all three places. Public and idempotent so devtools
## and the load path can force a repaint without waiting for a frame — a setter that changes
## the model and leaves the screen showing the old world is exactly the half-applied state
## CLAUDE.md warns a devtools verb must never leave behind.
func apply() -> void:
	if clock == null:
		return

	var tint := _flashed(clock.tint())

	if _modulate != null:
		_modulate.color = tint

	_apply_ocean(tint)
	_apply_hud(tint)
	_apply_lantern(tint)


## The sky's colour with whatever lightning is currently doing to it multiplied in.
##
## The early return is the contract, not an optimisation: with no bolt running this hands
## back the argument untouched, not the argument multiplied by one. A day/night curve that
## rounds a little differently once lightning exists is a regression no test of the curve
## itself would report, because every sample would move together. See the lightning section
## above for why the flash lands here rather than in a layer of its own.
func _flashed(tint: Color) -> Color:
	if _flash_peak <= 0.0:
		return tint

	var gain := 1.0 + flash_envelope(_flash_elapsed, FLASH_DURATION) * _flash_peak
	# Channel-wise rather than `tint * gain`, which would scale alpha too. The CanvasModulate
	# reads that alpha, and a sky that goes translucent for half a second shows the clear
	# colour behind the world.
	return Color(tint.r * gain, tint.g * gain, tint.b * gain, tint.a)


## Starts a flash for a bolt at `distance` (0.0 overhead, 1.0 on the horizon) and hands the
## thunder to the sound manager, which owns its own delay — the light arrives now and the
## sound arrives later, and splitting that across two systems is how it stays that way.
func _on_lightning_struck(distance: float) -> void:
	_flash_elapsed = 0.0
	_flash_peak = flash_peak_for(distance)

	# Guarded rather than assumed. The autoload is always there in the running game, but this
	# node can be built by hand into a tree that has no autoloads at all — the headless test
	# runner is its own SceneTree and instantiates none of them (ui/splash_text.gd carries the
	# same guard for the same reason). Losing the thunder is the right failure there; taking
	# the flash down with it is not.
	if GameSoundManager != null:
		GameSoundManager.play_thunder(distance)

	_spawn_bolt(distance)


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


# --- pure helpers (unit-tested; keep them free of node access) ----------------


## The brightness curve of one bolt, 0..1, `elapsed` seconds into a flash of `duration`.
##
## Exactly zero at both ends and never negative in between, so the caller can multiply by it
## unconditionally and a flash always leaves the sky exactly where it found it. Two strikes
## rather than one — see the STRIKE_* constants for why the gap is the load-bearing part.
##
## Static, and takes its duration as an argument rather than reading FLASH_DURATION, so the
## shape can be swept in a test with no SceneTree and no node — which is the only way the
## double strike gets asserted at all. A shape is not something a screenshot can pin down:
## one frame of it looks the same whichever curve produced it.
static func flash_envelope(elapsed: float, duration: float) -> float:
	if duration <= 0.0:
		# Reachable only by misconfiguration, but the alternative is a division by zero that
		# produces INF or NAN and then paints it into three canvases at once.
		return 0.0
	if elapsed <= 0.0 or elapsed >= duration:
		return 0.0

	var f := elapsed / duration
	return maxf(
		_strike(f, 0.0, STRIKE_ONE_PEAK_AT, STRIKE_ONE_END, 1.0),
		_strike(f, STRIKE_TWO_START, STRIKE_TWO_PEAK_AT, 1.0, STRIKE_TWO_HEIGHT)
	)


## One stroke: a linear rise to `height` at `peak_at`, then a cubic fall back to zero at
## `end`. Zero outside (start, end), so the two strokes can simply be max()'d together.
##
## The rise is linear and its window is deliberately about two frames wide, because a stroke
## that eases in is a stroke you can watch arrive. The fall is cubed instead, so the bright
## part is brief and the afterglow is long — that asymmetry is most of what separates a
## flash from a pulse.
static func _strike(f: float, start: float, peak_at: float, end: float, height: float) -> float:
	if f <= start or f >= end:
		return 0.0

	if f < peak_at:
		return height * (f - start) / maxf(peak_at - start, 0.0001)

	var fall := (f - peak_at) / maxf(end - peak_at, 0.0001)
	var remaining := 1.0 - fall
	return height * remaining * remaining * remaining


## How bright a bolt at `distance` flashes, 0.0 overhead to 1.0 on the horizon.
##
## Linear, not inverse-square. The physically correct falloff puts everything past about a
## third of the range at the same imperceptible brightness, so most of the values the clock
## can roll would be indistinguishable from each other — a range that exists in the model and
## not on the screen. Out-of-range input clamps rather than extrapolating: a negative
## distance must not produce a gain the tint cannot survive.
static func flash_peak_for(distance: float) -> float:
	return lerpf(FLASH_PEAK_NEAR, FLASH_PEAK_FAR, clampf(distance, 0.0, 1.0))


## Builds the arc for one strike, near the player, and returns immediately if it would land
## off screen.
##
## The bolt is deliberately not pooled or reused. It is at most one node alive for half a
## second, a few times per storm, and a pooled one would have to be re-jagged on every strike
## anyway — the whole reason it is regenerated is that a repeated silhouette stops reading as
## lightning and starts reading as a sprite being toggled.
## Re-aims the current bolt at an exact spot, and re-runs the flash from the top.
##
## Exists because a bolt that CHARGES a skeleton has to be seen hitting that skeleton. The
## signal carries only a distance, so `_spawn_bolt` can do no better than a plausible offset
## from the player — fine for a bolt that hits nothing, and obviously wrong for one whose whole
## point is what it landed on. EnemySpawner calls this once it knows which skeleton it picked.
##
## Restarting the envelope rather than leaving it mid-fade is deliberate: this runs in the same
## frame as the original strike, so the flash has advanced by at most one delta, and beginning
## again is what stops the re-aimed bolt appearing already half faded.
func strike_bolt_at(distance: float, at: Vector2) -> void:
	_flash_elapsed = 0.0
	_flash_peak = flash_peak_for(distance)
	_spawn_bolt(distance, at)


## `at` is where the bolt lands. Vector2.INF means "nowhere in particular" — pick a plausible
## spot near the player, which is what an ordinary bolt that hits nothing does.
func _spawn_bolt(distance: float, at: Vector2 = Vector2.INF) -> void:
	_clear_bolt()

	if _world == null or not is_instance_valid(_world):
		return

	var ground := at
	if not _is_real_position(at):
		var player := main.get_node_or_null(PLAYER_PATH) as Node2D
		if player == null:
			return

		# Offset grows with distance, so a far bolt is genuinely somewhere else rather than
		# being a small one drawn on top of the player. Past the cull it cannot be on screen at
		# all, and building it would be a node created purely to be invisible.
		var offset := lerpf(BOLT_NEAR_OFFSET, BOLT_FAR_OFFSET, clampf(distance, 0.0, 1.0))
		if offset > BOLT_CULL_OFFSET:
			return

		# Either side of the player, so strikes do not all march off in one direction.
		var side := 1.0 if randf() < 0.5 else -1.0
		ground = player.global_position + Vector2(offset * side, randf_range(-24.0, 24.0))

	_bolt = Node2D.new()
	_bolt.name = "LightningBolt"
	_bolt.z_index = BOLT_Z
	_bolt.z_as_relative = false
	_world.add_child(_bolt)

	# Glow first, core second: the core has to be drawn OVER its own halo or the halo reads as
	# a smudge across the middle of the arc rather than as light coming off it. Same ordering,
	# and the same reason, as the charged-skull icon's arcs in tools/generate_placeholder_art.gd.
	var points := _bolt_points(ground)
	_add_bolt_line(points, BOLT_GLOW, BOLT_WIDTH * 3.0)
	_add_bolt_line(points, BOLT_CORE, BOLT_WIDTH)

	# A short fork off the middle of the arc. One branch, not a tree: at this size a second
	# level of branching turns into a smudge, and the single fork is what stops the silhouette
	# reading as one drawn line.
	_add_bolt_line(_fork_points(points), BOLT_CORE, BOLT_WIDTH * 0.7)

	_add_impact(ground)

	_bolt.modulate.a = 0.0


## A jagged descent to `ground`, in the bolt's local space.
func _bolt_points(ground: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var drift := randf_range(-BOLT_JAG, BOLT_JAG)

	for i in BOLT_SEGMENTS + 1:
		var f := float(i) / float(BOLT_SEGMENTS)
		# The taper converges only over the LAST third, not across the whole descent. Tapering
		# linearly from the top (the obvious `* (1.0 - f)`) spends most of the arc's visible
		# length nearly straight, which is what made the first version read as a beam even
		# after the jitter was tripled — the jag was there, just all of it above the screen.
		var taper := minf(1.0, (1.0 - f) * 3.0)
		var jag := randf_range(-BOLT_JAG, BOLT_JAG) * taper
		points.append(Vector2(
			ground.x + jag + drift * taper,
			ground.y - BOLT_HEIGHT * (1.0 - f)
		))

	return points


## A branch leaving the arc partway down and petering out to one side.
func _fork_points(trunk: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	if trunk.size() < 4:
		return points

	var start := trunk[int(trunk.size() * 0.45)]
	var away := 1.0 if randf() < 0.5 else -1.0
	points.append(start)
	for i in 3:
		points.append(Vector2(
			start.x + away * BOLT_JAG * 0.8 * float(i + 1) + randf_range(-4.0, 4.0),
			start.y + BOLT_HEIGHT * 0.12 * float(i + 1)
		))
	return points


## The bright point where the arc meets the ground.
##
## Drawn as a two-point Line2D with round caps rather than a Polygon2D circle: it is one node
## either way, and this keeps every part of the bolt the same node type so the fade applied to
## the parent's modulate needs no per-child special case.
func _add_impact(ground: Vector2) -> void:
	var dot := Line2D.new()
	dot.points = PackedVector2Array([ground, ground + Vector2(0.01, 0.0)])
	dot.width = BOLT_IMPACT_RADIUS
	dot.default_color = BOLT_GLOW
	dot.begin_cap_mode = Line2D.LINE_CAP_ROUND
	dot.end_cap_mode = Line2D.LINE_CAP_ROUND
	_bolt.add_child(dot)

	var core := Line2D.new()
	core.points = dot.points
	core.width = BOLT_IMPACT_RADIUS * 0.45
	core.default_color = BOLT_CORE
	core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core.end_cap_mode = Line2D.LINE_CAP_ROUND
	_bolt.add_child(core)


func _add_bolt_line(points: PackedVector2Array, colour: Color, width: float) -> void:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = colour
	# Off: a rounded cap on a 1.6px line at this zoom just blunts the tip, and the joint mode
	# is what keeps the corners of the zigzag sharp enough to read as an arc.
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	line.joint_mode = Line2D.LINE_JOINT_SHARP
	_bolt.add_child(line)


## Whether `at` names a real place rather than the "pick one for me" sentinel.
##
## `is_finite` rather than `== Vector2.INF`, because a NaN would compare false against INF and
## then propagate silently through every point of the arc into a Line2D that draws nothing.
static func _is_real_position(at: Vector2) -> bool:
	return is_finite(at.x) and is_finite(at.y)


func _clear_bolt() -> void:
	if is_instance_valid(_bolt):
		# Renamed before freeing, because queue_free DEFERS: the old node is still in the tree
		# when the replacement is added on the same frame, so the name collides and Godot
		# silently renames the NEW one to @Node2D@NNN. Nothing breaks, but the bolt stops
		# having a findable path — which is how a strike that worked looked like a strike that
		# had produced nothing at all while I was verifying this.
		_bolt.name = "LightningBoltSpent"
		_bolt.queue_free()
	_bolt = null
