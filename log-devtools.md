# Devtools / `/verify` Gaps Log

Running log of gaps in the `/verify` workflow or the devtools harness, and the smallest
improvement that would have closed each one.

**Why this file exists.** The harness can only be improved from evidence, and the evidence
is perishable — the moment a workaround is found, the friction that forced it is forgotten.
This log is the harness's feedback channel: entries here are what later get upstreamed into
`godot-selftest-harness` itself, so a gap logged in one game becomes a fixed feature for
every game.

**Append a new entry at the end of every response** (a `Stop` hook in
`.claude/settings.json` reminds you when a code change lands without one). An honest
"no gaps this turn" line is a real entry — it is what makes the absence of a gap
distinguishable from a forgotten log.

## Format

```markdown
## YYYY-MM-DD — <what the response did>

- Gap: **<what was missing>** — <evidence: the command run, the output it gave, the
  workaround used instead>
  - Improvement: <the smallest change that would have closed it>
```

Guidelines that make an entry useful later:

- **Quote the evidence.** `devtools.py: error: unrecognized arguments: --property scale`
  is actionable; "get-state was awkward" is not.
- **Say what you did instead.** The workaround is the measure of the gap's cost.
- **Prefer the smallest fix.** "Add `--property` (repeatable) to `get-state`" beats
  "improve state inspection".
- **Note recurrences.** A gap that bites a second time is a stronger signal than a new
  one — say so rather than writing a fresh entry as if it were novel.
- **Log closures too.** When a gap gets fixed, record that, and record whether the fix
  actually paid off on the next run.

---

<!-- Entries below, newest at the bottom. -->

## 2026-08-01 — Re-ran `/scaffold-godot-harness` to refresh the harness in place

- Gap: **Scaffold overwrote `tools/*` and left `.bak` files it can never clean up** —
  step 4 backs up on any byte difference, so a pure version bump of the harness's own
  files produced `tools/lint_project.gd.bak`, `tools/run_tests.gd.bak`,
  `tools/devtools.py.bak` as untracked repo noise. Diffing each showed only upstream
  template evolution (new flags, new docstrings); no project edits existed to protect.
  Workaround: diffed all three by hand to confirm they were disposable, then reported
  them to the user rather than deleting unprompted.
  - [G-001] status: open | seen: 1 | harness: 0.4.0
  - Improvement: have step 4 skip the backup when the existing file matches a *known
    previous template version* — e.g. stamp a `# harness-version: N` header into copied
    tools and only back up when the target's stamp is absent or modified.

- Gap: **Step 7's config patch has no way to know a key was deliberately customized** —
  merging `hud_layer_name` worked only because the existing value (`UI2`) happened to be
  non-default; a project that legitimately set it back to `"HUD"` would be
  indistinguishable from an unpatched default on the next refresh.
  - [G-002] status: open | seen: 1 | harness: 0.4.0
  - Improvement: write a `"_scaffold_defaults"` sidecar block into
    `devtools_config.json` recording the values scaffold last wrote, so a later run can
    diff "what I wrote" against "what's there now" and only overwrite untouched keys.

