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
  - [G-001] status: fixed | seen: 1 | harness: 0.4.0 | fixed-in: 0.7.0
  - Improvement: have step 4 skip the backup when the existing file matches a *known
    previous template version* — e.g. stamp a `# harness-version: N` header into copied
    tools and only back up when the target's stamp is absent or modified.

- Gap: **Step 7's config patch has no way to know a key was deliberately customized** —
  merging `hud_layer_name` worked only because the existing value (`UI2`) happened to be
  non-default; a project that legitimately set it back to `"HUD"` would be
  indistinguishable from an unpatched default on the next refresh.
  - [G-002] status: fixed | seen: 1 | harness: 0.4.0 | fixed-in: 0.7.0
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
  - [G-003] status: fixed | seen: 2 | harness: 0.4.0 | fixed-in: 0.7.0
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
  - [G-023] status: fixed | seen: 1 | harness: unknown (no version marker installed) | fixed-in: 0.7.0
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

## 2026-08-01 — Commit step (/simplify cleanup pass)

- No gaps this turn. Committing exercised no `/verify` or devtools surface; the tree was
  already green from the pass logged above and split cleanly into four commits with no
  staging tricks needed. Worth recording for whoever picks up [G-023]: the harness plugin
  was updated (`/plugin` -> "Updated godot-selftest-harness") *after* that gap was written,
  so re-running `/scaffold-godot-harness` may already close it — check whether
  `tools/verify_ledger.py` and a `harness-version:` marker in `tools/lint_project.gd` are
  present before re-upstreaming it.

## 2026-08-01 — Refreshed the harness to 0.7.0 (/scaffold-godot-harness)

- Closed: **[G-023] is fixed in 0.7.0.** The refresh installed `tools/verify_ledger.py`
  (`python tools/verify_ledger.py stats` now answers `No ledger yet at .devtools\verify-runs.jsonl`
  instead of `No such file or directory`) and both halves now carry a version marker —
  `# harness-version: 0.7.0` in `tools/lint_project.gd` and `HARNESS_VERSION = "0.7.0"` in
  `dev_tools.gd` / `devtools.py`. The `harness:` field on future gaps can be filled from
  `devtools.py harness-version`. Marked `fixed-in: 0.7.0` above.
- Still open: **[G-026]** — 0.7.0 added no `.gdignore` handling; `grep -n gdignore
  addons/godot_selftest/scene_validator.gd tools/lint_project.gd` returns nothing, so the
  validator still walks `addons/virtual_joystick/test/`.

- Gap: **`/scaffold-godot-harness` step 11 has no Windows branch for locating Godot** — the
  documented probe is `$GODOT_BIN` -> `/Applications/Godot.app/...` -> `command -v godot`.
  On this machine all three miss (the binary is a bare
  `/c/Users/gotmi/Documents/Godot_v4.7.1-stable_win64.exe`, never on PATH), so step 11 falls
  through to `WARN: no Godot binary found` and steps 12's smoke check would be skipped
  entirely. Only this project's own `CLAUDE.md` records the real path; a first-time scaffold
  on a Windows box would report install-success having verified nothing.
  - [G-027] status: open | seen: 1 | harness: 0.7.0
  - Improvement: add a Windows branch to the step 11 probe — glob
    `~/Documents/Godot_v*_win64.exe`, `/c/Program Files/Godot/*.exe` and
    `$LOCALAPPDATA/Programs/Godot/*.exe` — and, once found, write the resolved path into
    `devtools_config.json` as `godot_bin` so `/verify` and later refreshes stop re-deriving it.

- Also closed by this refresh, each observed directly during it:
  **[G-001]** — step 4 now hash-checks against `.harness_manifest.json` + the plugin's
  `harness_history.json`; all six replaced files reported
  `updated from an earlier version (unmodified - no backup needed)` and
  `find . -name '*.bak'` came back empty, where the old rule would have made four.
  **[G-002]** — the config merge wrote a `_scaffold_defaults` block and correctly kept both
  customized keys: `= hud_layer_name kept as "UI2" (differs from the shipped default - now
  project-owned)`, same for `main_scene`.
  **[G-003]** — `harness_version` is now a registered verb and both halves stamp `0.7.0`.

- Gap: **`--import` silently rewrites `project.godot`, dropping comments and explicit
  settings** — CLAUDE.md requires `--import` after any new `class_name` and the scaffold
  smoke check runs it, but nothing warns that Godot *rewrites the file it read*. After
  `godot --headless --path . --import`, `git diff project.godot` showed a clean tree turn
  dirty with every explanatory comment stripped and three settings deleted outright:
  ```
  -window/stretch/mode="disabled"
  -renderer/rendering_method="forward_plus"
  -renderer/rendering_method.web="gl_compatibility"
  ```
  Godot drops keys it considers default, but `.web` is the override the in-file comment says
  keeps the itch.io build from failing to start in the browser — a loss that only surfaces on
  deploy, long after the commit. It was caught only because `git status` was read again before
  staging; had the refresh been committed straight from the earlier clean status, it would have
  shipped inside a "harness refresh" commit nobody would think to check for a renderer change.
  Workaround: `git checkout -- project.godot`, then re-confirmed the `DevTools` autoload
  survived (it did — it was already committed).
  - [G-028] status: open | seen: 1 | harness: 0.7.0
  - Improvement: have the scaffolder and `/verify` snapshot `project.godot` before any
    `--import` and restore it (or diff and warn loudly) afterward — the import step needs the
    *cache* rebuilt, never the project file edited. Failing that, CLAUDE.md's `--import` rule
    should carry an explicit "check `git diff project.godot` afterward" warning.

## 2026-08-01 — Commit + merge step (harness 0.7.0 refresh)

- No further gaps this turn. The two commits, the `--no-ff` merge into `main` and the
  upstreaming all ran clean. One thing worth recording for whoever hits [G-028]: `main` was
  re-verified *after* the merge (121/121, `grep -c 'SCRIPT ERROR'` = 0) and `project.godot`
  re-checked by hand — 21 comments and all three settings present. Running the test suite
  does **not** dirty `project.godot`; only `--import` does, which narrows the blast radius of
  that gap to the import step alone.

## 2026-08-01 — Reimagined the crafting UI (new panel in UI2, cost-charging fix, recipe expansion)

