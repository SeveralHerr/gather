extends Control
class_name RaidBanner

## The night-raid readout: a strip that drops in from the top of the screen when a raid opens,
## counts the raiders down while it runs, and slides away when it ends.
##
## This is the view half of `systems/raid_director.gd` and holds no raid state of its own — it
## renders what the director's signals say. Same split as `WorldClock` / `SkyLighting`, and the
## same reason: a model that draws cannot be tested headless and grows a second copy of its
## state inside whatever it draws into.
##
## ## Why it is here and not on the diegetic HUD
##
## It lives in the `UI` CanvasLayer (screen space). It must never be parented under
## `Player/Camera2D/HUD` — that Control is world-space at the camera's 8x zoom, so a strip put
## there is drawn *into the world*, scrolls with the camera and is dimmed by the day/night
## CanvasModulate. A raid readout that dims at night is a readout that is hardest to read
## exactly when it exists to be read.
##
## ## Sizing
##
## Nothing here is a raw pixel count. The project runs with `window/stretch/mode = "disabled"`,
## so a phone reports a genuinely smaller viewport and a hardcoded size renders that much
## smaller; every font size and pad goes through `UiTheme.scaled*` and is re-derived in
## `_apply_scale()` on every resize. The strip is anchored to the top-centre and grown from
## there — never positioned by arithmetic on a viewport dimension, which is the `gather-6fx`
## trap.

## Unscaled metrics. WIDTH is a minimum: the strip is centred, so it grows symmetrically.
const WIDTH := 280.0
const BAR_HEIGHT := 10.0
const MARGIN := 12.0
const INSET_PAD := 8.0

## How far above its resting place the strip starts, in unscaled pixels, and how long it takes
## to arrive. BACK easing overshoots downward and settles, so it reads as having been dropped
## rather than faded in.
const SLIDE_DISTANCE := 90.0
const SLIDE_IN_TIME := 0.45
const SLIDE_OUT_TIME := 0.35

## How long the "REPELLED" state stays on screen before the strip leaves. Long enough to read,
## short enough that it is gone before the player has finished collecting the coins.
const OUTRO_HOLD := 1.8

## The per-kill pulse: the strip swells briefly every time the count drops, so a kill registers
## on the readout as well as on the enemy. Small — this fires up to twelve times a night and a
## big pulse at that rate is a twitch, not feedback.
const PULSE_SCALE := 0.06
const PULSE_TIME := 0.18

## Fill colours. The bar runs from the raid's own ember orange toward red as the night is won,
## so the strip is a different colour at a glance when the fight is nearly over — the number is
## the precise readout and the colour is the peripheral one.
const BAR_FULL := Color(0.95, 0.35, 0.18)
const BAR_LOW := Color(1.0, 0.72, 0.28)

## Injected by `TileMapHandler._setup_raid_banner()` before this node enters the tree, so
## `_ready()` never has to go hunting through groups. Left null in a unit test that builds the
## banner on its own, which every read below tolerates.
var director: RaidDirector

var _strip: PanelContainer
var _column: VBoxContainer
var _title: Label
var _count: Label
var _bar: ProgressBar
var _strip_style: StyleBoxFlat
var _bar_fill: StyleBoxFlat
var _margin: MarginContainer

## Every text control paired with the unscaled font size it was authored at, the same
## `[control, base_size]` list the panels keep, so a label added later cannot be forgotten by
## the resize handler.
var _typography: Array[Array] = []

## Kept so a second event can kill the tween the first one started. Two tweens writing
## `position` in alternating frames is the flicker this avoids.
var _slide_tween: Tween
var _pulse_tween: Tween

## Where the strip sits when it is fully in. Recomputed on every resize, because it is derived
## from the scaled margin.
var _rest_y := 0.0

## Set while the outro is playing, so a raid that opens during it (a devtools time jump, or a
## night that clears on its last second) cancels the outro instead of being hidden by it.
var _leaving := false


