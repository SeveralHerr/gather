extends GameItem
class_name GameItemBoneEnemy

## A skull captured with the net. Using it drops the skull into the closest bone machine
## the player is standing inside — a BoneTurret or a BoneWorker. Both are assembled the
## same way and both expose `loaded` / `set_loaded()`, so neither is special-cased here.


## The stack is spent only when a machine actually took the skull. It used to be removed
## unconditionally, which lost the skull on a use that reached nothing at all and again on
## a use aimed at a machine that was already full — `set_loaded()` is idempotent, so that
## second case was a silent loss with no feedback of any kind.
func use(_target):
	var machine = find_closest_loadable()
	if machine == null:
		return

	machine.set_loaded()
	PlayerManager.player.inventory_data.remove_by_type(Types.Item.BoneEnemy)


## Whether using the skull right now would load anything.
##
## `use_slot_data()` consults this for every item now (gather-tan), so this is the live
## guard rather than advisory. `use()` still checks for itself — it is reachable from
## PlayerManager directly — and keeping the question in one function is what stops the two
## answers drifting apart.
func can_use() -> bool:
	return find_closest_loadable() != null


## The nearest machine still able to take a skull, from the areas the player overlaps.
##
## One pass over that list rather than one per machine type: two passes would double the
## work and make "whichever is closest" depend on which type happened to be checked first.
func find_closest_loadable():
	var player = PlayerManager.player
	if player == null:
		return null

	var closest_object = null
	var closest_distance = INF
	for area in player.area_2d.get_overlapping_areas():
		var node = area.get_parent()
		if not (node is BoneTurret or node is BoneWorker):
			continue
		# A full machine is not a target at all. Ranking it and then refusing would strand
		# the player beside a loaded turret, skull in hand, with an empty worker one step
		# further out.
		if node.loaded:
			continue

		var distance = player.global_position.distance_to(node.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_object = node

	return closest_object