- Value: **warranted** — runtime produced the one claim the diff could not: a real station,
  instanced from a tilemap cell, paying out of the player's real inventory, charged
  `{"Stone": 8, "Wood": 2}` for a Stone Pickaxe. Every version of this code before today
  charged 1 of each, and it looked correct in the source the whole time.
  - Expected: the panel opens on a real station from UI2 (not the deleted world-space path),
    and `queue_craft` shows `spent` equal to `expected_cost` for a multi-unit recipe — i.e. an
    8-stone recipe actually removes 8 stone, where every version of this code before today
    removed 1.
  - Got: `"expected_cost": {"Stone": 8, "Wood": 2}` / `"spent": {"Stone": 8, "Wood": 2}`,
    `inventory_before` 20/10 -> `inventory_after` 12/8. And the guard: an order for 5 while
    holding 12 stone returned `"refused_reason": "unaffordable"` with
    `"spent": {"Stone": 0, "Wood": 0}` — all-or-nothing, nothing half-paid. Separately,
    `craft_state` reported `unlocked_recipes: ["Plank", "Stone Pickaxe", "Chest"]` on a fresh
    station, which is the day-one seed fixing a plank recipe that no skill and no seed had
    ever unlocked — three of the four pickaxes were uncraftable on a clean save.
  - Cheaper: the new unit tests (`test_crafting.gd`) settle the cost arithmetic and
    `test_crafting_ui.gd` settles the layout, both in ~1s headless. What neither could do is
    show a station instancing from a tilemap cell, binding the live `Recipes` array by
    reference, and spending the player's actual inventory. That needed the running game.

- Gap: **`place_station` wrote a cell that instanced nothing, and the bridge could not say
  why** — `cmd place_station` returned `{"success": true, "message": "placed Sawmill"}` while
  `craft_state` kept answering `"stations": 0`, and `scene-tree` showed 14 TileMap children,
  all stone nodes. The verb had passed `item.tile_atlas_location` (the inventory *icon* cell,
  `(0,2)`) where the live path `player_manager.place_tile:29` passes `item.atlas_location`
  (`(0,0)`); a `TileSetScenesCollectionSource` silently instances nothing for the wrong
  coords. Nothing in the response distinguished "cell written" from "scene instanced".
  Workaround: read `player_manager.gd` and compare against `main.gd:set_tile_item`, which
  turns out to have the same latent bug and is dead code (no callers).
  - [G-029] status: open | seen: 1 | harness: 0.7.0
  - Improvement: `set_tile`-style verbs should verify the cell afterwards —
    `get_cell_source_id`/`get_cell_tile_data` on the written cell, and for a scene tile a
    child-count delta — and report `success: false` when the write produced no tile. A verb
    that reports success for a no-op is the "one half of an invariant pair" trap in the
    harness CLAUDE.md, in the harness's own tooling.

- Gap: **`verify_ledger reach` under-reports for anything that is not a node script under the
  root scene** — it said `reached 6/18`, listing `crafting/recipes.gd`,
  `inventory/inventory_data.gd`, `systems/skill_tree.gd`, `items/types.gd`,
  `devtools_ext/commands.gd` and `ui/recipe_card.gd` as NOT reached. All six ran: recipes.gd
  is the `/root/Recipes` autoload (outside `Main`, so a `Main` snapshot cannot contain it),
  inventory_data.gd is a `Resource`, skill_tree.gd is a `RefCounted`, types.gd is
  `class_name`-only, commands.gd is loaded by the DevTools autoload — none of them are ever a
  node's `script`. `ui/recipe_card.gd` is a node script, but the cards nest ~12 deep and the
  snapshot's max depth is 10, so 15 cards visible in the screenshot still read as unreached.
  Deleted files (`crafting/crafting_ui.gd`, `cost_row.tscn`) are also counted against reach.
  Workaround: computed the depth by hand
  (`max depth in snapshot: 10`, `recipe_card.gd -> False`) and reported reach with the
  structural blind spots named, rather than reporting 6/18 as if it were a coverage number.
  - [G-030] status: open | seen: 2 | harness: 0.7.0
  - Improvement: three things, cheapest first — (1) exclude paths deleted in the diff from the
    denominator; (2) have `scene-tree` take a depth argument for the reach snapshots, or have
    `reach` warn when the tree hit its depth cap; (3) widen the reach signal beyond node
    `script` paths — autoload scripts are enumerable from `/root`, and a "not a node script,
    reach cannot speak to this" bucket (which already exists for `.uid`/`.png`) would stop
    Resource and RefCounted scripts from reading as untested code.

## 2026-08-01 — Commit + merge + push of the crafting rework

- Value: **overkill** — the post-merge re-run confirmed exactly what the pre-merge run had
  already established. Worth the ~40s anyway because the merge commit is what ships and no
  earlier run had ever evaluated that tree, but it produced no new claim.
  - Expected: nothing new; a `--no-ff` merge of a branch whose tip was already green should be
    green, and the only real risk was `--import` having dirtied `project.godot` ([G-028]).
  - Got: `lint: 0 error(s), 7 warning(s) -> exit 0`, `Total: 137 | Passed: 137 | Failed: 0`,
    `grep -c 'SCRIPT ERROR'` = 0, and `git status --short project.godot` empty — so the
    renderer/`.web` override survived this session's three `--import` runs.
  - Cheaper: `git status --short project.godot` alone, 0.2s. That was the only question this
    turn could actually answer that the branch run had not.

- No gaps this turn. [G-028] did not bite: the `--import` calls in this session left
  `project.godot` untouched, which is consistent with the earlier note that the test suite
  never dirties it and narrows that gap further toward "import only, and not every import".

## 2026-08-01 — Hunting the mobile stuck-gather bug (gather-3zg)

- Value: **warranted** — the headless suite passing is itself the narrowing claim this turn
  needed: `test_mobile_controls` asserts press+release symmetry *at the overlay boundary*, so
  a green run exonerates `MobileControls` and puts the defect downstream of it.
  - Expected: either a red test naming the stuck gather, or a green suite proving the overlay
    is not where the release is lost.
  - Got: `Total: 137 | Passed: 137 | Failed: 0`, exit 0, zero `SCRIPT ERROR` in stderr, and
    specifically `test_gather_button_sends_a_press_and_a_release` green — "the press sends
    exactly one action" / "finger up releases gather". So the overlay emits both halves; the
    loss is in `InputManager` or `ResourceManager2`.
  - Cheaper: nothing. Reading `mobile_controls.gd` alone would have shown the code *intends*
    to send both halves; only the run shows the assertion still holds.

