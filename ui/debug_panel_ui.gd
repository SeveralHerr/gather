extends Control
class_name DebugPanelUi

## The manual-testing panel, on F3.
##
## Built in code rather than as a .tscn, matching the skill, land and crafting panels.
## It lives in the UI CanvasLayer (screen space) and must never be parented under
## Player/Camera2D/HUD: that Control is world space at the camera's 8x zoom and is
## sized for the diegetic HUD, so a full-screen panel there renders at about an eighth
## size and scrolls with the camera.
##
## main.gd only builds this behind OS.is_debug_build(), so in an export the node does
## not exist and InputManager.toggle_debug has no listener.
##
## Almost everything here drives the same calls the DevTools verbs in
## devtools_ext/commands.gd use, deliberately: those sequences already encode the
## ordering traps (revive needs five fields, not just health; an enemy's exports must
## be set before add_child). Where this panel does something the CLI cannot, the
## reason is noted at the call site.

## Capped, then clamped to the viewport. Nothing here may hardcode a viewport size.
const PANEL_MAX := Vector2(1120, 760)

## The palette, from `ui/ui_theme.gd`.
##
## This block used to be a full second copy of it, justified in a comment saying the
## project had no theme resource at all - every panel carried its own consts. That is no
## longer true: `UiTheme` is exactly that shared place, and a copy that agrees today is
## just a copy that can disagree after the next recolour. This one already had - COLOR_OK
## and COLOR_WARN were near-misses of the shared green and amber, not either of them.
##
## What is left is aliases, kept as *names* rather than substituted at every call site,
## because the names read better where they are used (`COLOR_OK` on a success status line
## says more than `COLOR_GOOD` does). COLOR_FRAME and COLOR_INSET are gone entirely: they
## only ever fed the two local style factories, and those now come from `UiTheme` too.
## Nothing may be added here that is not an alias - a colour *defined* in this file is the
## drift starting over.
##
## COLOR_WARN is the one that had to choose rather than map. It is only ever `_fail()`'s
## status line - "no player", "inventory full", "no scene for Elite" - so it is a warning
## and takes COLOR_ORANGE, not COLOR_GOLD, which the rest of the game spends on currency
## and on "this one matters".
const COLOR_BACKDROP := UiTheme.COLOR_BACKDROP
const COLOR_TEXT := UiTheme.COLOR_TEXT
const COLOR_TEXT_DIM := UiTheme.COLOR_TEXT_DIM
const COLOR_OK := UiTheme.COLOR_GOOD
const COLOR_WARN := UiTheme.COLOR_ORANGE

## How often the live readout re-reads the world while the panel is open. The readout
## is the only thing here that polls; every action is one-shot.
const REFRESH_SECONDS := 0.25

## Typed so `var type := ENEMY_TYPES[i]` infers String rather than Variant.
const ENEMY_TYPES: Array[String] = ["Bone", "Spider", "Elite"]
const ISLAND_IDS: Array[String] = ["forest", "ore", "boss"]

var input_manager: InputManager

var _panel_root: Control
var _frame: PanelContainer
var _readout: Label
var _status: Label
var _since_refresh := 0.0

var _item_picker: OptionButton
var _item_count: SpinBox
var _skill_picker: OptionButton
var _enemy_picker: OptionButton
var _speed_slider: HSlider
var _god_check: CheckBox


func _ready() -> void:
	add_to_group("UI")
	# The script root only hosts the panel. While closed it must not swallow clicks
	# meant for the world underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if input_manager == null:
		input_manager = get_node_or_null("../../Systems/InputManager") as InputManager
	if input_manager:
		input_manager.toggle_debug.connect(toggle)

	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	set_process(false)


# --- dependency lookup -------------------------------------------------------
#
# Resolved per call rather than cached in _ready(). Loading a save frees and rebuilds
# enemies, pickups and every non-zero tile layer, and the panel outlives all of it.

func _player() -> Player:
	return PlayerManager.player


func _lum() -> LevelUpManager:
	# Static finder that type-checks the group. main.tscn's root belongs to nearly
	# every group, so get_first_node_in_group would return the root instead.
	return LevelUpManager.find(self)


func _handler() -> TileMapHandler:
	for node in get_tree().get_nodes_in_group("TileMapHandler"):
		if node is TileMapHandler:
			return node
	return null


func _spawner() -> EnemySpawner:
	return get_tree().root.get_node_or_null("Main/World/EnemySpawner") as EnemySpawner


# --- construction ------------------------------------------------------------

## The clock and the lighting, by group. Both are created at runtime — the clock is authored
## into main.tscn under Systems but registers its group in _enter_tree, and SkyLighting is made
## by main.gd as a direct child of Main — so neither has a path this panel can rely on.
func _clock() -> WorldClock:
	for node in get_tree().get_nodes_in_group("WorldClock"):
		if node is WorldClock:
			return node
	return null


