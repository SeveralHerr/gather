extends Control
class_name CraftingUi

## The crafting panel. Built in code from the recipe registry rather than as a .tscn,
## for the same reason the skill panel is: the layout is one card per recipe, so a
## scene file would only be a second copy of data that has to be edited in lockstep.
##
## Lives in the UI2 CanvasLayer. The panel this replaced sat under Player/Camera2D/UI,
## which is world space at the camera's ~5x zoom - every child carried its own
## compensating scale (0.37, 0.25, 0.385...) and every offset was hand-tuned to a
## window size the project stopped using. Nothing here hardcodes a viewport dimension.
##
## Crafting is station-bound because a station is a machine, not a menu: it pays the
## cost up front and then ticks one item per second onto the ground at its own feet.

const PANEL_MAX := Vector2(1040, 620)
## Below this the detail pane cannot sit beside the grid, so the panel becomes two
## pages instead of trying to reflow into an unreadable column.
const COMPACT_WIDTH := 780.0

const COLOR_BACKDROP := Color(0.02, 0.03, 0.05, 0.78)
const COLOR_FRAME := Color("161a21")
const COLOR_INSET := Color("11141a")
const COLOR_TEXT := Color("f2f4f8")
const COLOR_TEXT_DIM := Color("7d8494")
const COLOR_SHORT := Color("e05a4f")

## Each station is tinted with the skill branch that unlocks most of its recipes, so
## the panel is coloured by the progression it belongs to.
const STATION_ACCENTS := {
	Types.Item.Sawmill: Color("6fcf6a"),
	Types.Item.Furnace: Color("e0a33c"),
}
const DEFAULT_ACCENT := Color("58a8e0")

## Injectable so the panel can be built headlessly, where no autoload exists.
var recipes
var items_registry
var input_manager: InputManager
var level_up_manager: LevelUpManager

var station: CraftingStation

var _panel_root: Control
var _frame: PanelContainer
var _station_icon: TextureRect
var _title: Label
var _search: LineEdit
var _body: HBoxContainer
var _browser: ScrollContainer
var _grid: GridContainer
var _empty_hint: Label
var _detail: PanelContainer
var _back_button: Button
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_rate: Label
var _cost_rows: VBoxContainer
var _qty_label: Label
var _craft_button: Button
var _status: Label
var _queue_bar: PanelContainer
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
	# while the panel is closed.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if recipes == null:
		recipes = get_node_or_null("/root/Recipes")
	if items_registry == null:
		items_registry = get_node_or_null("/root/GameItems")
	if input_manager == null:
		input_manager = get_node_or_null("../../InputManager") as InputManager
	if level_up_manager == null:
		level_up_manager = LevelUpManager.find(self)

	_build_panel()

	get_viewport().size_changed.connect(_layout)
	_layout()


# --- construction ------------------------------------------------------------

func _build_panel() -> void:
	_panel_root = Control.new()
	# Named rather than left as @Control@31: this is the handle the devtools bridge
	# addresses the panel by, and generated names shift with node count.
	_panel_root.name = "Panel"
	_panel_root.visible = false
	_panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel_root)

	var backdrop := ColorRect.new()
	backdrop.color = COLOR_BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.add_child(backdrop)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.add_child(center)

	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel", _frame_style())
	center.add_child(_frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_frame.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_build_header())

	var rule := HSeparator.new()
	column.add_child(rule)

	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)

	_body.add_child(_build_browser())
	_body.add_child(_build_detail())

	_queue_bar = _build_queue_bar()
	column.add_child(_queue_bar)

	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 11)
	_footer.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_footer)


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_FRAME
	style.border_color = Color(1, 1, 1, 0.08)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


func _inset_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_INSET
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	return style


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	_back_button = Button.new()
	_back_button.text = "<"
	_back_button.visible = false
	_back_button.custom_minimum_size = Vector2(34, 0)
	_back_button.pressed.connect(_show_grid_page)
	header.add_child(_back_button)

	_station_icon = TextureRect.new()
	_station_icon.custom_minimum_size = Vector2(34, 34)
	_station_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_station_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_station_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(_station_icon)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(_title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_search = LineEdit.new()
	_search.placeholder_text = "Search"
	_search.custom_minimum_size = Vector2(220, 0)
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	header.add_child(_search)

	return header


func _build_browser() -> Control:
	_browser = ScrollContainer.new()
	_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_browser.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browser.add_child(stack)

	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	stack.add_child(_grid)

	_empty_hint = Label.new()
	_empty_hint.visible = false
	_empty_hint.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	stack.add_child(_empty_hint)

	return _browser


func _build_detail() -> Control:
	_detail = PanelContainer.new()
	_detail.custom_minimum_size = Vector2(330, 0)
	_detail.add_theme_stylebox_override("panel", _inset_style())

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_detail.add_child(column)

	var product_row := HBoxContainer.new()
	product_row.add_theme_constant_override("separation", 10)
	column.add_child(product_row)

	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(48, 48)
	_detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	product_row.add_child(_detail_icon)

	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	product_row.add_child(names)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 17)
	_detail_name.add_theme_color_override("font_color", COLOR_TEXT)
	names.add_child(_detail_name)

	_detail_rate = Label.new()
	_detail_rate.add_theme_font_size_override("font_size", 11)
	_detail_rate.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	names.add_child(_detail_rate)

	column.add_child(HSeparator.new())

	var heading := Label.new()
	heading.text = "INGREDIENTS"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	column.add_child(heading)

	_cost_rows = VBoxContainer.new()
	_cost_rows.add_theme_constant_override("separation", 2)
	column.add_child(_cost_rows)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	column.add_child(_build_quantity_row())

	_craft_button = Button.new()
	_craft_button.text = "CRAFT"
	_craft_button.custom_minimum_size = Vector2(0, 38)
	_craft_button.pressed.connect(_on_craft_pressed)
	column.add_child(_craft_button)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 30)
	column.add_child(_status)

	return _detail


