# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Build & Test

_Add your build and test commands here_

```bash
# Example:
# npm install
# npm test
```

## Architecture Overview

_Add a brief overview of your project architecture_

## Conventions & Patterns

_Add your project-specific conventions here_

<!-- BEGIN godot-selftest-harness -->
## Self-Test Harness (godot-selftest-harness)

This project ships a **self-test harness**: a file-based DevTools bridge (control a
running game from the CLI), headless lint + unit-test runners (no game needed), and a
diff-aware **`/verify`** pre-commit gate. It is game-agnostic; project-specific behavior
is discovered at runtime or read from the config file below.

### DEVELOPMENT RULE (REQUIRED)
After **any** gameplay, script, or scene change, run **`/verify`** before considering the
work complete — don't wait for a commit request. It runs lint + tests, launches the game
muted, and asserts your actual diff at runtime (catching errors lint/tests can't).
Headless lint and unit tests need **no running game**; run them anytime:

```bash
godot --headless --path . --script res://tools/lint_project.gd   # UID + scene lint
godot --headless --path . --script res://tools/run_tests.gd      # unit tests (test_dir)
```

### Command cheat-sheet (`python3 tools/devtools.py <verb>`)
Launch first: `godot --path . --mute &` then `sleep 5 && python3 tools/devtools.py ping`.

| Verb | Use |
|---|---|
| `ping` / `quit` | Confirm bridge is live / shut game down cleanly |
| `scene-tree` | Discover root scene name + node paths (don't assume names) |
| `get-state --node PATH` | Read a node's properties (verbose — prefer one property) |
| `set-state --node PATH --property N --value V` | Set raw property (bypasses setters/signals) |
| `run-method --node PATH --method N --args "[...]"` | Call a method — preferred when a signal should fire |
| `node-bounds PATH` | Exact position/size (deterministic layout ground truth) |
| `ui-snapshot` / `ui-snapshot-diff` / `save-ui-baseline` | Structured UI state vs baseline |
| `validate-all` / `validate-ui` | Scene + UI layout validation (expect 0 issues) |
| `performance` | FPS vs `fps_min`, orphan nodes vs `orphan_max` |
| `input <press\|release\|tap\|clear\|list\|sequence>` | Simulate input actions |
| `set-game-speed N` / `wait-frames N` | Speed up / step time deterministically |
| `clear-nodes --group G` (or `--method`/`--class`) | Free matching nodes |
| `screenshot` | Visual check only (`sleep 0.5`–`1` after a state change) |
| `list-commands` | Discover all registered verbs (generic + project) |
| `cmd <verb> --args '{...}'` | Invoke any project-registered verb |

### Add project-specific debug verbs
Register domain verbs in `res://devtools_ext/commands.gd` (loaded after generic verbs,
last-writer-wins). Each handler returns exactly `{success:bool, message:String, data:Dictionary}`.

```gdscript
func register_commands(dev: Node) -> void:
    dev.register_command("spawn_enemy", func(args): 
        return {"success": true, "message": "ok", "data": {}})
```

Reach them from the CLI via `cmd spawn_enemy --args '{"count":3}'`; discover them via
`list-commands`. Use these for setup/trigger steps the generic primitives can't express.

**Attach liveness to every reply.** Register one status provider and its Dictionary is
merged into *every* response as `status` — the fact you need on every read and never
remember to ask for separately. Without it, a session that has silently died or frozen
keeps answering with well-formed zeros, which looks exactly like a clean pass.

```gdscript
    dev.register_status_provider(func(_args):
        var p = dev.get_tree().get_first_node_in_group("player")
        return {"player": "absent"} if p == null else {"player": "dead" if p.is_dead else "alive"})
```

Pair it with verbs that can *undo* the dead state (a `revive_player` that clears the
flag and leaves the death state, or a `god_mode` toggle). Restoring a health value is
usually not enough on its own — the death flag and state machine outlive it, so the
run stays frozen and unrescuable short of a relaunch.

### Config
`res://addons/godot_selftest/devtools_config.json` holds thresholds and hooks:
`fps_min`, `orphan_max`, `mute`, `main_scene`, `entry_hook {node_path, method}` (advances
past a menu into the playable scene), `test_dir`, `scan_root`, `hud_layer_name`.

### Token-aware
- Prefer `node-bounds` / `ui-snapshot` (compact, deterministic) over `screenshot`; only
  open a screenshot PNG when a genuine **visual** regression is suspected.
- `get-state` dumps all node properties — read the specific property you need.
- Run `/verify` **inline**; don't wrap routine validation in subagents/workflows.
- Launch with `--mute` for automated testing.

### (Re)install
Run **`/scaffold-godot-harness`** to install or refresh the harness. Re-running it also
refreshes this very section in place (it never duplicates it).
<!-- END godot-selftest-harness -->
