extends PlayerState

var is_done: bool = true

## The resting state, and also the project's safety net: it clears the attack hitbox and the
## gather sprite on every entry, which is what used to cover for the states that had no exit()
## of their own. They tear themselves down now (see PlayerState), so this is belt-and-braces
## rather than the only cleanup — but it stays, because it is the one state reached from
## everywhere and the cost is three property writes.
func enter() -> void:
	p = PlayerManager.player
	p.attack.visible = false
	p.attack.monitoring = false
	p.gather.visible = false
