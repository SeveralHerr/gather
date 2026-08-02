extends Control

## The corner "+N xp" readout. Since the xp splash pass this is the quieter, second view
## of the same event: LevelUpManager.add_xp emits added_xp once and spawns one world
## splash, and this label only listens - it never awards anything, so the two cannot
## double-count. Kept rather than folded into SplashText because it survives a burst
## (the timer restarts) and stays readable while a dozen splashes are flying.

const DISPLAY_TIME := 0.6

## Found by group rather than by path. This used to be `$"../LevelUpManager"`, a
## sibling reach that only worked while the model node was parked inside the HUD;
## it lives in `Systems` now and there is no fixed relative path between the two.
var level_up_ui: LevelUpManager

# One restartable timer instead of an await per event. With an await each, two gains
# inside the window left two pending clears, and the first to fire blanked the label
# while the second gain was still the current one.
var clear_timer: Timer


# Called when the node enters the scene tree for the first time.
func _ready():
	clear_timer = Timer.new()
	clear_timer.one_shot = true
	clear_timer.wait_time = DISPLAY_TIME
	clear_timer.timeout.connect(_on_clear)
	add_child(clear_timer)

	$XpLabel.text = ""

	# Deferred, not direct: this node is under World, which main.tscn declares before
	# Systems, so LevelUpManager has not run its own _ready yet and the group it adds
	# itself to is still empty here. A deferred call lands after every _ready in the
	# tree. Connecting directly gave a null and a silently dead xp readout.
	_bind_level_up_manager.call_deferred()


func _bind_level_up_manager() -> void:
	level_up_ui = LevelUpManager.find(self)
	if level_up_ui == null:
		push_error("FloatingText: no LevelUpManager found, the +N xp readout will never update")
		return
	level_up_ui.added_xp.connect(_on_xp_add)


func _on_xp_add(amount: int):
	$XpLabel.text = "+" + str(amount) + " xp"
	clear_timer.start(DISPLAY_TIME)


func _on_clear():
	$XpLabel.text = ""
