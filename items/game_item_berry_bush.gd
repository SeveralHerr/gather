extends GameItemPlaceable
class_name GameItemBerryBush

## An uprooted berry bush, in the inventory and on its way back into the ground.
##
## Placement itself is the ordinary GameItemPlaceable path — the only thing added is telling
## the bush that is about to exist that it was PLANTED rather than grown. A planted bush comes
## up bare and waits out a full regrow; see BerryBush._planted_cells for why that matters.
##
## The mark is written only when the placement actually landed. PlayerManager.place_tile does
## nothing at all on an occupied cell and reports that only by leaving the stack count alone,
## which is the same signal the base class watches to decide whether to award build xp.


func use(slot_data):
	var before: int = slot_data.count

	_place(slot_data, false)

	if slot_data.count >= before:
		return

	var cell = _placed_cell(PlayerManager.player)
	if cell == null:
		return

	BerryBush.mark_planted(cell)
