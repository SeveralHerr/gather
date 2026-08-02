extends Control
class_name CraftingUi

## The crafting panel. Built in code from the recipe registry rather than as a .tscn,
## for the same reason the skill panel is: the layout is one card per recipe, so a
## scene file would only be a second copy of data that has to be edited in lockstep.
##
## Lives in the UI CanvasLayer. The panel this replaced sat under Player/Camera2D/HUD,
## which is world space at the camera's ~5x zoom - every child carried its own
## compensating scale (0.37, 0.25, 0.385...) and every offset was hand-tuned to a
## window size the project stopped using. Nothing here hardcodes a viewport dimension.
##
## The chrome - dim backdrop, centring, frame, title bar, close button, and the three
## ways back out - is PanelFrame's now. This file used to hand-roll the first three,
## carried its own byte-identical copy of the COLOR_* palette, and had no close button
## at all: on a phone, where there is no Escape key, the only way out of the crafting
## panel was to walk back into the station's radius and press interact a second time.
## The station's name goes in the title bar, which is the reason `set_title()` exists -
## the panel is always opened against one specific machine.
##
## Every size on screen is derived from the live viewport through UiTheme.scaled*() in
## `_apply_scale()`, re-run on `size_changed`. The raw integers this file used to carry
## were chosen against one desktop window, and the recipe cards and their ingredient
## rows - the densest text in the game - were the first thing to stop being readable on
## a small one. Sizes only: positions still come from anchors and from PanelFrame's
## CenterContainer (gather-6fx).
##
## Crafting is station-bound because a station is a machine, not a menu: it pays the
## cost up front and then ticks one item per second onto the ground at its own feet.

## The panel's size at the reference scale, capped again by the viewport in `_layout`.
## Both are multiplied by UiTheme.scale_for(): the text inside grows with the window,
## so a frame that did not would overflow rather than stay tidy.
const PANEL_MAX := Vector2(1040, 620)
## Below this the detail pane cannot sit beside the grid, so the panel becomes two
## pages instead of trying to reflow into an unreadable column. Scaled like PANEL_MAX,
## so the threshold and the thing it measures move together.
const COMPACT_WIDTH := 780.0

## Panel-specific base metrics, pre-scale. Every one of these is fed through
## UiTheme.scaled() or scaled_touch() before it reaches a control; none is used raw.
const DETAIL_WIDTH := 330.0
const STATION_ICON := 34.0
const DETAIL_ICON := 48.0
const ROW_ICON := 24.0
const SEARCH_WIDTH := 220.0
const QTY_WIDTH := 52.0
## The steppers, the back button and the cancel button: small controls a finger still
## has to hit, so they go through scaled_touch() rather than scaled().
const BUTTON_SIDE := 34.0
const CRAFT_HEIGHT := 38.0
const STATUS_HEIGHT := 30.0
const PROGRESS_HEIGHT := 10.0

## Each station is tinted with the skill branch that unlocks most of its recipes, so
## the panel is coloured by the progression it belongs to. Sawmill green and the
## default blue are UiTheme's own; the furnace amber is deliberately darker than
## COLOR_GOLD, which is the currency colour and would read as "this is money".
const STATION_ACCENTS := {
	Types.Item.Sawmill: UiTheme.COLOR_GOOD,
	Types.Item.Furnace: Color("e0a33c"),
}
const DEFAULT_ACCENT := UiTheme.COLOR_ACCENT

## Injectable so the panel can be built headlessly, where no autoload exists.
var recipes
var items_registry
var input_manager: InputManager
var level_up_manager: LevelUpManager

var station: CraftingStation

## The shared chrome, and its inner body. `_frame` is the PanelContainer that actually
## carries the panel's size, so it is the node `_layout` writes the computed size onto
## and the one the layout tests measure - the chrome's own root is a full-rect Control
## and would answer every "does it fit" question with the window's own size.
var _chrome: PanelFrame
var _frame: PanelContainer