func _sky() -> SkyLighting:
	for node in get_tree().get_nodes_in_group("SkyLighting"):
		if node is SkyLighting:
			return node
	return null


func _build() -> void:
	_panel_root = Control.new()
	# Named rather than left as a generated @Control@31: the devtools bridge addresses
	# panels by path, and generated names shift with node count.
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
	_frame.add_theme_stylebox_override("panel", UiTheme.frame_style())
	center.add_child(_frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UiTheme.PAD_PANEL)
	margin.add_theme_constant_override("margin_right", UiTheme.PAD_PANEL)
	margin.add_theme_constant_override("margin_top", UiTheme.PAD_PANEL)
	margin.add_theme_constant_override("margin_bottom", UiTheme.PAD_PANEL)
	_frame.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", UiTheme.GAP)
	margin.add_child(column)

	_build_header(column)
	column.add_child(HSeparator.new())

	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)

	_build_state_tab(_tab(tabs, "State"))
	_build_player_tab(_tab(tabs, "Player"))
	_build_spawn_tab(_tab(tabs, "Spawn"))
	_build_world_tab(_tab(tabs, "World"))

	_status = Label.new()
	_status.name = "Status"
	_status.text = "ready"
	_status.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	_status.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	column.add_child(_status)

	var footer := Label.new()
	footer.text = "[F3] or [Esc] close   -   debug build only"
	footer.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	footer.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)


func _build_header(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)

	var title := Label.new()
	title.text = "DEBUG"
	title.add_theme_font_size_override("font_size", UiTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var subtitle := Label.new()
	subtitle.text = "manual testing"
	subtitle.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	subtitle.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(subtitle)


## Every tab is a scroller: the panel is clamped to the viewport, so on a short window
## the contents have to go somewhere rather than force the frame off screen.
func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", UiTheme.GAP)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body


# --- tab: State --------------------------------------------------------------

func _build_state_tab(body: VBoxContainer) -> void:
	_heading(body, "Live state")
	_hint(body, "Re-read every %.2fs while the panel is open." % REFRESH_SECONDS)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _inset_style())
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(box)

	_readout = Label.new()
	_readout.name = "Readout"
	_readout.text = "-"
	_readout.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	_readout.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(_readout)


# --- tab: Player -------------------------------------------------------------

func _build_player_tab(body: VBoxContainer) -> void:
	_heading(body, "Health")
	var health_row := _row(body)
	_button(health_row, "Full heal", _on_full_heal)
	_button(health_row, "Damage 1", func(): _on_damage(1))
	_button(health_row, "Damage 5", func(): _on_damage(5))
	_button(health_row, "Kill", _on_kill)
	_button(health_row, "Revive", _on_revive)

	_god_check = CheckBox.new()
	_god_check.name = "GodMode"
	_god_check.text = "God mode"
	_god_check.toggled.connect(_on_god_toggled)
	body.add_child(_god_check)
	_hint(body, "Sets Player.god_mode, which receive_hit checks alongside is_dead. " \
		+ "Kept separate from `invulnerable` because that flag belongs to the respawn " \
		+ "timer and is cleared when it expires.")

	body.add_child(HSeparator.new())

	_heading(body, "Progression")
	var xp_row := _row(body)
	_button(xp_row, "+10 xp", func(): _on_add_xp(10))
	_button(xp_row, "+100 xp", func(): _on_add_xp(100))
	_button(xp_row, "Next level", _on_next_level)
	_button(xp_row, "+1 point", func(): _on_grant_points(1))
	_button(xp_row, "+5 points", func(): _on_grant_points(5))
	_hint(body, "add_xp multiplies by stats.xp_mult, so with Scholar taken the granted " \
		+ "amount is larger than the button says. `Next level` compensates for that.")

	var skill_row := _row(body)
	_skill_picker = OptionButton.new()
	_skill_picker.name = "SkillPicker"
	_skill_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_row.add_child(_skill_picker)
	_button(skill_row, "Learn", _on_learn_skill)
	_button(skill_row, "Open tree", _on_open_skill_tree)
	_hint(body, "There is no respec: _apply_unlocks calls Recipes.add_recipe and " \
		+ "ResourceManager2.add_resource, and neither has an inverse, so a skill reset " \
		+ "would leave every unlocked recipe and spawnable behind. Reload a save instead.")

	body.add_child(HSeparator.new())

	_heading(body, "Movement")
	var speed_row := _row(body)
	var speed_label := Label.new()
	speed_label.text = "Speed x"
	speed_label.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	speed_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	speed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_row.add_child(speed_label)

	_speed_slider = HSlider.new()
	_speed_slider.name = "SpeedSlider"
	_speed_slider.min_value = 0.25
	_speed_slider.max_value = 6.0
	_speed_slider.step = 0.25
	_speed_slider.value = 1.0
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_speed_slider.value_changed.connect(_on_speed_changed)
	speed_row.add_child(_speed_slider)
	_button(speed_row, "Reset", func(): _speed_slider.value = 1.0)
	_hint(body, "Writes stats.move_speed_mult. PlayerStats.recompute() rebuilds every " \
		+ "stat from the taken set, so buying a skill or loading a save discards this - " \
		+ "re-drag the slider afterwards.")