- Gap: **no way to exercise "N input events in one frame" from a test** — the leading
  hypothesis is that `systems/input_manager.gd:44` calls `Input.is_action_just_pressed()`
  from inside `_input()`, which is frame-scoped while `_input()` is per-event. Reproducing
  that needs a test that dispatches several `InputEvent`s within one frame and counts signal
  emissions. `_T` offers `instantiate_ui` / `free_ui` and `await tree.process_frame`, but
  nothing to push a batch of events through a viewport in a single frame, and
  `Input.parse_input_event` from a headless test does not reach a `_input()` handler without
  a live viewport. Workaround this turn: static tracing plus a new `gather_state` project verb
  to assert the *consequence* (stranded tilemap cells) at runtime instead of the cause.
  - [G-031] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a `_T.dispatch_events(viewport, [events])` helper that pushes an array of
    events through `Viewport.push_input` without yielding between them, so frame-scoped vs
    event-scoped input bugs — a whole class, and the one that only bites on touch where the
    joystick emits a drag every frame — become unit-testable at all.

## 2026-08-01 — Fixing the gather re-entrancy defects (gather-3zg.1/.3/.4/.7)

- Value: **overkill** — lint and the suite confirmed only that a careful edit compiled and
  broke nothing. Neither could see the bug being fixed: the defect is a *tilemap cell left
  behind*, and no headless assertion reaches the tilemap.
  - Expected: green, because the change is a refactor of bookkeeping the tests never touched.
  - Got: `lint: 0 error(s), 7 warning(s) -> exit 0`, `Total: 137 | Passed: 137 | Failed: 0`,
    `grep -c 'SCRIPT ERROR'` = 0. Then 5 new tests green:
    `test_retargeting_hands_back_the_previous_tile` — "it released the tile it had, not the
    new one".
  - Cheaper: lint alone, ~25s. The suite re-run added nothing over it here.
  - Honest caveat on the new tests: `_release_target()` did not exist before this change, so
    they could not have been red on the old code. They lock the invariant going forward; they
    did not catch the bug. Runtime is still owed.

- Gap: **nothing can assert tilemap cell contents** — the whole bug is "a cell is left set",
  and `get-state` on the TileMap reports no cell contents, `gather_stats` counts *nodes* (a
  stranded highlight is not a node), and a screenshot of a stuck selector is pixel-identical
  to a legitimately selected tile. `validate-all` returned 0 issues throughout. Workaround:
  wrote a project verb, `gather_state`, that reads `get_used_cells(3)` and scans layer 1 for
  cells sitting on a `gathering_atlas_location`, with a `stranded` flag. Writing it also
  surfaced why a generic verb would not have done: the flag has to discount the chest
  highlight `player.gd:_process` legitimately redraws every frame, which is game knowledge.
  - [G-032] status: open | seen: 2 | harness: 0.7.0
  - Improvement: a generic `tilemap-cells --node PATH --layer N` verb returning used cells
    with their source id and atlas coords. Tile-based games keep real state in cells, and it
    is currently the one part of the scene the bridge cannot read at all — every project
    hitting this has to hand-roll its own verb.
  - Seen again by the stone-wall work, which needed to prove a placed wall had been
    autotiled — i.e. that its cell held one of 47 solved atlas coords rather than the blob's
    base. Same conclusion, second hand-rolled verb: `tile_at`, reading `get_cell_source_id`
    and `get_cell_atlas_coords` at an offset from the player. Two independent gathers of the
    same missing primitive in one day is the argument for the generic verb.

## 2026-08-01 — Runtime A/B of the mobile stuck-gather fix (gather-3zg)

- Value: **warranted** — the harness produced the one claim nothing else could: it reproduced
  the reported bug on the pre-fix build and showed it gone on the fixed one, from the same
  command sequence. Static tracing by three agents agreed on the mechanism but could not
  demonstrate it.
  - Expected: the pre-fix build would strand a tilemap cell after a retarget; the fixed build
    would not.
  - Got: pre-fix, after `goto_resource Tree` → press → `goto_resource Stone` → press → release:
    `highlight=[{'x': -3, 'y': -5}] mid_gather=[{'resource': 'Tree', ...}] stranded=True`
    — the orphaned Tree cell survived the release, on its animated mid-gather frame. Fixed
    build, identical sequence: one cell at each step, `stranded=False` throughout. Separately,
    pre-fix `input press gather` left `is_holding=False` — a live reproduction of gather-9p6 —
    while post-fix it drives the loop.
  - Cheaper: nothing. The whole defect is a cell left on a tilemap after a specific two-press
    sequence; no static read and no unit test in this project can reach it.

- The stash-based A/B is worth repeating as a technique: `git stash push <one file>`, relaunch,
  run the same script, `git stash pop`. The first attempt stashed only `input_manager.gd` and
  the bug did **not** reproduce, because the damage lives in `resource_manager2.gd` — a false
  "already fixed" that would have been easy to report as success. Stash *every* file in the
  causal chain, or the A/B silently tests the wrong thing.

- Gap: **`get-state` cannot read a `_panel_root.visible` behind an `is_open()`** — while
  testing the `disable_input` path I read `skill_panel` state that disagreed with
  `disable_input`, concluded the release was being swallowed, and said so before a clean
  re-run showed it was not. The verb reports `open` from `is_open()`, but `set_open()`
  early-returns on `_panel_root.visible == open`, so a panel whose root and wrapper disagree
  answers confidently and wrongly. Workaround: re-ran the sequence from a known-closed state
  and asserted every step instead of trusting the first reading.
  - [G-033] status: open | seen: 1 | harness: 0.7.0
  - Improvement: for state a verb derives from a method, also report the raw fields it derives
    from (here `_panel_root.visible` alongside `open`), so a disagreement is visible in the
    reply rather than inferred three commands later. Same argument as the status provider.
## 2026-08-01 — Stone wall + stone floor: generated art, a second wall terrain, recipes

- Value: **warranted** — runtime is the only place the new terrain could be shown to
  autotile, because nothing in the diff says whether Godot's solver accepts a blob
  copied cell-for-cell into a second atlas source.
  - Expected: placing a stone wall writes a cell that is *not* the registered `(0,4)`
    base but one of the 47 solved blob cells on source 11 — proving terrain 2 actually
    autotiles rather than dropping a single unconnected tile; and a stone wall adjacent
    to a wood wall leaves both runs unjoined. Neither is decidable from the diff; the
    tileset terrain data and Godot's solver decide it.
  - Got: three stone walls placed in a row came back as `source 11 atlas (1,4)`,
    `(2,4)`, `(3,4)` with `is_unsolved_base: False` on all three — left cap, middle,
    right cap, so the solver ran on terrain 2. The guard held too: after dropping a
    wood wall immediately to the left of the run, the stone left cap was still `(1,4)`
    and not the middle piece `(2,4)`, with `runs={'Stone Wall': 3, 'Wood Wall': 1}` —
    two separate runs, no cross-material blending. The floor case that the whole
    coordinate layout was designed around also held: `place_build StoneFloor` landed
    `layer 2 ... atlas (0,6) wall=''` and left `Stone Wall: 3` unchanged, i.e. it was
    not swept into the wall run by the source+rect classifier.
  - Cheaper: nothing. Unit tests can assert the WALL_TYPES table is self-consistent
    (and eight new ones now do), but "does `set_cells_terrain_connect` pick tiles from
    a second atlas source for a terrain index that did not exist an hour ago" has no
    headless expression — the TileSet only resolves terrains with a live TileMap.