var _header: HBoxContainer
var _station_icon: TextureRect
var _search: LineEdit
var _body: HBoxContainer
var _browser: ScrollContainer
var _grid: GridContainer
var _empty_hint: Label
var _detail: PanelContainer
var _detail_column: VBoxContainer
var _product_row: HBoxContainer
var _back_button: Button
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_rate: Label
var _ingredients_heading: Label
var _cost_rows: VBoxContainer
var _qty_row: HBoxContainer
var _minus_button: Button
var _plus_button: Button
var _max_button: Button
var _qty_label: Label
var _craft_button: Button
var _status: Label
var _queue_bar: PanelContainer
var _queue_row: HBoxContainer
var _queue_icon: TextureRect
var _queue_label: Label
var _queue_progress: ProgressBar
var _cancel_button: Button
var _footer: Label

var _cards: Array[RecipeCard] = []
var _selected: CraftingRecipe = null
var _amount := 1
var _compact := false

## get_atlas() mints a fresh AtlasTexture and load()s a sheet on every call, and this
## panel asks for a dozen icons every time the inventory changes.
var _icon_cache: Dictionary = {}


func _ready() -> void:
	add_to_group("UI")
	add_to_group("CraftingUi")

	# The root only hosts the panel; it must not swallow clicks aimed at the world
	# while the panel is closed. PanelFrame's backdrop does the swallowing when it is
	# open, and does it deliberately.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if recipes == null:
		recipes = get_node_or_null("/root/Recipes")
	if items_registry == null:
		items_registry = get_node_or_null("/root/GameItems")
	if input_manager == null:
		input_manager = get_node_or_null("../../Systems/InputManager") as InputManager
	if level_up_manager == null:
		level_up_manager = LevelUpManager.find(self)

	_build_panel()

	# Connected *after* _build_panel, and that order matters: PanelFrame connects its
	# own _apply_scale in its _ready (which runs inside the add_child above), so ours
	# lands second and gets the last word on the frame's minimum size.
	get_viewport().size_changed.connect(_layout)
	_layout()


# --- construction ------------------------------------------------------------

func _build_panel() -> void:
	_chrome = PanelFrame.new()
	# No minimum passed: this panel measures itself against the viewport in _layout()
	# rather than growing from a fixed base, because it has to fit a phone as well as
	# a 4K window. The title is replaced with the station's name on open.
	_chrome.setup("CRAFTING")
	# The X, the backdrop and Escape all land here, and all three go through set_open()
	# so the disable_input / mouse-mode / hotbar handshake runs exactly as it does when
	# the player walks away or presses interact again. A close that only hid the frame
	# would leave the player frozen with no menu on screen.
	_chrome.close_requested.connect(close)
	# PanelFrame re-applies its own scaling whenever it opens, which resets the frame
	# minimum size it thinks it owns; re-running our layout on the same signal puts the
	# viewport-derived size back, whoever did the opening.
	_chrome.opened.connect(_layout)
	add_child(_chrome)

	# Reached into on purpose. PanelFrame owns the chrome but not the policy for how big
	# this particular panel should be, and its own minimum-size field is a fixed base
	# multiplied by the scale - which a phone viewport can still overflow. `_layout()`
	# writes the viewport-capped size straight onto the body instead, and gets the last
	# word because our size_changed handler is connected after PanelFrame's.
	_frame = _chrome._frame

	var content := _chrome.content
	content.add_child(_build_header())

	_body = HBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_body)

	_body.add_child(_build_browser())
	_body.add_child(_build_detail())

	_queue_bar = _build_queue_bar()
	content.add_child(_queue_bar)

	_footer = Label.new()
	_footer.name = "Footer"
	_footer.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_footer)


## UiTheme's recessed style plus the content margin a pane needs to keep its own
## children off its edges. The margin is the only part that scales - the colour and
## the corner radius are shared with every other inset in the game.
func _inset_style(viewport_size: Vector2) -> StyleBoxFlat:
	var style := UiTheme.inset_style()
	style.set_content_margin_all(UiTheme.scaled(UiTheme.GAP + 2.0, viewport_size))
	return style