# --- tab: Spawn --------------------------------------------------------------

func _build_spawn_tab(body: VBoxContainer) -> void:
	_heading(body, "Give item")
	var give_row := _row(body)
	_item_picker = OptionButton.new()
	_item_picker.name = "ItemPicker"
	_item_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	give_row.add_child(_item_picker)

	_item_count = SpinBox.new()
	_item_count.name = "ItemCount"
	_item_count.min_value = 1
	_item_count.max_value = 9999
	_item_count.value = 10
	give_row.add_child(_item_count)
	_button(give_row, "Give", _on_give_item)
	_hint(body, "Only the 36 registered items are listed. Types.Item also holds seven " \
		+ "resource-node values (Tree, StoneResource, ...) that have no GameItem at all - " \
		+ "GameItems.get_item() errors on those, so they are spawned from the World tab.")

	var inv_row := _row(body)
	_button(inv_row, "+999 coins", _on_give_coins)
	_button(inv_row, "Clear inventory", _on_clear_inventory)
	_hint(body, "Inventory is a fixed 12 slots and never grows; a give into a full " \
		+ "inventory silently fails and is reported below.")

	body.add_child(HSeparator.new())

	_heading(body, "Enemies")
	var enemy_row := _row(body)
	_enemy_picker = OptionButton.new()
	_enemy_picker.name = "EnemyPicker"
	for type in ENEMY_TYPES:
		_enemy_picker.add_item(type)
	# Selected is not reliably 0 just because this was populated in order, and an
	# unselected OptionButton reports -1 - which GDScript happily negative-indexes into
	# the last entry rather than erroring, so the "Bone" button silently spawned the
	# boss. Pin it, and _picked() re-checks the range at every use.
	_enemy_picker.select(0)
	_enemy_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_row.add_child(_enemy_picker)
	_button(enemy_row, "Spawn", func(): _on_spawn_enemy(1))
	_button(enemy_row, "Spawn 5", func(): _on_spawn_enemy(5))

	var enemy_row2 := _row(body)
	_button(enemy_row2, "Kill all (loot)", func(): _on_clear_enemies(true))
	_button(enemy_row2, "Remove all (silent)", func(): _on_clear_enemies(false))
	_button(enemy_row2, "Toggle spawning", _on_toggle_spawning)
	_hint(body, "Removing enemies does not cancel an in-flight telegraph, so a spawn " \
		+ "already counting down still lands about 2s later.")


# --- tab: World --------------------------------------------------------------

func _build_world_tab(body: VBoxContainer) -> void:
	_heading(body, "Land")
	var land_row := _row(body)
	_button(land_row, "Buy parcel", func(): _on_buy_land(1))
	_button(land_row, "Buy 5", func(): _on_buy_land(5))
	_button(land_row, "Buy all", func(): _on_buy_land(99))
	_button(land_row, "Open panel", _on_open_land_panel)
	_hint(body, "Coins are topped up first and then purchase() is called for real, so " \
		+ "the land xp, the resource seeding and the state_changed signal all still fire.")

	body.add_child(HSeparator.new())

	_heading(body, "Teleport")
	var tp_row := _row(body)
	_button(tp_row, "Home", _on_goto_home)
	for id in ISLAND_IDS:
		_button(tp_row, id.capitalize(), func(): _on_goto_island(id))
	_hint(body, "Works whether or not the island is walkably connected yet, which early " \
		+ "on it will not be - islands are only reached by growing the coastline.")

	body.add_child(HSeparator.new())

	_heading(body, "Resources")
	var res_row := _row(body)
	_button(res_row, "Spawn 1", func(): _on_add_resources(1))
	_button(res_row, "Spawn 20", func(): _on_add_resources(20))
	_button(res_row, "Reseed home", _on_reseed)

	body.add_child(HSeparator.new())

	_heading(body, "Weather and lightning")
	var weather_row := _row(body)
	_button(weather_row, "Clear", func(): _on_set_weather(false))
	_button(weather_row, "Rain", func(): _on_set_weather(true))
	_button(weather_row, "Bolt (near)", func(): _on_strike(0.05))
	_button(weather_row, "Bolt (far)", func(): _on_strike(0.9))
	_button(weather_row, "Strike a skull", _on_charge_skeleton)
	_hint(body, "A bolt starts a storm first if the sky is clear - lightning outside rain " 		+ "is a state the game itself cannot reach, so forcing one would leave a flash with " 		+ "nothing behind it. Near and far are the same bolt at different distances: the " 		+ "flash brightness, the delay before the thunder and its volume all come off that " 		+ "one number, so a far bolt is dim and arrives late. 'Strike a skull' does what a " 		+ "lucky near bolt does - it REPLACES a live skeleton with a charged one, so net it " 		+ "rather than killing it.")

	body.add_child(HSeparator.new())

	_heading(body, "Save")
	var save_row := _row(body)
	_button(save_row, "Save", _on_save)
	_button(save_row, "Load", _on_load)
	_hint(body, "Load finishes a frame later - main.gd defers the chunk payloads and the " \
		+ "island reassert to _finish_load(), so the readout above settles one frame after " \
		+ "the click. Load also frees every live enemy and pickup.")


