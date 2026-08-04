extends RefCounted

## Guards the tool sprite the player is drawn holding against the tool they are
## actually holding.
##
## Two separate things decide that sprite and only one of them is code. `Gather` and
## `Attack/Sprite` are authored into main.tscn with a texture, and
## `PlayerManager.show_slot_data()` overwrites it from the equipped item — but only
## when something drives `HotBarInventory.hot_bar_selected`, which for a long time was
## real player input and nothing else. So the authored texture was what the player saw
## for the whole of their first session up to the first hotbar keypress, and it was the
## *iron* pickaxe while slot 1 held the wooden one (gather-g92).
##
## The runtime half of that fix is `_refresh_equipped()` and needs a running game to
## assert. This is the half a diff can check: the authored fallback has to name the same
## tool the player starts with, so that even with no push at all the two agree.

const MAIN_SCENE := "res://main.tscn"
const ITEMS_SCRIPT := "res://items/items.gd"

## The tools player.gd puts in slots 1 and 2 at `_ready()`. Named here rather than read
## off a Player instance because standing one up headless needs the whole of main.tscn.
const STARTING_PICKAXE := Types.Item.WoodPickaxe
const STARTING_SWORD := Types.Item.Sword

var _T

## The item registry, built from items.gd's own `_ready()` rather than read off the
## `GameItems` autoload. The autoload is not stood up under the headless runner — its
## `item_list` is empty there and `get_item()` answers null for everything, which would
## make every comparison below pass against Rect2() and prove nothing. Same reasoning as
## test_land_manager.gd:22, but taking the real registry instead of a stand-in, because
## the whole point here is to compare against the coordinates items.gd actually ships.
var _items: Node


func setup() -> void:
	_items = load(ITEMS_SCRIPT).new()
	_items._ready()


func teardown() -> void:
	if _items:
		_items.free()
		_items = null


## The `texture` property authored onto the node named `node_name` in main.tscn, read
## off the PackedScene rather than an instance — instancing main.tscn headless boots
## the whole game.
func _authored_texture(node_name: String) -> AtlasTexture:
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		return null

	var state: SceneState = packed.get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) != node_name:
			continue
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == "texture":
				return state.get_node_property_value(i, p) as AtlasTexture
	return null


## Asserts that the texture main.tscn authors onto `node_name` is the icon of `type`.
##
## Every failure mode is spelled out separately rather than folded into one region
## comparison, because two of them compare equal by accident: a missing node and an
## unregistered item both yield an empty Rect2, so `Rect2() == Rect2()` would report a
## pass for a test that reached neither of the things it names.
func _check_authored_sprite(node_name: String, type: Types.Item, label: String) -> String:
	var authored := _authored_texture(node_name)
	var err: String = _T.assert_true(
		authored != null, "main.tscn's %s node has an authored AtlasTexture" % label)
	if err != "":
		return err

	var item: GameItem = _items.get_item(type)
	err = _T.assert_true(item != null, "the item registry built and holds %s" % label)
	if err != "":
		return err

	# get_atlas() is the exact call PlayerManager.show_slot_data() makes, so comparing
	# its region compares the thing the player is drawn holding.
	var want: Rect2 = (item.get_atlas() as AtlasTexture).region
	return _T.assert_true(
		authored.region == want,
		"%s is authored at %s; the starting %s is at %s" % [
			label, str(authored.region), item.name, str(want)])


func test_the_authored_gather_sprite_is_the_pickaxe_the_player_starts_with() -> String:
	# The bug this is here for: region (96, 16) is tile (6, 1), the iron pickaxe — five
	# tiers above the wooden one in slot 1 — so a new player mined their first tree
	# swinging a tool they could not have crafted yet.
	return _check_authored_sprite("Gather", STARTING_PICKAXE, "Gather")


func test_the_authored_attack_sprite_is_the_sword_the_player_starts_with() -> String:
	# This one was already right, by luck rather than by rule — nothing had ever
	# checked it. Pinning it is what stops the next atlas reshuffle putting the attack
	# sprite where the gather sprite was.
	return _check_authored_sprite("Sprite", STARTING_SWORD, "Attack/Sprite")


func test_the_hotbar_can_push_the_equipped_item_without_a_selection_change() -> String:
	# The runtime half. `_refresh_equipped` is what populate_hot_bar calls so that a
	# boot, a save load or a craft into the live slot reaches the player; deleting it
	# and leaving `select_slot` as the only path is the regression, and it is invisible
	# in a diff of anything but this one file.
	var script: GDScript = load("res://inventory/hot_bar_inventory.gd")

	var err: String = _T.assert_true(script != null, "the hotbar script loads")
	if err != "":
		return err

	var names := []
	for method in script.get_script_method_list():
		names.append(str(method["name"]))

	return _T.assert_true(
		names.has("_refresh_equipped"),
		"HotBarInventory still has a way to re-push the equipped item (has %s)" % str(names))