func _build_header() -> Control:
	_header = HBoxContainer.new()
	_header.name = "Header"

	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "<"
	_back_button.visible = false
	_back_button.pressed.connect(_show_grid_page)
	UiTheme.style_button(_back_button)
	_header.add_child(_back_button)

	# The station's name lives in the title bar now, so this is the only identity mark
	# the header still carries - it reads as a chip beside the search box rather than
	# as a second, competing heading.
	_station_icon = TextureRect.new()
	_station_icon.name = "StationIcon"
	_station_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_station_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_station_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_header.add_child(_station_icon)

	var spacer := Control.new()
	spacer.name = "HeaderSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)

	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Search"
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	_header.add_child(_search)

	return _header


func _build_browser() -> Control:
	_browser = ScrollContainer.new()
	_browser.name = "Browser"
	_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Vertical only. The recipe list is always taller than the panel on a phone, and
	# the column count in _layout() is picked so the grid never needs the other axis.
	_browser.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browser.add_child(stack)

	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = 5
	stack.add_child(_grid)

	_empty_hint = Label.new()
	_empty_hint.name = "EmptyHint"
	_empty_hint.visible = false
	_empty_hint.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	stack.add_child(_empty_hint)

	return _browser


func _build_detail() -> Control:
	_detail = PanelContainer.new()
	_detail.name = "Detail"

	_detail_column = VBoxContainer.new()
	_detail_column.name = "DetailColumn"
	_detail.add_child(_detail_column)

	_product_row = HBoxContainer.new()
	_product_row.name = "ProductRow"
	_detail_column.add_child(_product_row)

	_detail_icon = TextureRect.new()
	_detail_icon.name = "DetailIcon"
	_detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_product_row.add_child(_detail_icon)

	var names := VBoxContainer.new()
	names.name = "Names"
	names.add_theme_constant_override("separation", 0)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_product_row.add_child(names)

	_detail_name = Label.new()
	_detail_name.name = "DetailName"
	_detail_name.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	names.add_child(_detail_name)

	_detail_rate = Label.new()
	_detail_rate.name = "DetailRate"
	_detail_rate.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	names.add_child(_detail_rate)

	var rule := HSeparator.new()
	rule.name = "DetailRule"
	_detail_column.add_child(rule)

	_ingredients_heading = Label.new()
	_ingredients_heading.name = "IngredientsHeading"
	_ingredients_heading.text = "INGREDIENTS"
	_ingredients_heading.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	_detail_column.add_child(_ingredients_heading)

	_cost_rows = VBoxContainer.new()
	_cost_rows.name = "CostRows"
	_detail_column.add_child(_cost_rows)

	var spacer := Control.new()
	spacer.name = "DetailSpacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_column.add_child(spacer)

	_detail_column.add_child(_build_quantity_row())

	_craft_button = Button.new()
	_craft_button.name = "CraftButton"
	_craft_button.text = "CRAFT"
	_craft_button.pressed.connect(_on_craft_pressed)
	UiTheme.style_button(_craft_button)
	_detail_column.add_child(_craft_button)

	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_column.add_child(_status)

	return _detail


func _build_quantity_row() -> Control:
	_qty_row = HBoxContainer.new()
	_qty_row.name = "QuantityRow"

	_minus_button = Button.new()
	_minus_button.name = "MinusButton"
	_minus_button.text = "-"
	_minus_button.pressed.connect(func(): _set_amount(_amount - 1))
	UiTheme.style_button(_minus_button)
	_qty_row.add_child(_minus_button)

	_qty_label = Label.new()
	_qty_label.name = "QuantityLabel"
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_qty_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_qty_row.add_child(_qty_label)

	_plus_button = Button.new()
	_plus_button.name = "PlusButton"
	_plus_button.text = "+"
	_plus_button.pressed.connect(func(): _set_amount(_amount + 1))
	UiTheme.style_button(_plus_button)
	_qty_row.add_child(_plus_button)

	var spacer := Control.new()
	spacer.name = "QuantitySpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_qty_row.add_child(spacer)

	_max_button = Button.new()
	_max_button.name = "MaxButton"
	_max_button.text = "MAX"
	_max_button.pressed.connect(_set_amount_to_max)
	UiTheme.style_button(_max_button)
	_qty_row.add_child(_max_button)

	return _qty_row