- Gap: **No verb reports which harness version is installed** — deciding whether this
  refresh was a no-op or a real upgrade required diffing template files against the
  repo by hand. `list-commands` shows verbs but not the harness revision.
  Bit again 2026-08-01 during the itch.io/mobile `/verify` run: the workflow now *instructs*
  reading it ("`harness:` The installed version, from `python3 tools/devtools.py
  harness-version`"), but the verb still does not exist —
  `python tools/devtools.py harness-version` printed
  `usage: devtools.py [-h] ... {ping,screenshot,validate,...,node-bounds}`, i.e. an argparse
  rejection, so every `harness:` field in this file is a hand-guess.
  - [G-003] status: open | seen: 2 | harness: 0.4.0
  - Improvement: add a `harness-version` verb (and a line in `lint_project.gd`'s header
    output) reporting the template revision the installed files came from.

## 2026-08-01 — Forager pass: continuous spawning, land purchase, ore tiers, XP splash (in progress)

- Gap: **`run_tests.gd --filter` matches method names only, so a filter that hits nothing
  exits 0 with a full skip** — a subagent ran
  `run_tests.gd -- --filter spawner` on a new `test/unit/test_enemy_spawner.gd`; every
  test in the suite was skipped and the runner still reported
  `Total: 0 | Passed: 0 | Failed: 0` with `EXIT=0`. That is byte-for-byte what a clean
  pass looks like to an agent grepping for the exit code. Workaround: fell back to
  running the whole suite, which defeats the point of a filter when several agents are
  adding test files concurrently.
  - [G-004] status: open | seen: 2 | harness: 0.4.0
  - Improvement: match `--filter` against the test *script filename* as well as the
    method name, and make a run that selected zero tests exit non-zero (or at minimum
    print `filter '<x>' selected 0 of N tests` as a warning).

- Gap: **Nothing in the harness lets more than one agent verify at a time** — the bridge
  is a single command/result file pair, so four parallel subagents had to be forbidden
  from launching the game at all, and one owner (me) does every runtime check serially.
  `godot --headless --path . --import` is a second shared-state hazard: the class cache
  is a single file, so a new `class_name` from any agent forces a global rebuild.
  Workaround: pre-created stub files declaring all four new `class_name`s, ran `--import`
  once up front, then told every agent not to run it.
  - [G-005] status: open | seen: 1 | harness: 0.4.0
  - Improvement: teach `tools/devtools.py` to derive its command/result filenames from a
    `--session` id (defaulting to the current behaviour), and have `scaffold` document a
    `--session` + `use_custom_user_dir` recipe, so N agents can each own an instance.

- Gap: **New scripts created outside the editor have no `.uid` sidecar and lint does not
  notice** — `lint_project.gd` reported `UIDs: OK` for `test/unit/test_enemy_spawner.gd`
  while the file had no sidecar at all, because the check only validates sidecars that
  exist. CLAUDE.md requires committing them alongside the script.
  - [G-006] status: open | seen: 1 | harness: 0.4.0
  - Improvement: have the UID pass flag `.gd` files under `scan_root`/`test_dir` with no
    `.uid` sidecar as a warning, so the omission is visible before commit rather than at
    review time.

- Gap (second sighting, same turn): the `--filter` gap above was hit independently by a
  second agent — `run_tests.gd -- --filter skill` selected 7 methods and silently missed
  most of `test_skill_tree.gd` and all of `test_ore_chain.gd`, so it too fell back to the
  full 111-test suite. Two of four agents hit it, which makes it the highest-value fix in
  this log for concurrent work.
  - [G-004] status: open | seen: 2 | harness: 0.4.0
  - Improvement (restated concretely): add `--file <basename>` to `run_tests.gd`, matched
    against the test script path, so an agent can run exactly the file it owns.

## 2026-08-01 — Reviewed the self-learning loop itself (no code changed)

- Gap: **No entry in this log has a status, so "is this already fixed?" is unanswerable
  from the file** — the Format section says "Log closures too", but every one of the six
  entries reads as permanently open. Answering whether the loop had ever actually closed
  required leaving the project entirely: `git -C ~/Documents/GitHub/godot-selftest-harness
  log --oneline` showed `922c45d Ship the devtools gaps log, and close the gaps it recorded
  (0.4.0)`. Nothing in this repo records that.
  - [G-007] status: open | seen: 1 | harness: 0.4.0
  - Improvement: give each gap a stable id and a status line —
    `- [G-007] status: open | fixed-in: 0.5.0 | seen: 2` — so a fixed gap can be filtered
    out before the log is pasted back, and recurrences can be counted instead of narrated.

- Gap: **The `Stop` hook checks that the log file changed, not that anything was said** —
  `tools/check_devtools_log.py:132` is `missing = [f for f in log_files if f not in
  normalized]`, so any byte-level change to `log-devtools.md` satisfies it. A session that
  appends "no gaps this turn" forever passes the check forever, which is precisely the
  decay mode the hook exists to catch.
  - [G-008] status: open | seen: 1 | harness: 0.4.0
  - Improvement: require an entry whose `## ` heading carries today's date, rather than
    treating the file's mere presence in `git status` as compliance.

- Gap: **Nothing records which harness version a gap was observed against** — this log
  already flagged the missing `harness-version` verb on 2026-08-01, and the absence bites
  again here: a gap logged before an upgrade cannot be distinguished from a regression
  after one. Second sighting of the same underlying miss.
  - [G-003] status: open | seen: 2 | harness: 0.4.0
  - Improvement: have `/verify` stamp the installed harness revision into each entry's
    heading automatically, so version is captured without the model having to remember.

- Gap: **Nothing detects a second Godot instance still holding the bridge**, and the
  error it produces points at the wrong cause. A prior session's process was still
  alive; `devtools.py ping` answered `game not running: 'ping' was never picked up`
  while `tasklist | grep -i godot` showed **two** live PIDs, and a save/load test in
  between returned an empty reply that crashed the python client with
  `json.decoder.JSONDecodeError: Expecting value: line 1 column 1`. I spent a cycle
  hunting a non-existent load crash before checking the process list. The existing
  "Crossed replies" detection did not fire, because the stale instance was answering
  every request — just for a different world.
  - [G-009] status: open | seen: 1 | harness: 0.4.0
  - Improvement: have the DevTools autoload write a `devtools_owner.json` with its PID
    and start time, and have `devtools.py` refuse to run (naming the other PID) when a
    live owner file belongs to a different process. Failing that, make `ping`'s
    "game not running" message list matching OS processes.

- Gap: **`run-method` requires an absolute `/root/...` path while every other verb takes
  the short form.** `--node Main/InputManager` returned `Failed: Node not found:
  Main/InputManager`, but `cmd`-registered verbs resolve `Main/...` fine via
  `get_tree().root.get_node_or_null`. The inconsistency cost a debugging round on a
  path that was actually correct.
  - [G-010] status: open | seen: 1 | harness: 0.4.0
  - Improvement: have `run-method` / `get-state` / `set-state` retry a failed lookup
    with `/root/` prefixed, or say so in the error text.

- Gap: **`saveObject()` failures are structurally invisible** — a `-> Dictionary` method
  that raises still returns `{}`, so `SaveLoad` wrote a blank line and lost a whole
  node's state with no failed assertion anywhere. This is the same trap the test runner
  has (`gather-1t9`), but in game code, and it hid a real data-loss bug
  (`gather-hxa.8`) for as long as the file has existed.
  - [G-011] status: open | seen: 1 | harness: 0.4.0
  - Improvement: add a `save_roundtrip` verb that calls every `SaveLoad` member's
    `saveObject()` and reports any that return an empty dict or omit `filepath` —
    a one-call check for a class of bug that is otherwise silent.

- Verified this turn with no gap: `spawn_stats`, `coin_count`, `land_state`, `buy_land`,
  `land_panel`, `splash`, `spawn_resource` and `goto_resource --args '{"name":...}'` all
  behaved as intended, and the status provider's new `gold` / `live_enemies` /
  `spawner_running` / `live_splashes` fields caught state that no other read exposed.

## 2026-08-01 — Wrote an upstream handoff prompt for harness 0.5.0 (no game code changed)

- Gap (second sighting): **the missing upstream path, logged earlier today, is now the
  only reason this turn had work to do.** Producing the handoff meant reading this log,
  `~/Documents/GitHub/godot-selftest-harness/log-devtools.md`, `plugin.json` (`0.4.0`),
  `templates/tools/run_tests.gd:174` and the scaffold step headings by hand, then writing
  the result to `prompt-harness-0.5.0.md` for a human to carry across. Confirmed the
  transport has never run for this batch: the harness log's only heading is
  `## 2026-08-01 — Ship the gaps log, close what it recorded (0.4.0)`, so all six of this
  project's gaps are still local.
  - [G-012] status: open | seen: 2 | harness: 0.4.0
  - Improvement: as already filed — an `upstream_gaps` script that appends open gaps to
    the harness repo's log, deduped by id. The prompt written this turn is the manual
    version of exactly that script, which is the strongest evidence yet that it should
    exist.

## 2026-08-01 — commit the Forager pass

- No gaps this turn. Branching, staging and three commits needed nothing the harness
  provides; the pre-commit gate (`lint_project.gd` exit 0, `run_tests.gd` 114/114, zero
  `SCRIPT ERROR` lines) was re-run against the committed tree and agreed with the
  pre-commit run.

## 2026-08-01 — itch.io web deploy workflow + mobile touch controls (fan-out)

- Gap: **No harness check that the project's renderer is web-exportable** — gather ships
  `config/features=PackedStringArray("4.7", "Forward Plus")` while a Godot 4 web export only
  runs on `gl_compatibility`. Nothing in `lint_project.gd` or `/verify` flags this; it was
  caught only by hand-diffing `project.godot` against the AtomicRobot repo, which has
  `renderer/rendering_method="gl_compatibility"`. A Forward+ web build exports cleanly and
  then fails to start in the browser — the failure surfaces on itch.io, not in CI.
  - [G-013] status: open | seen: 1 | harness: 0.4.0
  - Improvement: add a lint rule that reads `renderer/rendering_method` (plus its `.web` /
    `.mobile` overrides) and errors when a `Web` preset exists in `export_presets.cfg`
    without a compatibility override.

- Gap: **`/verify` has no headless export check** — the harness validates lint, tests and
  runtime, but nothing exercises `--export-release`, so a broken or missing export preset is
  invisible until CI. The new `Web` preset in `export_presets.cfg` could not be validated
  locally at all; the deploy agent reported "I did not run the Godot binary, so the new preset
  has not been round-tripped through the editor."
  - [G-014] status: open | seen: 1 | harness: 0.4.0
  - Improvement: a `tools/check_exports.gd` that enumerates presets, asserts each has an
    `export_path` and that the matching export template is installed, runnable headless.

- Gap: **Bridge is single-instance, so parallel agents cannot self-verify** — the known
  one-command/one-result-file limitation meant all three subagents had to be forbidden from
  running Godot at all (`--import` also races on `.godot/`), pushing every check onto the
  orchestrator serially after fan-out.
  - [G-005] status: open | seen: 3 | harness: 0.4.0
  - Improvement: have `devtools.py` and the headless runners namespace their bridge and import
    cache per-instance (env var or `--userdata`-style flag), so N agents can verify in parallel.

- Gap: **Nothing validates a vendored addon's UIDs against the host project before lint runs** —
  the ported `addons/virtual_joystick/test/test.tscn` carried AtomicRobot's icon UID
  (`uid="uid://cw7a6wede53n1"` for `res://icon.svg`) while gather's is `uid://c6knbegisd067`,
  so `lint_project.gd` (`scan_root: "res://"`) would have reported it as a project defect
  rather than as imported third-party debt. Found by hand-diffing, patched by hand.
  - [G-015] status: open | seen: 1 | harness: 0.4.0
  - Improvement: teach `lint_project.gd` a `--baseline`-style vendored-path skip list (or reuse
    the existing `--baseline` split) so `addons/*` findings report as PRE-EXISTING/VENDORED
    instead of NEW.

- Gap: **No way to read whether an input action is currently pressed** — the whole point of
  the touch overlay is that a button latches a real `InputMap` action and later releases it,
  but `input list` reports only the *bindings*:
  `gather: E - Physical` / `attack: Space - Physical`. There is no `Input.is_action_pressed`
  readout, so proving "the MINE button is holding `gather` right now" had to be done
  indirectly through whatever gameplay node happened to expose the state —
  `cmd player_state` (`state=PlayerGather`) for gather, and
  `get-state --node /root/Main/DestroyManager --property is_holding_e` for destroy. A project
  without such a node could not assert a held action at all.
  - [G-021] status: open | seen: 1 | harness: 0.4.0
  - Improvement: add `input state [ACTION...]` returning
    `{action: {pressed: bool, strength: float}}` from `Input.is_action_pressed` /
    `get_action_strength`, so a hold/release pair is assertable without a gameplay proxy.

- Gap: **The drift check names files but cannot say which side is ahead** — Phase 0 reported
  `DRIFT:` on all six harness files (`dev_tools.gd`, `scene_validator.gd`, `devtools.py`,
  `lint_project.gd`, `run_tests.gd`, `check_devtools_log.py`) while `tools/*.bak` copies from
  the last in-place refresh sat untracked beside them. `cmp -s` gives a boolean, so
  "the project patched this locally" and "the install predates the plugin" look identical, and
  the workflow's own instruction to compare `git log -1 --format=%cd` fails for the plugin side
  because those templates live outside this repo. Resolved by reporting drift unresolved.
  - [G-022] status: open | seen: 1 | harness: 0.4.0
  - Improvement: stamp a `# harness-template: <sha>` line into each copied template at scaffold
    time; the drift check then compares stamps and reports ahead/behind instead of just differs.
    Closes with [G-003], which is the same missing-version-identity problem at verb level.

## 2026-08-01 — Enlarged the game window to 1920x1080 and re-anchored every UI (gather-6fx)

- Gap: **`set-state` cannot write a vector-typed property** — the documented `run-method`
  coercion gap (`gather-6sp`) also applies to `set-state`. Resizing the viewport to exercise
  `camera_hud.gd`'s `size_changed` handler needed `/root.size`, and every value form silently
  produced garbage rather than erroring:
  ```
  $ devtools.py set-state --node "/root" --property size --value '{"x":1280,"y":720}'
  State updated
  $ devtools.py get-state --node "/root" --property size
  size: (232, 64)
  ```
  `--value '[1280,720]'` produced the same `(232, 64)`. The run still proved the reflow
  (the HUD tracked 232x64 exactly: `Rect: -160, -62, 47x13` == `232/4.935 x 64/4.935`), but
  by accident — the resize I asked for is not the resize I got, and nothing said so.
  - [G-016] status: open | seen: 1 | harness: 0.4.0
  - Improvement: have `set-state` coerce a 2/3/4-element array or an `{x,y,...}` dict to the
    property's declared type via `type_convert()`, and **fail loudly** when the target
    property is a vector type and the value cannot be converted, instead of writing whatever
    the bad cast yields and answering `State updated`.

- Gap: **No verb resizes the window, so the single most important behaviour of a
  resolution change is untestable by design** — `/verify` has `set-game-speed`,
  `wait-frames` and `step-time` for the time axis and nothing at all for the viewport axis.
  Every anchor, every `size_changed` handler and every `get_viewport_rect()` caller in the
  project is only ever exercised at one size unless you quit and relaunch with
  `--resolution WxH`, which costs a full boot per data point and cannot test the
  *transition* at all.
  - [G-017] status: open | seen: 1 | harness: 0.4.0
  - Improvement: add a generic `set-resolution --size WxH` verb that calls
    `DisplayServer.window_set_size()` and returns the resulting `get_viewport_rect().size`,
    so a caller can assert the resize landed before asserting on layout.

- Gap: **`validate-ui` applies screen-space checks to world-space Controls, so its verdict
  is a function of where the player is standing** — this project's diegetic HUD hangs off
  `Player/Camera2D`, and `ui_negative_pos` reports its *global* position:
  ```
  [WARN] ui_negative_pos: Label 'Label3' has negative position (-267, -51)
  ```
  That number is the player's world position plus an offset; it says nothing about layout.
  9 of the run's 9 findings were this. Deciding whether the change regressed anything took a
  full `git stash` + relaunch + `validate-ui` on HEAD to compare (HEAD: 10 issues, branch: 9
  — the change removes `ui_zero_size` on `UI`), which is exactly the hand-triage that lint's
  `--baseline` exists to abolish.
  - [G-018] status: open | seen: 1 | harness: 0.4.0
  - Improvement: give `validate-ui` the same `--baseline PATH` / `--baseline-write PATH`
    split `lint_project.gd` already has, so UI findings report as `NEW` vs `PRE-EXISTING`;
    and skip `ui_negative_pos` for Controls whose canvas ancestor is not a `CanvasLayer`,
    where negative coordinates are the normal case rather than a defect.

- Gap: **`input press <action>` does not drive the gather loop, and the failure is
  indistinguishable from a real bug** — after `cmd goto_resource` put the player 6 units from
  a Stone node, holding `gather` for 1.8s left `state: PlayerIdle` and `xp: 0`, with the
  census unchanged. Confirming this was pre-existing rather than a regression from the scene
  edits cost another stash + relaunch cycle on HEAD (identical `PlayerIdle`). CLAUDE.md
  already warns that driving gather through the hotbar's stop signal leaves the timer
  running; the *start* side has the same class of problem and is undocumented.
  - [G-019] status: open | seen: 1 | harness: 0.4.0
  - Improvement: add a project verb `gather_once` in `devtools_ext/commands.gd` that calls
    `ResourceManager2.start_removing_resource()` directly and returns the node it engaged
    (or an explicit `"no resource in reach"`), so a gather assertion tests the gather loop
    instead of testing input plumbing.

- Gap: **Harness drift is detected but the report has no bearing on the run** — Phase 0
  flagged `DRIFT: tools/check_devtools_log.py differs from the plugin template`, with the
  plugin ahead (`Sat Aug 1 15:45:28 2026` vs the project's `Sat Aug 1 14:33:55 2026`). Three
  stale `.bak` files from an earlier refresh (`tools/devtools.py.bak`, `tools/lint_project.gd.bak`,
  `tools/run_tests.gd.bak`) are still sitting untracked in the tree, which is what a
  half-finished refresh looks like.
  - [G-020] status: open | seen: 1 | harness: 0.4.0
  - Improvement: have `/scaffold-godot-harness` delete its own `.bak` files once the refreshed
    file passes a syntax check, so a completed refresh leaves no residue to mistake for drift.

- Closure (paid off): **the exit-`2` contract on `run_tests.gd` caught a real "you verified
  nothing"** — a final gate re-run against the tree picked up `test/unit/test_mobile_controls.gd`
  (in-flight work from outside this session) and reported:
  ```
  tests exit=2
    Total: 114  |  Passed: 114  |  Failed: 0  |  Skipped: 0
  SCRIPT ERROR: Parse Error: Identifier "MobileControls" not declared in the current scope.
    [ERR]  res://test/unit/test_mobile_controls.gd: Script failed to compile (see stderr)
  ```
  The summary line alone reads as a clean pass; only the exit code and the `[ERR]` line say
  otherwise. `--import` then took the suite to `121 passed, exit 0`. This is the fix from
  the earlier "0 tests discovered, ALL TESTS PASSED" gap working exactly as intended.

## 2026-08-01 — Commit step (window enlargement + in-flight mobile work)

- No gaps this turn. Committing exercised no `/verify` or devtools surface. Worth noting for
  the record only: two files (`project.godot`, `log-devtools.md`) carried both this session's
  edits and concurrent work from outside it, and `git add -p` is unavailable to agents, so the
  split was done by staging reconstructed blobs with `git hash-object -w` + `git update-index`.
  That is a git-workflow constraint, not a harness gap, and it worked — `git diff HEAD` is
  empty and `project.godot` reassembled with all eight sections intact.

## 2026-08-01 — /simplify cleanup pass (mobile controls, camera HUD, CI, dead .bak files)

- Gap: **the harness install predates `verify_ledger.py` and `harness-version`** — `/verify`
  Phase 5 says to record the run, but:
  ```
  python tools/verify_ledger.py record --run .devtools/run.json
  can't open file '...\tools\verify_ledger.py': [Errno 2] No such file or directory
  ```
  and `grep -m1 'harness-version:' tools/lint_project.gd` printed nothing, so the `harness:`
  field every Phase 6 gap is supposed to carry cannot be filled either. The run was verified
  but not recorded, which is exactly the history the ledger exists to accumulate.
  - [G-023] status: open | seen: 1 | harness: unknown (no version marker installed)
  - Improvement: re-run `/scaffold-godot-harness` to pick up `verify_ledger.py` +
    `tools/upstream_gaps.py` + the version marker. Failing that, `/verify` should detect the
    missing script and say "ledger not installed" rather than surfacing a raw Python traceback
    that reads like a broken command.

- Gap: **`gather_stats` cannot observe an in-progress gather** — the one verb named for the
  gather loop returns only world state (`cap`, `census`, `land_tiles`, `live_nodes`,
  `spawnable`, `tuning`). Holding the touch MINE button and re-reading it produced a
  byte-identical response, so the hold was unobservable through the verb that exists for it:
  ```
  {'cap': 40, 'land_tiles': 111, 'live_nodes': 40, 'spawnable': [...], 'tuning': {...}}
  ```
  Falling back to `get-state --node /root/Main/ResourceManager --property hold_timer` returned
  `@Timer@14:<Timer#92090140860>` — an opaque object id, not a remaining time. The hold was
  verified indirectly instead (the ITEM button cycling `HotBarInventory.selected_index` 0 -> 1
  proves the same touch -> `_input` -> `send_action` path).
  - [G-024] status: open | seen: 1 | harness: unknown
  - Improvement: add `is_gathering`, `hold_time_left` and `target_resource` to the
    `gather_stats` payload — three fields off `ResourceManager2`, and the gather loop becomes
    assertable at runtime instead of only in unit tests.

- Gap: **git-bash rewrites `/root/...` node paths into Windows paths** — every `--node`
  argument starting with `/root` is mangled by MSYS path conversion before Python sees it:
  ```
  Unknown property on C:/Program Files/Git/root/Main/ResourceManager: removing_resource
  ```
  `devtools.py` normalizes it back (the node resolved and `hold_timer` returned fine), but the
  mangled path is echoed in every error message, so a genuine typo and a path-conversion
  artifact look identical and the first instinct is to debug the wrong thing.
  - [G-025] status: open | seen: 1 | harness: unknown
  - Improvement: echo the *normalized* path in error messages, not the raw argv one.

- Gap: **`.gdignore` does not exclude a directory from `validate-all`** — added
  `addons/virtual_joystick/{previews,test}/.gdignore` so the vendored demo leaves the import
  and lint scan, but the validator still walks it:
  ```
  res://addons/virtual_joystick/test/test.tscn:
    [INFO] relative_nodepath: Node 'Player' property 'joystick_left' uses relative path: ...
  ```
  Two of the 28 validate-all findings are from a directory Godot itself is told to skip.
  - [G-026] status: open | seen: 1 | harness: unknown
  - Improvement: have `scene_validator.gd` skip any directory containing a `.gdignore`, the
    same rule the engine applies.
