extends Control
class_name LandPurchaseUi

## The "buy the next parcel" panel. Built in code rather than as a .tscn because
## main.tscn is shared and the layout here is four labels and a button — a scene
## file would only be a second copy of it to keep in sync.
##
## The chrome is not built here any more: PanelFrame supplies the backdrop, the
## centred frame, the title bar and — the part this panel never had — a close
## button, so a player on a phone is no longer required to find the toolbar button
## that opened it and press it a second time. The palette and every size come from
## UiTheme rather than from a private copy of the constants, which is what let the
## three panels drift apart in the first place.
##
## Nothing here is a raw pixel count. The project runs with
## `window/stretch/mode = "disabled"`, so a phone reports a genuinely smaller
## viewport and a size typed in as an integer renders that much smaller; every
## font size and pad below goes through `UiTheme.scaled*` and is re-derived in
## `_apply_scale()` whenever the window changes size.
##
## Lives in the UI2 CanvasLayer (screen space). It must never be parented under
## Player/Camera2D/UI: that Control is in world space at 0.23 scale and is sized
## for the diegetic HUD, so a full-screen panel there renders at a fifth size and
## scrolls with the camera.

## The frame's unscaled minimum size. Height is 0 — the content decides it, so the
## panel never opens with a band of dead space under the button.
const PANEL_MIN_SIZE := Vector2(430, 0)

## Unscaled height of the buy button. It goes through `scaled_touch()` rather than
## `scaled()`: it is the one control in this panel a finger has to hit, and 34px on
## a phone is below the accessibility floor.
const BUY_BUTTON_HEIGHT := 34.0

## Unscaled padding inside the recessed numbers block, and the gap between its rows.
const INSET_PAD := 10.0
const ROW_GAP := 4.0

## All three are injected by TileMapHandler._setup_land_purchase() before this
## node enters the tree, so _ready() never has to go hunting through groups.
var land_manager: LandManager
var tile_map_handler: TileMapHandler
var input_manager: InputManager

## The shared chrome. Replaces the hand-built _panel_root / backdrop / centre /
## frame / margin stack this file used to carry, and owns the panel's visibility —
## `is_open()` reads it rather than a private flag.
var _frame: PanelFrame

var _column: VBoxContainer
var _blurb: Label
var _rows: VBoxContainer
var _inset_style: StyleBoxFlat
var _gold_label: Label
var _cost_label: Label
var _size_label: Label
var _status_label: Label
var _buy_button: Button

## Every text control paired with the unscaled font size it was authored at, as
## `[control, base_size]`. `_apply_scale()` walks this instead of the file growing
## a field per label — and, more usefully, a label added later cannot be forgotten
## by the resize handler as long as it is built through `_typed()`.
var _typography: Array[Array] = []

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

	# Nothing here scales on its own — see the stretch-mode note at the top — so a
	# resize has to re-run the whole derivation.
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_scale):
		viewport.size_changed.connect(_apply_scale)

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
	_frame = PanelFrame.new()
	_frame.setup("EXPAND THE ISLAND", PANEL_MIN_SIZE)
	# The X, the backdrop and Escape all arrive here as one signal. Routing it
	# through set_open() rather than straight to _frame.close() is what keeps the
	# cursor / disable_input handshake below running on every way out, including
	# the two that did not exist before.
	_frame.close_requested.connect(_on_close_requested)
	add_child(_frame)

	# PanelFrame.content is a plain VBoxContainer that is valid the moment setup()
	# returns, so the rest of this reads exactly as it did against the old column.
	_column = _frame.content

	_blurb = _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	_blurb.name = "Blurb"
	_blurb.text = "Buy the next parcel with gold. New coastline appears; everything you have already built stays put."
	_blurb.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_blurb)

	_column.add_child(HSeparator.new())

	var inset := PanelContainer.new()
	inset.name = "Numbers"
	# Held as a field because the content margin is a size like any other and has
	# to be re-derived on a resize; a StyleBox edited in place re-lays-out its owner.
	_inset_style = UiTheme.inset_style()
	inset.add_theme_stylebox_override("panel", _inset_style)
	_column.add_child(inset)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	inset.add_child(_rows)

	_gold_label = _add_row(_rows, "Gold", UiTheme.COLOR_GOLD)
	_cost_label = _add_row(_rows, "Next parcel", UiTheme.COLOR_TEXT)
	_size_label = _add_row(_rows, "Island", UiTheme.COLOR_TEXT)

	_status_label = _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	_status_label.name = "Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_status_label)

	_buy_button = _typed(Button.new(), UiTheme.FONT_BODY) as Button
	_buy_button.name = "BuyButton"
	_buy_button.text = "BUY LAND"
	UiTheme.style_button(_buy_button)
	_buy_button.pressed.connect(_on_buy_pressed)
	_column.add_child(_buy_button)

	# The frame now carries an X, the backdrop closes on a tap and Escape works, so
	# the footer names all three rather than only the key a phone does not have.
	var footer := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	footer.name = "Footer"
	footer.text = "[B] · [Esc] · tap outside to close"
	footer.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(footer)

	_apply_scale()


