# Gather

Gather is a compact single-scene Godot 4.7 game focused on gathering, crafting, and survival.
It combines a simple item-driven gather loop with resource nodes, enemies, crafting stations, and a built-in self-test harness for reliable development.

![Gather screenshot](docs/screenshot.png)

## Key Features

- Resource gathering with tool-based timing and bonus yields
- Crafting stations, recipes, and player progression
- Enemies, waves, and pickup/vacuum systems
- Save/load support using a `SaveLoad` group and JSON persistence
- Built-in Godot self-test harness for linting, unit tests, and runtime validation
- Beads issue tracking support via `.beads`

## Project Structure

All files and folders use snake_case; PascalCase is reserved for `class_name`
declarations and node names.

- `main.tscn` / `main.gd` — core scene, world generation, tile writes, and save format
- `player/` — player node, manager, and reach; `player/states/` holds the player state machine
- `enemies/` — enemy scenes and wave spawning; `enemies/states/` holds the enemy state machine
- `items/` — item and resource definitions, the shared `Types.Item` enum, pickups
- `inventory/` — inventory data, hotbar, and slot systems
- `crafting/` — crafting recipes, stations, and UI
- `turrets/` — turret and projectile logic
- `world/` — camera, resource gathering and spawning, plus `resource_nodes/`,
  `tile_scenes/`, and `vfx/`
- `systems/` — input, health, save/load, sound, level-up, and collision helpers
- `ui/` — HUD elements such as the gather progress bar and floating damage numbers
- `assets/` — `art/`, `audio/`, `tilesets/`, `materials/`, and `shaders/`
- `tools/` — lint and test runner scripts
- `test/unit/` — headless unit tests
- `devtools_ext/` — project-specific DevTools commands
- `addons/godot_selftest/` — test harness implementation

## Requirements

- Godot Engine 4.7.x
- No external package manager required

## Setup

1. Open the project in Godot:
   ```bash
   "GODOT_PATH" --path . --mute
   ```
2. After adding or changing `class_name` scripts, run the import step:
   ```bash
   "GODOT_PATH" --headless --path . --import
   ```

## Run

Launch the game:
```bash
"GODOT_PATH" --path . --mute
```

## Linting and Testing

Run project linting:
```bash
"GODOT_PATH" --headless --path . --script res://tools/lint_project.gd
```

Run unit tests:
```bash
"GODOT_PATH" --headless --path . --script res://tools/run_tests.gd
```

## Development Workflow

- Use `bd` for issue tracking and work management
- Keep `project.godot` and `class_name` imports up to date
- Use `tools/devtools.py` and the DevTools bridge for automated runtime validation


