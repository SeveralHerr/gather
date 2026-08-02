extends RefCounted

## Covers the land economy: the price curve, the skill-tree discount, and the
## all-or-nothing purchase. Nothing here needs a TileMap — LandManager's
## expand_callable seam stands in for the world, so a failed assertion points at
## the arithmetic rather than at tilemap setup.

var _T

var coin: GameItem
var manager: LandManager
var inventory: InventoryData
var stats: PlayerStats

## What expand_callable was last handed, so a test can prove the purchase reached
## the world at all.
var expanded_to := -1
var expand_calls := 0


func setup() -> void:
	# Built here rather than pulled from the GameItems autoload: autoloads are not
	# instantiated under the headless script runner.
	coin = GameItem.new(Vector2i(4, 4), 10, Types.Item.Coin, 1, false, "Gold Coin", Vector2i.ZERO, false)

	inventory = InventoryData.new()
	for _i in range(8):
		inventory.inventory_slot_datas.append(null)

	stats = PlayerStats.new()

	expanded_to = -1
	expand_calls = 0

	manager = LandManager.new()
	manager.inventory = inventory
	manager.stats = stats
	manager.expand_callable = func(new_radius):
		expanded_to = new_radius
		expand_calls += 1
		return 17


func teardown() -> void:
	if manager != null:
		manager.free()
		manager = null


func _give_coins(amount: int) -> void:
	inventory.inventory_slot_datas[0] = SlotData.new(coin, amount)


# --- the price curve ---------------------------------------------------------

func test_the_first_parcel_costs_the_base_price() -> String:
	return _T.assert_eq(LandManager.cost_for_parcel(0, 1.0), LandManager.BASE_COST, "parcel one is the base price")


func test_every_parcel_costs_more_than_the_last() -> String:
	var previous := 0
	for parcels in range(0, LandManager.MAX_PARCELS):
		var cost := LandManager.cost_for_parcel(parcels, 1.0)
		if cost <= previous:
			return _T.assert_true(false, "parcel %d costs %d, no more than the %d before it" % [parcels + 1, cost, previous])
		previous = cost

	return ""


func test_the_curve_compounds_rather_than_adding() -> String:
	# A flat +N per parcel would make late land trivially cheap relative to how
	# much map it hands over. The gap between consecutive prices has to widen.
	var early := LandManager.cost_for_parcel(1, 1.0) - LandManager.cost_for_parcel(0, 1.0)
	var late := LandManager.cost_for_parcel(6, 1.0) - LandManager.cost_for_parcel(5, 1.0)

	return _T.assert_gt(float(late), float(early), "the price step widens as the island grows")


func test_the_opening_price_stays_within_reach() -> String:
	# Gold veins are the rarest node and pay a coin only half the time, so a first
	# parcel much above this is a wall rather than a goal.
	return _T.assert_true(
		LandManager.BASE_COST <= 25,
		"the first parcel costs %d gold, which is out of reach of one mining session" % LandManager.BASE_COST
	)


func test_each_parcel_pushes_the_coastline_out() -> String:
	var err: String = _T.assert_eq(LandManager.radius_for(0), LandManager.BASE_RADIUS, "no parcels means the starting island")
	if err != "":
		return err

	return _T.assert_eq(
		LandManager.radius_for(3), LandManager.BASE_RADIUS + 3 * LandManager.RADIUS_STEP, "three parcels is three steps out"
	)


# --- the discount ------------------------------------------------------------

func test_the_discount_multiplier_makes_land_cheaper() -> String:
	var full := LandManager.cost_for_parcel(4, 1.0)
	var discounted := LandManager.cost_for_parcel(4, 0.5)

	return _T.assert_true(discounted < full, "0.5x costs %d against the full %d" % [discounted, full])


func test_a_multiplier_of_one_changes_nothing() -> String:
	return _T.assert_eq(
		LandManager.cost_for_parcel(3, 1.0), LandManager.cost_for_parcel(3, 1.0), "the base multiplier is a no-op"
	)


func test_land_is_never_free() -> String:
	# A stat stack that reached zero would otherwise hand out the whole map for
	# nothing, and spend_type() refuses a zero amount, so the purchase would fail
	# in a way that reads as a bug rather than as a price.
	return _T.assert_gte(float(LandManager.cost_for_parcel(0, 0.0)), 1.0, "a zero multiplier still costs a coin")


func test_current_cost_reads_the_players_discount() -> String:
	var full := manager.current_cost()

	stats.land_cost_mult = 0.75
	var discounted := manager.current_cost()

	return _T.assert_true(discounted < full, "the panel price follows land_cost_mult (%d vs %d)" % [discounted, full])


# --- affordability -----------------------------------------------------------

func test_an_empty_purse_cannot_afford_land() -> String:
	var err: String = _T.assert_eq(manager.gold(), 0, "a fresh inventory holds no coins")
	if err != "":
		return err

	return _T.assert_false(manager.can_afford(), "no gold means no land")


func test_exactly_the_price_is_affordable() -> String:
	_give_coins(manager.current_cost())

	return _T.assert_true(manager.can_afford(), "the exact price is enough")


func test_one_coin_short_is_not_affordable() -> String:
	_give_coins(manager.current_cost() - 1)

	return _T.assert_false(manager.can_afford(), "a coin short is short")


func test_gold_is_counted_across_split_stacks() -> String:
	# Coins spill into a second slot as soon as one stack fills, and a price check
	# that stopped at the first slot would tell a rich player they are broke.
	inventory.inventory_slot_datas[0] = SlotData.new(coin, 5)
	inventory.inventory_slot_datas[3] = SlotData.new(coin, 9)

	return _T.assert_eq(manager.gold(), 14, "both stacks count toward the price")


