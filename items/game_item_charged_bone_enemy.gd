extends GameItem
class_name GameItemChargedBoneEnemy

## A charged skeleton captured with the net (gather-8ft). The blue skull is caught exactly the
## way an ordinary one is, so this is GameItemBoneEnemy's sibling: using it drops the skull
## into the closest bone machine the player is standing inside — a BoneTurret or a BoneWorker —
## and charges that machine in the same action. Loading and charging are one step because the
## item IS the charged skull; there is no state in which a machine has taken this skull and is
## running uncharged.
##
## ## Why this duplicates GameItemBoneEnemy instead of extending it
##
## The parent's `use()` ends in `remove_by_type(Types.Item.BoneEnemy)`, hardcoded. An override
## that forgot to replace that line would spend an ORDINARY skull out of the pack and leave the
## charged one sitting there, which the player reads as the charged skull being unusable and
## their plain skulls evaporating — a loss with no error and no obvious cause. Sixty lines of
## near-identical search is a cheaper thing to carry than a base class whose one inherited
## method silently deletes the wrong item. Duplicating also keeps `is GameItemBoneEnemy`
## meaning "the plain skull", which is what any later type check will assume.


## The stack is spent only when a machine actually took the skull, and only after BOTH writes
## landed. Removing it first is the silent loss GameItemBoneEnemy documents: a use that reached
## nothing at all consumed the item and reported nothing. Ordering the removal after
## `make_charged()` extends that rule to the second half — a skull spent on a load that somehow
## did not charge would be a rare drop turned into an ordinary one, which is worse than losing
## it outright because the machine looks like it worked.
func use(_target):
	var machine = find_closest_loadable()
	if machine == null:
		# can_use() already answered this, but use() is reachable from PlayerManager directly
		# and a null here would raise on the next line — inside an untyped `use`, which aborts
		# the method in silence.
		return

	machine.set_loaded()
	machine.make_charged()
	PlayerManager.player.inventory_data.remove_by_type(Types.Item.ChargedBoneEnemy)


## Whether using the skull right now would load anything.
##
## `use_slot_data()` consults this for every item now (gather-tan), so this is the live guard
## rather than advisory. `use()` still checks for itself, and both ask the one search function
## below — that is what stops the two answers drifting apart.
func can_use() -> bool:
	return find_closest_loadable() != null


## The nearest machine still able to take a skull, from the areas the player overlaps.
##
## One pass over that list rather than one per machine type: two passes would double the work
## and make "whichever is closest" depend on which type happened to be checked first.
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
		# An EMPTY machine only. A charged skull loads a machine, it does not retrofit one that
		# is already working: skipping full machines is what stops the player standing beside a
		# loaded turret and having the skull ranked toward it, with an empty worker one step
		# further out that would have taken it.
		if node.loaded:
			continue

		var distance = player.global_position.distance_to(node.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_object = node

	return closest_object