func _ready() -> void:
	add_to_group("UI")

	# The root spans the screen only so the strip can be anchored to the top of it; it must
	# never be the node that swallows a click aimed at the world.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build()

	if director == null:
		for node in get_tree().get_nodes_in_group("RaidDirector"):
			# The scene root used to belong to every group in the project, so a type check rather
			# than get_first_node_in_group is the house pattern for a group lookup.
			if node is RaidDirector:
				director = node
				break

	if director != null:
		director.raid_started.connect(_on_raid_started)
		director.raid_progress.connect(_on_raid_progress)
		director.raid_cleared.connect(_on_raid_cleared)
		director.raid_survived.connect(_on_raid_survived)

	UiTheme.connect_resize(self, _apply_scale)
	_apply_scale()

	# A load can restore a raid that is already running, and the director emits `raid_progress`
	# from its `loadObject`. That emit may land before this node exists, so the banner asks once
	# on the way up rather than waiting for the next change.
	_sync_from_director.call_deferred()


# --- construction ------------------------------------------------------------


func _build() -> void:
	_strip = PanelContainer.new()
	_strip.name = "Strip"
	# Anchored to the top-centre and grown outward from it, so the strip's width comes from its
	# content rather than from a measurement of the viewport.
	_strip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_strip.grow_vertical = Control.GROW_DIRECTION_END
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Held as a field because the content margin is a size like any other and has to be
	# re-derived on a resize; a StyleBox edited in place re-lays-out its owner.
	_strip_style = UiTheme.overlay_style(true)
	_strip.add_theme_stylebox_override("panel", _strip_style)
	_strip.visible = false
	_strip.modulate = Color(1, 1, 1, 0)
	add_child(_strip)

	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(_margin)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_column)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(row)

	_title = _typed(Label.new(), UiTheme.FONT_BODY) as Label
	_title.name = "Title"
	_title.text = "RAID"
	_title.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title)

	_count = _typed(Label.new(), UiTheme.FONT_BODY) as Label
	_count.name = "Count"
	_count.add_theme_color_override("font_color", UiTheme.COLOR_GOLD)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_count)

	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 1.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_theme_stylebox_override("background", UiTheme.inset_style())
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = BAR_FULL
	_bar_fill.set_corner_radius_all(UiTheme.RADIUS_CONTROL)
	_bar.add_theme_stylebox_override("fill", _bar_fill)
	_column.add_child(_bar)


## Registers a text control's unscaled font size and hands it straight back, so a build line
## stays a single statement.
func _typed(control: Control, base_size: int) -> Control:
	_typography.append([control, base_size])
	return control


# --- sizing ------------------------------------------------------------------


## Re-derives every size from the current viewport. Runs at build time and on every resize —
## nothing here scales on its own, see the sizing note at the top.
func _apply_scale() -> void:
	if _strip == null:
		return

	# The same factor the panels and the toolbar are built at, so they grow in step.
	var factor := UiTheme.scale_for_node(self)

	UiTheme.apply_typography(_typography, factor)

	var pad := int(round(UiTheme.scaled(INSET_PAD, factor)))
	_margin.add_theme_constant_override("margin_left", pad)
	_margin.add_theme_constant_override("margin_right", pad)
	_margin.add_theme_constant_override("margin_top", pad)
	_margin.add_theme_constant_override("margin_bottom", pad)

	_column.add_theme_constant_override("separation", int(round(UiTheme.scaled(UiTheme.GAP * 0.5, factor))))
	_strip_style.set_corner_radius_all(int(round(UiTheme.scaled(UiTheme.RADIUS_CONTROL, factor))))

	var width := UiTheme.scaled(WIDTH, factor)
	_strip.custom_minimum_size = Vector2(width, 0)
	# The strip is centred on the top anchor, so its left offset is minus half its own width.
	# This is a size halved, not a viewport measurement — the anchor is what does the centring.
	_strip.offset_left = -width * 0.5
	_strip.offset_right = width * 0.5

	_bar.custom_minimum_size = Vector2(0, UiTheme.scaled(BAR_HEIGHT, factor))

	_rest_y = UiTheme.scaled(MARGIN, factor)
	# Only move the strip if it is not mid-flight; a resize during the slide would otherwise
	# teleport it to its resting place and cancel the animation visually.
	if _slide_tween == null or not _slide_tween.is_running():
		_strip.offset_top = _rest_y if _strip.visible else _hidden_y(factor)

	# Pivot at the middle so the per-kill pulse swells the strip about its own centre rather
	# than dragging it right and down from its top-left corner.
	_strip.pivot_offset = Vector2(width * 0.5, _strip.size.y * 0.5)


func _hidden_y(factor: float) -> float:
	return _rest_y - UiTheme.scaled(SLIDE_DISTANCE, factor)