- Gap: **`verify_ledger reach` under-reports for anything that is not a node script**
  — same shape as before, this run said `reached 2/9`, listing `crafting/recipes.gd`,
  `systems/skill_tree.gd`, `items/game_item.gd`, `items/types.gd` and
  `devtools_ext/commands.gd` as NOT reached. All five ran: `craft_state` returned
  `"unlocked_recipes": [... "Stone Floor", "Stone Wall"]` after `learn_skill light_step`,
  which is recipes.gd and skill_tree.gd end to end; `commands.gd` is the extension every
  `cmd` call in this run went through; `game_item.gd` supplied the
  `STONE_BUILD_SOURCE_ID` the placements keyed off. Bumped the existing entry rather
  than filing a second one.
  - [G-030] status: open | seen: 2 | harness: 0.7.0
  - Improvement: as recorded on G-030 — a "not a node script, reach cannot speak to
    this" bucket, which the tool already has for `.uid`/`.png`, would stop autoload and
    RefCounted scripts from reading as untested code.

- Gap: **`lint_project.gd` does not compile-check scripts, so a broken `main.gd` passed
  lint clean** — after the wall refactor, lint reported `lint: 0 error(s), 7 warning(s)
  -> exit 0` while `main.gd` had three real parse errors (`Identifier "wall_tiles_min"
  not declared`, and two `Cannot use subscript operator on a base of type "null"`). They
  only surfaced on the *next* phase, as `Failed to load script "res://items/items.gd"`
  buried in the unit-test log — and that log still printed `Total: 145 | ALL TESTS
  PASSED | exit 0`, because the tests that depend on items.gd were the ones that failed
  to load rather than to run. Two gates in a row reported success on a project that
  could not boot. Workaround: grepped the test log for `SCRIPT ERROR` by hand, which is
  the only reason it was caught at all.
  - [G-034] status: open | seen: 1 | harness: 0.7.0
  - Improvement: lint already walks every `.gd` under `scan_root` for the UID pass —
    have it `load()` each one and report a failed compile as a lint *error*. Failing
    that, `run_tests.gd` should exit 2 when any `Failed to load script` appears on
    stderr, on the same reasoning that already makes an unparseable test script exit 2:
    a suite that could not load half its dependencies verified nothing.