# --- actions: player ---------------------------------------------------------

func _on_full_heal() -> void:
	var player := _player()
	if player == null:
		return _fail("no player")
	player.health_manager.reset_health()
	# Nothing else syncs the diegetic HP bar; a direct health_manager write leaves it stale.
	player.update_hp_bar()
	_ok("healed to %d" % player.health_manager.current_health)


func _on_damage(amount: int) -> void:
	var player := _player()
	if player == null:
		return _fail("no player")
	# take_damage rather than receive_hit: receive_hit is what god mode suppresses, and a
	# damage button that silently does nothing while god mode is on is worse than useless.
	player.health_manager.take_damage(amount)
	player.update_hp_bar()
	_ok("hp %d/%d" % [player.health_manager.current_health, player.health_manager.max_health])


func _on_kill() -> void:
	var player := _player()
	if player == null:
		return _fail("no player")
	# set_health(0) emits `died`, which is the real death path (respawn, invuln, the lot).
	player.health_manager.set_health(0)
	player.update_hp_bar()
	_ok("killed - respawn is async, give it half a second")


## The five-field sequence from the revive_player verb. reset_health() alone leaves
## is_dead set and input disabled, so the run stays frozen and unrescuable.
func _on_revive() -> void:
	var player := _player()
	if player == null:
		return _fail("no player")
	player.is_dead = false
	player.invulnerable = false
	player.input_manager.disable_input = false
	# A death blink tween may have left the sprite part-transparent.
	player.animated_sprite_2d.modulate.a = 1.0
	player.health_manager.reset_health()
	player.update_hp_bar()
	_ok("revived at %d hp" % player.health_manager.current_health)


func _on_god_toggled(pressed: bool) -> void:
	var player := _player()
	if player == null:
		return _fail("no player")
	player.god_mode = pressed
	_ok("god mode %s" % ("on" if pressed else "off"))


func _on_add_xp(amount: int) -> void:
	var lum := _lum()
	if lum == null:
		return _fail("no LevelUpManager")
	var granted := lum.add_xp(amount)
	_ok("granted %d xp (asked %d), level %d" % [granted, amount, lum.level])


## Divides out stats.xp_mult so the award lands on the threshold rather than past it.
func _on_next_level() -> void:
	var lum := _lum()
	if lum == null:
		return _fail("no LevelUpManager")
	var remaining: int = maxi(1, lum.next_level - lum.xp)
	var mult := 1.0
	var player := _player()
	if player != null:
		mult = maxf(0.01, player.stats.xp_mult)
	var before := lum.level
	lum.add_xp(int(ceil(float(remaining) / mult)))
	_ok("level %d -> %d, %d points banked" % [before, lum.level, lum.points])


## No grant_points() exists; points is a plain var and SkillTreeUi only redraws on the
## signal, so both halves are needed.
func _on_grant_points(amount: int) -> void:
	var lum := _lum()
	if lum == null:
		return _fail("no LevelUpManager")
	lum.points += amount
	lum.points_changed.emit(lum.points)
	_ok("%d points banked" % lum.points)


func _on_learn_skill() -> void:
	var lum := _lum()
	if lum == null:
		return _fail("no LevelUpManager")
	var index := _picked(_skill_picker)
	if index < 0:
		return _fail("no skill selected")
	var id := String(_skill_picker.get_item_metadata(index))
	if id == "":
		return _fail("no skill selected")
	# purchase() spends a point and refuses if the prerequisites are unmet, so top up
	# first and let it answer honestly about the tier gate.
	if lum.points <= 0:
		lum.points += 1
		lum.points_changed.emit(lum.points)
	if lum.purchase(id):
		_ok("learned %s" % id)
		_refresh_skill_picker()
	else:
		var missing: Array = lum.tree.missing_requirements(id, lum.taken)
		_fail("refused %s (needs %s)" % [id, ", ".join(missing) if missing.size() > 0 else "?"])


