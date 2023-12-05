extends Node

var fsm: StateMachine
var p : Player
var is_done: bool = true

func enter():
	p = PlayerManager.player
	p.attack.visible = false
	p.attack.monitoring = false
	p.gather.visible = false
	pass