- Gap: **no way to place a building tile through the generic primitives** — `set_tile`
  takes two `Vector2i`, and `run-method` hands raw JSON to `callv` with no vector
  coercion (the project's own `gather-6sp`), so the entire build path was undrivable.
  Workaround: added `place_build` and `tile_at` project verbs, which is the documented
  answer and worked first try — recording it because the *generic* gap is real and
  every project hits it independently.
  - [G-035] status: open | seen: 1 | harness: 0.7.0
  - Improvement: teach `run-method` to coerce a 2-element JSON array into `Vector2`/
    `Vector2i` when the target method's argument list says so — `Object.get_method_list()`
    exposes the parameter types, so the coercion can be driven off the signature rather
    than guessed.

## 2026-08-01 — UI/UX overhaul: shared panel kit, close buttons, mobile sizing, joystick overlap

- Value: **warranted** — runtime produced two claims the diff could not: the inventory
  frame and the virtual joystick occupy disjoint rects, and the new close button hands
  `disable_input` back rather than soft-locking the player.
  - Expected: runtime will show whether the inventory panel now actually renders above
    the joystick and centred, and — the thing no headless test can reach — whether
    closing a panel via the new X button runs the `disable_input` handshake, or
    soft-locks the player with movement disabled.
  - Got: inventory frame `Rect: 616, 341, 688x397` against joystick
    `Rect: 38, 667, 375x375` — disjoint in x, and the frame centre is exactly
    (960, 540) on a 1920x1080 viewport. The old scene offsets computed to x 14..78,
    y 902..966, which is inside the joystick rect, so the reported bug is confirmed and
    fixed. On the handshake: `disable_input: true` with the panel open, then
    `emit_signal("pressed")` on the `CloseButton` gave `visible: false` **and**
    `disable_input: false`. The close button measures `51x51`, clearing the 48px floor.
    Also confirmed the new press-gate both ways: tapping the BAG button at (1707, 88)
    with the skill panel open left `InventoryInterface.visible: false`, while the same
    tap with no panel open gave `visible: true`.
  - Cheaper: nothing. Both facts only exist in a running game — the unit tests construct
    panels in isolation, where there is no InputManager to hand input back to and no
    joystick to overlap.

- Gap: **A stale bus file in a shared `user://` answers requests with another build's
  data, with no process running to explain it.** First `scene-tree` of the session
  returned a `UI2` whose children were in the pre-change order *and* included an
  `IslandCompass` node that does not exist anywhere in this worktree
  (`grep -rl IslandCompass .` matched only the JSON I had just written). The game log
  also showed a `_cmd_set_state` on camera zoom that I never sent
  (`ERROR: Zoom level must be different from 0`, at `dev_tools.gd:707`).
  `Get-CimInstance Win32_Process` showed exactly **one** Godot process, and it was mine —
  so this was not the live-second-instance case in [G-009]; it was leftover
  `devtools_commands.json` / `devtools_results.json` from an earlier session in the
  shared `user://`. The existing id-echo "Crossed replies" check did not fire. I only
  caught it because a node name happened not to exist in my source; had the stale tree
  been merely *older* rather than foreign, I would have verified nothing and reported a
  pass. Workaround: relaunch with `-- --devtools-session uiverify` and call with
  `--session uiverify`, which gives a private file pair; `ping` then confirms
  `session: uiverify`.
  - [G-036] status: open | seen: 1 | harness: 0.7.0
  - Improvement: have the DevTools autoload delete any pre-existing command/result file
    for its own bus id during `_ready()`, and have `devtools.py` reject a result whose
    request id it never issued instead of returning it. Note `GODOT_USERDATA` does not
    help here — it redirects only the *client*; the game resolves `user://` from the
    engine, so the two silently poll different directories and the error reads as a
    dead game.

- Gap: **`place_station` can drop a station outside the crafting panel's own keep-open
  radius, making the panel unverifiable from the CLI.** `_cmd_place_station` ring-searches
  from the player's tile but its `dx` loop starts at `-ring` and takes the first free
  cell, biasing toward the far corner. Observed: player at (12.9, 8.9), station placed at
  (24, 56) — 48 units away, while `crafting_ui.gd:640` closes the panel past 24. So
  `cmd crafting_panel --args '{"open":true}'` returns `"open": true` and the very next
  command reads `Visible: False` / `"panel_open": false`. `set-game-speed 0` does not
  help (`_physics_process` still runs), and `set-state` cannot reposition the player
  because it will not coerce a dict to `Vector2` — it silently wrote (0, 0), which is
  [G-035] biting a second verb. Walking there with `input press move_down` +
  `step-time` was blocked by collision after ~9 units. Net result: `ui/recipe_card.gd`
  is the one changed file this run could not reach, and the crafting panel was verified
  only through its 5 passing unit tests plus a `set_title` readback of `SAWMILL`.
  Filed as gather-7y9. (The commit that introduced this entry, 441668f, cites a
  non-existent `gather-1ph` for the same bug — the id was written before the bead was
  read back. gather-7y9 is the real one.)
  - [G-037] status: open | seen: 1 | harness: 0.7.0
  - Improvement: have `place_station` collect the candidate free cells and pick the one
    nearest the player rather than the first the scan hits, so the station lands inside
    the interaction radius the panel itself requires.

## 2026-08-01 — planned pregenerated islands (forest / ore / boss), no code changed

- Value: **inconclusive** — planning-only turn; no gameplay, script or scene changed, so
  the harness was never run and there was nothing for it to assert.
  - Expected: n/a — the question was "what does this feature collide with", which is a
    static-reading question, answered by four read-only research agents over `main.gd`,
    `world/`, `enemies/`, `systems/save_load.gd` and `assets/tilesets/world_tile_set.tres`.
  - Got: n/a at runtime. The findings that shape the plan all came from reading code —
    e.g. `main.gd:619-641` floods `get_used_rect()` with water then calls
    `set_cells_terrain_connect` *inside* the per-tile loop, and `land_tiles()`
    (`main.gd:349`) is global so three new islands would inflate `resource_cap()`,
    `cap_for_land_tiles()` and the 8s respawn timer at once.
  - Cheaper: nothing — reading was the correct and only tool for a planning turn.
    Launching the game to "confirm" would have proved nothing the diff-free tree could
    not already say.

- Gap: **no verb reports the island footprint, so the connection guarantee in
  `gather-b6r.5` has no cheap runtime oracle.** `land_cells_for_radius` is noise-filtered
  and the noise is a smooth gradient over the ±34 span, so at max radius the home island
  can be lopsided with a whole side missing — which decides whether a pregenerated island
  ever becomes walkable. Today the only readouts are `count_land_tiles()` (a scalar, via
  `gather_stats`) and `screenshot`. Neither can answer "is cell X connected to the home
  island", and a scalar count is identical whether the land is one blob or two.
  Workaround for this turn: none needed, since nothing was built yet — recording it now
  because the acceptance criterion on `gather-b6r.5` ("reachable across a sample of random
  seeds") is unverifiable without it and will otherwise get eyeballed on one run.
  - [G-036] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a generic `tilemap-region --layer N --atlas X,Y` verb returning the
    connected components of matching cells as bounding boxes plus cell counts. That is
    game-agnostic (it only needs a `TileMap` and an atlas coord), and it turns "did the
    islands connect" into one assertion instead of a screenshot. The project-specific
    alternative — an `island_census` verb in `devtools_ext/commands.gd` — is the
    documented fallback and is what I will add if the generic one does not exist by then.

## 2026-08-01 — built the pregenerated islands (forest / ore / boss) end to end

- Value: **warranted** — runtime and the seed sweep each produced a defect the diff could
  not, and they were different defects.
  - Expected: the islands would generate, connect once land was bought, keep their themed
    spawn tables, and survive a save/load round-trip.
  - Got: four things reading the code would not have given me. (1) `island_census` on a
    fresh world reported `boss` with `land_tiles: 47` but a region radius of
    `island_radius + ISTHMUS_WIDTH` — the isthmus tail fell **outside** its own region, so
    the far end reverted to the mainland's table and would have quietly restocked the one
    region whose purpose is to stay empty. Fixed by giving `LandRegion` an explicit cell
    set. (2) After the first save/load, `chest=["empty","empty","empty"]` — and the
    `print(dict["y"], chunk.position.y)` already sitting in `save_load.late_load` emitted
    **zero** lines, proving the SaveChunks group was empty when it ran. Scene tiles
    instantiate a frame after their cell is written, so `late_load` matched saved payloads
    against nodes that did not exist yet. That is a pre-existing bug affecting *every*
    chest in the game; the reward chest is just the first one whose contents anyone
    checked. (3) A zoomed-out screenshot showed the sea crossed by straight three-wide
    causeways: `_isthmus_cells` carved unconditionally instead of only when the island
    would not otherwise connect. (4) `node-bounds` reported the compass and the ocean
    backdrop both at `0x0` — `set_anchors_preset` leaves the offsets at zero; the project
    convention is `set_anchors_and_offsets_preset`.
  - Cheaper: nothing for (1)–(4). Each needed either the running game or a seed sweep.
    The *placement* bug was cheaper still headlessly — see below.

- Value note on the seed sweep: `test/unit/test_island_manager.gd` found **36 stranded
  islands across 200 seeds (6%)** on the first run, after the game had launched twice and
  reported `"every island connects at max land"` both times. Both runtime checks were
  true and both were one seed. The cause was not the isthmus at all: thresholding the
  noise leaves detached islets, `_reach_along` happily anchored a corridor to one, and the
  island ended up joined to a rock in the sea. A 6% failure that looks correct on screen is
  exactly the shape a single playthrough cannot see. **The headless sweep was the cheapest
  thing that could have found this, and it should have come before the launch, not after.**

- Gap: **`performance` reported `Orphan growth: +0` on a save/load round-trip that
  `gather-jjg` says leaks 2 orphans** — and the baseline resets per session, so a `+0`
  after a load is unfalsifiable without knowing when the baseline was taken. The reading
  was the same before and after my change, which means it told me nothing about whether I
  made the known leak worse. Workaround: none; I recorded the absolute (`absolute 0`)
  alongside the growth and moved on.
  - [G-037] status: open | seen: 1 | harness: 0.7.0
  - Improvement: have `performance` report the baseline's *age* in frames and whether it
    was taken this session, and let `--reset-baseline` be asserted against explicitly, so
    "+0" can be distinguished from "+0 because the baseline moved under you".

- Gap: **three Godot instances were live on one bus and answered each other's commands.**
  Symptom was a census reporting `home_radius: 34` in a session where no land had been
  bought, and a response missing the `boss` key I had just added — i.e. an *older build*
  replying. Both readings were well-formed and neither was flagged. `ping` reported a
  healthy bridge throughout. This is the documented one-bus hazard and a stored memory, and
  I still lost about ten minutes to it because nothing in the reply says which process
  produced it. Workaround: `Get-Process Godot* | Stop-Process -Force` before every launch.
  - [G-038] status: open | seen: 1 | harness: 0.7.0
  - Improvement: put the answering process's pid and its script-load timestamp in the
    `status` block on every reply. The bus already echoes a request id to catch crossed
    replies; a pid would catch the case where the reply is *not* crossed but comes from a
    different, staler game than the one just launched. Failing that, have the game write
    its pid beside the bus at startup and let the client warn when it changes between calls.

## 2026-08-02 — commit the islands work, then fix gather-74z (save_load debug print + uncleared `loads`)

- Value: **warranted** — a `get-state` on one property settled a question the diff could
  only argue about, and it settled it against my own framing of the bug.
  - Expected: after two `_load()` calls in one session, `SaveLoad.loads` would hold one
    entry rather than two, and I expected the *visible* symptom of the old behaviour to be
    a doubled or corrupted chest.
  - Got: `loads: [{"data": ["{\"count\":40,\"type\":31}", ...], "x": 584.0, "y": 40.0}]`
    — exactly one entry after the second load, and the chest read back
    `['Gold Coin x40', 'Gold Ore x8', 'Iron Ore x12']` unchanged. Reading
    `world/tile_scenes/test_chest.gd:50` while the run was up showed why the second half of
    my expectation was wrong: `load()` *assigns* `inventory_slot_datas = []` before
    refilling, so re-applying an identical payload is idempotent. The uncleared array is a
    real bug, but its damage is a stale payload from an *earlier, different* save file
    landing on whatever SaveChunks node now occupies that position — not duplication. I
    would have written the wrong thing in the commit message without this.
  - Cheaper: reading `test_chest.gd` alone would have corrected the mechanism, but not
    confirmed the clear actually fires on the real load path — `_load()` is reached through
    an input action and a Control in the camera HUD, which no unit test in this project
    instantiates. The one-property read was the cheap half and the decisive half.

- Gap: **`get-state` has no machine-readable output mode**, so scripted assertions on it
  are guesswork. `python tools/devtools.py get-state --node PATH --property loads` prints
  `loads: [{...}]` — GDScript-flavoured, not JSON — and piping it to `json.load` fails with
  `JSONDecodeError: Expecting value: line 1 column 1 (char 0)`. `run-method` has the same
  shape (`Result: None`). I wanted `len(properties['loads'])` as an assertion and had to
  eyeball the string instead, which is precisely the read that a tired session gets wrong.
  `run_tests.gd` has `--json`; the bridge client does not.
  - [G-039] status: open | seen: 1 | harness: 0.7.0
  - Improvement: add a global `--json` flag to `tools/devtools.py` that prints the raw
    response dictionary the game already sends, for every verb. The data is structured on
    the wire — only the client's pretty-printer discards it. `cmd island_census` already
    emits JSON, which is why every scripted assertion I write ends up routed through a
    project verb rather than through the generic primitives.

- Gap: **the documented `python3` invocation does not run on this machine** — it is the
  Microsoft Store alias stub,
  so the documented `python3 tools/devtools.py ping` fails with "Python was not found; run
  without arguments to install from the Microsoft Store". CLAUDE.md warns to probe by
  running it, and I still spent a launch cycle on it because the harness docs and the
  `/verify` skill both spell `python3`.
  - [G-040] status: open | seen: 3 | harness: 0.7.0
  - Improvement: ship a `tools/devtools` shim (or have the skill resolve the interpreter
    once and cache it) so the documented invocation is interpreter-agnostic; the Store stub
    exits 9009 with a message on stdout, which is detectable.

## 2026-08-02 — slowed the spawn cadences, cut kill xp, flattened ore xp, steepened the level curve

- Value: **warranted** — the two edits that could not be checked by reading were both scene
  edits, and runtime is the only thing that reads a `.tscn` the way the engine does.
  - Expected: the two hand-edited .tscn Timer hunks landed on the nodes I meant —
    ResourceTimer.wait_time == 24.0 and the EnemySpawner timer re-rolling into 16-26s —
    plus add_xp granting the new XP_KILL of 3 against a level-2 threshold of 13.
  - Got: `wait_time: 24.0` on ResourceTimer and `spawn_stats` reporting
    `"base_interval": 21.0, "spawn_interval": 20.8669`, so both hunks hit their intended
    Timer. `_on_died` moved xp `11 -> 14`, exactly XP_KILL. The curve claim needed pushing
    past level 4 to be worth anything — 1.28 and 1.30 agree on the first three thresholds
    (10/13/17) — and at level 5 the live game reported `next_level: 30`, where the old
    growth gives 29. After the ore edit, `gather_stats` reported `xp: 1` for all six
    resources (proving `_apply_tuning` reaches `GameResource`, not just that the dict was
    edited), and a real 6-second `input press gather` on a coal node moved xp `6 -> 7`
    where coal used to pay 3.
  - Cheaper: a unit test over `Resources.TUNING` would have settled the ore half in ~40s
    headless. Nothing cheaper covers the two `main.tscn` Timer hunks — a scene edit can
    only be shown to have hit the intended node by loading the scene.

- Gap: **an `input tap` that engages nothing is indistinguishable from one that works** —
  `python tools/devtools.py input tap gather --hold 3.0` printed `Tapped: gather (hold:
  3.0s)` and xp did not move; `player_state` afterwards showed `"state": "PlayerIdle"`, so
  the press had been and gone without the gather ever starting. The reply is the same
  string whether the action reached a handler or fell on the floor. Workaround was to
  re-anchor with `goto_resource` and drive it as `input press` + `step-time --seconds 6` +
  `input release`, sampling state between each.
  - [G-041] status: open | seen: 1 | harness: 0.7.0
  - Improvement: have `input tap`/`press` return the count of handlers the dispatched
    `InputEventAction` was consumed by (`get_viewport().set_input_as_handled` already
    distinguishes this), or at minimum echo the acting node's state machine state before
    and after, so "nothing listened" is visible in the reply.

- Gap: **no way to hold xp income still while asserting an xp delta** — the ambient world
  pays xp on its own (pickups at 1 per 3 drops, and enemies the spawner trickles in), so
  between `get-state ... --property xp` and the gather it drifted `3 -> 4 -> 6` unprompted.
  Every xp assertion in this run had to be read as "at least/at most", and the coal
  assertion (+1) is only conclusive because the old value (3) is above the noise floor. A
  smaller change than 3->1 would not have been measurable this way at all.
  - [G-042] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a project verb `xp_ledger` returning the last N awards as
    `{source, amount}` rather than a running total — the awards are already individually
    routed through `LevelUpManager.add_xp`, so attribution exists at the call site and is
    thrown away. Failing that, a generic `freeze_ambient` that pauses spawners and pickup
    collection for the duration of an assertion.

- [G-040] bit again (`seen` bumped to 2): `python3` is the Store alias stub on this
  machine, and the `/verify` skill still spells `python3` in every command block. Its own
  Phase 0 probe found `python` correctly — the cost is that every copied command block has
  to be edited by hand afterwards.

## 2026-08-02 — scoped an in-game debug UI panel (gather-w1s), research phase

- Value: **inconclusive** — no runtime run yet; this response was research fan-out plus
  scoping, and the harness was only touched to resolve the interpreter and confirm no
  game was live. The substantive verdict belongs to the implementation response.
  - Expected: nothing from runtime at this stage.
  - Got: `harness-version` returned `game not running: 'harness_version' was never picked
    up (2.0s grace...)` — correct, nothing was launched. Version read from source instead
    (`dev_tools.gd:17,24` -> 0.7.0).
  - Cheaper: reading `devtools_ext/commands.gd` and `ui/skill_tree_ui.gd` directly, which
    is what the read-only agents did. Static reading was the right tool for a design pass.

- Gap: **no way to enumerate registered project verbs without a running game** — the
  planned debug panel wants to drive the same handlers the CLI does, so the verb roster is
  a design input, not a runtime question. `list-commands` is the documented source of
  truth and it requires a live bus; recovering the roster meant hand-parsing the
  `register_command` block in `devtools_ext/commands.gd:14-46`. Worked, but it is the kind
  of list that silently drifts from the docs.
  - [G-043] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a headless mode for `list-commands` (load the extension script, call
    `register_commands` against a stub Node, dump the `_handlers` keys and exit) so the
    verb roster is readable from the same place lint and tests run.

- [G-040] bit again (`seen` bumped to 3): `python3 tools/devtools.py harness-version` died
  on the Store alias stub before reaching the bridge. `python` resolves to 3.12.10 on this
  machine. Same fix as before; nothing new to add.

## 2026-08-02 — retuned the forest/ore island spawn weights so each island reads as its theme (gather-mv2)

- Value: **warranted** — the census proved the whole seeding pipeline honours the new
  weights, and that the ambient timer keeps honouring them as it fills the island to cap,
  which is the half the unit test cannot reach.
  - Expected: the generated ore island's per-region census comes back majority coal+iron
    rather than majority stone, and the forest island nearly all trees — a claim the diff
    cannot make, since what lands is the product of the weights, the unlocked set
    (copper/gold skill-gated), the region's cells including the isthmus, and the seeder's
    cap/attempt limit.
  - Got: `cmd island_census` at world generation returned
    `"ore": {"Coal": 8, "Iron": 6}` and `"forest": {"Tree": 14}` — zero stone on the ore
    island, where the old weights made stone the single most likely roll there. After
    `set-game-speed 20` for ~240 game-seconds the ore island had filled to its cap,
    `"ore": {"Coal": 10, "Iron": 10}` at `nodes 20 cap 20`, still zero stone, while
    `"boss": {}` stayed empty and home kept its mixed `{"Coal":1,"Iron":4,"Stone":16,"Tree":11}`.
  - Cheaper: the new `test/unit/test_island_theming.gd` settles the weighted roll itself at
    4000 samples per island for ~60ms and no game — it is the better tool for the
    distribution. Nothing cheaper covers the ambient timer topping the ore island up to
    its cap without ever placing a stone, which is what LandRegion exists to guarantee.

- Gap: **`verify_ledger.py reach` scopes "changed files" to the branch, not the working
  tree** — it reported `reached 15/23 changed file(s)` and listed `test/unit/test_ore_chain.gd`,
  `ui/debug_panel_ui.gd` and `devtools_ext/commands.gd` as unreached. This session changed
  three files (`world/island_manager.gd`, `world/resource_manager2.gd`, and a new test);
  the other twenty are earlier branch commits plus another session's uncommitted work in
  the same tree. Both files this session touched *were* reached, but that had to be
  established by subtracting the NOT-reached list from `git status --porcelain` by hand.
  The failure mode is the flattering one: a large branch dilutes the ratio, so a run that
  reached everything it changed still reads as 65% covered.
  - [G-044] status: open | seen: 1 | harness: 0.7.0
  - Improvement: report reach for the working-tree diff and the branch diff as two
    numbers, or take a `--since` ref so the run can scope reach to what it actually edited.

## 2026-08-02 — built the in-game debug panel on F3 (gather-w1s)

- Value: **warranted** — runtime found a defect that neither the diff nor lint could see:
  the enemy dropdown was spawning the boss.
  - Expected: that the F3 action actually reaches DebugPanelUi through InputManager and
    opens the panel, that the panel's Controls lay out inside the viewport (a code-built
    TabContainer with no explicit size is exactly the thing that comes out 0x0), and that
    the action buttons' calls resolve against the live objects — especially the ones I
    inferred from agent reports rather than ran: `spawner.timer`, `handler.land_manager`,
    `islands[id]["centre"]`, `PlayerStats.BASE` iteration, and `lum.tree.order`.
  - Got: layout was fine (`Rect: 400, 160, 1120x760` — clamped and centred), and all five
    inferred APIs resolved, proven in one assertion by the readout text:
    `stats gather_speed_mult 1.0 ... land_cost_mult 1.0` / `enemies 5 live / cap 4
    spawner running next 14.0s` / `land radius 10 parcels 0/12 next cost 12 tiles 259` /
    `census Stone 16 Tree 21 Coal 11 Iron 9` / `islands boss, ore, forest`. The find was
    elsewhere: `spawned 3 x Elite (7 live, cap 4)` from a picker whose first entry is
    "Bone". `get-state ... --property selected` returned `selected: 2`. GDScript
    negative-indexes, so an OptionButton reporting -1 makes `ENEMY_TYPES[selected]` return
    the *last* entry — the boss — instead of erroring. Fixed with an explicit `select(0)`
    plus a `_picked()` range guard; re-verified as `spawned 2 x Bone (4 live, cap 5)`.
  - Cheaper: nothing. The diff reads correctly, lint is clean, and no unit test
    instantiates this panel. Only a running game distinguishes `selected: 0` from
    `selected: 2`.

- Gap: **`input tap` on a release-triggered action toggled the panel twice, minutes
  apart** — `input tap debug_panel` opened the panel (`visible: true`, confirmed with
  `disable_input: true`), and four read-only commands later it was `visible: false` with
  nothing having sent input in between. Split into halves it is deterministic:
  `input press debug_panel` -> `visible: false` (correct, InputManager fires on release),
  `input release debug_panel` -> `visible: true`, still true after `wait-frames 60`. A
  second `input tap` from open then produced exactly one toggle and stayed put, so it is
  intermittent rather than a plain double-fire. Most plausible mechanism is Godot
  synthesizing a release for a still-held simulated action when the window's focus
  changes — which is guaranteed here, since every CLI call runs while the game is
  unfocused. Workaround: drove the rest of the run with explicit `press`/`release` and
  `run-method`.
  - [G-044] status: open | seen: 1 | harness: 0.7.0
  - Improvement: have `input tap` await its own release and report the action's final
    state in the reply (`{"action": "...", "pressed": false}`), so a tap that left
    something held is visible at the call rather than four commands later. Failing that,
    document that release-triggered actions should use explicit press/release.

- Gap: **launching the game rewrites `main.tscn` and the `.tres` assets, and the workflow
  never mentions it** — a session that started `(clean)` ended with
  `main.tscn | 235 ++++----` and `world_tile_set.tres | 3612 +++-----` (1354 insertions,
  2264 deletions) purely from Godot 4.7 re-serializing on load (adding `uid=` to every
  `ext_resource`). Phase 5 says to commit the ledger and hands back a `git status` in
  which these sit indistinguishable from real edits, and the tileset rewrite is exactly
  the kind of thing that gets waved through in a diff that large. Reverted with
  `git checkout --` after confirming none of it was mine.
  - [G-045] status: open | seen: 1 | harness: 0.7.0
  - Improvement: have Phase 5 snapshot `git status --short` before Phase 2 and diff it
    against the post-run status, listing engine-touched files separately from the working
    diff — the data is free and it is the difference between reverting three files and
    committing a 3600-line tileset rewrite by accident.

- Gap: **`verify_ledger.py record` silently drops reach when the snapshots are gone** —
  the workflow calls `tree-*.json` "inputs, not records" and says to leave them out of the
  commit, so I deleted them before recording; `record` then wrote the row anyway with
  `reach not computed (no scene-tree snapshot)`. The row that survives is the one missing
  the only field the workflow says to believe over self-reported checks. (Reach *was*
  computed separately: `reached 16/23 changed file(s)`, with all four of my scripts in the
  reached set.)
  - [G-046] status: open | seen: 1 | harness: 0.7.0
  - Improvement: have `reach` cache its computed result next to the ledger so `record` can
    pick it up without the raw snapshots, or make Phase 5 state plainly that the snapshots
    must outlive the `record` call.

## 2026-08-02 — committed the debug panel (bdd222f)

- Value: **overkill** — no harness run this turn. Staging and committing already-verified
  work needs nothing the running game could add, and the `/verify` that justified the
  commit is the entry directly above this one.
  - Expected: nothing; this turn ran no runtime check by design.
  - Got: `git commit` reported `9 files changed, 1092 insertions(+), 2 deletions(-)`, and
    `git status --short` came back empty afterwards.
  - Cheaper: this was already the cheapest path — `git log`/`git status` alone.

- No gaps this turn.

## 2026-08-02 — merged tune/slower-spawns-and-xp into main (92938bf)

- Value: **overkill** — deliberately ran nothing. `git diff --stat main
  tune/slower-spawns-and-xp` came back empty after the merge, so main's tree is
  byte-identical to the branch tip that the run two entries above already verified at
  runtime. Re-running lint, tests and the game would have re-derived a known result.
  - Expected: nothing; the question this turn was whether the merge changed any content,
    which is a git question rather than a runtime one.
  - Got: empty `git diff --stat` between main and the branch, and `--no-ff` produced a
    merge commit with no conflicts (`22 files changed, 1482 insertions(+), 45 deletions(-)`).
  - Cheaper: this was the cheapest check — one `git diff --stat`, no Godot launch.

- No gaps this turn.

## 2026-08-02 — merged the UI panel kit into main and consolidated the branches (3d4bb09)

- Value: **warranted** — the merge dragged a 3073-line rewrite of the three panels the
  debug panel calls into, and only the running game could say whether the debug panel
  still worked on top of it.
  - Expected: that `_on_open_skill_tree` / `_on_open_land_panel` still resolve, since the
    kit rewrote skill_tree_ui.gd and land_purchase_ui.gd wholesale and the debug panel
    drives them through `set_open()`.
  - Got: the API survived (`func set_open(open: bool)` still at skill_tree_ui.gd:456,
    land_purchase_ui.gd:262), and the handoff works end to end — after
    `_on_open_skill_tree`, the debug panel read `visible: false` and `skill_panel`
    reported `"open": true`. The readout also came back fully populated on the merged
    tree. What the merge *did* change is the node layout: the panels now expose
    `SkillTreeUI/PanelFrame` (ui/panel_frame.gd) instead of `SkillTreeUI/Panel`, leaving
    the debug panel the only panel still hand-rolling its own styleboxes — filed as a
    follow-up rather than fixed here.
  - Cheaper: `grep -n '^func set_open' ui/*.gd` would have settled the API question in a
    second, and did. It could not have settled the handoff actually running, which is the
    half that mattered.

- Gap: **`cmd skill_panel --args '{}'` toggles, so using it to *read* state changes it** —
  I called it to check whether the skill tree had opened and got `"open": false`, which
  looked like the debug panel's button had failed. It had not; the read closed the panel.
  The verb is documented as "absent = toggle", so this is a footgun in the project's own
  extension rather than the harness core, but the shape is general: several verbs here
  (`skill_panel`, `land_panel`, `crafting_panel`) are setter-or-toggle depending on
  whether a key is present, and none of them has a pure reader.
  - [G-047] status: open | seen: 1 | harness: 0.7.0
  - Improvement: give the toggle verbs a read-only sibling, or make the status provider
    carry the panel-open flags (it already carries `skill_panel_open`) so state can be
    read without dispatching a mutation. Asserting on a mutating verb is a mistake the
    reply cannot warn you about.

## 2026-08-02 — pushed main to origin

- Value: **overkill** — ran nothing. The tree being pushed is the one verified two entries
  above (import, lint, 174/174 tests and the post-merge runtime checks), and `git fetch`
  confirmed origin had moved zero commits since, so there was no new content for a runtime
  check to reach.
  - Expected: nothing; the only open question was whether the push was still a
    fast-forward, which is a git question.
  - Got: `commits on origin/main not local: 0` after a fetch, and `## main...origin/main
    [ahead 10]` — a clean fast-forward with no rebase or merge needed.
  - Cheaper: this was the cheapest check — one `git fetch` plus one `git rev-list --count`.

- No gaps this turn.