func _on_open_skill_tree() -> void:
	var ui := get_parent().get_node_or_null("SkillTreeUI")
	if ui == null:
		return _fail("no SkillTreeUI")
	set_open(false)
	ui.set_open(true)


func _on_speed_changed(value: float) -> void:
	var player := _player()
	if player == null:
		return
	player.stats.move_speed_mult = value
	_ok("move_speed_mult %.2f" % value)


# --- actions: spawn ----------------------------------------------------------

func _on_give_item() -> void:
	var player := _player()
	if player == null:
		return _fail("no player")
	var index := _picked(_item_picker)
	if index < 0:
		return _fail("no item selected")
	var type = _item_picker.get_item_metadata(index)
	if type == null:
		return _fail("no item selected")
	var want := int(_item_count.value)
	# One SlotData carrying the whole count: pick_up_slot_data merges into an existing
	# stack of the same type and there is no stack cap anywhere.
	var item: GameItem = GameItems.get_item(type)
	if player.inventory_data.pick_up_slot_data(SlotData.new(item, want)):
		_ok("gave %d x %s" % [want, item.name])
	else:
		_fail("inventory full - %s not added" % item.name)


func _on_give_coins() -> void:
	var player := _player()
	if player == null:
		return _fail("no player")
	var coin: GameItem = GameItems.get_item(Types.Item.Coin)
	if player.inventory_data.pick_up_slot_data(SlotData.new(coin, 999)):
		_ok("coins: %d" % player.inventory_data.count_of_type(Types.Item.Coin))
	else:
		_fail("inventory full")


## InventoryData has no clear(), so the slots are nulled directly and the UI is told.
func _on_clear_inventory() -> void:
	var player := _player()
	if player == null:
		return _fail("no player")
	var inv := player.inventory_data
	for i in inv.inventory_slot_datas.size():
		inv.inventory_slot_datas[i] = null
	inv.inv_updated()
	if player.hot_bar_inventory:
		player.hot_bar_inventory.update_placed_slot()
	_ok("inventory cleared (%d slots)" % inv.inventory_slot_datas.size())


func _on_spawn_enemy(count: int) -> void:
	var spawner := _spawner()
	var player := _player()
	if spawner == null:
		return _fail("no EnemySpawner")
	if player == null:
		return _fail("no player - Enemy._ready looks the player up and would crash")
	var index := _picked(_enemy_picker)
	if index < 0:
		return _fail("no enemy type selected")
	var type := ENEMY_TYPES[index]
	for i in count:
		var scene := spawner.scene_for_type(type)
		if scene == null:
			return _fail("no scene for %s" % type)
		var enemy = scene.instantiate()
		# The scene already carries `type`, `max_health` and `damage` as exports, and
		# _ready() is what turns max_health into a HealthManager - so this must be
		# added to the tree before anything reads health_manager, and the parent has
		# to be the spawner or the enemy is left out of both saving and the live count.
		spawner.add_child(enemy)
		var angle := TAU * float(i) / float(maxi(1, count))
		enemy.position = player.position + Vector2(48, 0).rotated(angle)
	_ok("spawned %d x %s (%d live, cap %d)" \
		% [count, type, spawner.count_live_enemies(), spawner.enemy_cap()])


func _on_clear_enemies(with_loot: bool) -> void:
	var spawner := _spawner()
	if spawner == null:
		return _fail("no EnemySpawner")
	var killed := 0
	for child in spawner.get_children():
		if child is Enemy:
			if with_loot:
				# Routes through _on_died: particles, drops, coins and kill xp.
				child.health_manager.set_health(0)
			else:
				child.queue_free()
			killed += 1
	_ok("%s %d enemies" % ["killed" if with_loot else "removed", killed])


func _on_toggle_spawning() -> void:
	var spawner := _spawner()
	if spawner == null:
		return _fail("no EnemySpawner")
	if spawner.timer.is_stopped():
		spawner.timer.start(spawner.next_interval())
		_ok("spawning on, next in %.1fs" % spawner.timer.time_left)
	else:
		spawner.timer.stop()
		_ok("spawning paused")


# --- actions: world ----------------------------------------------------------

