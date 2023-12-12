extends GameItem
class_name GameItemNet
	
func use(_target):
	PlayerManager.player.state_machine.change_to("PlayerNet")
	pass
