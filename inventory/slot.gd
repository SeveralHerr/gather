extends PanelContainer
class_name NewSlot

## One inventory cell: an item icon with its stack count in the corner.
##
## The same scene backs three owners — the bag grid, a chest's grid and the hotbar —
## so nothing in here may assume which one built it.
##
## Size is pushed in by the owner through apply_metrics() rather than fixed at the
## 64x64 inventory_slot.tscn declares. The project runs with window/stretch/mode
## "disabled" (see `[display]` in project.godot), so a phone's viewport is its real
## pixel size and a 64px cell there is well under a fingertip. The owner derives one
## edge from UiTheme.scaled_touch() and hands the same number to every slot it
## builds, which is what keeps the bag, a chest and the hotbar sized alike instead of
## each one inventing its own number.

signal slot_clicked(index: int, button: int)

## The edge inventory_slot.tscn is authored at, and what owners scale from. A slot
## nobody ever calls apply_metrics() on still comes out at this size.
const BASE_SIZE := 64.0

## Icon padding and count-text size as fractions of the slot edge, both read off the
## scene's own values at that 64px edge (a 4px margin, ~14px text). Fractions rather
## than constants so a slot scaled up for a large window does not end up with a
## hairline margin and a tiny label floating in it.
const PAD_RATIO := 0.0625
const LABEL_RATIO := 0.22

@onready var texture_rect: TextureRect = $MarginContainer/TextureRect
@onready var quantity_label: Label = $QuantityLabel
@onready var _margin: MarginContainer = $MarginContainer

## Last edge handed to apply_metrics(). Remembered because owners size a slot in the
## same breath as they build it, which can land before the slot is in the tree and
## therefore before @onready has resolved the two nodes _apply_metrics() writes to.
var _side := 0.0


func _ready():
	gui_input.connect(_on_gui_input)
	if _side > 0.0:
		_apply_metrics()


## Draws this slot `side` real pixels square and scales its icon padding and count
## text to match. Idempotent — a viewport resize re-applies it — and safe to call
## before the slot has entered the tree.
func apply_metrics(side: float) -> void:
	if side <= 0.0:
		return
	_side = side
	custom_minimum_size = Vector2(side, side)
	if is_node_ready():
		_apply_metrics()


func _apply_metrics() -> void:
	var pad := maxi(2, int(round(_side * PAD_RATIO)))
	_margin.add_theme_constant_override("margin_left", pad)
	_margin.add_theme_constant_override("margin_top", pad)
	_margin.add_theme_constant_override("margin_right", pad)
	_margin.add_theme_constant_override("margin_bottom", pad)
	quantity_label.add_theme_font_size_override(
		"font_size", maxi(UiTheme.FONT_MIN, int(round(_side * LABEL_RATIO))))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and (event.button_index == MOUSE_BUTTON_LEFT \
			or event.button_index == MOUSE_BUTTON_RIGHT) \
			and event.is_pressed():
		slot_clicked.emit(get_index(), event.button_index)

func set_text(text):
	quantity_label.text = text

func set_slot_data(slot_data: SlotData) -> void:
	var item = slot_data.item
	if not item:
		return

	texture_rect.texture = item.get_atlas()
	tooltip_text = item.name

	if slot_data.count >= 1:
		quantity_label.text = "x%s" % slot_data.count
		quantity_label.show()
	else:
		quantity_label.hide()