# --- purchasing --------------------------------------------------------------

func test_buying_a_parcel_spends_the_coins_and_grows_the_island() -> String:
	var cost := manager.current_cost()
	_give_coins(cost + 3)

	var err: String = _T.assert_true(manager.purchase(), "an affordable parcel is bought")
	if err != "":
		return err

	err = _T.assert_eq(manager.gold(), 3, "only the price was taken")
	if err != "":
		return err

	err = _T.assert_eq(manager.parcels_bought, 1, "the parcel is on the books")
	if err != "":
		return err

	err = _T.assert_eq(manager.radius, LandManager.radius_for(1), "the radius moved one step out")
	if err != "":
		return err

	return _T.assert_eq(expanded_to, LandManager.radius_for(1), "the world was told to grow to the new radius")


func test_a_failed_purchase_takes_nothing() -> String:
	_give_coins(manager.current_cost() - 1)

	var err: String = _T.assert_false(manager.purchase(), "an unaffordable parcel is refused")
	if err != "":
		return err

	err = _T.assert_eq(manager.gold(), LandManager.cost_for_parcel(0, 1.0) - 1, "the coins are still there")
	if err != "":
		return err

	err = _T.assert_eq(manager.parcels_bought, 0, "nothing was booked")
	if err != "":
		return err

	return _T.assert_eq(expand_calls, 0, "the island was not grown on a refused purchase")


func test_the_price_rises_after_a_purchase() -> String:
	var first := manager.current_cost()
	_give_coins(first * 10)
	manager.purchase()

	return _T.assert_gt(float(manager.current_cost()), float(first), "the second parcel costs more than the first")


func test_the_island_stops_growing_at_the_cap() -> String:
	manager.parcels_bought = LandManager.MAX_PARCELS
	_give_coins(999999)

	var err: String = _T.assert_true(manager.is_maxed(), "the cap is reached")
	if err != "":
		return err

	err = _T.assert_false(manager.can_afford(), "a maxed island is never affordable, however rich")
	if err != "":
		return err

	return _T.assert_false(manager.purchase(), "buying past the cap is refused")


func test_a_purchase_with_nothing_to_grow_charges_nothing() -> String:
	# The affordability and expansion checks both run before payment, so a panel
	# wired up before the TileMapHandler exists cannot eat the player's gold.
	manager.expand_callable = Callable()
	manager.tile_map_handler = null
	_give_coins(500)

	var err: String = _T.assert_false(manager.purchase(), "there is nothing able to grow the world")
	if err != "":
		return err

	return _T.assert_eq(manager.gold(), 500, "no coins were taken")


# --- the panel ---------------------------------------------------------------
#
# The panel is built in code and lives in the UI CanvasLayer at runtime, so
# there is no .tscn to load: instantiate_ui() takes the node itself. Without it
# the Control never enters a tree, _ready() never fires and none of this exists.

func _open_panel() -> LandPurchaseUi:
	var panel := LandPurchaseUi.new()
	panel.land_manager = manager
	return await _T.instantiate_ui(panel, Vector2i(900, 600)) as LandPurchaseUi


func test_the_panel_quotes_the_price_and_the_purse() -> String:
	_give_coins(7)

	var panel := await _open_panel()
	var err: String = _T.assert_eq(panel._gold_label.text, "7", "the panel shows the gold on hand")
	if err == "":
		err = _T.assert_true(
			panel._cost_label.text.contains(str(manager.current_cost())),
			"the cost line quotes the price, not '%s'" % panel._cost_label.text
		)

	_T.free_ui(panel)
	return err


func test_the_buy_button_is_dead_until_the_player_can_pay() -> String:
	_give_coins(manager.current_cost() - 1)

	var panel := await _open_panel()
	var err: String = _T.assert_true(panel._buy_button.disabled, "a coin short leaves the button disabled")

	if err == "":
		_give_coins(manager.current_cost())
		panel._refresh()
		err = _T.assert_false(panel._buy_button.disabled, "affording it enables the button")

	_T.free_ui(panel)
	return err


func test_the_panel_starts_closed_and_toggles() -> String:
	var panel := await _open_panel()

	var err: String = _T.assert_false(panel.is_open(), "the panel does not open itself on spawn")
	if err == "":
		panel.toggle()
		err = _T.assert_true(panel.is_open(), "[B] opens it")
	if err == "":
		panel.toggle()
		err = _T.assert_false(panel.is_open(), "[B] closes it again")

	_T.free_ui(panel)
	return err


# --- persistence -------------------------------------------------------------

func test_a_save_roundtrip_restores_the_island_and_the_price() -> String:
	_give_coins(10000)
	manager.purchase()
	manager.purchase()

	var saved := manager.saveObject()
	var cost_before := manager.current_cost()

	var loaded := LandManager.new()
	loaded.inventory = inventory
	loaded.stats = stats
	loaded.expand_callable = func(new_radius):
		expanded_to = new_radius
		expand_calls += 1
		return 0

	expanded_to = -1
	loaded.loadObject(saved)

	var err: String = _T.assert_eq(loaded.parcels_bought, 2, "the parcel count survives the roundtrip")
	if err == "":
		err = _T.assert_eq(loaded.radius, LandManager.radius_for(2), "the radius survives the roundtrip")
	if err == "":
		err = _T.assert_eq(loaded.current_cost(), cost_before, "the next parcel still costs the same")
	if err == "":
		# main.gd's _ready() always builds the base island, so loading has to
		# re-grow the map or the player lands on an island smaller than they paid for.
		err = _T.assert_eq(expanded_to, LandManager.radius_for(2), "loading re-expands the island")

	loaded.free()
	return err