func _build_queue_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.name = "QueueBar"
	bar.visible = false

	_queue_row = HBoxContainer.new()
	_queue_row.name = "QueueRow"
	bar.add_child(_queue_row)

	_queue_icon = TextureRect.new()
	_queue_icon.name = "QueueIcon"
	_queue_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_queue_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_queue_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_queue_row.add_child(_queue_icon)

	_queue_label = Label.new()
	_queue_label.name = "QueueLabel"
	_queue_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_queue_row.add_child(_queue_label)

	_queue_progress = ProgressBar.new()
	_queue_progress.name = "QueueProgress"
	_queue_progress.show_percentage = false
	_queue_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_queue_row.add_child(_queue_progress)

	_cancel_button = Button.new()
	_cancel_button.name = "CancelButton"
	_cancel_button.text = "CANCEL"
	_cancel_button.pressed.connect(_on_cancel_pressed)
	# The destructive variant: cancelling throws away a work order the player paid for.
	UiTheme.style_button(_cancel_button, true)
	_queue_row.add_child(_cancel_button)

	return bar


# --- layout ------------------------------------------------------------------

## Every dimension is derived from the live viewport, never from a constant tuned to
## one window size. Growing the window shows more world (stretch mode is disabled),
## so a fixed panel size would be a different fraction of the screen at every
## resolution and would overflow a phone viewport outright.
func _layout() -> void:
	if _frame == null or not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	_apply_scale(viewport_size)

	var factor := UiTheme.scale_for(viewport_size)

	# PANEL_MAX is unscaled: PanelFrame multiplies it by the same factor and then
	# clamps the result to the viewport, so it is the single writer of the frame's
	# size. This used to write _frame.custom_minimum_size directly, which left two
	# writers racing on one property and a correctness argument that rested on
	# signal-connection order.
	_chrome.set_panel_size(PANEL_MAX)
	var panel_size := _chrome.panel_size()

	_set_compact(panel_size.x < COMPACT_WIDTH * factor)

	# What is left for the card grid once the frame's own padding, its border and (in
	# the wide layout) the detail pane have taken their share.
	var gap := UiTheme.scaled(UiTheme.GAP, viewport_size)
	var browser_width: float = panel_size.x \
		- UiTheme.scaled(UiTheme.PAD_PANEL, viewport_size) * 2.0 \
		- float(UiTheme.BORDER_WIDTH) * 2.0
	if not _compact:
		browser_width -= _detail.custom_minimum_size.x + gap
	_grid.columns = clampi(
		int(browser_width / (UiTheme.scaled_touch(RecipeCard.CARD_SIZE.x, viewport_size) + gap)),
		2, 6)


