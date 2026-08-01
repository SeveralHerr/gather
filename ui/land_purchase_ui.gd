extends Control
class_name LandPurchaseUi

## The "buy the next parcel" panel. Built in code rather than as a .tscn because
## main.tscn is shared and the layout here is four labels and a button — a scene
## file would only be a second copy of it to keep in sync.
##
## Lives in the UI2 CanvasLayer (screen space). It must never be parented under
## Player/Camera2D/UI: that Control is in world space at 0.23 scale and is sized
## for the diegetic HUD, so a full-screen panel there renders at a fifth size and
## scrolls with the camera.

const PANEL_MIN_SIZE := Vector2(430, 0)

const COLOR_BACKDROP := Color(0.02, 0.03, 0.05, 0.78)
const COLOR_FRAME := Color("161a21")
const COLOR_INSET := Color("11141a")
const COLOR_TEXT := Color("f2f4f8")
const COLOR_TEXT_DIM := Color("7d8494")
const COLOR_GOLD := Color("ffd166")
const COLOR_BAD := Color("e2725b")

## All three are injected by TileMapHandler._setup_land_purchase() before this
## node enters the tree, so _ready() never has to go hunting through groups.
var land_manager: LandManager
var tile_map_handler: TileMapHandler
var input_manager: InputManager

var _panel_root: Control
var _gold_label: Label
var _cost_label: Label
var _size_label: Label
var _status_label: Label
var _buy_button: Button

var _inventory: InventoryData


func _ready():
	add_to_group("UI")

	# The root only hosts the panel; while closed it must not swallow clicks
	# aimed at the world underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if land_manager == null:
		for node in get_tree().get_nodes_in_group("LandManager"):
			# The scene root belongs to a great many groups, so a type check
			# rather than get_first_node_in_group is the only reliable lookup.
			if node is LandManager:
				land_manager = node
				break

	if land_manager == null:
		push_error("LandPurchaseUi: no LandManager in the scene; the panel will be inert")
		return

	_build_panel()

	land_manager.state_changed.connect(_refresh)
	land_manager.land_purchased.connect(_on_land_purchased)

	if input_manager:
		input_manager.toggle_land.connect(toggle)

	_bind_inventory()
	_refresh()


## The gold readout has to follow the wallet, not just the panel. The purse comes
## from the LandManager rather than from PlayerManager directly: the manager
## already owns "what land is paid out of", and routing through it is what lets a
## test drive this panel without a Player in the scene.
func _bind_inventory() -> void:
	if land_manager == null:
		return

	_inventory = land_manager.inventory_data()
	if _inventory and not _inventory.inventory_updated.is_connected(_on_inventory_updated):
		_inventory.inventory_updated.connect(_on_inventory_updated)


# --- construction ------------------------------------------------------------

func _build_panel() -> void:
	_panel_root = Control.new()
	# Named rather than left as @Control@31: these are the handles the devtools
	# bridge addresses the panel by, and generated names shift with node count.
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

	var frame := PanelContainer.new()
	frame.custom_minimum_size = PANEL_MIN_SIZE

	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = COLOR_FRAME
	frame_style.border_color = Color("2c3340")
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", frame_style)
	center.add_child(frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = "EXPAND THE ISLAND"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(title)

	var blurb := Label.new()
	blurb.text = "Buy the next parcel with gold. New coastline appears; everything you have already built stays put."
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(PANEL_MIN_SIZE.x - 36, 0)
	column.add_child(blurb)

	column.add_child(HSeparator.new())

	var inset := PanelContainer.new()
	var inset_style := StyleBoxFlat.new()
	inset_style.bg_color = COLOR_INSET
	inset_style.set_corner_radius_all(4)
	inset_style.set_content_margin_all(10)
	inset.add_theme_stylebox_override("panel", inset_style)
	column.add_child(inset)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	inset.add_child(rows)

	_gold_label = _add_row(rows, "Gold", COLOR_GOLD)
	_cost_label = _add_row(rows, "Next parcel", COLOR_TEXT)
	_size_label = _add_row(rows, "Island", COLOR_TEXT)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status_label)

	_buy_button = Button.new()
	_buy_button.name = "BuyButton"
	_buy_button.text = "BUY LAND"
	_buy_button.custom_minimum_size = Vector2(0, 34)
	_buy_button.pressed.connect(_on_buy_pressed)
	column.add_child(_buy_button)

	var footer := Label.new()
	footer.text = "[B] close"
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)


## One "label ....... value" line. Returns the value Label so the caller keeps a
## handle on the half that changes.
func _add_row(parent: VBoxContainer, caption: String, value_color: Color) -> Label:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % caption

	var name_label := Label.new()
	name_label.text = caption
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	row.add_child(name_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var value := Label.new()
	value.name = "Value"
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", value_color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	parent.add_child(row)
	return value


# --- open / close ------------------------------------------------------------

func is_open() -> bool:
	return _panel_root != null and _panel_root.visible


func toggle() -> void:
	set_open(not is_open())


func set_open(open: bool) -> void:
	if _panel_root == null or _panel_root.visible == open:
		return

	_panel_root.visible = open

	# Same handshake the inventory, crafting and skill panels use: free the cursor
	# and stop the player walking around behind the menu. Assigned rather than
	# toggled, so a panel opened twice cannot leave input disabled forever.
	if input_manager:
		input_manager.disable_input = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED

	if open:
		_bind_inventory()
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


# --- state -------------------------------------------------------------------

func _on_inventory_updated(_inventory_data: InventoryData) -> void:
	# Only the panel's own numbers move, and only while it is on screen.
	if is_open():
		_refresh()


func _on_land_purchased(_new_radius: int, _tiles_added: int) -> void:
	GameSoundManager.play_sound(GameSoundManager.SoundType.POP)
	_refresh()


func _refresh() -> void:
	if land_manager == null or _gold_label == null:
		return

	var gold := land_manager.gold()
	_gold_label.text = "%d" % gold

	var tiles := "?"
	if tile_map_handler:
		tiles = str(tile_map_handler.count_land_tiles())
	_size_label.text = "radius %d  ·  %s tiles" % [land_manager.radius, tiles]

	if land_manager.is_maxed():
		_cost_label.text = "—"
		_cost_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		_status_label.text = "The island is as big as it gets."
		_status_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		_buy_button.disabled = true
		_buy_button.text = "NO LAND LEFT"
		return

	var cost := land_manager.current_cost()
	var affordable := land_manager.can_afford()

	_cost_label.text = "%d gold" % cost
	_cost_label.add_theme_color_override("font_color", COLOR_GOLD if affordable else COLOR_BAD)

	_buy_button.disabled = not affordable
	_buy_button.text = "BUY LAND — %d GOLD" % cost

	if affordable:
		_status_label.text = "Parcel %d of %d" % [land_manager.parcels_bought + 1, LandManager.MAX_PARCELS]
		_status_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	else:
		_status_label.text = "%d more gold needed" % (cost - gold)
		_status_label.add_theme_color_override("font_color", COLOR_BAD)


func _on_buy_pressed() -> void:
	if land_manager == null:
		return
	land_manager.purchase()
	_refresh()