func _build_quantity_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(34, 0)
	minus.pressed.connect(func(): _set_amount(_amount - 1))
	row.add_child(minus)

	_qty_label = Label.new()
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_label.custom_minimum_size = Vector2(52, 0)
	_qty_label.add_theme_font_size_override("font_size", 16)
	_qty_label.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(_qty_label)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(34, 0)
	plus.pressed.connect(func(): _set_amount(_amount + 1))
	row.add_child(plus)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var max_button := Button.new()
	max_button.text = "MAX"
	max_button.pressed.connect(_set_amount_to_max)
	row.add_child(max_button)

	return row


func _build_queue_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.visible = false
	bar.add_theme_stylebox_override("panel", _inset_style())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	_queue_icon = TextureRect.new()
	_queue_icon.custom_minimum_size = Vector2(24, 24)
	_queue_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_queue_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_queue_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_queue_icon)

	_queue_label = Label.new()
	_queue_label.add_theme_font_size_override("font_size", 13)
	_queue_label.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(_queue_label)

	_queue_progress = ProgressBar.new()
	_queue_progress.show_percentage = false
	_queue_progress.custom_minimum_size = Vector2(0, 10)
	_queue_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_queue_progress)

	_cancel_button = Button.new()
	_cancel_button.text = "CANCEL"
	_cancel_button.pressed.connect(_on_cancel_pressed)
	row.add_child(_cancel_button)

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

	var margin: float = clampf(minf(viewport_size.x, viewport_size.y) * 0.035, 8.0, 40.0)
	var panel_size := Vector2(
		minf(PANEL_MAX.x, viewport_size.x - margin * 2.0),
		minf(PANEL_MAX.y, viewport_size.y - margin * 2.0))
	_frame.custom_minimum_size = panel_size
	_frame.size = panel_size

	_set_compact(panel_size.x < COMPACT_WIDTH)

	var browser_width: float = panel_size.x - 36.0
	if not _compact:
		browser_width -= _detail.custom_minimum_size.x + 12.0
	_grid.columns = clampi(int(browser_width / (RecipeCard.CARD_SIZE.x + 8.0)), 2, 6)


func _set_compact(value: bool) -> void:
	if _compact == value:
		return
	_compact = value

	# Two pages rather than a reflow: swapping the body between an HBox and a VBox at
	# runtime means reparenting live children, and a detail pane stacked under a grid
	# is unreadable at the width that triggers this anyway.
	_detail.custom_minimum_size.x = 0 if _compact else 330
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
	return _panel_root != null and _panel_root.visible


func open_station(new_station: CraftingStation) -> void:
	_bind_station(new_station)
	set_open(true)


func set_open(open: bool) -> void:
	if _panel_root == null or _panel_root.visible == open:
		return

	_panel_root.visible = open

	# Set, never toggled. The handler this replaced flipped disable_input, so opening
	# the crafting panel on top of the inventory handed control back to the player and
	# closing it disabled input for good.
	if input_manager:
		input_manager.disable_input = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED

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


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


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

	for recipe in ready_now + blocked + locked:
		var card := RecipeCard.new(
			recipe.product, _item_name(recipe.product), _icon_for(recipe.product), _accent())
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
	_title.text = (item.name if item else "Crafting").to_upper()
	_footer.text = "[ESC] close     Shift+click a recipe to fill the quantity"

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
		_status.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	elif not affordable:
		_status.text = "Not enough %s" % _shortfall_text(_selected).split(" ")[-1]
		_status.add_theme_color_override("font_color", COLOR_SHORT)
	else:
		_status.text = ""
		_status.add_theme_color_override("font_color", COLOR_TEXT_DIM)


func _build_cost_row(type: Types.Item, have: int, need: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := TextureRect.new()
	icon.texture = _icon_for(type)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = _item_name(type)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(name_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var value := Label.new()
	value.text = "%d/%d" % [have, need]
	value.add_theme_font_size_override("font_size", 13)
	value.add_theme_color_override("font_color", COLOR_SHORT if have < need else COLOR_TEXT)
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