## Re-derives every font size, pad and control size in the panel from the viewport.
## Same job as PanelFrame's own `_apply_scale`, for the parts of the panel PanelFrame
## does not own, and driven by the same `size_changed`.
func _apply_scale(viewport_size: Vector2) -> void:
	if _chrome == null:
		return

	var gap := int(round(UiTheme.scaled(UiTheme.GAP, viewport_size)))
	var font_body := UiTheme.scaled_font(UiTheme.FONT_BODY, viewport_size)
	var font_small := UiTheme.scaled_font(UiTheme.FONT_SMALL, viewport_size)
	var button_side := UiTheme.scaled_touch(BUTTON_SIDE, viewport_size)

	# PanelFrame scales its own column but not the container it hands us, so the gaps
	# between our header, body, queue bar and footer are ours to keep in step.
	_chrome.content.add_theme_constant_override("separation", gap)
	_header.add_theme_constant_override("separation", gap)
	_body.add_theme_constant_override("separation", gap)
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	_detail_column.add_theme_constant_override("separation", gap)
	_product_row.add_theme_constant_override("separation", gap)
	_qty_row.add_theme_constant_override("separation", gap)
	_queue_row.add_theme_constant_override("separation", gap)
	_cost_rows.add_theme_constant_override("separation", int(round(UiTheme.scaled(2.0, viewport_size))))

	var station_icon := UiTheme.scaled(STATION_ICON, viewport_size)
	_station_icon.custom_minimum_size = Vector2(station_icon, station_icon)

	_search.custom_minimum_size = Vector2(UiTheme.scaled(SEARCH_WIDTH, viewport_size), button_side)
	_search.add_theme_font_size_override("font_size", font_body)

	_empty_hint.add_theme_font_size_override("font_size", font_body)
	_footer.add_theme_font_size_override("font_size", font_small)

	# The detail pane and the queue bar are the panel's two recessed areas; their
	# content margin is the only scaled part of the shared inset style.
	_detail.add_theme_stylebox_override("panel", _inset_style(viewport_size))
	_queue_bar.add_theme_stylebox_override("panel", _inset_style(viewport_size))
	_detail.custom_minimum_size.x = _detail_width(viewport_size)

	var detail_icon := UiTheme.scaled(DETAIL_ICON, viewport_size)
	_detail_icon.custom_minimum_size = Vector2(detail_icon, detail_icon)
	# The detail pane's own heading, one step up from the body text around it so the
	# selected product reads as the subject of the pane.
	_detail_name.add_theme_font_size_override(
		"font_size", UiTheme.scaled_font(UiTheme.FONT_TITLE, viewport_size))
	_detail_rate.add_theme_font_size_override("font_size", font_small)
	_ingredients_heading.add_theme_font_size_override("font_size", font_small)

	_qty_label.custom_minimum_size = Vector2(UiTheme.scaled(QTY_WIDTH, viewport_size), button_side)
	_qty_label.add_theme_font_size_override("font_size", font_body)

	_status.custom_minimum_size = Vector2(0, UiTheme.scaled(STATUS_HEIGHT, viewport_size))
	_status.add_theme_font_size_override("font_size", font_small)

	var row_icon := UiTheme.scaled(ROW_ICON, viewport_size)
	_queue_icon.custom_minimum_size = Vector2(row_icon, row_icon)
	_queue_label.add_theme_font_size_override("font_size", font_body)
	_queue_progress.custom_minimum_size = Vector2(0, UiTheme.scaled(PROGRESS_HEIGHT, viewport_size))

	# Every button in the panel is a finger target, so each one takes the touch floor
	# on the axis that would otherwise collapse to its label's height.
	_back_button.custom_minimum_size = Vector2(button_side, button_side)
	_minus_button.custom_minimum_size = Vector2(button_side, button_side)
	_plus_button.custom_minimum_size = Vector2(button_side, button_side)
	_max_button.custom_minimum_size = Vector2(button_side, button_side)
	_cancel_button.custom_minimum_size = Vector2(0, button_side)
	_craft_button.custom_minimum_size = Vector2(
		0, UiTheme.scaled_touch(CRAFT_HEIGHT, viewport_size))
	for button in [_back_button, _minus_button, _plus_button,
			_max_button, _craft_button, _cancel_button]:
		button.add_theme_font_size_override("font_size", font_body)

	# The cards are the panel's primary touch target and the reason any of this
	# matters; they carry their own scaling so a card built mid-session gets it too.
	for card in _cards:
		card.apply_scale(viewport_size)

	# Rebuilt rather than restyled: the rows are thrown away on every refresh anyway,
	# and they read the scale from the viewport when they are made.
	_refresh_detail_if_open()


## Zero in compact mode, where the detail pane is a page of its own and must be free to
## use the whole panel width.
func _detail_width(viewport_size: Vector2) -> float:
	return 0.0 if _compact else UiTheme.scaled(DETAIL_WIDTH, viewport_size)


func _refresh_detail_if_open() -> void:
	if station != null and is_open():
		_refresh_detail()


func _set_compact(value: bool) -> void:
	if _compact == value:
		return
	_compact = value

	# Two pages rather than a reflow: swapping the body between an HBox and a VBox at
	# runtime means reparenting live children, and a detail pane stacked under a grid
	# is unreadable at the width that triggers this anyway.
	_detail.custom_minimum_size.x = _detail_width(get_viewport_rect().size)
	_search.visible = not _compact
	_footer.visible = not _compact
	if _compact:
		_show_grid_page()
	else:
		_back_button.visible = false
		_browser.visible = true
		_detail.visible = true


func _show_grid_page() -> void:
	if not _compact:
		return
	_browser.visible = true
	_detail.visible = false
	_back_button.visible = false


func _show_detail_page() -> void:
	if not _compact:
		return
	_browser.visible = false
	_detail.visible = true
	_back_button.visible = true


# --- open / close ------------------------------------------------------------