## Tops the wallet up and then buys for real, so the xp award, the resource seeding and
## the state_changed signal all still happen. purchase() always charges; there is no
## free-grant path that keeps those side effects.
func _on_buy_land(count: int) -> void:
	var handler := _handler()
	var player := _player()
	if handler == null or handler.land_manager == null:
		return _fail("no LandManager")
	if player == null:
		return _fail("no player")
	var land := handler.land_manager
	var bought := 0
	for i in count:
		if land.is_maxed():
			break
		if not land.can_afford():
			var coin: GameItem = GameItems.get_item(Types.Item.Coin)
			player.inventory_data.pick_up_slot_data(SlotData.new(coin, land.current_cost()))
		if not land.purchase():
			break
		bought += 1
	_ok("bought %d, radius %d, %d/%d parcels, %d land tiles" \
		% [bought, land.radius, land.parcels_bought, LandManager.MAX_PARCELS,
			handler.count_land_tiles()])


func _on_goto_home() -> void:
	var handler := _handler()
	var player := _player()
	if handler == null or player == null:
		return _fail("no world")
	player.position = handler.tileMap.map_to_local(TileMapHandler.HOME_CENTRE)
	_ok("teleported home")


func _on_goto_island(id: String) -> void:
	var handler := _handler()
	var player := _player()
	if handler == null or player == null or handler.island_manager == null:
		return _fail("no IslandManager")
	var islands: Dictionary = handler.island_manager.islands
	if not islands.has(id):
		return _fail("no island %s (have %s)" % [id, ", ".join(islands.keys())])
	var centre: Vector2i = islands[id]["centre"]
	player.position = handler.tileMap.map_to_local(centre)
	_ok("teleported to %s at %s" % [id, centre])


func _on_add_resources(count: int) -> void:
	var handler := _handler()
	if handler == null or handler.resource_manager == null:
		return _fail("no ResourceManager")
	var added := 0
	for i in count:
		if handler.resource_manager.add_random_resource():
			added += 1
	_ok("added %d/%d nodes, %d live" \
		% [added, count, handler.count_resource_nodes()])


func _on_reseed() -> void:
	var handler := _handler()
	if handler == null or handler.resource_manager == null:
		return _fail("no ResourceManager")
	handler.resource_manager.seed_island()
	_ok("reseeded home to %d nodes" % handler.count_resource_nodes())


func _on_save() -> void:
	var handler := _handler()
	if handler == null or handler.save_load == null:
		return _fail("no SaveLoad")
	handler.save_load._on_save_pressed()
	_ok("saved")


func _on_load() -> void:
	var handler := _handler()
	if handler == null or handler.save_load == null:
		return _fail("no SaveLoad")
	handler.save_load._on_load_pressed()
	_ok("loaded - chunks and islands settle next frame")


func _on_open_land_panel() -> void:
	var ui := get_parent().get_node_or_null("LandPurchaseUI")
	if ui == null:
		return _fail("no LandPurchaseUI")
	set_open(false)
	ui.set_open(true)


# --- readout -----------------------------------------------------------------

func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < REFRESH_SECONDS:
		return
	_since_refresh = 0.0
	_refresh_readout()


func _refresh_readout() -> void:
	if _readout == null:
		return
	var lines: Array[String] = []

	var player := _player()
	if player == null:
		lines.append("player   absent")
	else:
		lines.append("player   hp %d/%d   pos %.0f,%.0f   state %s" % [
			player.health_manager.current_health, player.health_manager.max_health,
			player.position.x, player.position.y,
			player.state_machine.state.name if player.state_machine.state else "?"])
		lines.append("         dead %s   invuln %s   god %s   damage %d" % [
			player.is_dead, player.invulnerable, player.god_mode,
			player.damage + player.stats.damage_bonus])
		var coins := player.inventory_data.count_of_type(Types.Item.Coin)
		lines.append("         coins %d" % coins)

	var lum := _lum()
	if lum != null:
		# `next_level` is cumulative, so "xp 716/1479" does not say what the level in progress
		# costs — and the cost per level is the whole subject of the curve. Both readings, since
		# the pair is what makes a pacing complaint checkable against the arithmetic.
		lines.append("level    %d   xp %d/%d (this level %d)   points %d   skills %d" % [
			lum.level, lum.xp, lum.next_level, LevelUpManager.cost_of_level(lum.level + 1),
			lum.points, lum.taken.size()])

	if player != null:
		# Driven off PlayerStats.BASE so a stat added later shows up here for free.
		var stat_bits: Array[String] = []
		for key in PlayerStats.BASE.keys():
			stat_bits.append("%s %s" % [key, player.stats.get(key)])
		lines.append("stats    " + "   ".join(stat_bits))

	var spawner := _spawner()
	if spawner != null:
		lines.append("enemies  %d live / cap %d   spawner %s   next %.1fs" % [
			spawner.count_live_enemies(), spawner.enemy_cap(),
			"paused" if spawner.timer.is_stopped() else "running",
			spawner.timer.time_left])

	var handler := _handler()
	if handler != null:
		lines.append("fps      %d" % Engine.get_frames_per_second())
		if handler.land_manager != null:
			var land := handler.land_manager
			lines.append("land     radius %d   parcels %d/%d   next cost %d   tiles %d" % [
				land.radius, land.parcels_bought, LandManager.MAX_PARCELS,
				land.current_cost(), handler.count_land_tiles()])
		lines.append("nodes    %d" % handler.count_resource_nodes())
		var census: Dictionary = handler.resource_node_census()
		var census_bits: Array[String] = []
		for key in census.keys():
			census_bits.append("%s %d" % [key, census[key]])
		lines.append("census   " + ("   ".join(census_bits) if census_bits.size() > 0 else "-"))
		if handler.island_manager != null:
			var ids: Array = handler.island_manager.islands.keys()
			lines.append("islands  " + (", ".join(ids) if ids.size() > 0 else "none"))

	_readout.text = "\n".join(lines)


