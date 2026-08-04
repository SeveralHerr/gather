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


## Planting pays nothing. Build xp is per cell and never refunded, so with the item recoverable
## it made one bush walked across fresh ground worth 1 xp a tile: plant, uproot, plant one over.
## Bounded by the buildable area rather than infinite, which is why it survived the pass that
## closed the uproot loop — but it is still xp for moving a bush around, and a bush is now the
## one placeable that pays for none of its three actions.
##
## Nothing is written to LevelUpManager.built_cells either. A cell in that ledger has "already
## paid", and this one never did — a wall put up there later is a genuine first build and should
## still score.
func awards_build_xp() -> bool:
	return false


func use(slot_data):
	var before: int = slot_data.count

	_place(slot_data, false)

	if slot_data.count >= before:
		return

	var cell = _placed_cell(PlayerManager.player)
	if cell == null:
		return

	BerryBush.mark_planted(cell)
