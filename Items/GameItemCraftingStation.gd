extends GameItem
class_name GameItemCraftingStation

func use(target):
	PlayerManager.player.state_machine.change_to("PlayerAttack")
	pass