func _refresh_skill_picker() -> void:
	var lum := _lum()
	if _skill_picker == null or lum == null:
		return
	var previous := _skill_picker.selected
	_skill_picker.clear()
	for id in lum.tree.order:
		var skill = lum.tree.skills[id]
		var mark := "x" if lum.taken.has(id) else ("." if lum.is_available(id) else "-")
		_skill_picker.add_item("[%s] %s  (%s t%d)" % [mark, skill.display_name, skill.branch, skill.tier])
		_skill_picker.set_item_metadata(_skill_picker.item_count - 1, id)
	if previous >= 0 and previous < _skill_picker.item_count:
		_skill_picker.selected = previous
	elif _skill_picker.item_count > 0:
		_skill_picker.select(0)


func _refresh_item_picker() -> void:
	if _item_picker == null or _item_picker.item_count > 0:
		return
	# get_all_types() is the registered-item list. Types.Item itself also holds the
	# seven resource-node values, and GameItems.get_item() errors on those.
	var rows: Array = []
	for type in GameItems.get_all_types():
		rows.append({"type": type, "name": GameItems.get_item(type).name})
	rows.sort_custom(func(a, b): return a["name"] < b["name"])
	for row in rows:
		_item_picker.add_item(row["name"])
		_item_picker.set_item_metadata(_item_picker.item_count - 1, row["type"])
	if _item_picker.item_count > 0:
		_item_picker.select(0)


## OptionButton.selected is -1 when nothing is chosen, and GDScript negative-indexes
## rather than erroring - so an unguarded `list[picker.selected]` quietly returns the
## last entry. Every read of a picker index goes through here.
func _picked(picker: OptionButton) -> int:
	if picker == null:
		return -1
	var index := picker.selected
	if index < 0 or index >= picker.item_count:
		return -1
	return index


# --- open / close ------------------------------------------------------------

func is_open() -> bool:
	return _panel_root != null and _panel_root.visible


func toggle() -> void:
	set_open(not is_open())


func set_open(open: bool) -> void:
	if _panel_root == null or _panel_root.visible == open:
		return

	_panel_root.visible = open

	# The same handshake the skill, land and crafting panels use: stop the player
	# walking around behind the menu. Assigned rather than toggled, so two overlapping
	# panels cannot leave input disabled forever. The cursor is not part of it any
	# more — it is visible for the whole session now (player.gd).
	if input_manager:
		input_manager.disable_input = open

	# The readout is the only polling thing here, so it only runs while visible.
	set_process(open)

	if open:
		_refresh_item_picker()
		_refresh_skill_picker()
		if _god_check and _player() != null:
			_god_check.set_pressed_no_signal(_player().god_mode)
		if _speed_slider and _player() != null:
			_speed_slider.set_value_no_signal(_player().stats.move_speed_mult)
		_since_refresh = REFRESH_SECONDS
		_refresh_readout()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


# --- layout & style ----------------------------------------------------------

## Nothing here hardcodes a viewport dimension - the window is 1920x1080 with stretch
## disabled, so a resize shows more world and every panel has to re-clamp itself.
func _layout() -> void:
	if _frame == null or not is_inside_tree():
		return
	var view := get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var pad: float = clampf(minf(view.x, view.y) * 0.035, 8.0, 40.0)
	var wanted := Vector2(
		minf(PANEL_MAX.x, view.x - pad * 2.0),
		minf(PANEL_MAX.y, view.y - pad * 2.0))
	_frame.custom_minimum_size = wanted
	_frame.size = wanted