func is_open() -> bool:
	return _chrome != null and _chrome.is_open()


func open_station(new_station: CraftingStation) -> void:
	_bind_station(new_station)
	set_open(true)


func set_open(open: bool) -> void:
	if _chrome == null or _chrome.is_open() == open:
		return

	if open:
		_chrome.open()
	else:
		_chrome.close()

	# Set, never toggled. The handler this replaced flipped disable_input, so opening
	# the crafting panel on top of the inventory handed control back to the player and
	# closing it disabled input for good. The early return above keeps a second
	# set_open(true) from doing any of this twice.
	if input_manager:
		input_manager.disable_input = open

	var hotbar := get_node_or_null("../HotBarInventory")
	if hotbar:
		hotbar.visible = not open

	if open:
		_amount = 1
		_search.text = ""
		_rebuild_grid()
		_refresh()
	else:
		_unbind_station()


func close() -> void:
	set_open(false)


func _process(_delta: float) -> void:
	if not is_open() or station == null:
		return
	# Walking away closes the panel, the way the chest inventory already does. A
	# station's work order keeps running either way.
	if station.global_position.distance_to(PlayerManager.get_global_position()) > 24.0:
		set_open(false)


# --- station binding ---------------------------------------------------------

func _bind_station(new_station: CraftingStation) -> void:
	if station == new_station:
		return
	_unbind_station()
	station = new_station
	if station == null:
		return
	if not station.produced.is_connected(_on_station_produced):
		station.produced.connect(_on_station_produced)
	if not station.order_changed.is_connected(_on_order_changed):
		station.order_changed.connect(_on_order_changed)
	_selected = station.selected_recipe


func _unbind_station() -> void:
	if station == null:
		return
	if station.produced.is_connected(_on_station_produced):
		station.produced.disconnect(_on_station_produced)
	if station.order_changed.is_connected(_on_order_changed):
		station.order_changed.disconnect(_on_order_changed)
	station = null


func _on_station_produced(_product: Types.Item, _remaining: int) -> void:
	# Driven by the station's own tick rather than polled every frame from _process,
	# which is what the old panel did whether or not it was even visible.
	_refresh_queue()


func _on_order_changed() -> void:
	_refresh()


# --- grid --------------------------------------------------------------------

func _accent() -> Color:
	if station == null:
		return DEFAULT_ACCENT
	return STATION_ACCENTS.get(station.type, DEFAULT_ACCENT)


func _icon_for(type: Types.Item) -> Texture2D:
	if _icon_cache.has(type):
		return _icon_cache[type]
	var item = _item(type)
	var texture: Texture2D = item.get_atlas() if item else null
	_icon_cache[type] = texture
	return texture


func _item(type: Types.Item):
	if items_registry == null:
		return null
	return items_registry.get_item(type)


func _item_name(type: Types.Item) -> String:
	var item = _item(type)
	return item.name if item else "?"


## Recipes are ordered craftable-now, then unaffordable, then locked, so the top-left
## of the grid is always what the player can actually do. Sorted once per open rather
## than on every refresh - cards that reshuffle under the cursor as an ore drops into
## the bag are worse than a slightly stale order.
func _rebuild_grid() -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()

	# The search box is cleared on open, but setting `text` does not emit text_changed,
	# so the "no recipe matches" line would otherwise still be up from the last session
	# with a full grid of cards behind it.
	_empty_hint.visible = false

	if station == null or recipes == null:
		return

	var all = recipes.all_recipes(station.type)
	var ready_now := []
	var blocked := []
	var locked := []

	for recipe in all:
		if recipe == null:
			continue
		if not recipes.is_unlocked(recipe.product, station.type):
			locked.append(recipe)
		elif _inventory() and _inventory().can_afford(recipe.cost_list, 1):
			ready_now.append(recipe)
		else:
			blocked.append(recipe)

	var viewport_size := get_viewport_rect().size if is_inside_tree() else Vector2.ZERO
	for recipe in ready_now + blocked + locked:
		var card := RecipeCard.new(
			recipe.product, _item_name(recipe.product), _icon_for(recipe.product), _accent())
		# Sized for this viewport before it is ever drawn; _apply_scale() re-runs this
		# for every live card when the window changes.
		card.apply_scale(viewport_size)
		card.chosen.connect(_on_card_chosen)
		_grid.add_child(card)
		_cards.append(card)

	if _selected == null or not _has_recipe(_selected):
		_selected = ready_now[0] if not ready_now.is_empty() else (all[0] if not all.is_empty() else null)