## One "label ....... value" line. Returns the value Label so the caller keeps a
## handle on the half that changes.
func _add_row(parent: VBoxContainer, caption: String, value_color: Color) -> Label:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % caption

	var name_label := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	name_label.text = caption
	name_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	row.add_child(name_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var value := _typed(Label.new(), UiTheme.FONT_BODY) as Label
	value.name = "Value"
	value.add_theme_color_override("font_color", value_color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	parent.add_child(row)
	return value


## Registers a text control's unscaled font size and hands it straight back, so a
## build line stays a single statement.
func _typed(control: Control, base_size: int) -> Control:
	_typography.append([control, base_size])
	return control


# --- sizing ------------------------------------------------------------------

## Re-derives every font size and pad from the current viewport. Runs once at
## build time and again on every window resize.
func _apply_scale() -> void:
	if _frame == null:
		return

	var factor := UiTheme.scale_for_node(self)
	# UiTheme's helpers take a viewport size rather than a factor, so reconstruct
	# the size that yields exactly this factor. Same round trip panel_frame.gd
	# makes, which is why the frame's chrome and this content grow in step.
	var vp := Vector2.ONE * UiTheme.REFERENCE_EDGE * factor

	for entry in _typography:
		var control: Control = entry[0]
		control.add_theme_font_size_override("font_size", UiTheme.scaled_font(entry[1], vp))

	_column.add_theme_constant_override("separation", int(round(UiTheme.scaled(UiTheme.GAP, vp))))
	_rows.add_theme_constant_override("separation", int(round(UiTheme.scaled(ROW_GAP, vp))))
	_inset_style.set_content_margin_all(UiTheme.scaled(INSET_PAD, vp))

	# The blurb is the only thing in here wide enough to decide the panel's width,
	# so it is pinned to the frame's own width minus its padding. Without this it
	# would size itself to one very long line and drag the frame out with it.
	_blurb.custom_minimum_size = Vector2(
		UiTheme.scaled(PANEL_MIN_SIZE.x - UiTheme.PAD_PANEL * 2.0, vp), 0
	)

	_buy_button.custom_minimum_size = Vector2(0, UiTheme.scaled_touch(BUY_BUTTON_HEIGHT, vp))


# --- open / close ------------------------------------------------------------

func is_open() -> bool:
	return _frame != null and _frame.is_open()


func toggle() -> void:
	set_open(not is_open())


## The one place visibility changes. Kept as the public entry point because the
## InputManager signal, the devtools `land_panel` verb and the tests all drive the
## panel through it; the frame only owns *how* it is drawn.
func set_open(open: bool) -> void:
	if _frame == null or _frame.is_open() == open:
		return

	if open:
		_frame.open()
	else:
		_frame.close()

	# Same handshake the inventory, crafting and skill panels use: free the cursor
	# and stop the player walking around behind the menu. Assigned rather than
	# toggled, so a panel opened twice cannot leave input disabled forever.
	if input_manager:
		input_manager.disable_input = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED

	if open:
		_bind_inventory()
		_refresh()


## Escape, the X and a tap on the backdrop all land here. The panel no longer
## handles ui_cancel itself — PanelFrame does, and only while it is on screen, so
## two open panels cannot both answer one press.
func _on_close_requested() -> void:
	set_open(false)


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
		_cost_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
		_status_label.text = "The island is as big as it gets."
		_status_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
		_buy_button.disabled = true
		_buy_button.text = "NO LAND LEFT"
		return

	var cost := land_manager.current_cost()
	var affordable := land_manager.can_afford()

	_cost_label.text = "%d gold" % cost
	_cost_label.add_theme_color_override("font_color", UiTheme.COLOR_GOLD if affordable else UiTheme.COLOR_BAD)

	_buy_button.disabled = not affordable
	_buy_button.text = "BUY LAND — %d GOLD" % cost

	if affordable:
		_status_label.text = "Parcel %d of %d" % [land_manager.parcels_bought + 1, LandManager.MAX_PARCELS]
		_status_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	else:
		_status_label.text = "%d more gold needed" % (cost - gold)
		_status_label.add_theme_color_override("font_color", UiTheme.COLOR_BAD)


func _on_buy_pressed() -> void:
	if land_manager == null:
		return
	land_manager.purchase()
	_refresh()
