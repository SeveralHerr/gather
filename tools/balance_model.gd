@tool
extends SceneTree

## Launcher for the balance model. See tools/balance_model_impl.gd for what it computes.
##
## The work lives in a separate script that is load()ed at runtime rather than referenced
## here, and that split is load-bearing: under `--script` Godot compiles this file before
## the autoloads exist, so any global class that mentions `GameItems`, `PlayerManager` or
## `GameSoundManager` — which is most of the game — fails to compile with
## `Identifier not found`, and the run dies before _initialize(). tools/run_tests.gd loads
## its test scripts the same way for the same reason.

func _initialize() -> void:
	var impl = load("res://tools/balance_model_impl.gd").new()
	quit(impl.run())