# --- the director's signals --------------------------------------------------


func _on_raid_started(day: int, size: int) -> void:
	_leaving = false
	_title.text = "RAID · NIGHT %d" % day
	_title.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_bar_fill.bg_color = BAR_FULL
	_bar.value = 1.0
	_count.text = "%d" % size
	_count.add_theme_color_override("font_color", UiTheme.COLOR_GOLD)
	_slide_in()


func _on_raid_progress(remaining: int, total: int) -> void:
	# A progress emit for a raid that is not running is the director closing one out; the
	# outro owns the strip at that point and must not be overwritten by a "0" state.
	if total <= 0 or _leaving:
		return

	if not _strip.visible:
		# A load into a running raid arrives here rather than through `raid_started`.
		_title.text = "RAID · NIGHT %d" % (director.raid_day if director != null else 0)
		_slide_in()

	_count.text = "%d" % remaining
	var fraction := clampf(float(remaining) / float(total), 0.0, 1.0)
	_bar.value = fraction
	_bar_fill.bg_color = BAR_LOW.lerp(BAR_FULL, fraction)
	_pulse()


func _on_raid_cleared(_day: int, _reward_coins: int) -> void:
	_title.text = "RAID REPELLED"
	_title.add_theme_color_override("font_color", UiTheme.COLOR_GOOD)
	_count.text = ""
	_bar.value = 0.0
	_bar_fill.bg_color = UiTheme.COLOR_GOOD
	_pulse()
	_slide_out_after(OUTRO_HOLD)


## Dawn arrived with raiders still standing. Deliberately worded as survival rather than as a
## failure: nothing was taken away, and the raiders are still out there — see
## `RaidDirector._end_raid_at_dawn`, which leaves them alive on purpose.
func _on_raid_survived(_day: int, remaining: int) -> void:
	_title.text = "DAWN — %d STILL OUT THERE" % remaining if remaining > 0 else "DAWN"
	_title.add_theme_color_override("font_color", UiTheme.COLOR_GOLD)
	_count.text = ""
	_bar.value = 0.0
	_slide_out_after(OUTRO_HOLD)


## Draws whatever the director is doing right now, for the case where a signal was emitted
## before this node was listening — a load that restores a running raid does exactly that.
func _sync_from_director() -> void:
	if director == null or not director.raid_active:
		return
	_on_raid_started(director.raid_day, director.raid_size)
	_on_raid_progress(director.remaining(), director.raid_size)


# --- animation ---------------------------------------------------------------


func _slide_in() -> void:
	if _strip == null:
		return

	var factor := UiTheme.scale_for_node(self)
	_kill(_slide_tween)

	if not _strip.visible:
		_strip.offset_top = _hidden_y(factor)
		_strip.visible = true

	_slide_tween = create_tween()
	_slide_tween.set_parallel(true)
	_slide_tween.tween_property(_strip, "offset_top", _rest_y, SLIDE_IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_slide_tween.tween_property(_strip, "modulate:a", 1.0, SLIDE_IN_TIME * 0.6)


func _slide_out_after(delay: float) -> void:
	if _strip == null or not _strip.visible:
		return

	_leaving = true
	var factor := UiTheme.scale_for_node(self)
	_kill(_slide_tween)

	_slide_tween = create_tween()
	_slide_tween.tween_interval(delay)
	_slide_tween.set_parallel(true)
	_slide_tween.tween_property(_strip, "offset_top", _hidden_y(factor), SLIDE_OUT_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_slide_tween.tween_property(_strip, "modulate:a", 0.0, SLIDE_OUT_TIME)
	_slide_tween.chain().tween_callback(_on_left)


func _on_left() -> void:
	_leaving = false
	if _strip != null:
		_strip.visible = false


## The swell on a kill. Scale rather than size, so it does not re-run the layout of everything
## in the strip several times a night.
func _pulse() -> void:
	if _strip == null or not _strip.visible:
		return
	_kill(_pulse_tween)
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_strip, "scale", Vector2.ONE, PULSE_TIME) \
		.from(Vector2.ONE * (1.0 + PULSE_SCALE)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


## Whether the strip is on screen. For tests and for the devtools bridge — `visible` on this
## node is always true, because the root is a full-rect Control that only hosts the strip.
func is_showing() -> bool:
	return _strip != null and _strip.visible