func _has_recipe(recipe: CraftingRecipe) -> bool:
	if station == null or recipes == null:
		return false
	for candidate in recipes.all_recipes(station.type):
		if candidate == recipe:
			return true
	return false


func _find_recipe(product: Types.Item) -> CraftingRecipe:
	if station == null or recipes == null:
		return null
	for recipe in recipes.all_recipes(station.type):
		if recipe and recipe.product == product:
			return recipe
	return null


func _on_card_chosen(product: Types.Item, want_max: bool) -> void:
	_selected = _find_recipe(product)
	_amount = 1
	if want_max:
		_set_amount_to_max()
	_show_detail_page()
	_refresh()


func _on_search_changed(text: String) -> void:
	var needle := text.strip_edges().to_lower()
	var shown := 0
	for card in _cards:
		var match_found := needle == "" or _item_name(card.product).to_lower().contains(needle)
		card.visible = match_found
		if match_found:
			shown += 1
	_empty_hint.visible = shown == 0
	_empty_hint.text = "No recipe matches \"%s\"" % text


# --- refresh -----------------------------------------------------------------

func _inventory() -> InventoryData:
	if PlayerManager.player == null:
		return null
	return PlayerManager.player.inventory_data


func _refresh() -> void:
	if station == null:
		return

	var item = _item(station.type)
	_station_icon.texture = _icon_for(station.type)
	# The station's name is the panel's heading now. It answers "which machine am I
	# standing at" from the title bar, where a player already looks for it.
	_chrome.set_title((item.name if item else "Crafting").to_upper())
	_footer.text = "[ESC] or the X closes     Shift+click a recipe to fill the quantity"

	_refresh_cards()
	_refresh_detail()
	_refresh_queue()


func _refresh_cards() -> void:
	var inventory := _inventory()
	for card in _cards:
		var recipe := _find_recipe(card.product)
		if recipe == null:
			continue

		if not recipes.is_unlocked(recipe.product, station.type):
			card.set_state(RecipeCard.State.LOCKED, _unlock_hint(recipe.product))
		elif inventory and inventory.can_afford(recipe.cost_list, 1):
			# How many you could make right now answers "is it worth walking here"
			# as well as "can I", which a tick or a colour alone does not.
			card.set_state(RecipeCard.State.READY, "x%d" % inventory.affordable_count(recipe.cost_list))
		else:
			card.set_state(RecipeCard.State.BLOCKED, _shortfall_text(recipe))

		card.set_selected(_selected != null and card.product == _selected.product)


## Names the skill that would unlock a recipe, read back out of the skill tree's own
## unlock lists so nothing has to be authored twice.
func _unlock_hint(product: Types.Item) -> String:
	if level_up_manager == null or station == null:
		return "Locked"
	for id in level_up_manager.tree.order:
		var skill = level_up_manager.tree.get_skill(id)
		for unlock in skill.recipes:
			if unlock["product"] == product and unlock["station"] == station.type:
				return skill.display_name
	return "Locked"


func _shortfall_text(recipe: CraftingRecipe) -> String:
	var inventory := _inventory()
	if inventory == null:
		return "?"
	for type in recipe.cost_list:
		var need := int(recipe.cost_list[type])
		var have := inventory.count_of_type(type)
		if have < need:
			return "%d/%d %s" % [have, need, _item_name(type)]
	return ""