## `UiTheme.inset_style()` plus a content margin, which is the one thing this panel needs
## that the shared well does not provide: everywhere else an inset wraps a container that
## supplies its own padding, whereas here the readout Label is the direct child, so with
## no margin the text starts hard against the outline. Built on the factory rather than
## hand-rolled so the `anti_aliasing` setting (and every later addition to it) comes for
## free - a StyleBoxFlat assembled locally is how this file ended up divergent last time.
func _inset_style() -> StyleBoxFlat:
	var style := UiTheme.inset_style()
	style.set_content_margin_all(UiTheme.PAD_PANEL)
	return style


func _heading(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UiTheme.FONT_BODY)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	parent.add_child(label)


func _hint(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Deliberately still a literal, and not derived from PAD_PANEL: it is the wrap width a
	# hint gets inside the widest the panel is ever allowed to be, and it has to leave room
	# for the tab strip and the scrollbar as well as the margins. Tie it to the padding and
	# it silently retunes itself the next time the padding moves.
	label.custom_minimum_size = Vector2(PANEL_MAX.x - 120.0, 0)
	parent.add_child(label)


func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.GAP)
	parent.add_child(row)
	return row


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	# 30, not UiTheme.TOUCH_MIN: this is the one panel that is never played on a phone -
	# main.gd only builds it behind OS.is_debug_build(), and there are five buttons to a
	# row. A 48px floor here wraps every row and costs the readout its screen height.
	button.custom_minimum_size = Vector2(0, 30)
	UiTheme.style_button(button)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _ok(message: String) -> void:
	if _status:
		_status.text = message
		_status.add_theme_color_override("font_color", COLOR_OK)
	_refresh_readout()


func _fail(message: String) -> void:
	if _status:
		_status.text = message
		_status.add_theme_color_override("font_color", COLOR_WARN)


# --- actions: weather and lightning ------------------------------------------

func _on_set_weather(rain: bool) -> void:
	var clock := _clock()
	if clock == null:
		return _fail("no WorldClock")

	# A whole storm rather than a sliver: one short enough to expire on the next tick would
	# take itself away before the player saw it, and the button would read as broken.
	if rain:
		clock.set_weather(
			WorldClock.Weather.RAIN,
			WorldClock.RAIN_MAX_FRACTION * WorldClock.DAY_LENGTH_SECONDS
		)
	else:
		clock.set_weather(WorldClock.Weather.CLEAR, 0.0)

	# Repaint rather than wait for SkyLighting's own _process. The panel is modal-ish and the
	# player is looking at it when they click, so a tint that lags a frame behind the button
	# reads as the button having missed.
	_repaint_sky()
	_ok("weather: %s" % WorldClock.weather_name(clock.weather))


func _on_strike(distance: float) -> void:
	var clock := _clock()
	if clock == null:
		return _fail("no WorldClock")

	# The storm-first rule and the arm-before-emit ordering live on the clock, so this button
	# and the strike_lightning devtools verb cannot disagree about what a forced bolt does.
	var started_storm := clock.force_lightning(distance)
	_repaint_sky()

	var note := " (started a storm)" if started_storm else ""
	_ok("bolt at distance %.2f%s" % [distance, note])


func _on_charge_skeleton() -> void:
	var spawner := _spawner()
	if spawner == null:
		return _fail("no EnemySpawner")

	var clock := _clock()
	if clock == null:
		return _fail("no WorldClock")

	var struck: Enemy = spawner.charge_random_skeleton()
	if struck == null:
		# Distinct from success on purpose. "There were no plain skeletons" and "it worked" are
		# different worlds, and a button that said the same for both would send the reader
		# looking for the bug in the lighting.
		return _fail("no plain skeleton to strike - spawn one first")

	# Fire a REAL bolt, not just the charge. This button used to call charge_random_skeleton and
	# stop, so a skeleton turned blue with no flash, no arc and no thunder — the button did the
	# rare thing and showed none of it, which reads as the lightning being broken rather than as
	# the button being partial. Going through force_lightning is also what keeps this honest: it
	# starts a storm if the sky is clear, so the state left behind is one the game can reach.
	clock.force_lightning(0.0)

	# Overhead, and aimed at the skeleton — the whole point of the button is seeing what was
	# hit. strike_bolt_at restarts the envelope, so this replaces the bolt force_lightning just
	# caused rather than adding a second one.
	var sky := _sky()
	if sky != null:
		sky.strike_bolt_at(0.0, struck.global_position)
	_repaint_sky()

	_ok("bolt struck a skeleton at (%.0f, %.0f) - net it, do not kill it" % [
		struck.global_position.x, struck.global_position.y
	])


func _repaint_sky() -> void:
	var sky := _sky()
	if sky:
		sky.apply()