func _refresh_detail() -> void:
	for child in _cost_rows.get_children():
		child.queue_free()

	if _selected == null:
		_detail_name.text = "-"
		_detail_rate.text = ""
		_detail_icon.texture = null
		_qty_label.text = "0"
		_craft_button.disabled = true
		_status.text = "Nothing unlocked at this station yet."
		return

	_detail_icon.texture = _icon_for(_selected.product)
	_detail_name.text = _item_name(_selected.product)
	var per_item: float = station.timer.wait_time if station.timer else 1.0
	_detail_rate.text = "1 every %s second%s" % [
		("%.1f" % per_item).trim_suffix(".0"), "" if is_equal_approx(per_item, 1.0) else "s"]

	var inventory := _inventory()
	for type in _selected.cost_list:
		var need := int(_selected.cost_list[type]) * _amount
		var have := inventory.count_of_type(type) if inventory else 0
		_cost_rows.add_child(_build_cost_row(type, have, need))

	_qty_label.text = str(_amount)

	var unlocked: bool = recipes.is_unlocked(_selected.product, station.type)
	var affordable: bool = inventory != null and inventory.can_afford(_selected.cost_list, _amount)
	_craft_button.disabled = not (unlocked and affordable)
	_craft_button.text = "CRAFT x%d" % _amount

	if not unlocked:
		_status.text = "Locked - learn %s" % _unlock_hint(_selected.product)
		_status.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	elif not affordable:
		_status.text = "Not enough %s" % _shortfall_text(_selected).split(" ")[-1]
		_status.add_theme_color_override("font_color", UiTheme.COLOR_BAD)
	else:
		_status.text = ""
		_status.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)


## Built fresh on every refresh, so it reads its own sizes from the viewport rather
## than waiting for _apply_scale() to come round and restyle it.
func _build_cost_row(type: Types.Item, have: int, need: int) -> Control:
	var viewport_size := get_viewport_rect().size if is_inside_tree() else Vector2.ZERO
	var font_body := UiTheme.scaled_font(UiTheme.FONT_BODY, viewport_size)
	var icon_side := UiTheme.scaled(ROW_ICON, viewport_size)

	var row := HBoxContainer.new()
	row.name = "CostRow"
	row.add_theme_constant_override("separation", int(round(UiTheme.scaled(UiTheme.GAP, viewport_size))))

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = _icon_for(type)
	icon.custom_minimum_size = Vector2(icon_side, icon_side)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = _item_name(type)
	name_label.add_theme_font_size_override("font_size", font_body)
	name_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	row.add_child(name_label)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var value := Label.new()
	value.name = "Value"
	value.text = "%d/%d" % [have, need]
	value.add_theme_font_size_override("font_size", font_body)
	value.add_theme_color_override("font_color", UiTheme.COLOR_BAD if have < need else UiTheme.COLOR_TEXT)
	row.add_child(value)

	return row


func _refresh_queue() -> void:
	if station == null:
		return
	var running := station.count > 0
	_queue_bar.visible = running
	if not running:
		return

	var product: Types.Item = station.selected_recipe.product if station.selected_recipe else Types.Item.X
	var done: int = maxi(station.starting_count - station.count, 0)
	_queue_icon.texture = _icon_for(product)
	_queue_label.text = "%s  %d / %d" % [_item_name(product), done, station.starting_count]
	_queue_progress.max_value = maxf(station.starting_count, 1)
	_queue_progress.value = done


# --- actions -----------------------------------------------------------------

func _set_amount(value: int) -> void:
	_amount = maxi(value, 1)
	_refresh_detail()
	_refresh_cards()


func _set_amount_to_max() -> void:
	var inventory := _inventory()
	if _selected == null or inventory == null:
		return
	_set_amount(maxi(inventory.affordable_count(_selected.cost_list), 1))


func _on_craft_pressed() -> void:
	if station == null or _selected == null:
		return
	if not recipes.is_unlocked(_selected.product, station.type):
		return

	if station.enqueue(_selected, _amount, _inventory()):
		GameSoundManager.play_sound(GameSoundManager.SoundType.POP)
		_amount = 1
		_refresh()
	else:
		# No sound on a refusal. In a resource game you hit this constantly, and a
		# failure buzz gets old in about ninety seconds.
		_shake(_craft_button)


func _on_cancel_pressed() -> void:
	if station == null:
		return
	station.cancel()
	_refresh()


func _shake(control: Control) -> void:
	var origin := control.position.x
	var tween := create_tween()
	for offset in [6.0, -5.0, 3.0, 0.0]:
		tween.tween_property(control, "position:x", origin + offset, 0.045)
	tween.tween_callback(func(): control.position.x = origin)
