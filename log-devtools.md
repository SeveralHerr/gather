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
  - [G-004] status: fixed | fixed-in: 0.5.0 | seen: 2 | harness: 0.4.0
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
  - [G-004] status: fixed | fixed-in: 0.5.0 | seen: 2 | harness: 0.4.0
  - Improvement (restated concretely): add `--file <basename>` to `run_tests.gd`, matched
    against the test script path, so an agent can run exactly the file it owns.

## 2026-08-01 — Reviewed the self-learning loop itself (no code changed)

- Gap: **No entry in this log has a status, so "is this already fixed?" is unanswerable
  from the file** — the Format section says "Log closures too", but every one of the six
  entries reads as permanently open. Answering whether the loop had ever actually closed
  required leaving the project entirely: `git -C ~/Documents/GitHub/godot-selftest-harness
  log --oneline` showed `922c45d Ship the devtools gaps log, and close the gaps it recorded
  (0.4.0)`. Nothing in this repo records that.
  - [G-007] status: fixed | fixed-in: 0.5.0 | seen: 1 | harness: 0.4.0
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
  - [G-009] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.4.0
  - Improvement: have the DevTools autoload write a `devtools_owner.json` with its PID
    and start time, and have `devtools.py` refuse to run (naming the other PID) when a
    live owner file belongs to a different process. Failing that, make `ping`'s
    "game not running" message list matching OS processes.

- Gap: **`run-method` requires an absolute `/root/...` path while every other verb takes
  the short form.** `--node Main/InputManager` returned `Failed: Node not found:
  Main/InputManager`, but `cmd`-registered verbs resolve `Main/...` fine via
  `get_tree().root.get_node_or_null`. The inconsistency cost a debugging round on a
  path that was actually correct.
  - [G-010] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.4.0
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
  - [G-012] status: fixed | fixed-in: 0.7.0 | seen: 2 | harness: 0.4.0
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
  - [G-015] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.4.0
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
  - [G-021] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.4.0
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
  - [G-022] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.4.0
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
  - [G-016] status: fixed | fixed-in: 0.8.0 | seen: 2 | harness: 0.4.0
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
  - [G-017] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.4.0
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
  - [G-020] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.4.0
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
  - [G-024] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: unknown
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
  - [G-025] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: unknown
  - Improvement: echo the *normalized* path in error messages, not the raw argv one.

- Gap: **`.gdignore` does not exclude a directory from `validate-all`** — added
  `addons/virtual_joystick/{previews,test}/.gdignore` so the vendored demo leaves the import
  and lint scan, but the validator still walks it:
  ```
  res://addons/virtual_joystick/test/test.tscn:
    [INFO] relative_nodepath: Node 'Player' property 'joystick_left' uses relative path: ...
  ```
  Two of the 28 validate-all findings are from a directory Godot itself is told to skip.
  - [G-026] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: unknown
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
  - [G-027] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-028] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-030] status: fixed | fixed-in: 0.8.0 | seen: 2 | harness: 0.7.0
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
  - [G-031] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-032] status: fixed | fixed-in: 0.8.0 | seen: 2 | harness: 0.7.0
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
  - [G-033] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-030] status: fixed | fixed-in: 0.8.0 | seen: 2 | harness: 0.7.0
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
  - [G-034] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-035] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-036] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-037] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-065] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0 (was G-036, reassigned — ID collision)
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
  - [G-066] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0 (was G-037, reassigned — ID collision)
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
  - [G-038] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-039] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-040] status: fixed | fixed-in: 0.8.0 | seen: 3 | harness: 0.7.0
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
  - [G-041] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-042] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-043] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-044] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-067] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0 (was G-044, reassigned — ID collision)
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
  - [G-045] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-046] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
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
  - [G-047] status: fixed | fixed-in: 0.8.0 | seen: 2 | harness: 0.7.0
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

## 2026-08-02 — HUD toolbar for the skill/land/bag panels, and freeing the cursor

- Value: **warranted** — runtime produced two claims the diff could not, and the second
  was a bug that predates this change by months.
  - Expected: that the strip really lands in UI2 with three on-screen buttons inside the
    viewport and clear of the hotbar and the points badge; that clicking one drives the
    existing InputManager path all the way to the panel opening; that the strip then hides
    itself and comes back on close; and that the cursor is MOUSE_MODE_VISIBLE during play.
  - Got: all four, plus the one nobody was looking for. `get-state --node
    /root/Main/UI2/SkillTreeUI/PointsBadge --property global_position` answered
    `{"x": -276.0, "y": 87.0}` on a 1920-wide viewport — the banked-points badge, the only
    cue that a level-up handed out a skill point, has been rendering 276px off the *left*
    edge of the screen for its entire existence. `_scale_badge()` anchored it TOP_RIGHT and
    then wrote `position = Vector2(-(width + margin), …)`, but `Control.position` is
    relative to the parent's top-left whatever the anchors say. Filed `gather-5p3`, fixed
    by writing offsets from the anchor; the badge now reads `{"x": 1644.0, "y": 87.0}` and
    is visible in the screenshot. Also: a real pointer event, `touch press --pos 1850,42`,
    opened the land panel — which is the whole point, because under the old
    MOUSE_MODE_CAPTURED no pointer event could reach a Control at all.
  - Cheaper: nothing. The badge bug exists only in a laid-out Control, and no unit test in
    this repo can build a `SkillTreeUi` — see the gap below. Lint, the 180-test suite and
    reading `skill_tree_ui.gd:429` all pass it silently; the comment on the line even
    asserts the wrong semantics out loud ("this position is measured from that corner").

- Gap: **`cmd skill_panel --args '{}'` toggles, so using it to read state changes it** —
  hit again, twice. `skill_panel --args '{}'` and `land_panel --args '{}'` were both called
  to check whether a toolbar button had opened a panel, and both reported `"open": false`
  because the read itself had closed what the button opened. The workaround was to stop
  using the verbs entirely and read `node-bounds …/PanelFrame | grep Visible`, which is a
  pure read and worked first time.
  - [G-047] status: fixed | fixed-in: 0.8.0 | seen: 2 | harness: 0.7.0
  - Improvement: unchanged from the original entry — give the toggle verbs a read-only
    sibling, or put the panel-open flags in the status provider.

- Gap: **no way to stand up a Control whose collaborators come from deep `@onready` node
  paths, so the badge bug could not be turned into a unit test** — `SkillTreeUi._ready()`
  builds the badge only after finding a `LevelUpManager` in the tree, and `LevelUpManager`
  resolves `$"../PlayerInfo/XpBar"` and `$"../../../../../ResourceManager"` at ready time.
  Standing up the second means a `ResourceManager2`, whose own `_ready()` dereferences
  `tile_map_handler.resource_found` and `tile_map_handler.tileMap` — so the fixture for a
  50-line badge is most of `main.tscn`. `_T.instantiate_ui()` takes a Node and handles the
  viewport, which is the hard half, but there is nothing for "give this node the neighbours
  its `@onready`s expect". The bug was therefore verified at runtime and left with no
  regression guard; `test_hud_toolbar.gd` covers the strip but cannot touch the badge.
  - [G-048] status: open | seen: 2 | harness: 0.7.0
  - Improvement: a `_T.stub_tree({"../PlayerInfo/XpBar": ProgressBar, …})` helper that
    materialises placeholder nodes at a set of node paths before the node under test enters
    the tree. It cannot satisfy a typed `@onready` that needs a real class, but it would
    cover the common case — a path that exists only so `get_node` does not error — which is
    what four of the five paths above are.

## 2026-08-02 — removed Q/E hotbar stepping, moved it to the arrow keys

- Value: **warranted** — the run existed because no existing primitive could deliver the
  event under test, and building the missing one is what proved the fix.
  - Expected: that Left/Right really step the hotbar through `_unhandled_key_input`, that Q
    and E no longer do, and that E still gathers — none of which the existing input verbs
    could reach, because they all dispatch `InputEventAction` and `_unhandled_key_input`
    only sees `InputEventKey`.
  - Got: exactly that, but only after adding the verb. The first attempt, `input tap gather`
    five times, reported `selected_index: 0` before and after — which looks like a pass and
    proves nothing, because the old buggy code would have reported the same. With
    `cmd press_key`: Right took the selection `0 -> 1 -> 2`, Left `2 -> 1`, the number key
    `4` selected index 3, and Q and E both left it at 3. `E` still gathers — `xp 0 -> 1`
    with the pickaxe held — so removing the hotbar's claim on it did not disturb the
    binding. The mutation check is the strongest evidence: putting `STEP_NEXT_KEY` back to
    `KEY_E` fails all three assertions of the new `test_hotbar_selection.gd`, one of them
    naming `gather` as the clashing action.
  - Cheaper: the new unit test alone came close and is the durable guard, but it checks the
    binding *table*, not the routing — it cannot show that Left actually reaches
    `step_selection` through the event pipeline. Nothing cheaper covered both.

- Gap: **the bridge has no raw-key primitive, so every raw-keycode handler in the project
  is unreachable from it** — `list-commands` offers `input_press` / `input_release` /
  `input_tap` / `input_sequence` / `input_actions`, and all of them dispatch an
  `InputEventAction`. `_unhandled_key_input` is only ever called with an `InputEventKey`,
  so the hotbar's number keys, its step keys and the Q/E pair were all invisible to the
  harness. That is not a small corner: it is why `E` being simultaneously `gather` and
  "next hotbar slot" — every pickaxe swing advancing the hotbar a slot — survived lint, the
  full unit suite and a complete `/verify` run earlier the same day.
  - [G-049] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: a generic `key <press|release|tap> --key NAME` verb in the harness core,
    taking the name `OS.find_keycode_from_string` accepts and setting both `keycode` and
    `physical_keycode` (projects split between the two — this one compares `keycode` in
    GDScript while `project.godot` binds by `physical_keycode`). Worked around by
    registering `press_key` in `devtools_ext/commands.gd`; it is ~25 lines and nothing in
    it is project-specific, so it belongs upstream rather than in every project that
    reads a raw key.

## 2026-08-02 — Answered "why does copper never spawn?" (read-only, no code change)

- Value: **inconclusive** — the harness was not run at all; the question was fully answered
  by reading four tuning files, and there was nothing to verify because nothing changed.
  - Expected: nothing — I never formed a runtime prediction, because the first grep hit
    (`STARTING_RESOURCES` in `world/resource_manager2.gd:45`) already settled it.
  - Got: `STARTING_RESOURCES` lists coal and iron but not copper; `skill_tree.gd:121-133`
    gates `Types.Item.CopperResource` behind the `iron_age` / "Copper Age" node. Reported
    the inversion (copper is the *lower* tier by pickaxe speed and smelt order, yet is the
    gated one, and its `spawn_weight` 0.8 sits below iron's 1.0) without touching the game.
  - Cheaper: nothing — reading was already the cheap path. Worth recording the inverse of
    the usual failure: the temptation here was to launch the game and `island_census` to
    "confirm no copper spawns", which would have cost a launch to re-observe the symptom
    the user had already reported and would not have located the gate.

- Gap: no gaps this turn — the harness was never invoked, so it had no opportunity to fall
  short. Logged deliberately so this turn is distinguishable from a forgotten entry.

## 2026-08-02 — Swapped the copper/iron gate so ore rarity tracks the crafting tier (gather-8al)

- Value: **warranted** — runtime placed a resource the seeder had never placed before, and
  named the post-load unlocked set, neither of which the diff or the unit suite could show.
  - Expected: copper has never been placed by the world seeder before — it was skill-gated,
    and its art lives on placeholder tileset source 10 rather than source 4 like every other
    starting resource. Runtime should show whether the seeder actually places source-10
    tiles at generation, and whether iron is genuinely absent from a fresh world.
  - Got: exactly that. A fresh world censused `home: {Coal 3, Copper 1, Stone 14, Tree 9}`
    and `ore: {Coal 11, Copper 2, Stone 2}` — copper placed from source 10 at generation,
    iron absent from every region. After `learn_skill smelting`, 60 rolls of
    `add_random_resource` produced `home: Iron 2` / `ore: Iron 1`, so the gate opens as well
    as closes. The strongest single line came from `gather_stats` after calling `loadObject`
    with `{"resources": []}` — the old-save case: `"spawnable": ["Stone","Tree","Stone",
    "Coal","Copper"]`, proving the new re-seed in `loadObject` restores copper without
    handing back the iron that save never earned. `"tuning"` in the same reply read
    `Copper 1.0 / Iron 0.8 / Gold 0.4`, the inverted ladder now upright.
  - Cheaper: nothing for the placement half — only the running game puts a source-10 tile
    through the seeder. The *tuning* half was settled by `test_ore_chain.gd` in 4s, and the
    two new tests there (mutation-checked: reverting `STARTING_RESOURCES` fails them with
    "iron spawns unlocked but copper is the first bar the furnace can make") are the durable
    guard. Runtime earned its keep on world-gen and on the load path, not on the numbers.

- Gap: **reach cannot see a RefCounted, so the file carrying the actual design change scores
  as unreached** — `verify_ledger.py reach` reported `NOT reached: ... systems/skill_tree.gd`,
  yet that file holds the `[Types.Item.IronResource]` unlock this whole change moved, and the
  run demonstrably exercised it (`cmd learn_skill --args '{"id":"smelting"}'` → `"learned
  smelting"` → iron nodes appear in the census). Reach intersects the diff against `script`
  fields in a `scene-tree` snapshot, and `SkillTree` extends `RefCounted` precisely so tests
  can build it without a SceneTree — it is never any node's script and so can never be
  reached by construction. Same for `crafting/recipes.gd`: autoloads live at `/root`, outside
  the `Main`-rooted snapshot. A verdict that silently downgrades on these is measuring the
  object model, not the run.
  - [G-050] status: open | seen: 4 | harness: 0.8.0
  - Improvement: have `reach` credit a file when a `cmd`/`run-method` call during the run
    touched it — the client already knows every verb it invoked, so recording the invoked
    verb names in the run row and letting projects map verb -> files would cover both
    RefCounted helpers and autoloads. Failing that, snapshot from `/root` rather than the
    main scene so autoloads at least appear. Worked around by reading the census delta after
    `learn_skill` and reporting reach as partial-by-construction in the summary.

## 2026-08-02 — Committed the ore-gating change (re-gated on a tree that had moved)

- Value: **warranted** — the headless gates caught that the working tree was no longer the
  one the earlier runtime run verified, which is the one thing a stale green run cannot say
  about itself.
  - Expected: nothing new from the game; this was a commit turn. What I did predict was that
    `git status` would match the 8 files I left behind.
  - Got: it did not. The tree had grown to 13 modified files — an ore-scarcity pass had
    landed inside `items/resources.gd` (every ore weight x0.7, plus new `ORE_TYPES` /
    `MAINLAND_ORE_SHARE` consts) and an unrelated splash-text change had appeared in
    `ui/splash_text.gd` + `systems/level_up_manager.gd`. Re-running the gates gave
    `Total: 192 | Passed: 192` against the 185 the earlier run had asserted, i.e. seven tests
    that did not exist when I called the suite green. Committing on the strength of the
    earlier run would have shipped ~180 unreviewed lines under a message describing none of
    them; the split into "ore work now, splash text left alone" came directly from this.
  - Cheaper: `git status` alone would have shown the file list, but not that the new code was
    green — and the whole reason to re-check was that the *contents* of a file I was
    committing had changed underneath me. Lint + tests, 40s, was the right price.

- Gap: no gaps this turn — the harness was used only for its headless half, which did exactly
  what it claims. Logged explicitly so this turn is distinguishable from a forgotten entry.

## 2026-08-02 — Corrected the stale TUNING header and pushed the branch

- Value: **overkill** — a comment-only edit followed by a push. Lint confirmed what reading
  the five changed lines already settled.
  - Expected: nothing. The change was five lines of prose inside a comment block; there was
    no runtime behaviour to predict, and I said so before running anything.
  - Got: `lint: 0 error(s), 7 warning(s) -> exit 0`, i.e. the file still parses. That is the
    entire content of the check. The unit suite was not re-run, correctly — no code path
    changed.
  - Cheaper: nothing, and that is the point: lint alone was already the cheap option at ~8s,
    and skipping even that on a "just a comment" edit is how an unterminated block comment
    reaches a push. Recorded as overkill rather than warranted because the run confirmed
    only what was already known, which is exactly the case that otherwise goes unlogged.

- Gap: no gaps this turn.

## 2026-08-02 — Denser themed islands, thinner mainland ore, one coalesced XP splash

- Value: **warranted** — runtime gave the two numbers the diff cannot: what the density
  constant becomes as actual island node counts, and how many labels a burst of xp leaves
  in the world.
  - Expected: the forest and ore islands each stock ~30% more nodes than the old 0.3
    density (per-region census up from ~23 to ~30 each), and a rapid burst of xp awards
    leaves exactly one SplashText in the world container carrying the summed total instead
    of one node per award.
  - Got: half right, and the half that was wrong mattered. `island_census` reported
    `forest land=66 cap=25 nodes=17` and `ore land=68 cap=26 nodes=18` — the caps moved as
    predicted (19->25, 20->26) but the *stocked* counts are 17/18, not ~30, because
    `SEED_FILL_RATIO` fills to 70% of cap and the respawn timer walks the rest up over
    play. The +30% is real (13/14 before) but the absolute number I predicted was off by
    nearly half, which no reading of `ISLAND_RESOURCE_DENSITY := 0.39` would have caught.
    `home land=65 cap=40` also confirmed the mainland is still pinned to
    `MIN_RESOURCE_CAP` and untouched by the island constant. On the splash: five separate
    `add_xp(1)` calls left `container children: 1` reading `+5 XP`, and a 4-award burst
    read `+7 XP` at `scale: 0.264` against the 0.2 base, i.e. the swell is running. The
    guard held too — a level-crossing award still put 9 children in the container, so
    LEVEL/SKILL POINT splashes are not being swallowed by the xp label.
  - Cheaper: the unit tests settled the coalescing identity, the colour ramp, the distance
    guard and the mainland ore share (`ordinary ground rolled ore ...%` vs
    `MAINLAND_ORE_SHARE`) for ~20s headless. Nothing cheaper could produce the island node
    counts — that number is generation plus seeding plus the fill ratio, and it is the
    entire claim of the density change.

- Gap: **reach cannot see a node that only exists for 0.85s** — `verify_ledger.py reach`
  reported `NOT reached: ... ui/splash_text.gd` on a run whose central assertion was
  `get-state --node /root/Main/Node2D/SplashTexts/SplashText --property text` returning
  `+5 XP`. Reach intersects the diff against `script` paths in a `scene-tree` snapshot, and
  every SplashText had freed itself by the time the Phase 5 snapshot was taken, so a file
  the run demonstrably exercised is filed as unverified. Worked around by taking the
  evidence from the live `get-state` and saying so in the summary — but the ledger row now
  under-reports, which is the one thing the ledger exists to prevent.
  - [G-051] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: have the game side accumulate a set of script paths seen across *every*
    `scene-tree` call in the session (or a `scripts-seen` verb that reports it), so reach is
    a union over the run rather than a single instant. A transient node — a splash, a
    particle, a projectile, a pickup — is exactly the kind of thing worth verifying at
    runtime and exactly the kind reach currently cannot credit.

## 2026-08-02 — Committed the parallel splash-text work and closed the session out

- Value: **warranted** — the gates were the only thing standing behind a commit message for
  ~225 lines I did not write.
  - Expected: the headless suite either covers the splash-text coalescing or it does not, and
    that decides whether I can honestly commit someone else's in-flight work or have to leave
    it in the tree.
  - Got: `Total: 192 | Passed: 192`, with `git diff test/unit/test_splash_text.gd` naming five
    new tests — `test_xp_awards_in_one_place_become_a_single_label`,
    `..._walks_up_the_colour_ramp`, `..._swells`, `test_xp_far_away_gets_its_own_label`,
    `test_a_finished_xp_label_does_not_absorb`. That last one is the load-bearing one: the
    change adds a `static var _live_xp` holding a node across frames, and a static reference
    to a freed node is exactly the leak this project already fixed once in HealthManager. A
    test naming it meant the risk had been considered, so the commit could say so.
  - Cheaper: reading the diff, which I did anyway and which is what let me describe the
    generation-stamped guard accurately. The suite added the part reading cannot give — that
    the five tests actually pass on this tree rather than on the tree they were written
    against. Both were needed; neither alone was enough to commit code I had not authored.

- Gap: no gaps this turn.

## 2026-08-02 — Merged hud-affordances into main locally

- Value: **warranted** — the merge brought together two branches' worth of work that had
  never been in one tree at the same time, and the gates are what say the combination holds.
  - Expected: a clean merge (main was an ancestor, so no textual conflict was possible), but
    the interesting question was semantic: the branch carried an ore-tuning change and an
    xp-splash change that had been developed in parallel sessions and only ever tested
    separately. `LevelUpManager.add_xp` is on both paths — it awards the xp a gather pays and
    it spawns the splash — so a break would surface there, not in the diff.
  - Got: `Total: 192 | Passed: 192` and `lint: 0 error(s), 7 warning(s)` on the merged tree,
    same counts as each side reported alone, so nothing was lost or double-counted in the
    merge. `git status` clean and `main...origin/main` at `7 0`.
  - Cheaper: `git merge` alone reports conflicts, and there were none — but "no conflict" and
    "still works" are different claims, and only the suite makes the second one. 40s for the
    only evidence that the two parallel branches compose.

- Gap: no gaps this turn.

## 2026-08-02 — pushed main (8 commits) and synced beads to the Dolt remote

- Value: **overkill** — no gameplay, script, or scene change happened this turn; the harness was correctly not run at all.
  - Expected: nothing — a push of already-committed, already-verified work has no runtime claim to make.
  - Got: n/a, `/verify` was not invoked. `git status` reported a clean tree and `[ahead 8]`; `git push` reported `ea52901..051ab89  main -> main`.
  - Cheaper: exactly what was done — `git status --short --branch` alone, ~1s.

- Gap: no gaps this turn — the harness was out of scope for a pure push, and nothing about the push needed a capability it lacks.

## 2026-08-02 — Restructured main.tscn into World / UI / Systems and rewired every path

- Value: **warranted** — lint exited 0 and all 192 unit tests passed while `main.tscn` was still broken in three independent places; only launching the game found them.
  - Expected: the game boots with the restructured tree and every rewired path resolves - specifically that `ResourceManager.tile_map_handler = NodePath("../..")` now reaches Main and not Systems, that `Systems/InventoryManager` still readies after the `UI` CanvasLayer so the hotbar's `@onready` fields are non-null, that `camera_hud` still finds its children under the renamed `HUD`, and that gathering still awards XP through the moved ResourceManager into the renamed `LevelUpManager`. Neither lint nor the unit suite loads `main.tscn`, so none of this is observable without the running game.
  - Got: three real breaks, each invisible to both headless gates. (1) `ERROR: Node not found: "../LevelUpUI" (relative to "/root/Main/World/Player/Camera2D/HUD/FloatingText")` then `Invalid access to property or key 'added_xp' on a base object of type 'null instance'` — `ui/floating_text.gd:11` held the one `LevelUpUI` reference no rename pattern matched. (2) After fixing that, `Cannot call method 'connect' on a null value. at: Player._ready (res://player/player.gd:121)` — the exported NodePaths *inside* `main.tscn` (`Player.input_manager`, `Player.resourceManager`, `ResourceTimer.resourceManager`) still pointed at `../../InputManager`, and a null `@export` NodePath raises nothing on its own. (3) Removing the root's 18 stale scene groups made `test_chest.gd`'s `get_nodes_in_group("InventoryManager")[1]` out of bounds, and revealed `pick_up.gd`'s `[0]` had been resolving to the *root*, never the real `SoundManager`. Post-fix: clean boot, gather 25->26 xp, `FpsLabel` scale `0.4125` = authored `0.275` x `1.5` (proving `SCALED_CHILDREN` matched the new name rather than silently `continue`-ing), and the pre-restructure `saveFile` restored position `(8,8)` and level 6 through the new `LEGACY_PATHS` map with zero `no node at` warnings.
  - Cheaper: nothing. The `@export` NodePath failure in particular has no static signature — `lint_project.gd` reports `SceneState: … NodePath unresolved` for *every* NodePath in the file as a documented false positive, so the three genuinely-broken ones were indistinguishable from the seven fine ones until `Player._ready` ran.

- Gap: **lint cannot distinguish a genuinely unresolvable scene NodePath from its own false positives** — `lint_project.gd` printed `res://main.tscn | : SceneState: 'resource_manager' NodePath unresolved: Systems/ResourceManager` for correct paths and stayed silent about `Player.input_manager = NodePath("../../InputManager")`, which pointed at a node that no longer existed. Workaround was launching the game and reading `Player._ready` blow up. The checker already walks `SceneState`; resolving each NodePath against the scene's own node list would separate "cannot see into an instanced sub-scene" from "this target is not in this file", and the second class is exactly what a restructure produces.
  - [G-052] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: in the `SceneState` pass, resolve each NodePath against the set of node paths declared in the same `.tscn`. Report `ERROR` when the path is rooted in this scene and matches nothing; keep the current advisory `INFO` only when it crosses into an instanced sub-scene it genuinely cannot see.

- Gap: **`reach` cannot see code that runs but owns no node** — the ledger reported `NOT reached: devtools_ext/commands.gd`, yet every assertion this run made went through it (`add_xp`, `goto_resource`, `gather_state`, `island_census`, `player_state`). Same for `items/pick_up_manager.gd`, whose pickups were created and vacuumed between two snapshots. Reach is computed by intersecting the diff against `script`/`scene_file` paths in a `scene-tree` snapshot, so an autoload, a devtools extension, or a transient node is structurally invisible to it and lands in the "not reached" list beside files that genuinely were not loaded.
  - [G-053] status: fixed | fixed-in: 0.8.0 | seen: 3 | harness: 0.7.0
  - Improvement: fold the autoload list (`project.godot [autoload]`) and the configured `extension_script` into the reached set, and report transient-node scripts separately as `reached-transient` rather than as not reached — so the not-reached list stays a list of things that actually went unverified.

## 2026-08-02 — Moved LevelUpManager out of the camera HUD into Systems

- Value: **warranted** — the move inverts this node's ready order against every consumer that binds to it by group, and both resulting breaks survived green lint and 192 green tests.
  - Expected: moving LevelUpManager out of the camera HUD into Systems inverts its ready order relative to Player and the UI layer, so anything that binds to it by group during `_ready` will silently find nothing; runtime should show which consumers break and whether the XP bar, the +N xp readout and the skill panel still work.
  - Got: exactly two consumers broke, and only one of them said so. `ERROR: SkillTreeUi: no LevelUpManager in the scene; the panel will be inert` at boot — the panel lives in the `UI` CanvasLayer, which `main.tscn` declares before `Systems`, so `get_nodes_in_group("LevelUpManager")` was still empty in its `_ready`. `ui/floating_text.gd` had the identical problem one branch over and would have produced *no* diagnostic at all — it holds a typed `LevelUpManager` and connects one signal, so a null would have meant the "+N xp" readout simply never updated. Both now bind via `call_deferred`. After the fix: XP bar reads `value 7.0 / max_value 10.0` against a model reporting `xp 7 next 10` (proving the lazy `_xp_bar_node()` resolver spans HUD-to-Systems), `XpLabel.text = "+7 xp"`, `learn_skill swift_hands` moved `gather_speed_mult` 1.0 -> 0.85, and the legacy `saveFile` still carrying `"/root/Main/Node2D/Player/Camera2D/UI/LevelUpUI"` restored to level 6 / xp 32 with zero unmigrated entries.
  - Cheaper: nothing. Ready order is not visible in a diff — `main.tscn` says nothing about which branch registers its groups first, and the unit suite never instantiates the scene, so both breaks were reachable only by booting.

- Gap: no new gaps this turn — [G-052] (lint cannot tell a genuinely unresolvable scene NodePath from its own false positives) was not re-triggered because this change moved a node rather than repointing an exported NodePath, and [G-053] (reach cannot see code that runs but owns no node) reported the same eleven files again but did not obstruct anything.

## 2026-08-02 — Re-tuned the XP curve so the opening stops handing out six skill points

- Value: **overkill** (runtime half not attempted — the orchestrator forbade launching the
  game, since another agent held the single-file DevTools bus). The change is two integers
  and a lot of prose; the curve is pure arithmetic behind two `static func`s, so the
  headless unit suite reaches 100% of what changed and a running game would only have
  re-derived the same numbers slower.
  - Expected: `XP_FIRST_LEVEL 10 -> 40` and `XP_GROWTH 1.30 -> 1.19` produce thresholds
    40, 48, 58, 70, 84, 100 and a 16th-point total of 578 — predicted from a PowerShell
    model of `int(ceil(t * growth))` before running anything, and predicted to still clear
    `test_the_whole_tree_is_reachable_in_one_run`'s unmoved 650 bound.
  - Got: the engine printed `CURVE: 40, 48, 58, 70, 84, 100, 119, 142, 169, 202, 241, 287,
    342, 407, 485, 578` — identical to the model, which is the one thing worth having
    checked, because `ceil()` on a float product is exactly where a hand-computed curve
    goes wrong (the issue text itself quotes 10/1.30 as "10, 13, 17, 22, 29, 38"; the
    engine's real values are 10, 13, 17, 23, 30, 39, so the reported "38" was already off).
    Full suite `Total: 193 | Passed: 193 | Failed: 0`, exit 0, zero `SCRIPT ERROR` in
    stderr; lint `0 error(s), 7 warning(s) -> exit 0`, all seven the documented
    `SceneState: … NodePath unresolved` false positives.
  - Cheaper: the PowerShell model alone, ~2s — it turned out to agree exactly. What it
    could *not* have told me is that it agreed, which is the whole reason the engine was
    asked. Reading `xp_for_level()` (12 lines) plus running the one test file would have
    been the honest minimum, and is roughly what was done.

- Gap: **no way to evaluate an expression against project classes headlessly** — needed a
  single value (`LevelUpManager.xp_for_level(n)` for n in 2..17) straight from the engine
  rather than from a model of it. There is no verb for this: `run-method` is bridge-only
  and the bridge was off-limits, and `run_tests.gd` only runs discovered `test_*` methods.
  Workaround was writing `test/unit/test_zzz_scratch_curve.gd` whose whole body is
  `return _T.assert_true(false, "CURVE: " + ", ".join(out))`, running it with
  `--file test_zzz_scratch_curve` to read the value out of the *failure* message
  (`Selected: 1 of 194 discovered`, exit 1), then deleting the file. Abusing a failing
  assert as a print statement means the artifact that answers the question is one that
  must never be committed, and a forgotten cleanup ships a permanently-red suite.
  - [G-054] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: a headless `tools/eval.gd` taking a GDScript expression on the command
    line, resolving `class_name` globals, and printing the result — the no-game sibling of
    `run-method`. `godot --headless --path . --script res://tools/eval.gd -- --expr
    'LevelUpManager.xp_for_level(7)'`. Cheap to build (one `Expression.parse/execute`) and
    it removes the only reason to ever create a scratch test file.

## 2026-08-02 — Seeded a fixed handful of iron and gold onto the ore island (gather-frv)

- Value: **insufficient** (runtime half forbidden — the orchestrator held the single-file
  DevTools bus for another agent, so headless only). Reach decides this, not impression:
  the 200-seed sweep executes `IslandManager.vein_cells` and the constants, which is the
  genuinely uncertain half, but nothing in the suite ever executes `seed_ore_veins()`, the
  `is_occupied` guard, the `set_resource -> _on_resource_added -> set_tile` write, or the
  `ore_veins_seeded` save round-trip. "Four iron and two gold are visibly standing on the
  ore island of a fresh world, and are still there after `[` then `]`" remains an argument
  from reading the code, not an observation.
  - Expected: the sweep would show whether ring-2/ring-3 candidates survive
    `ISLAND_EDGE_BITE` biting into a radius-6 disc — i.e. whether the inward walk and the
    all-eight-neighbours interior test are ever actually needed, and whether any seed ends
    up short of six veins or with two veins on one cell.
  - Got: `[PASS] test_ore_island_veins_land_on_solid_ground_across_many_seeds (32ms)` —
    200 seeds against 200 distinct ore-island centres taken right around the placement
    ring, six distinct interior cells every time, none outside the 3-tile ring. It also
    caught a real defect on the first run, in my own assertion rather than in the feature:
    `seed 4001: vein at (29, 3) is 3.6 tiles out, past the 3-tile ring` — a ring-3 cell is
    `cos/sin` rounded to the grid, so it can be `(2, 3)`, Euclidean 3.606. That is exactly
    the off-by-geometry mistake a sweep surfaces and one playthrough never would. Full
    suite `Total: 189 | Passed: 189 | Failed: 0`; lint `0 error(s), 7 warning(s) -> exit 0`
    with `UIDs: OK`.
  - Cheaper: for the constants, the counts and the prose — reading them, 0s. For the
    placement, nothing cheaper existed: the island's shape is a noise field resampled per
    seed and per centre, and CLAUDE.md is right that one run is one seed. What would have
    been cheaper than *this* work is a way to run the seeding pass itself headlessly; see
    the gaps below.

- Gap: **[G-048] again, from the world-generation side rather than the UI side** — the same
  "the fixture for a small change is most of `main.tscn`" wall, hit by a non-Control. Unit-
  testing `seed_ore_veins()` needs a `ResourceManager2` (whose `_ready` dereferences
  `tile_map_handler.resource_found` and `tile_map_handler.tileMap`), a `TileMapHandler` with
  a real terrain-solving TileMap, and the `GameItems`/`Resources` registries, so the reachable
  surface stops at the one `static func` I could carve out. The workaround was to design for
  it — `vein_cells` is deliberately static and pure so that the seed-dependent half is
  testable at all — which is a good shape but it is a shape the harness forced, and the
  imperative half (place, guard, flag, persist) is guarded by nothing.
  - [G-048] status: open | seen: 2 | harness: 0.7.0
  - Improvement: as filed — plus the observation that the helper wants to cover plain
    `Node`s, not only `Control`s: `_T.stub_tree()` framed around `instantiate_ui` would not
    have helped here.

- Gap: **a `--file` selector cannot report its own result when an unrelated test script
  fails to compile** — `run_tests.gd -- --file test_island_manager` printed
  `Selected: 7 of 189 discovered (file 'test_island_manager')` and
  `Total: 189 | Passed: 7 | Failed: 0`, then `RUNNER ERROR - the suite did not run to
  completion (exit 2)`. The 2 came entirely from `res://test/unit/test_mobile_controls.gd`,
  which another agent's in-flight `ui/mobile_controls.gd` (`Identifier "HOTBAR_CYCLE" not
  declared`) breaks — a file my diff does not touch and my selector did not select.
  Discovery loads every script before the selector is applied, so exit 2 is contagious: in a
  parallel-agent repo the documented "2 means you verified nothing" reading is wrong here,
  because the selected 7 verifiably ran and passed. Workaround was reading the per-test
  lines and the `Selected:` line and disregarding the exit code, which is precisely the
  habit the exit codes exist to prevent.
  - [G-055] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: score the exit code over the *selected* set. A discovery-time compile
    failure in an unselected script should be a printed `[ERR]` and a distinct signal (a
    `Discovery errors: N` line, or exit 3), never the same 2 that means "your run did not
    happen". With a selector active, exit 1 if a selected test failed, 0 if none did, and
    let the unselected wreckage be reported without being fatal.

## 2026-08-02 — merged the mobile MINE/HIT/BREAK buttons into one contextual primary (gather-mxf)

- Value: **warranted** — the unit run produced the one claim the diff genuinely could not,
  and it is the claim the whole change turns on.
  - Expected: that the risky half of a contextual hold button is the *release*, and that
    `send_action(_button_action.get(button), false)` would happily send `attack` to close a
    press that had sent `gather` the moment the world moved under the finger — leaving
    `ResourceManager2`'s hold timer with nothing left to stop it (gather-3zg from a new
    direction). I wrote `_latched_action` before running anything, predicting the test would
    only confirm it.
  - Got: it confirmed it, but the run's real contribution was the *reverse* direction I had
    not thought to guard. `test_a_context_flip_mid_hold_still_releases_the_action_it_pressed`
    asserts `sent[1] == ["attack", false]` after the context flips back to gather mid-swing,
    and then that "the next press re-resolves" — which is what caught that the latch has to
    be erased in `_release()` *after* the last finger and not in `_press()`, and that
    `_release()`'s early return for a second finger on the same button must not erase it.
    `test_sliding_off_the_button_releases_what_it_pressed` covers the drag path, which is a
    second, separate call site into `_release()` that a press/release-only test never reaches.
  - Cheaper: nothing meaningfully cheaper. Lint (`0 error(s), 7 warning(s) -> exit 0`, 4s)
    settled the syntax and would have said nothing about pairing; reading `_press`/`_release`
    is what produced the hypothesis but not the second call site.

- Gap: **the live half of the resolution rule is unreachable from a headless test, so the
  test seam I added to make it testable is also what lets the real code go unrun** —
  `resolve_primary(item, enemy_in_reach)` is static and pure and its 12-row table is walked
  exhaustively, but the two functions that *supply* those arguments in the game,
  `_held_item()` (walks `get_parent().get_node_or_null("HotBarInventory")` then
  `Object.get("selected_slot_data")`) and `_enemy_in_reach()` (filters
  `get_tree().get_nodes_in_group("SaveLoad")` by `is Enemy` against `PlayerManager.player`),
  are executed by no test in the suite. `instantiate_ui` gives the overlay a `SubViewport`
  with no sibling `HotBarInventory`, no `PlayerManager.player` and no `Enemy`, so both return
  their null-guard answers and the whole live path is a straight line to
  `resolve_primary(null, false)`. `run_tests.gd -- --file test_mobile_controls` reports
  `Selected: 14 of 203 discovered (file 'test_mobile_controls')`, `Total: 203 | Passed: 14 |
  Failed: 0 | Skipped: 189`, exit 0 — a clean pass that is silent about whether the button
  can read the world at all. The workaround was `var primary_resolver: Callable`, injected by
  every test that needs a non-default answer; it makes the *pairing* assertable, which is the
  part that can strand a timer, and explicitly gives up on the *reading*. A typo in the
  `"selected_slot_data"` string literal would pass this entire suite.
  - [G-056] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: a `_T.stub_siblings({name: Node})` that mounts named siblings alongside the
    control `instantiate_ui` creates, plus a documented way to populate an autoload field
    (`PlayerManager.player`) and a group for the duration of one test. Both `_held_item()` and
    `_enemy_in_reach()` would then be one three-line fixture away from being asserted, and the
    resolver seam could go back to being a convenience rather than the only route in. This is
    the same shortfall [G-048] describes from the world-generation side — "the reachable
    surface stops at the one `static func` I could carve out" — arriving at a UI file, which
    suggests the fixture, not the file, is what is missing.

- Gap: **no runtime pass at all this turn, by instruction** — the orchestrator forbade
  launching the game or running `/verify` because the DevTools bridge is a single shared
  command/result file pair and sibling agents were live (the same collision [G-055] was filed
  against from the other side: another agent's `--file` run took exit 2 from *this* file
  mid-edit). So `.devtools/verify-runs.jsonl` gets no row for a change that is entirely about
  what a thumb sees and does, and the three things only the running game can answer —
  whether `CONTEXT_POLL_INTERVAL = 0.15` repaints fast enough to be believed, whether
  `ENEMY_REACH = 28.0` flips at the moment it should rather than across the clearing, and
  whether BREAK at the top-right is actually reachable one-handed — are unverified by
  anything but argument. Not a harness defect; recorded so the ledger's denominator is not
  quietly wrong about a diff of this shape.
  - [G-057] status: open | seen: 1 | harness: 0.7.0
  - Improvement: the per-session bus already exists (`-- --devtools-session <id>` +
    `--session <id>`), but `user://` is still shared for screenshots, baselines and the
    `.godot/` import cache, so it is not enough on its own and the standing advice is a
    manual project copy plus `GODOT_USERDATA`. A `devtools.py launch --isolated` that does the
    copy, the session id and the userdata dir in one command would make "verify inline" the
    default in a parallel-agent repo instead of something an orchestrator has to forbid.

## 2026-08-02 — Juice pass: trauma shake, per-swing gather impact, pickup pop, hit-stop (gather-ydm)

- Value: **insufficient** — lint and 228 tests both went green and neither of them can see a
  single thing this change is *for*. Reach was zero by construction: no game was launched, so
  `.devtools/verify-runs.jsonl` gets no row and nothing observed a pixel move.
  - Expected: that headless would settle the two invariants that fail *silently* (shake
    reaching exactly zero; `Engine.time_scale` always being handed back) and would be unable
    to say anything at all about the ~12 tween/particle/procedural effects that are the
    actual deliverable.
  - Got: exactly that, and the split is worth quoting. `test_shake_decays_to_exactly_zero`
    asserts `camera.offset == Vector2.ZERO` after `SHAKE_DURATION + 0.1`, which the *old*
    implementation could never have passed — `lerpf(x, 0, k)` is geometric, its `if
    shake_strength > 0` guard therefore stayed true forever, and no line in the file ever
    assigned `Vector2.ZERO`, so the camera was being given a fresh random offset every frame
    for the rest of the session after the first hit. That is a real claim the diff alone does
    not make. `test_hit_stop_survives_the_trigger_being_freed` is the other one. Against that:
    the gather squash, the chip bursts, the pickup pop and land squash, the collect sparkle,
    the death pop, the knockback squash, both screen flashes and the gather-bar pulse have
    **zero** assertions between them, because headless pumps no frames and has no viewport.
    25 of 25 passed and I still do not know whether the game feels different.
  - Cheaper: for the shake and hit-stop halves, nothing — those needed the tests and got real
    value from them. For everything else, `/verify` with a screenshot and a `step-time 0.4`
    mid-gather would have been the *only* thing worth running, and it is the one thing that
    was off the table.

- Gap: **[G-057] again — no runtime pass at all, by instruction, on a change that is 100%
  visual.** Same collision as last turn: the bridge is one shared command/result file pair, a
  sibling agent was live, so `godot --path .`, `/verify` and every `devtools.py` verb were
  forbidden. Last turn this cost a mobile-controls diff its runtime row; this turn it costs a
  diff whose *entire* acceptance criterion is "does a five-year-old notice". The harness
  version came from lint's own banner (`lint: godot-selftest-harness 0.7.0`) rather than
  `harness-version`, because even that verb was out of bounds.
  - [G-057] status: open | seen: 2 | harness: 0.7.0
  - Improvement: unchanged from last turn — `devtools.py launch --isolated` doing the project
    copy, the session id and `GODOT_USERDATA` in one command. Two consecutive turns have now
    shipped un-runtime-verified work for the same reason, which is the strongest argument for
    it so far.

- Gap: **the harness owns `Engine.time_scale` and has no way to say so, or to ask who else
  does.** `dev_tools.gd:1412` (`_cmd_set_game_speed`) writes it unconditionally and reports
  `previous_scale`; `dev_tools.gd:1469` (`_cmd_step_time`) pins it to 1.0 and restores
  `previous_scale` afterwards. Neither has any notion of the *game* also driving it, which is
  exactly what hit-stop does. Two concrete failure modes fall out of reading those two
  handlers, and I had to design around both without being able to observe either: a
  `set-game-speed` issued during a dip has its `previous_scale` recorded as `0.12` and would
  be "restored" to a value that was never the session's intent; and a `step-time` sampling
  across a dip has its process clock stretched, which surfaces as the `budget_exhausted`
  warning — i.e. as a *starved tree*, which is a completely different diagnosis from "the game
  deliberately slowed down for 100ms". My mitigation was to make `Juice.hit_stop` refuse to
  engage unless `Engine.time_scale` is already exactly 1.0, so the two never overlap in the
  engaging direction; that is a decision I made from source-reading, and it is untested
  against the actual verbs.
  - [G-058] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: a `time-scale` status field in the standard status provider (who set it, and
    when), plus `step-time` reporting `time_scale_changed_during: bool` instead of folding a
    deliberate game-side dip into `budget_exhausted`. That turns "is this a hitch or is this
    hit-stop?" from an argument into a field.

## 2026-08-02 — runtime pass over the four-stream session (XP curve, ore veins, juice, mobile primary button)

- Value: **warranted** — runtime produced three claims the diff could not, one of which
  invalidated my own measuring instrument mid-run.
  - Expected: the camera returns to exactly Vector2.ZERO after a shake decays (the old code
    never did), Engine.time_scale returns to exactly 1.0 after overlapping hit-stops and
    cannot be left stuck, and the ore island carries 4 iron + 2 gold on a fresh world — none
    of which any headless test executes.
  - Got: all three, plus one I had not predicted. `island_census` returned
    `"ore": {"Coal":2,"Copper":8,"Gold":2,"Iron":4,"Stone":2}` while `gather_stats.spawnable`
    returned `["Stone","Tree","Stone","Coal","Copper"]` — the veins are present *and* the roll
    still cannot produce them, which is the whole design in two readings. Camera went
    `trauma: 0.0 / offset {0.0, 0.0}` and was byte-identical 3s later. Hit-stop: after two
    overlapping `_on_died()` calls the trauma-decay probe read `0.666680`, against `0.666666`
    for a known-1.0 clock and `0.933333` for a known-0.2 clock. The unpredicted one: a single
    150 XP award moved `points: 0 -> 9`, i.e. the `SceneTreeTimer` refactor of
    `_splash_level_up` did not break multi-level banking inside `add_xp`'s threshold loop.
  - Cheaper: nothing. The seeding path, the live `time_scale` writes and the live
    `_held_item()` resolution are all absent from the headless suite by construction — 228
    unit tests passed without touching any of them.

- Gap: **`wait-frames` is time_scale-independent, which silently invalidates it as a clock probe**
  — I used `time python tools/devtools.py wait-frames 60` to check whether hit-stop had left
  `Engine.time_scale` stuck, and got `real 0m0.729s` after a kill against `0m0.745s` at rest.
  That reads as a clean pass. It is not evidence of anything: calibrating against a *known*
  slow clock gave `set-game-speed 0.2` → `wait-frames 60` = `0m0.680s`, identical. Godot's
  `time_scale` scales delta, not the tick rate, so physics still ticks 60x per real second and
  the verb cannot see the clock at all. Had I not calibrated, I would have reported the
  hit-stop safety property as verified on the strength of a measurement that could not fail.
  Workaround: used camera `trauma` decay as the probe instead — it advances on scaled delta,
  and discriminated 0.667 / 0.933 / (0.96 predicted for a stuck 0.12 dip) cleanly.
  - [G-059] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: have `performance` report `Engine.time_scale` in its output. It is one line,
    it is the state most likely to be left dirty by a test run, and there is currently **no**
    verb that reads it — `set_game_speed` only writes. A `get-state` on a node cannot reach
    `Engine`, so today the only way to know the game's clock is to infer it.

- Gap: **transient effects shorter than the bus round-trip are unobservable** — `HIT_STOP_MAX`
  is 0.25s and a devtools call round-trips in ~0.7s, so I could confirm the dip *ended*
  correctly but never that it *engaged*. `run-method _on_died` then `get-state` always lands
  after the deadline. This is the same shape as G-058 but from the opposite side (that one is
  about `step-time` across a dip; this is about sampling inside one).
  - [G-060] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a `--after-frames N` flag on `get-state`, so the read is scheduled inside the
    game at a known frame offset from the triggering call rather than racing the file bus.

- Gap: **G-056 closed by this run, not by a code change** — the mobile primary button's live
  resolution path (`_held_item()` / `_enemy_in_reach()`), which every unit test stubs via
  `primary_resolver`, was exercised for real by sweeping `select_slot(0..5)` and reading back
  `_primary_action` / `_primary_label`: slot 0 pickaxe → `gather/MINE`, slot 1 sword →
  `attack/HIT`, slot 2 placeable → `gather/BUILD`. The stub was never the problem; nobody had
  driven the real thing.
  - [G-056] status: fixed | fixed-in: 0.8.0 | seen: 2 | harness: 0.7.0
  - Improvement: unchanged — the resolver seam is right, but the log should record that the
    live path is verifiable in ~6 bridge calls and is worth doing once per change to it.

- Note (not a gap): reach reports `systems/juice.gd` NOT reached. It is a static `RefCounted`
  with no `class_name` node ever instanced, so it cannot appear in a `scene-tree` snapshot by
  construction — reach measures node scripts. Its behaviour was verified through observable
  effects on `world/camera.gd` and on `Engine.time_scale`. Same applies to `ui/splash_text.gd`,
  `ui/damage_number.gd` and `items/pick_up_manager.gd`, all of which spawn transients that had
  been freed before the snapshot. Do not read those four as unverified; do not read them as
  verified either without saying which effect stood in for them.

## 2026-08-02 — closing the place/destroy xp faucet (gather-5s5)

- Value: **warranted** — runtime settled the one thing the unit tests structurally cannot:
  whether the ledger is keyed on the cell the game actually builds on.
  - Expected: the headless tests prove the ledger blocks a second award, but they call
    award_build_xp() directly. What they cannot show is that the real input path reaches it
    at all, or that _placed_cell()'s local_to_map round-trip names the same cell that
    PlayerManager.place_tile wrote to — a half-tile disagreement there would record a
    neighbouring square and leave the faucet fully open with every test still green.
  - Got: driving the real path (`select_slot(3)` then `input tap gather`) moved
    `xp: 0 -> 1` and `built_cells: {} -> {"(0, 0)": true}`, and each later successful
    placement added exactly one distinct cell for exactly one xp — four placements, four
    cells, `xp: 4`. Then the real save format: `input tap save` / `input tap load` returned
    all five cells with identical keys, which is the check that matters most, because a
    ledger that does not survive JSON reopens the faucet on the first load and nothing in
    the session would show it.
  - Cheaper: nothing for the cell-identity claim. The 20-cycle re-award test is much cheaper
    headless and that is where it lives; only the wiring needed the game.

- Gap: **`place_build` bypasses the code path it appears to test** — it calls
  `handler.set_tile(...)` directly (`devtools_ext/commands.gd:1100`), so it never runs
  `GameItemPlaceable._place()` and never awards build xp. My first runtime check used it and
  read `xp: 0, built_cells: {}` after a successful `"placed Wood Wall at (-1, 0)"`, which
  looks exactly like the new code being broken. It is not — the verb was never on that path,
  before this change or after. Ten minutes went into the wrong hypothesis.
  - [G-061] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: either route `place_build` through `PlayerManager.place_tile(slot_data)` so
    it exercises the real chain, or rename it `set_build_tile` and say in its message that it
    writes the tilemap directly. A setup verb that silently skips the gameplay path is the
    "setter must leave the game in a state the game itself can reach" rule from the harness
    docs, broken.

- Gap: **`tile_at`'s cell and the game's "tile in front of player" are not the same cell** —
  `tile_at` reported `front cell {'x': 0, 'y': -1} source -1` for a cell that was
  simultaneously empty and unbuildable, because `_cell_near_player` does not apply the
  facing offset that `main.gd:get_tile_in_front_of_player()` does (`+/- Vector2i(1, 0)` on
  `is_facing_left()`). Every placement assertion I tried to anchor on it was ambiguous.
  - [G-062] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: have `tile_at` default to the game's own facing-aware front cell (call
    `get_tile_in_front_of_player()` when no offset args are given), and return the facing in
    `data` so the caller can see which square was read.

- [G-060] status: **wontfix** | seen: 2 | harness: 0.7.0 — filed last run as "transient
  effects shorter than the bus round-trip are unobservable", about not being able to catch
  hit-stop mid-dip. Withdrawn: `test_juice.test_hit_stop_dips_the_time_scale` already asserts
  `Engine.time_scale == Juice.HIT_STOP_SCALE` headlessly, and hit-stop is a static function
  with no scene dependency, so the headless assertion is strictly stronger than a screenshot
  of the same moment. The gap was real about the bus and irrelevant to the code.

## 2026-08-02 — drop particles were hiding the drops

- Value: **warranted** — the fix is two numbers and a z_index, and runtime is the only thing
  that could confirm either half.
  - Expected: the report was "you can no longer see the item on the ground due to the
    particles", which reads as a particle-count problem. I expected to be trimming amounts.
  - Got: the count was only half of it. `items/pick_up.tscn` puts drops at `z_index = 1` and
    both emitters were created at `z_index = 60` — so the break burst rendered *above* the
    very items the break had just produced, and no amount of trimming would have fixed the
    ordering. Confirmed live afterwards: `GatherBurst z_index: 0, amount: 6, lifetime: 0.3`,
    `CollectSparkle z_index: 0, amount: 4, lifetime: 0.22`, and a screenshot at the break
    showing the stone drop drawn on top of the burst with slot 6 going to x2.
  - Cheaper: reading `pick_up.tscn` for the drops' z_index next to the two `z_index = 60`
    lines would have found the ordering bug in about a minute, without launching anything.
    The running game was still needed to confirm the drop is now on top, but the *diagnosis*
    was available statically and I went to the game first.

- Gap: **no gaps this turn.** The bridge did everything asked. Two notes on technique rather
  than on the harness: `set-game-speed 0.08` is what made a 0.3s burst catchable by a
  screenshot at all, and it distorts what it shows — the XP splash looked enormous under it
  purely because `_absorb_xp`'s stacking tween was stretched eight-fold. A slow-motion
  screenshot is good for "is this drawn in front of that" and bad for "is this too big".

## 2026-08-02 — walls could be built on open water and over resources (gather-llu)

- Value: **warranted** — runtime is the only place the *stack* half of the fix is visible, and
  it corrected my reading of the screenshot that started the session.
  - Expected: in the live game a wall is refused on a sea cell and on a resource cell — the
    stack count stays put — while still going down on clear grass; and the hotbar preview tint
    agrees with the placement decision. The unit tests exercise `is_occupied` in isolation and
    never run `PlayerManager.place_wall`, so only runtime can show the stack-decrement and
    preview halves.
  - Got: all four placement cases, read off `player_state.selected_count` + `tile_at`. Walked
    east until the player was pinned at the shore with `layer 0 at (5, -7): source -1 atlas
    (-1, -1)` in front — literal open water — then `input tap gather`: `Stone Wall 9` before,
    `Stone Wall 9` after, cell still `source -1`. Same for the resource cell `(-1, -5): source 9`
    and for a second press onto the wall just placed. Control case placed normally, `10 → 9`.
    The preview read `modulate {r:1, g:0, b:0}` over the sea cell and `{r:1, g:1, b:1}` over a
    player-laid stone floor, where the wall then went down `9 → 8`.
    The correction: I had read the grey/red pair in the reported screenshot as two placed
    builds. The screenshot this run took shows the same dark red box floating beside the
    player — it is `HeldItemTexture` at `modulate a=140`, i.e. the *preview*. So the preview
    had been saying "no" over the water the whole time and `place_wall` placed anyway; the
    two disagreed because only the preview passed `is_wall = false`.
  - Cheaper: the new unit test settles the `is_occupied` truth table for a few seconds of
    headless run, and it is what caught that walls were also overwriting each other. Nothing
    cheaper covers the stack-decrement path or the preview tint — those needed the game.

- Gap: **the Phase 0 drift check reports every harness file as drifted on a CRLF checkout.**
  `cmp -s` against `templates/` flagged all 8 files; `diff <(tr -d '\r' < src) <(tr -d '\r' < dst)`
  is empty for all 8. The project's copies have Windows line endings, the plugin's have Unix,
  and the check compares bytes — so "DRIFT" here means nothing at all, and a real local patch
  would be indistinguishable from this noise.
  - [G-063] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: normalize line endings on both sides before comparing, e.g.
    `diff -q <(tr -d '\r' < "$src") <(tr -d '\r' < "$f")` in the Phase 0 snippet.

- Gap: **[G-006-style] no verb drives a placement through the real `place_wall` path.**
  `place_build` calls `handler.set_tile` directly and skips `is_occupied` entirely (the same
  bypass `gather-15o` files against build XP), and `run-method` cannot pass the `Vector2i` that
  `is_occupied` takes (`gather-6sp`). The workaround was to reach the fix through the whole
  player: `give_item` → `run-method select_slot` → walk with `input press move_*` until the
  terrain in front was the case under test → `input tap gather`. That worked, and it is honest
  end-to-end coverage, but finding a plain-grass cell and an open-water cell took ~15 bridge
  calls of blind walking because the only way to ask "what is in front of me" is `tile_at` one
  offset at a time.
  - [G-064] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: a project verb `goto_cell` taking a predicate (`"grass_clear"`, `"shore"`,
    `"resource"`) that teleports the player beside a matching cell and sets facing — the
    placement analogue of `goto_resource`, which already exists for exactly this reason on the
    gather side.

- Note: `step-time --seconds 3` did not sustain a held movement action — the player advanced
  4px where 2.5s of wall-clock `input press` + `sleep` moved it ~55px. Not filed as a gap
  because the docs only promise `step-time` advances the clock, not that polled input state
  survives it; worth knowing before using it to walk anything anywhere.

## 2026-08-02 — Advisory: where the Fable model earns its cost in this repo

- Value: **inconclusive** — the harness was not exercised this turn; the question was
  strategic (which workloads justify a 2x-priced model), and the evidence came from
  `bd list`/`bd stats`, the gap corpus in this file, and file sizes.
  - Expected: that the repo's answerable-by-harness work (the P2/P3 bug backlog) would
    turn out to be the *wrong* target for an expensive model, and the unmeasured
    cross-cutting work would be the right one.
  - Got: 26 open issues, 24 of which name their own fix in the title; against 72 open
    `[G-NNN]` gaps in this log that nobody has ever clustered. The asymmetry is the
    recommendation.
  - Cheaper: nothing — `bd list` + `grep -c "status: open"` was already the cheap path,
    and no runtime state was in question.

- Gap: **no gaps this turn** — the harness was not run, so it had no opportunity to fall
  short. Filing nothing rather than manufacturing an entry.

## 2026-08-02 — Crispness fix for DamageNumber, plus the stale-4.935 comment sweep

- Value: **warranted** — headless lint + tests were the only affordable check here (the
  devtools bridge was owned by another process this session), and they were enough to
  settle the one thing the diff could not: that routing `DamageNumber` through
  `SplashText.pixel_scale` does not break the class-resolution order between two
  `class_name` scripts in `ui/`.
  - Expected: lint clean; tests green except whatever `test_splash_text.gd` is doing
    while it is being edited concurrently.
  - Got: `lint: 0 error(s), 7 warning(s) -> exit 0`, and
    `Total: 246 | Passed: 245 | Failed: 1 | Skipped: 0` with the single failure being
    `[FAIL] test_a_coalesced_label_walks_up_the_colour_ramp` in the concurrently-edited
    file. stderr carried 3 pre-existing `ERROR: Cannot get path of node as it is not in
    a scene tree` from `level_up_manager.gd:364` / `recipes.gd:274`, none from the diff.
  - Cheaper: nothing much — lint alone (4s) would have caught a broken static call, and
    that was the only real risk. The test run mostly bought the confirmation that the
    one red test was not mine.

- Gap: **no gaps this turn** — the work was comment text plus one constant family, and
  headless lint/tests reached all of it. The only thing runtime could have added is a
  screenshot of the number, and the bridge was unavailable by instruction, not by defect.

## 2026-08-02 — 1:1 rasterization for the corner "+N xp" readout (ui/floating_text.gd)

- Value: **warranted** — the fix hinges on an arithmetic claim about a product of three
  numbers living in three files (XpLabel's `scale = 0.45` in `main.tscn`, the camera's
  zoom 8, and `CameraHud`'s viewport legibility factor), and reading the diff alone had
  already produced the wrong figure once.
  - Expected: lint clean; the new `test_floating_text.gd` to fail on
    `test_the_offset_grows_with_the_type`, because `Control.position` is written and read
    back on a Label that never enters the tree and `get_parent_anchorable_rect()` returns
    an empty rect outside it.
  - Got: all six new tests green, including the offset round-trip —
    `Selected: 6 of 252 discovered`, exit 0. Offsets do resolve outside the tree against a
    zero parent rect, so the whole styling path is assertable statically. The full suite
    was `Total: 252 | Passed: 251 | Failed: 1`, the one failure being
    `[FAIL] test_a_coalesced_label_walks_up_the_colour_ramp` in the concurrently-edited
    `test_splash_text.gd` (identical to the entry above, which saw it at 246 discovered).
    stderr: the same 3 pre-existing `Cannot get path of node` from
    `level_up_manager.gd:364` / `recipes.gd:274`, none from this diff.
  - Cheaper: reading `camera_hud.gd:40` + `:105-115` was what actually produced the
    finding (`FloatingText`, not `XpLabel`, is the node whose transform the HUD rewrites,
    so the on-screen magnification was 5.4x and not the 3.6x the scene file suggests) —
    that was free. The test run bought the *invariant*: font size now reproduces the old
    on-screen height across the whole `SCALE_MIN..SCALE_MAX` band, which no amount of
    reading establishes.

- Gap: **no way to assert an accumulated CanvasItem transform headlessly** — the property
  that actually matters here is `XpLabel.get_global_transform_with_canvas().get_scale()`
  against the camera zoom, i.e. the product across `HUD -> FloatingText -> XpLabel`. In a
  `--script` run there is no camera transform applied to the root viewport, so the test
  can only assert the one factor it passes in and trust that nothing above multiplies it.
  The workaround was to make `style_xp_label()` static and total (it takes the zoom
  reciprocal and the legibility factor as arguments), plus a comment in
  `camera_hud.gd:37-48` saying why `FloatingText` must stay out of `SCALED_CHILDREN` — a
  convention, not a gate. A future edit re-adding it would make the label blurry again and
  every test here would still pass.
  - [G-073] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: a `run-method`-free bridge verb (or a headless helper) that reports a
    node's accumulated canvas transform scale, so "these glyphs rasterize 1:1" is one
    assertion against the live tree rather than an argument reconstructed from three
    files. `node-bounds` reports position/size but not the accumulated scale.

## 2026-08-02 — drafted the bone-worker base + assembled sprites (no project code touched)

- Value: **inconclusive** — the harness was never run, correctly: nothing under `res://`
  changed. The whole turn produced two PNGs and a generator in the session scratchpad,
  pending art approval before any scene, script or beads work starts.
  - Expected: nothing. A sprite that has not been imported into the project cannot fail
    lint, cannot fail a test, and cannot be reached by a runtime assertion.
  - Got: n/a — no `/verify`, no lint, no test run. `git status` for the repo is unchanged
    apart from this log entry.
  - Cheaper: this *was* the cheap path. The feedback loop that mattered was PIL rendering
    a 10x nearest-neighbour preview strip and reading it back, which took six iterations
    and never involved Godot. Running lint would have asserted a diff that does not exist.

- Gap: **no way to preview a candidate sprite against real game tiles without importing
  it.** Judging 16x16 pixel art needs it seen at game scale, on the tileset's own grass,
  next to a tileset tree — otherwise the axe head reads as a floating grey brick (it did,
  for three iterations). The workaround was a throwaway `mockup.py` that opens
  `assets/art/tiles.png` with PIL, crops the pine at `(80,48,96,80)` and the grass green
  `(90,197,79)` by scanning the land tiles for the modal colour, and composites the
  candidate over it. Finding those two coordinates cost four crop-and-look rounds, because
  nothing in the project states where anything sits in the 400x400 atlas.
  - [G-074] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
    (verified 2026-08-02: `devtools.py --json scripts-seen` now exists, and `reach` prints
    the worktree/branch split off it — `branch … reached 2/3`, the one miss being the test
    script itself, which no runtime session loads by design.)
  - Improvement: a `tile_at` style verb — or a headless `tools/atlas_map.gd` — that dumps
    the registry's `atlas_location` + `tile_source_id` per `Types.Item`, so "where is the
    tree tile" is one query instead of a binary search by cropping. The registry already
    holds this; it is just not readable from outside a running game. Would also have made
    the palette sampling one command rather than four PIL one-liners.

## 2026-08-02 — XP splash: crispness fix, juice pass, pickup-XP removal, corner readout deleted

- Value: **warranted** — runtime produced three claims the diff could not, and one of them
  reversed a design decision.
  - Expected: the splash's transform scale reads exactly 0.125 (=1/8) from the live Camera2D
    rather than the old 0.2, its container's texture_filter is NEAREST, an xp streak grows
    font_size (not scale) up to the cap while scale stays pinned, and the new procedural
    `_process` driver still frees every label — with no tween left, a stranded splash would
    show as a climbing `live_splashes`.
  - Got: all four held, and the streak assertion is the one worth quoting. Six `cmd splash`
    calls at one spot produced `text: +12 XP`, `theme_override_font_sizes/font_size: 33`,
    `theme_override_constants/outline_size: 6`, `scale: {"x": 0.125, "y": 0.125}` — i.e. the
    swell re-rasterized (22→33, the exact `round(22 * 1.5)` for five absorbs) while the
    transform never moved. Ten ticks hit the cap dead on: `font_size: 60` = `round(34*1.75)`.
    Separately, gathering five nodes moved `LevelUpManager.xp` 0→5 with `PickUps` draining to
    0 children, which is the evidence that removing the pickup award left the gather income
    intact rather than double-counting or under-counting it.
  - Cheaper: nothing. The unit tests pin the sizing arithmetic and did catch a real ordering
    bug (below), but they cannot see `texture_filter`, cannot see the live camera zoom — the
    stale-constant bug that caused the blur is *invisible* to a test that hardcodes the same
    stale constant — and cannot count xp across a real gather-and-vacuum cycle.

- Gap: **`verify_ledger reach` cannot see transient nodes, so it under-reports runtime
  coverage for anything short-lived.** `reach` reported `ui/splash_text.gd` and
  `items/pick_up.gd` as NOT reached, in the same run where I read live state off
  `/root/Main/World/SplashTexts/SplashText` (`font_size: 60`, `text: +10 XP`) and watched
  `PickUps` go to 0 children. Both files unquestionably executed. Reach intersects the diff
  against `script`/`scene_file` in a `scene-tree` snapshot, and both snapshots are taken at
  phase boundaries — by then every splash had freed itself (`live_splashes: 0`, which is the
  *pass condition* for this change) and every drop was collected. The failure mode is
  perverse: **the better the cleanup, the worse the reported reach**, so a leak-free
  short-lived node can never be credited.
  - [G-068] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0 (was G-074, reassigned — ID collision)
  - Improvement: have `dev_tools.gd` accumulate a set of every script path seen on any node
    across the session (hook `node_added`, or union the script paths on each `scene-tree`
    call into a persistent set) and expose it as a `scripts-seen` verb. `reach` should union
    that with the snapshots. A one-line addition to the status provider — `"scripts_seen": N`
    — would also make it visible that the set is being collected.

- Gap: **no way to assert a fractional-scale/filter combination, which is the actual bug
  class here.** The whole defect was "a 16px glyph atlas magnified 1.6x through a LINEAR
  filter". I can read `texture_filter: 1` and `scale: {"x": 0.125}` separately and do the
  multiplication in my head against a zoom I fetched from a third node, but nothing asserts
  the *product*. A future edit that changes the camera zoom re-breaks every world-space label
  in the game and every check here still passes.
  - [G-075] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: a `canvas-scale --node PATH` verb returning the accumulated
    `get_global_transform_with_canvas().get_scale()` plus the effective texture filter, so
    "this text rasterizes 1:1" is one assertion instead of three reads and an inference.
    This is the same gap [G-073] filed from the HUD side; if that entry is still open, these
    should be merged — [G-073] wanted the accumulated transform, this wants the filter with
    it, and they are one verb.

## 2026-08-02 — installed the approved art and scaffolded the BoneWorker scene tile

- Value: **warranted** (lint half; runtime pass still pending) — hand-editing a TileSet
  `.tres` is the failure mode lint exists for, and this change hand-wrote three separate
  things Godot normally authors: a `.tscn` with an inline `SpriteFrames`, a new
  `TileSetScenesCollectionSource`, and the `sources/12` + `load_steps` bookkeeping.
  - Expected: either a parse failure in `world_tile_set.tres` from a miscounted
    `load_steps`, or a cascade of `Could not find type "BoneWorker"` if `--import` had
    not regenerated `.godot/global_script_class_cache.cfg`.
  - Got: `lint exit=0`, `UIDs: OK`, and `res://world/tile_scenes/bone_worker.tscn: OK` on
    line 30 — the new scene was actually opened and resolved, not skipped. `grep BoneWorker
    .godot/global_script_class_cache.cfg` confirmed the class registered, and the
    `bone_worker.gd.uid` sidecar was generated (`uid://76vononphgej`).
  - Cheaper: nothing. Reading the `.tres` back proves the text is what I typed, not that
    Godot accepts it — `load_steps=30` is a number no amount of re-reading validates.

- Gap: **no headless way to assert a tile is placeable end-to-end.** Lint says the scene
  parses and the tileset loads, but the thing that actually matters — that
  `Types.Item.BoneWorker` (source 12, atlas (0,0)) resolves to `bone_worker.tscn` when
  `PlayerManager.place_tile` writes it — needs the running game, and the registry is built
  imperatively in `_ready()` so no static reader can answer it either. The workaround is to
  defer it to the orchestrator's runtime pass, which means three subagents are building on
  a registration nobody has yet proved works.
  - [G-075] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a headless runner mode that boots the autoload set (`GameItems`,
    `Recipes`, …) without the main scene, so `item_list[type].tile_source_id` and the
    tileset's `get_source(id)` can be asserted in a unit test. Today `test_dir` tests are
    plain `RefCounted` with no autoloads, so anything registry-shaped is untestable
    headlessly and gets pushed into the one runtime pass that must be serialised across
    agents.

- Gap: **fanning out agents forces all runtime verification through one serialised owner.**
  Re-confirming the bridge constraint from a previous session: three concurrent agents
  were each given an explicit "never launch the game" instruction and restricted to
  disjoint file sets, because a second Godot instance silently answers another agent's
  devtools request. This is a real tax on parallelism — the agents can lint and unit-test
  but cannot check their own work against the running game, so every runtime finding
  round-trips through the orchestrator.
  - [G-046] status: open | seen: 3 | harness: 0.7.0
  - Improvement: per-session bus isolation exists (`-- --devtools-session <id>` plus
    `GODOT_USERDATA`), but it is not wired into the agent workflow — a subagent has no
    documented recipe for claiming its own session. A `devtools.py session-claim` that
    allocates an id and a userdata dir would let fanned-out agents verify independently.

## 2026-08-02 — runtime pass on the BoneWorker feature (gather-yye)

- Value: **warranted** — runtime produced four claims no unit test could, and one of them is
  the whole point of the feature's main bug fix.
  - Expected: that a BoneWorker tile placed from the registry actually instantiates through
    tileset source 12 and swaps sprites when loaded, and that the whole
    `_find_tree_cell`/`_fell`/`_deliver` path works against a real TileMap — none of which
    any of the 265 headless tests reach, because the harness has no TileMap-backed world.
  - Got: all of it, plus two invariants that only exist as live state. `place_worker`
    returned `placed a bone worker at (-1, -2)` with `trees_in_range: 1`, and
    `worker_state` resolved the instanced node at
    `/root/Main/World/TileMap/BoneWorker/LoadedSprite` — the registry→tileset→scene wiring
    is real. Across the run `trees_in_range` went `2 -> 0` while `wood_pickups_nearby` went
    `0 -> 3` (two trees at the 1..2 tuning range), with `XP: 0 | level: 1` before *and*
    after — the gather-5s5 faucet stays shut, which is a claim about a system the diff
    deliberately routes around (`clear_tile` instead of `remove_resource`) and therefore
    cannot show. `animating` was `true` with a tree in reach and `false` at zero trees,
    proving the `_working` gate rather than `loaded` drives the animation. And the
    gather-yye.3 fix asserted directly: with every machine already loaded,
    `had_target_in_reach = False`, `skulls_spent = 0`, and an independent `worker_state`
    read showed `skulls_held` still `1`. The old code removed the stack unconditionally.
  - Cheaper: nothing. No headless test can build a TileMap-backed world, and "no xp was
    awarded" and "the skull survived" are both absences — readable only as live state.

- Gap: **reach cannot see RefCounted item classes, so it under-reports what ran.** The
  ledger recorded `reached 3/9 changed file(s); NOT reached: … items/game_item_bone_enemy.gd
  …`, but that file was exercised decisively — `had_target_in_reach: False` can only be
  produced by `GameItemBoneEnemy.can_use()`, and the skull-preservation result by its
  `use()`. Reach is computed by intersecting the diff against `script`/`scene_file` paths in
  a `scene-tree` snapshot, and this project's entire item model is `GameItem` subclasses held
  as plain RefCounted values in `items.gd`'s `item_list` — they are never any node's script,
  so no amount of exercising them can register. The same applies to `items/types.gd` and to
  `devtools_ext/commands.gd`, which ran on every single call in this session. The honest
  residue after discounting those is `crafting/recipes.gd` and `systems/skill_tree.gd`, which
  genuinely were not reached: the recipe cost and the Industry unlock were never opened in a
  running game.
  - [G-076] status: open | seen: 1 | harness: 0.7.0
  - Improvement: have the game side report the set of script paths actually *loaded*
    (`ResourceLoader`'s cache, or a `ClassDB`/`global_script_class_cache` walk) as a second
    reach input alongside the scene tree, so non-Node scripts can register. Without it, any
    project whose logic lives in Resources or RefCounted gets a permanently deflated reach
    number, which trains readers to ignore the field — the opposite of why it exists.

- Gap: **no verb places an arbitrary placeable tile, so the chest-delivery branch is
  untestable.** `_deliver()` prefers a chest in reach and falls back to a ground pickup; only
  the fallback got exercised. `place_build` refused with
  `type must be one of ["woodwall", "stonewall", "woodfloor", "stonefloor"]`, and
  `place_station` only maps `sawmill`/`furnace`. Driving the real path instead —
  `select_slot(4)` then `_on_gather()` — left the player still holding `Chest x 1` with the
  target cell reading `source -1` (empty), so placement silently no-opped exactly as
  `GameItemPlaceable`'s own comment warns. The only `TestChest` in the world turned out to be
  a worldgen chest at `(-552, 136)`, ~570px from the worker. Two smaller things compounded
  it: `set-state --property position --value "[400,400]"` reported `State updated` and wrote
  `(0, 0)` — the no-vector-coercion gap (gather-6sp) applying to `set-state`, not just
  `run-method`, and silently writing a wrong value rather than failing — and `tile_at`
  ignored its `x`/`y` arguments entirely, returning cell `(0, -1)` for all six cells queried.
  - [G-077] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a generic `place_tile` verb taking an item name and a cell offset, built on
    the same `handler.set_tile(cell, source_id, atlas)` call `place_worker` already uses.
    Every placeable in the game is one registry lookup away, and the per-feature placer verbs
    (`place_station`, `place_build`, now `place_worker`) are three partial reimplementations
    of it that each cover their own author's case and nobody else's.
## 2026-08-02 — Gated island spawning on the home coastline actually reaching the island

- Value: **warranted** — the gate turns on a flood fill over a per-seed coastline, so "which
  parcel opens which island" is not a property of the diff at all, and the four worlds this
  run drew disagreed with each other about it.
  - Expected: at generation the islands report 0 resource nodes and no boss; buying the
    parcel that first reaches an island opens exactly that island and stocks it on the same
    tick, veins and boss included - none of which the diff can settle, because which parcel
    reaches which island is a property of the noise seed.
  - Got: exactly that, and the spread across seeds is the part reading the diff would have
    missed. Seed 2629016503 opened `forest` on parcel 2 and `ore` on parcel 6; seed
    3487495103 had `forest` already open at generation (its pre-drawn isthmus ran into the
    starting coastline) and opened `boss` on parcel 11; seed 150278244 opened nothing until
    parcel 4; the verify seed opened all three at once on the twelfth and last parcel, with
    `"bought 1 of 1 parcel(s), opened [\"boss\", \"ore\", \"forest\"]"`. At generation
    `island_census` read `forest opened=False nodes=0`, `ore opened=False nodes=0`, `boss
    opened=False nodes=0` with `boss {'alive': False, 'chest': []}` — and after the last
    parcel `ore {"Coal": 12, "Copper": 9, "Gold": 2, "Iron": 4, "Stone": 3}` (the seeded
    veins, arriving on opening rather than at generation) and `boss {'alive': True, 'hp': 90,
    'chest': ['Gold Coin x40', 'Gold Ore x8', 'Iron Ore x12']}`. `enemy_cap` moved 3 -> 11 ->
    25 as land became reachable, which is the ceiling half of the change and has no other
    readout. The save/load leg was the one I expected to break and did not: censuses either
    side of `[` / `]` were byte-identical (`forest 19 nodes`, `ore 19 nodes` with `Gold 2,
    Iron 4` un-doubled), and a purchase made *after* the load still opened the boss island on
    a region the loader had rebuilt from scratch.
  - Cheaper: nothing for the seed-dependence. `test_island_gating.gd` settles the flag's
    truth table and its save roundtrip in 4s and is the durable guard, but it cannot say that
    a parcel bought in a real world reaches a real coastline — and the one thing I would have
    got wrong from reading alone is that a pre-drawn isthmus sometimes makes the forest island
    walkable before the first purchase, which no test asserts and which changes how the
    feature plays on that seed.

- Gap: no new gaps this turn. Two known ones bit again and had their counts bumped rather
  than being re-filed: [G-050] (`reach` cannot see a `RefCounted`) reported `NOT reached:
  world/land_region.gd`, which is the file holding the `connected` flag this entire change is
  about — `LandRegion` extends `RefCounted` and is never any node's script, so it is
  unreachable by construction even though `island_census` printed its `accepts_ambient_*`
  results back to me on every call. [G-053] (`reach` cannot see code that runs but owns no
  node) reported `NOT reached: devtools_ext/commands.gd` while every assertion above went
  through `cmd island_census` / `cmd buy_land` in that very file. Net effect: `reached 4/7`
  on a run where 6 of the 7 were demonstrably exercised, which is a reach number that has to
  be explained in prose every time rather than read.

## 2026-08-02 — Merged the island gating onto a main that had gained the bone worker

- Value: **warranted** — the gates ran against the *merged* tree, which is a tree neither
  parent had ever been verified as, and that is the only place a bad conflict resolution
  shows up.
  - Expected: resolving the `devtools_ext/commands.gd` conflict by deleting
    `_walkable_from_home` while keeping 397 lines of bone-worker verbs either parses and
    registers both verb sets, or silently drops one of them — a hand-resolved conflict in a
    file that is one long list of function definitions can lose a whole feature's verbs
    without changing a single line the diff would show as conflicting.
  - Got: both sets present in one `list-commands` (`buy_land`, `island_census`,
    `place_worker`, `worker_state`), 274/274 tests where each parent had 255 and 19+255, and
    the merged build still reads `forest opened=False nodes=0`, `ore opened=False nodes=0`,
    `boss alive False` at generation. Zero `ERROR:`/`SCRIPT ERROR` lines in the launch log.
  - Cheaper: lint alone would have caught a parse error, and it ran in 12s — but not a
    *dropped* verb, which parses fine and registers nothing. `list-commands` was the cheap
    assertion that separated those two, and it is one call.

- Gap: no gaps this turn. The merge exercised no harness capability that was missing;
  `list-commands` answered the one question the conflict raised directly.

## 2026-08-03 — runtime pass on the walking bone worker (gather-qju)

- Value: **warranted**, and decisively — the runtime pass found two bugs that a green
  287-test suite and a clean lint both sailed straight past, either of which made the
  feature do nothing at all.
  - Expected: that the worker leaves its tile, routes to a tree with TilePathFinder, fells
    it and comes back — none of which any headless test reaches, because the harness has no
    TileMap-backed world.
  - Got: first, nothing whatsoever. `state=IDLE pos=(24.0,40.0) home=False path=0` for four
    consecutive samples across 19 game-seconds while `trees_in_range` read 1. Bisecting by
    hand: `run-method _find_tree_cell` returned `{'cell': (0, 3)}`, so the scan was fine and
    the pathfinder was refusing. Two separate causes, both invisible to `for_cells` tests:
    `is_walkable` tested layer 0 against `GRASS_ATLAS` (9,17), which is only what LandManager
    writes for *bought* land — the pre-baked home island is source 0 atlas (0,0), so the
    entire island was unwalkable; and `find_path` required a walkable *start*, but a
    BoneWorker IS a layer-1 scene tile, so its own cell is solid and every route out of it
    was refused. After both fixes the worker walked: caught mid-stride at
    `state=TO_TREE pos=(93.1,29.1) path=2`, and the player collected 13 wood off its felling.
  - Cheaper: nothing. Both bugs are "the real world does not look like the test world" —
    `for_cells` supplies its own blocked set and therefore cannot express either one, and
    reading the code proves nothing about which atlas coordinate the baked island uses.

- Gap: **no headless fixture for "the actual world", so world-shaped assumptions go
  unchecked until runtime.** Every routing rule was unit-tested and correct in the abstract;
  what was wrong was the mapping from those rules onto real tile data. The unit suite cannot
  see that a scene tile occupies its own cell, or which atlas coord the starting island uses,
  because `for_cells` invents the world it tests against.
  - [G-078] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a headless fixture that loads `world/tile_map.tscn` (a plain PackedScene,
    no autoloads needed) and exposes its layer-0/1 cells, so "is the home island walkable"
    becomes a unit test rather than a runtime discovery. The scene is already on disk and
    already parsed by lint; nothing about it needs a running game.

- Gap: **[G-077] regressed to open — the work that closed it was lost.** A generic
  `place_tile` verb had been written and was reported working, but the working tree was
  reset before it was committed, so `place_build` is again the only placer and it still
  refuses everything but walls and floors. The wall-avoidance proof below had to be built out
  of `place_build woodwall` alone: boxing the worker's home cell on all four sides, then
  showing production frozen at `wood_held=13` across 36 game-seconds while
  `_find_tree_cell()` still returned `{'cell': (3, -6)}` — it can see a tree and cannot reach
  it. That is a good assertion, but it took four calls and a control check where one
  `place_tile Chest` would have tested the delivery branch directly.
  - [G-077] status: open | seen: 2 | harness: 0.7.0
  - Improvement: unchanged — one generic `place_tile` taking an item name and a cell.
    **Process note, which is the real lesson: commit each agent's work as it lands.** Three
    agents' output was held uncommitted pending a single runtime pass and a reset took all of
    it. The two commits before this entry exist because that lesson was applied.

## 2026-08-03 — worker chains trees, wanders when idle, and swings the player's pickaxe

- Value: **warranted** — all three behaviours are animation- and state-shaped, and the
  headless suite cannot observe any of them; it stayed at 287/287 green throughout.
  - Expected: that the worker moves tree-to-tree instead of trailing home between logs, that
    it drifts rather than freezing when nothing is choppable, and that the borrowed Gather
    sprite actually animates rather than sitting still at rotation 0.
  - Got: chaining, `state=CHOPPING` at four different positions in a row with `wood_held`
    climbing 0 -> 1 -> 3 -> 4 and no RETURNING between them. Wandering, `WANDER` sampled at
    (71.8,8.2), (51.5,-3.5), (40.0,17.2) and (33.6,33.6) with TO_TREE reappearing in between
    as trees respawned and `wood_held` reaching 16 — it goes back to work rather than
    wandering forever. The swing, `get-state Gather` returned `visible: true` and
    `rotation: 1.50041770935059` — mid-arc on the 0 -> 1.5708 track, so the AnimationPlayer
    is genuinely running and not parked.
  - Cheaper: nothing. A property read of a rotating sprite is the whole assertion, and
    `WANDER` only exists in a world that has run out of trees.

- Gap: **no gaps this turn.** `worker_state`'s `script_vars` passthrough carried `_state`,
  `_carry` and `_path` without needing a new verb for each behaviour added, `step-time`
  advanced far enough to exhaust the trees, and `get-state --property` settled the animation
  question directly. The one thing not asserted visually is what the swing looks like: the
  camera follows the player, so a screenshot taken while the worker chopped framed the player
  instead. The property read is the stronger assertion regardless, so this is a note rather
  than a gap.

- Finding worth recording, not a harness gap: **trees cannot wiggle, and do not wiggle for
  the player either.** `resource_manager2.gd:178-186` says it outright — a layer-1 tilemap
  cell "has no transform, no modulate and no material, so THERE IS NOTHING TO ANIMATE", which
  is why `_swing()` calls `hit_react()` only on a `GameSceneResource`. Trees are plain cells.
  The worker therefore emits the same gather chips on the same `Juice.GATHER_SWING_INTERVAL`
  cadence, through a new public `ResourceManager2.emit_gather_chips()` rather than a second
  particle node per worker. Making a tree flinch means making Tree a scene tile, which is a
  tileset and save-format change.

## 2026-08-03 — grey stone worker, and both machines slowed 400%

- Value: **warranted** — runtime is the only place the second machine exists at all; the
  suite stayed 287/287 through a new enum entry, a new tileset source and a new scene.
  - Expected: that Types.Item.StoneWorker resolves through tileset source 13 to
    stone_worker.tscn, and that an exported harvest_type actually redirects the same script
    at a different resource rather than silently falling back to Tree.
  - Got: placed through the real inventory chain (give_item, select_slot, _on_gather) rather
    than a setup verb, and `scene-tree` resolved
    `/Main/World/TileMap/StoneWorker` running `res://world/tile_scenes/bone_worker.gd` — one
    script, two machines. `get-state` returned `harvest_type: 0` (StoneResource) and
    `_find_tree_cell()` returned `{'cell': (7, 2)}`, so it targets stone, not the Tree
    default. Then `TO_CHEST carry=2` with `time_to_next_cycle` reading 19.6 and 18.3 —
    it mined a node, took the 1..2 yield, and the 20s cadence is live.
  - Cheaper: nothing. An exported default that silently wins is invisible to a type checker
    and to lint, and the only proof is a running instance reporting the overridden value.

- Gap: **[G-077] bit again, third sighting.** `place_tile` still does not exist, so placing
  the new machine meant `give_item` then scanning eight hotbar slots with `select_slot` to
  find which one it landed in, then `run-method _on_gather` — five calls plus a loop where
  one would have done. It did have the accidental virtue of exercising the real placement
  chain rather than a setup shortcut, which is worth keeping as an option, but it should be
  the deliberate choice and not the only road.
  - [G-077] status: open | seen: 3 | harness: 0.7.0
  - Improvement: unchanged — one generic `place_tile` taking an item name and a cell.

- Not verified, and not claimed: **the chest-delivery branch, still.** The stone worker
  entered TO_CHEST and drained `carry` 2 -> 1 -> 0, but `chests_in_range` read `[]` at every
  sample, so a chest deposit and the ground-drop fallback are indistinguishable from this
  evidence. gather-yye.7 stays open. Distinguishing them needs a chest placed at a chosen
  cell beside a worker, which is the same missing verb.

## 2026-08-03 — workers visibly carry what they harvested

- Value: **warranted** — a purely visual change, so the running game is the only thing that
  can answer it, and the 20s cadence made the honest sampling approach fail first.
  - Expected: that the Carried sprite appears with the harvested resource's own icon while a
    load is in hand and vanishes when it is put away.
  - Got: stepping 8 game-seconds at a time never caught it. Six consecutive `CHOPPING|0`
    samples — the chop is 20s and the carry window between felling and depositing is shorter
    than the sampling interval, so polling for it is the wrong instrument. Driving it instead
    (`set-state _carry 2` then `run-method _update_carry_visual`) gave
    `visible: true, scale (0.6, 0.6), position (5, 2)`, and setting `_carry 0` gave
    `visible: false`. The screenshot then showed the worker holding a log at hand height.
  - Cheaper: nothing, but the *method* was: forcing the state beat waiting for it, and the
    six wasted samples were the cost of not seeing that immediately. A brief state reached
    on a 20s cycle should be set, not sampled.

- Gap: **no gaps this turn.** `set-state` on an int plus `run-method` on the refresh function
  was enough to drive the visual directly, and computing the crop from the worker's and
  player's `global_position` against the camera's zoom 8 put the screenshot on the right
  16 pixels without any new verb.

## 2026-08-03 — closed the open items: place_tile, chest delivery, and worker collision

- Value: **warranted** — the new verb immediately paid for itself by exposing a third
  pathfinding bug, and then settled a branch that had been unverified across two features.
  - Expected: that place_tile could put a chest beside a worker, and that the worker would
    then deposit into it rather than dropping on the ground — the branch G-077 had blocked.
  - Got: the chest went down (`written_source 8` read back against `source 8`, so the write
    was confirmed rather than assumed) and the worker then sat in IDLE forever anyway.
    `run-method _find_tree_cell` returned `{'cell': (-2, -3)}` — a tree one cell north — while
    the worker stood at (-2,-2) doing nothing. Cause: `find_path_adjacent` filters candidate
    approach squares through `is_walkable`, and the walker's OWN cell is solid because a
    BoneWorker is a layer-1 scene tile, so a worker placed next to its target had its one
    legitimate approach square discarded. Placement had always been far enough away to hide
    it. After the fix: `chest=["Wood x4", "empty", "empty"]` — chest delivery finally proven.
  - Cheaper: nothing. This is the third distinct "the real world is not the test world" bug
    in this class, and `for_cells` cannot express any of them because it invents its world.

- Gap: **[G-077] fixed.** `place_tile` takes any placeable by registry name at an absolute
  cell, a player offset, or the first free cell nearby, and reports `set_tile_disabled` plus
  a read-back `written_source` so a silent no-op cannot be mistaken for success again.
  `place_build` and `place_station` were left alone rather than rewritten as wrappers — they
  work, they are used by existing runs, and consolidating them is a separate change.
  - [G-077] status: fixed | fixed-in: 0.7.0 | seen: 3 | harness: 0.7.0
  - Improvement: delivered.

- Gap: **[G-062] fixed.** `tile_at` ignored `x`/`y` entirely and answered about the player's
  own cell for every query; six different cells returned the same one. `_cell_near_player`
  now honours absolute coordinates and is shared by every read and write verb.
  - [G-062] status: fixed | fixed-in: 0.7.0 | seen: 1 | harness: 0.7.0
  - Improvement: delivered.

- Gap: **no new gaps.** Worker/player collision was settled with `input press move_right`
  plus `step-time` and two `get-state` reads: the player went from x=8 to x=43 through a
  worker sitting at x=40. No verb was missing for any of it.

## 2026-08-02 — Built the itch.io store page: cover, banner, screenshots, copy and theme

- Value: **warranted** — the store art does not exist anywhere in the repo, so the running
  game was the only place it could come from, and driving it produced a scene the default
  world never shows.
  - Expected: `goto_resource` would drop the player somewhere photogenic and one screenshot
    would be enough. A fresh world is sparse, so I expected to have to fake density.
  - Got: I did not have to fake it. `island_census` reported the home island at
    `{"Coal":3,"Copper":1,"Stone":20,"Tree":9}` — 33 nodes, which reads as an empty field in
    a 630x500 crop. `buy_land {"count":15}` bought 7 parcels for 517 gold and answered
    `"opened":["ore","forest"]`, `radius 10 -> 24`, `tiles 289 -> 913`; after
    `step-time --seconds 45` the census was `home` 144 nodes and `ore`
    `{"Coal":5,"Copper":8,"Gold":2,"Iron":4,"Stone":2}`. `goto_resource {"name":"Gold"}`
    then put the player on the ore island, which is the frame that became the cover and the
    banner — four ore types, a stepped shoreline and the player in one shot.
  - Cheaper: nothing. There is no cover art, no banner and no screenshot in the repo; the
    only image is `icon.svg`. Every pixel shipped here was rendered by the running game.

- Gap: **[G-016] `set-state` still cannot write a vector-typed property.** Zooming the camera
  out to fit more world into the cover crop:
  ```
  $ devtools.py set-state --node /root/Main/World/Player/Camera2D --property zoom --value '[5.5,5.5]'
  State updated
  $ devtools.py get-state --node /root/Main/World/Player/Camera2D --property zoom
  zoom: {"x": 8.0, "y": 8.0}
  ```
  `State updated` on a write that did not happen. I spent a detour reading `world/camera.gd`
  looking for per-frame zoom enforcement that does not exist — the scene authors zoom 8 and
  nothing rewrites it. Second sighting; `seen:` bumped on the original entry rather than
  re-filed.
  - [G-016] status: open | seen: 2 | harness: 0.7.0
  - Improvement: unchanged from the original entry — coerce via `type_convert()` and **fail
    loudly**. The cost here was not the failed write, it was `State updated` sending me into
    the wrong file.

- Gap: **`screenshot` cannot exclude the HUD or crop, so it cannot produce store art.** A
  store cover is game pixels with no UI on them, at a fixed aspect. The verb only captures
  the whole window with everything visible, so the sequence was two `set-state` calls to hide
  `/root/Main/World/Player/Camera2D/HUD` and `/root/Main/UI` by hand, then a separate PIL
  script to crop 1260x1000 out of 1920x1080 and box-filter it to 630x500. Hiding the UI by
  hand is also easy to get wrong in the other direction — I re-enabled both before the
  gallery shots, and nothing would have told me if I had not.
  - [G-079] status: open | seen: 1 | harness: 0.7.0
  - Improvement: `screenshot --region X,Y,W,H` and `--hide-group GROUP` (repeatable), so a
    crop is reproducible from the command line instead of living in a throwaway script, and
    so "capture the world without the HUD" is one call that cannot leave the HUD hidden.

- Gap: **nothing in the harness can answer "does the shipped web build still boot".** The
  page now serves `gather-html5.zip` pushed by CI, and every check available here runs the
  desktop build from source. The export that itch actually serves is never exercised.
  - [G-080] status: open | seen: 1 | harness: 0.7.0
  - Improvement: an entry point that serves `bin/` and drives the exported HTML5 build
    through the same bridge, so `--export-release` output is verifiable before it is public.

## 2026-08-02 — Uploaded the store images to itch.io (no Godot harness surface touched)

- Value: **inconclusive** — this turn was entirely browser automation against itch.io; the
  Godot game was never launched, so no harness capability was exercised and none can be
  graded. Recorded so the absence is explicit rather than a forgotten entry.
  - Expected: n/a — no runtime claim was made about the game.
  - Got: n/a.
  - Cheaper: n/a.

- Correction to the previous entry's prose (not to a filed gap): I reported the itch.io
  image uploaders as undrivable. That was wrong, and the earlier conclusion that a drop had
  succeeded was also wrong — the cover that appeared had been uploaded by hand and showed a
  "Wave 3" HUD from a build that predates the wave removal. The widget has no DOM file input
  and no working drop handler, but it *does* build a real `<input type=file>` and call
  `.click()` on it. Patching `HTMLInputElement.prototype.click` to swallow the call for
  `type === 'file'` yields the input with its listeners attached and no OS dialog; assigning
  `input.files` from a `DataTransfer` and dispatching `change` then runs itch's own upload
  path. All five images went up that way.

- Gap: no gaps this turn — the harness was not used.
## 2026-08-02 — Log bookkeeping: renumber ID collisions, file the un-filed friction (0.8.0 prep)

- Value: **inconclusive** — no code ran; this entry converts prose observations already in
  this log into tracked gaps so the 0.8.0 close-out can cite them. Four ID collisions were
  also repaired above: G-036(b)→G-065, G-037(b)→G-066, G-044(b)→G-067, G-074(b)→G-068
  (edited in place with a reassignment note; G-069..G-072 remain unissued).
  - Expected: n/a (bookkeeping).
  - Got: n/a.
  - Cheaper: nothing — the collisions made "is this fixed?" ambiguous for four IDs.

- Gap: **`step-time` does not sustain a held input action across stepped frames** — first
  observed as an unfiled Note (2026-08-02): `step-time --seconds 3` advanced a held-move
  player 4px where 2.5s of wall-clock `input press` + `sleep` moved it ~55px. The docs only
  promise the clock advances, but the practical effect is that "press, step-time, read"
  silently asserts nothing about held-input behavior.
  - [G-084] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: `step-time --hold <action>` that re-asserts the action's pressed state on
    every stepped frame, and a `held_actions` field in the reply so the caller can see
    whether anything was sustained.

- Gap: **a `blocked` check does not affect the run verdict** — ledger row
  2026-08-02T04:58:57Z records `{"name": "crafting recipe cards rendered", "result":
  "blocked"}` and still `"verdict": "pass"`. A check that could not run is being scored as
  if it had passed.
  - [G-085] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: `verify_ledger.py record` should refuse `verdict: pass` when any check is
    `blocked` (downgrade to `aborted` or a new `partial`), so the summary can't claim more
    than the run demonstrated.

- Gap: **a stash-based A/B that stashes only one file of a multi-file change produces a
  false "already fixed"** — recorded 2026-08-01: stashing `input_manager.gd` alone made the
  bug not reproduce because the rest of the causal chain was still applied. Nothing in the
  /verify workflow warns that an A/B must carry the whole diff.
  - [G-086] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a Phase 4 note (and checklist line) for A/B testing: stash/restore the
    full changed-file set from Phase 0's diff, never a hand-picked subset.

- Gap: **slow-motion screenshots distort size and stacking judgments** — recorded
  2026-08-02: at `set-game-speed 0.08` the XP splash "looked enormous" purely because a
  stacking tween was stretched eight-fold. Good for draw-order questions, misleading for
  scale questions; nothing documents the distinction.
  - [G-087] status: open | seen: 1 | harness: 0.7.0
  - Improvement: one paragraph in the verify skill's screenshot guidance: use slow-mo for
    ordering/occlusion, use `canvas-scale`-style reads (see G-073/G-075) for size claims.

- Gap: **`--import`'s blast radius is known only from prose** — two entries (2026-08-01,
  2026-08-02) narrowed it by hand: running the test suite does not dirty `project.godot`;
  only `--import` does, and not every import. That scoping lives nowhere actionable, so
  every agent re-derives when a dirty `project.godot` is self-inflicted.
  - [G-088] status: fixed | fixed-in: 0.8.0 | seen: 1 | harness: 0.7.0
  - Improvement: document the blast radius next to the `--import` instruction in
    CLAUDE.harness.md, and have the verify skill snapshot/restore `project.godot` around
    any `--import` it performs (pairs with G-028).

- Gap: **no seed-sweep / property-test tier, though it repeatedly proved the cheapest
  decisive check** — the island-connectivity work found a 6% stranding rate only via a
  200-seed headless sweep after two live runs both reported "every island connects"
  (2026-08-01), and the entry concluded the sweep "should have come before the launch, not
  after". The lesson exists only as prose.
  - [G-089] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a documented sweep pattern in the verify skill (Phase 1.5: "if the diff
    touches procedural generation, run the relevant `test_*` sweep with a seed count from
    config before launching"), plus a `sweep_hints` config key mapping path globs to test
    filters.

## 2026-08-02 — Implemented the gather-side verb stream: goto_cell, panels_state, freeze_ambient, place_build-via-real-path, tile_at in-front default, place_station nearest-cell, gather_stats in-progress fields (beads gather-dsk/15o/tfb/7y9/6l7/j99/2b4)

- Value: **warranted** — runtime produced three claims the diff could not: (1) facing
  alignment actually holds end-to-end (`goto_cell` grass_clear: stand (3,1), facing_left
  true, `tile_in_front` (2,1) == matched cell — the game's own
  get_tile_in_front_of_player agreeing with the verb's math); (2) the real placement path
  pays xp (`place_build` woodwall: `"xp_before": 0, "xp_after": 1, "consumed": 1` — the
  exact G-061 symptom, dead); (3) freeze really holds the world still
  (`time_to_next_spawn` bit-identical at 0.187189594905178 across 30 stepped seconds,
  live_nodes 69 -> 69 over 60 more, then resumed and re-rolled to 19.4s after unfreeze).
  - Expected: alignment or occupancy would be where goto_cell/place_build broke, since
    facing is only recorded as a sprite flip and nothing in the diff exercises it.
  - Got: all three assertions above, plus `place_station` `"distance_px": 21.76` (< the
    24-unit keep-open radius; the pre-fix far-corner scan landed at 48), and one honest
    surprise: live enemies bump the teleported player between CLI calls, so a
    goto_cell-then-place_build recipe must recompute dx from the player's *current* cell
    (place_build's own re-teleport makes it self-aligning; the first refused attempt was
    a genuinely occupied cell, not a verb bug).
  - Cheaper: nothing headless reaches facing/occupancy/xp — but the pure nearest-cell
    half (cells_within + cell_nearest_to) was settled by 4 unit tests in 2ms, which is
    exactly where that logic was extracted to so it could be.

- Gap: **`cmd` verbs are not hyphen-aliased, contradicting commands.gd's own header** —
  `cmd goto-cell --args '{"predicate":"grass_clear"}'` returned
  `"message": "Unknown action: goto-cell"`; `cmd gather-stats` (the header's own example)
  fails identically. Workaround: underscore forms work; my new docstrings now show those.
  - [G-082] status: open | seen: 1 | harness: 0.7.0
  - Improvement: normalize hyphens to underscores in the game-side dispatcher for `cmd`
    payload actions (the top-level verbs already get this), or fix the header comment.

- Gap: **a fresh git worktree cannot run ANY harness validation before `--import`, and
  `--import` is barred by its project.godot rewrite (G-028/G-088)** — first lint run in
  the never-imported worktree produced 1108 SCRIPT ERRORs ("Identifier "Types" not
  declared…" for every global class) yet still `exit 0`, and the runner then printed
  `[PASS]` for tests whose first line had errored (`Invalid call. Nonexistent function
  'cells_within' in base 'GDScript'` — the gather-1t9 shape, four times). Workaround that
  worked end-to-end: copy the project (minus .git/.godot) to a scratch dir, run
  `--import` there, verify there — 0 script errors, 250/250, full runtime session.
  - [G-083] status: open | seen: 1 | harness: 0.7.0
  - Improvement: a documented `worktree-verify` recipe (or flag on /verify) that
    auto-stages the scratch copy + import; failing that, the runner should refuse to
    report PASS when the class cache is absent, since every "pass" in that state is
    unverified.

## 2026-08-02 — Harness 0.8.0 refresh landed on this branch; 53 gaps above closed

- Value: **warranted** — the refresh itself was the assertion: all 8 installed files
  updated "unmodified - no backup needed" (the G-001/G-020 fix demonstrating itself),
  `eval.gd` newly installed, `godot_bin` recorded, and the sticky config ownership
  held (`hud_layer_name`/`main_scene` kept project-owned).
  - Expected: a clean pristine-upgrade with zero `.bak` residue and no config clobber.
  - Got: exactly that, quoted above; plus lint against the real tree now reads
    `0 error(s), 0 warning(s)` where every prior run carried 7 false positives.
  - Cheaper: nothing — upgrade behavior only shows on a real upgrade.

- Gap: **no gaps this turn** — the status flips above (fixed-in: 0.8.0) are the
  closures; G-082 and G-083 from the verb-stream session remain the open items.

## 2026-08-02 — the hotbar floating to mid-screen on a landscape phone

- Value: **warranted** — the fix is arithmetic a unit test can check, but the bug only
  existed at an aspect ratio nobody sees on a desktop, and the running game is what
  produced the two numbers that name it.
  - Expected: at 844x390 with a touchscreen reported, the live `HotBarInventory`'s bottom
    edge should sit within ~20px of the viewport bottom (y≈370), not ~45% up it (y≈220),
    and its rect must not intersect the joystick or the primary button.
  - Got: `node-bounds /root/Main/UI/HotBarInventory` → `Rect: 234, 324, 377x58` — the row
    ends at y=382 on a 390-tall viewport, 8px of margin, exactly `scaled(10)`. Beside it,
    `run-method get_bottom_obstruction_height --args "[]"` → **176.15** against **0.0** for
    the same call with the row's own span. That pair is the entire bug in two numbers: 176
    of 390 is 45% of the screen, claimed by a joystick whose rect (`14, 214, 162x162`) does
    not come within 58px of the hotbar horizontally.
  - Cheaper: the three new unit tests settle the arithmetic in 14ms with no boot, and had I
    *known* the span was the problem they would have sufficed. Nothing cheaper would have
    told me the span was the problem — `_bottom_obstruction()` reads as obviously correct
    until you put a number on the joystick's height next to a 390px screen.

- **[G-017] paid off the same day it shipped.** `set-resolution --size 390,844` flipped the
  live session to portrait and back without a relaunch, which turned a two-boot,
  ~90s-per-data-point check into two calls — and, more to the point, tested the thing the
  relaunch approach structurally could not: the `size_changed` *transition*. The hotbar
  re-solved correctly in both directions (portrait `6, 601, 377x58` above a joystick
  starting at y=668; back to landscape, `234, 324, 377x58` again, byte-identical to before
  the round trip). Filed 2026-07-?? at 0.4.0, fixed in 0.8.0, and this is the first run to
  use it. Worth recording that the log→upstream→fix loop closed.

- Gap: **a stale `.godot` class cache is undiagnosable from either gate's output.** After
  rebasing this worktree onto a `main` that had added `class_name BoneWorker`, lint exited
  1 and the runner exited 2 with `Total: 295 | Passed: 257 | Failed: 5` and **135**
  `SCRIPT ERROR` lines, every one of them a cascade from a single missing entry in
  `.godot/global_script_class_cache.cfg`:
  ```
  SCRIPT ERROR: Parse Error: Could not find type "BoneWorker" in the current scope.
  ERROR: Failed to load script "res://items/items.gd" with error "Compilation failed".
  ERROR: Failed to load script "res://devtools_ext/commands.gd" with error "Parse error".
  ```
  CLAUDE.md documents `--import` as required after *adding* a `class_name`; the case that
  bites is *receiving* one — a rebase, a pull, a branch switch — where you did not add
  anything and the failure presents as five broken tests in files you never touched.
  `--import` fixed it (`0 error(s), 0 warning(s)`, 295/295), but only because the project's
  own docs had the answer; the harness's output pointed nowhere.
  - [G-090] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `lint_project.gd` compare the `class_name` declarations it already
    scans against `.godot/global_script_class_cache.cfg` and, on a mismatch, fail with one
    line — `stale class cache: BoneWorker declared in res://… but absent from the cache; run
    --import` — ahead of the 135 parse errors rather than buried under them. It has both
    halves of the comparison in hand already.

## 2026-08-02 — hotbar arrows to the touch floor where there is room for it

- Value: **warranted** — the unit tests assert the widths, but `validate-ui`'s verdict is
  the thing the bead was filed off, and only the running game can flip it.
  - Expected: the two `small_tap_target` warnings should disappear at 844x390 with the
    arrows measuring 48x48 instead of 29x48, while portrait keeps ~28px arrows because six
    48px slots plus two 48px arrows physically need ~398px of a 390px screen.
  - Got: `validate-ui` went from `[FAIL] 2 UI issues found` to `[OK] No UI issues found`
    in landscape, with `node-bounds …/PrevButton` → `220, 328, 48x48` (was `29x48`). The
    row grew 377→415px wide and still ends at y=382 on a 390-tall viewport, so the
    bottom-edge fix from the previous commit survived the resize. `set-resolution --size
    390,844` then confirmed the other half exactly as predicted: `12, 606, 28x48`, still
    two warnings, and a 375px row inside a 390px screen.
  - Cheaper: the three new unit tests cover the arithmetic in 1ms with no boot — and would
    have been enough for the *fix*. They cannot say whether `validate-ui` agrees, which is
    the whole question the bead asked, so the boot earned its keep on the verdict alone.

- Note, not a gap: **`validate-ui` is a function of the live viewport, and nothing says
  so.** The same build is `[OK]` at 844x390 and `[FAIL] 2 UI issues found` at 390x844 —
  correctly, since `small_tap_target` is measuring real pixels — but a run that happens to
  boot in one orientation reports a clean sheet for a layout that violates the rule in the
  other. This bit twice today in opposite directions: the first run *found* the arrow
  warnings only because it was launched landscape to chase an unrelated bug, and this run
  would have declared the fix complete had it not been rotated back. `set-resolution`
  ([G-017], fixed in 0.8.0) is what makes checking both cheap, so the gap is not a missing
  capability — it is that nothing prompts you to use it. Worth `/verify` suggesting a
  second `validate-ui` at a transposed viewport whenever the diff touches UI layout.

- No new gaps this turn otherwise. [G-090] (stale class cache undiagnosable) was not
  re-triggered — the cache was rebuilt in the previous run.

## 2026-08-03 — a scripted demo director + movie-writer capture for the README turret clip

- Value: **warranted** — runtime found a defect that no reading of the diff would have,
  and found it twice in different guises.
  - Expected: that `demo_clip` drives all four beats to completion with an empty `notes`
    array — specifically that the net swing lands a `BoneEnemy` in the inventory and the
    load press flips a turret's `loaded` flag. Neither is derivable from the diff: the
    capture depends on the 0.2s swing surviving the key release and on the skeleton
    sitting inside a ~15px hitbox, and both fail silently.
  - Got: on the final run, `demo_state` → `beat=done, notes=[]` and `worker_state` →
    all five turrets `loaded: true` with `skulls_held: 0` (the skull was spent loading
    one). Getting there took four failed takes, and the payoff was the third: releasing
    the use key runs `Player._gather_input_release`, which calls `animation_player.stop()`
    — so a two-frame simulated tap killed the 0.2s `Net_Right` animation about fifteen
    milliseconds in, before the net swept anywhere near the skeleton. `stop()` emits no
    `animation_finished`, so `PlayerNet` never exited either, and the only trace anywhere
    was `ERROR: Signal 'body_entered' is already connected` on the *second* swing. A held
    key fixed it. Runtime also produced two facts the source cannot state: `EnemyIdle`
    only hands over to `EnemyFollow` inside 30px (so a wave spawned 5 tiles out just
    wanders), and a turret's `LineOfSight` is 40px — which together set the entire shot,
    and turned a planned camera pull-back into "do not change the zoom at all".
  - Cheaper: nothing. The net capture has no headless path — it needs a live `Area2D`
    overlap during a 0.2-second animation, driven by real input, with a chasing
    `CharacterBody2D` on the other end.

- Gap: **[G-050] again on 0.8.0 — reach still cannot see a `RefCounted`, and it
  downgraded a run that demonstrably exercised the file.** `verify_ledger.py record`
  printed `downgraded warranted -> insufficient: no changed file was loaded at runtime
  (devtools_ext/demo_director.gd)`, in the same run where `cmd demo_clip` had just driven
  that file through six beat marks and `worker_state` confirmed five turrets loaded by it.
  `DemoDirector` extends `RefCounted` and is held as a field by `commands.gd`, so it is
  never any node's script and cannot appear in a `scene-tree` snapshot by construction —
  the same shape as `skill_tree.gd` when this was first filed. `commands.gd` is credited
  as `implicit`; a script it owns is not. Workaround: report the downgrade as a reach
  blind spot in the summary and cite the `worker_state` assertion instead.
  - [G-050] status: open | seen: 3 | harness: 0.8.0
  - Improvement: unchanged and now overdue — credit a file when a `cmd`/`run-method` call
    during the run touched it. The client knows every verb it invoked; mapping an invoked
    verb back to the extension's `_director`/handler file closes this without any engine
    support. Failing that, extend the `implicit` credit from the extension script to
    scripts it `preload`s or constructs.

- Gap: **`devtools.py launch --isolated` advertises userdata isolation it does not
  deliver, and the failure reads as a dead game.** It prints `userdata:
  C:\...\devtools_userdata__8__cbit` and `Subsequent calls: ... --userdata <that path>`,
  but Godot resolves `user://` from the engine and honours no `GODOT_USERDATA`, so the
  temp dir stayed empty (`ls` → nothing) and every call with the flag it told me to use
  failed with `game not running: 'ping' was never picked up`. Dropping `--userdata` and
  keeping only `--session` worked first try. This is the *client* half of the note already
  under [G-036]; the difference is that `--isolated` now actively hands you the broken
  invocation.
  - [G-091] status: open | seen: 1 | harness: 0.8.0
  - Improvement: either drop the `userdata` line from `--isolated` output and say plainly
    that only the bus is isolated, or make it real by writing a scratch copy of
    `project.godot` with `use_custom_user_dir=true` — which is the [G-057] ask anyway.

- Gap: **`launch` cannot pass extra arguments to the Godot binary, so any run needing an
  engine flag has to re-implement launching.** Recording needs `--write-movie
  <dir>/frame.png --fixed-fps 30`, and `cmd_launch` builds a fixed
  `[godot, --path, project, --mute]` with no passthrough. `tools/capture_clip.py` therefore
  duplicates the whole launch path — binary resolution from `devtools_config.json`, the
  `GODOT_DEVTOOLS_SESSION` env var, detached stdout/stderr redirection — about 30 lines
  that will drift from the harness's copy. It also has to *not* pass `--mute`, since the
  movie writer records the audio bus into a `.wav` and a muted run captures silence.
  - [G-092] status: open | seen: 1 | harness: 0.8.0
  - Improvement: let `launch` forward everything after a bare `--` to the Godot command
    line (`devtools.py launch --isolated -- --write-movie out/frame.png --fixed-fps 30`),
    and make `--mute` opt-out rather than unconditional.

## 2026-08-03 — Fanned out the save/load hardening (user://, atomic write, format version, player payload)

- Value: **inconclusive** — no runtime evidence yet by design; three subagents are writing
  code and tests under an explicit ban on running any Godot binary, and every gate runs
  serially here afterwards.
  - Expected: nothing from the harness this turn beyond confirming no game held the bus.
  - Got: `harness-version` reported the bus owner as `pid 18512 … that process has likely
    exited`, i.e. a clean bus, so the later serial `/verify` will not be racing anything.
  - Cheaper: reading `systems/save_load.gd` and `player/player.gd` directly, which is what
    actually produced the four issues (gather-2rb/pjp/8rs/vn0). The relative-path bug at
    `save_load.gd:67` is visible in the source; no run was needed to find it.

- Gap: **Nothing in the harness lets N agents validate in parallel, so the only safe
  policy is "agents never run Godot".** The bridge is one command/result pair and `.godot/`
  is one import cache, so three agents each running `run_tests.gd` is already a shared-writer
  hazard before the bridge is even involved. I forbade all Godot execution in the subagent
  prompts and took every gate myself, which serialises the slowest part of the work behind
  one agent.
  - [G-093] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `devtools.py scratch-clone` that stamps out a copy of the project with
    `use_custom_user_dir=true` and a unique `custom_user_dir_name`, prints the path, and
    cleans up on exit — the [G-057] ask, but reached for parallel *validation* rather than
    parallel play. Headless lint/test would still need a separate `.godot/` per clone,
    which the clone gives for free.

## 2026-08-03 — Triaged the save-contract audit into beads; warned the player.gd agent off an x/y collision

- Value: **inconclusive** — no harness use this turn. The audit was static reading, and the
  two implementation agents are still running under the no-Godot ban, so there was nothing
  to run yet.
  - Expected: n/a, no run planned.
  - Got: n/a. The one finding that mattered most — `save_load.gd:124` routes any entry with
    top-level `x`+`y` into the SaveChunks bucket, so renaming the player's `px`/`py` would
    have silently stopped `Player.loadObject` ever being called — came from reading the
    reader, not from running it.
  - Cheaper: nothing cheaper existed; this is the case where static reading beat runtime,
    because the failure is a *routing* decision that produces no error and no symptom until
    a player reloads.

- Gap: **no gaps this turn** — the harness was not exercised, so it had no opportunity to
  fall short. Recorded so this turn is distinguishable from a forgotten log.

- Note for the next entry: the `x`/`y` discriminator above is exactly the class of bug
  `/verify` cannot see. A save round-trip that writes and re-reads in one session still
  passes, because the player entry lands in `loads` and the *previous* in-memory state is
  never contradicted. gather-bdv (round-trip tests asserting post-load state) is the real
  guard; note it if the upcoming verify run comes back green on this diff.

## 2026-08-03 — Reviewed the save_load.gd diff; blocked on a concurrent agent before any gate

- Value: **inconclusive** — still nothing run. One agent finished but the other has
  `player/player.gd` modified mid-flight, and a headless suite run would compile a
  half-written file and report failures belonging to neither change.
  - Expected: n/a, no run attempted.
  - Got: a static substitute that was actually worth it — `grep -rl` over `*.uid` showed
    both hand-written sidecars (`uid://bqn4vxk2dh7rm`, `uid://dqk3n8vw1ptr6`) are unique in
    the repo, and neither uses `z`, which Godot's UID alphabet (a–y plus digits) excludes.
    That is most of what `UIDs: OK` would have told me, available while the tree is
    unbuildable.
  - Cheaper: nothing — this WAS the cheap path. The point is that it was available during a
    window when the real gate was not.

- Gap: **A subagent that cannot run Godot also cannot generate a `.uid`, so it hand-writes
  one and nobody can validate it until the orchestrator imports.** The agent said so
  explicitly: "the `.uid` I hand-wrote has not been validated by Godot." Lint's `UIDs: OK`
  covers presence and staleness but is only reachable with a working tree that compiles,
  which is exactly what a fan-out does not have until every agent lands.
  - [G-094] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `devtools.py new-uid` that emits a fresh, correctly-encoded, collision-
    checked uid string without launching the editor or importing. It is a pure function over
    `ResourceUID::id_to_text` plus a scan of existing sidecars, it needs no game, and it
    would let any agent write a valid sidecar for a script it just created.

## 2026-08-03 — /verify on the save/load hardening (user://, atomic write, format version, player payload)

- Value: **warranted** — runtime loaded a real save written by the pre-change code and
  proved the old-to-new conversion end to end, which no unit test in this repo could have.
  - Expected: the running game writes `user://saveFile` (not the repo-root `saveFile`), its
    first line is the version header, and a save-mutate-load cycle restores the real Player
    node's position, health and inventory — proving the live `saveObject()` payload routes
    through `Player.loadObject` rather than into the SaveChunks bucket. The unit tests only
    prove the parser agrees with hand-built dictionaries.
  - Got: an untouched `saveFile` from Aug 2, written before any of this work, loaded with
    `loaded_format_version: 0`; the player moved `(8.0, -14.07) -> (-3.05, -14.05)`; and the
    live `saveObject()` then returned `{'inv_json': [{'count': 1, 'type': 22}, … , None,
    None, …], 'pos': {'args': [-3.05…, -14.05…], 'type': 'Vector2'}}` — six items recovered
    out of the old embedded-JSON strings, re-emitted as nested dicts with positional nulls,
    and **no top-level `x`/`y`**. Then `{"save_format_version":1}` as line one of the new
    file, no stray `.tmp`, reload reporting version `1`, position byte-identical, and the
    repo-root file sha256-unchanged.
  - Cheaper: nothing. CLAUDE.md already says it — `saveFile` is gitignored, so a broken load
    is not something CI or a fresh clone can show you, and the only way to catch it is to
    load a save written before the change. That file existed on this machine and nowhere
    else.

- Gap: **`reach` counts `test_dir` scripts in the worktree denominator, but a game session
  can never load them.** This run reported `worktree … reached 2/4 changed file(s); NOT
  reached: test/unit/test_player_save.gd, test/unit/test_save_load.gd`. Both game files were
  reached; the two "misses" are unit tests that ran in Phase 1 and are structurally incapable
  of appearing in a `scene-tree` snapshot. The `.uid` sidecars beside them were correctly
  binned as "not applicable", so the classifier already has the concept — the test scripts
  just are not in it. Effect is the unflattering mirror of the fixed [G-044]: writing a test
  alongside a fix permanently caps your reach ratio below 100%.
  - [G-095] status: open | seen: 3 | harness: 0.8.0
  - Improvement: put paths under the configured `test_dir` in the existing "not applicable"
    bucket, or better, credit them from the Phase 1 run — `run_tests.gd` already knows
    exactly which test scripts it selected and executed.

- Note (my slip, not a harness gap): I tailed `performance` to 8 lines and cut off the FPS
  reading, then quit the game, so the `fps_min` check could not be evaluated. Recorded as
  `"result": "blocked"`, which correctly downgraded the ledger row `pass -> partial`. Orphan
  growth was `+2` against a `orphan_growth_max` of 20 — and that `+2` is almost certainly the
  known leak in gather-jjg rather than anything new here.

## 2026-08-03 — gather-5my (parse before wiping the tilemap) + a demo homestead save fixture

- Value: **warranted** — runtime showed a 32-cell house still standing after a load that,
  before this change, would have cleared it and aborted.
  - Expected: loadObject must survive a corrupt tile payload without clearing the tilemap
    first, and a full demo homestead must survive a save/load round-trip with every scene
    tile back at its own cell.
  - Got: feeding `{"tiles":["{not json","[1,2]","{}","42"]}` to `/root/Main.loadObject` left
    `32 used cell(s)` untouched; the partial case (`2 valid Chest entries + 2 corrupt`)
    replayed `(0, 0) source=8` and `(1, 0) source=8` and nothing else, so a bad line costs
    exactly its own tile. The fixture round-tripped as 22 lines / 2016 tiles / 12 SaveChunks
    with all 32 object cells and the auto-tiled wall corners (`atlas=(1, 7)`, `(3, 9)`)
    restored identically.
  - Cheaper: nothing for the corrupt-payload claim. `test_tilemap_payload.gd` covers
    `parse_tile_payload` in isolation and is the right place for the parse rules, but the
    actual assertion — the house is still there — needs a house, and therefore the game.

- Gap: **`cmd` and `run-method` results are printed as Python-repr-ish text, not JSON, so
  every reply has to be re-parsed by hand.** `cmd build_demo_world` printed a dict I had to
  slice from the first `{` and feed to `json.loads`, and `run-method` answers `Result: None`
  for a `-> void` — indistinguishable from a call that raised, which is the exact failure
  mode `gather-5my` is about. I asserted around it by reading the world afterwards, but a
  verb that reports "did this call complete" would have been a one-liner.
  - [G-096] status: open | seen: 1 | harness: 0.8.0
  - Improvement: give `run-method` a `--json` envelope like `scripts-seen` has, and have it
    distinguish "returned null" from "aborted" — the bridge already knows, since a raise
    unwinds before the reply is written.

- Note: `--rect` needs `--rect="-24,-2,14,12"` (with `=`) when the value starts with `-`;
  the space form is eaten by argparse as a flag. Not filed as a gap — standard argparse.

## 2026-08-03 — Answered where the demo save fixture shows up in-game

- Value: **overkill** — no harness use, and none was warranted: the question was answered by
  two greps over `project.godot` and `ui/debug_panel_ui.gd`.
  - Expected: n/a, no run planned or needed.
  - Got: n/a. `grep` found exactly two load triggers (the `]` binding, keycode 93, and
    `debug_panel_ui.gd:384`), both calling `SaveLoad._load()`, which reads one path. No save
    enumeration exists anywhere, so the fixture cannot appear in a list.
  - Cheaper: this WAS the cheap path — two greps, ~2s. Launching the game to look for a load
    menu would have cost a minute and proven less, since absence of a UI is easier to
    establish from the input map and the one button than from a screenshot.

- Gap: **no gaps this turn** — the harness was not exercised. Recorded so this turn stays
  distinguishable from a forgotten log.

## 2026-08-03 — Save slots: wiring agent landed, mobile reachability closed

- Value: **inconclusive** — no harness run; two of three agents are still writing and the
  tree does not compile as a whole yet.
  - Expected: n/a, no run attempted.
  - Got: n/a from the harness. The turn's real finding was static — `hud_toolbar.gd:240`
    hides the whole button cluster when `DisplayServer` reports a touchscreen, and
    `mobile_controls.gd:181` listed only `["inventory", "skills", "land"]`, so the new panel
    would have been unreachable on a phone. My own brief to the agent claimed the opposite.
  - Cheaper: two greps, which is exactly what found it. Runtime would have needed
    `set-feature --touchscreen true` and a screenshot to show the same thing, and would have
    shown it as an absence — the hardest thing to notice in a screenshot.

- Gap: **no headless way to check a layout budget** — deciding whether a fourth toolbar
  button fits a 390px portrait viewport meant deriving it on paper across `UiTheme.scale_for`,
  `scaled`, `scaled_touch` and `_apply_scale`, because the only executable check needs a
  running game or a full test run with `_T.instantiate_ui`. The subagent reached the same
  wall and proposed the same fix independently.
  - [G-097] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a headless `layout-probe` that takes a scene path plus a viewport size and
    prints the resulting node rects, so a width budget is one command rather than a launch.
  - Note: the agent proposed filing this as [G-060], which is already taken *and* resolved
    `wontfix` in this file. Ids are assigned by the orchestrator, not by subagents — worth
    stating in the brief next time, since a colliding id silently corrupts `upstream_gaps.py`.

## 2026-08-03 — Save/load slots: three parallel agents, integrated and verified

- Value: **warranted** — runtime caught an integration break that lint and 349 unit tests
  could not see, because each half was correct on its own.
  - Expected: the three agents' pieces would meet at seams I under-specified; runtime should
    show whether the panel, the storage layer and the input path actually connect, not just
    whether each parses.
  - Got: `cmd slot_panel --args '{"open":true}'` answered **`no save-slot panel in the
    scene`** on a build where lint reported `Scripts: 127 compiled OK` and the suite reported
    `349 passed, 0 failed`. The panel exposed `is_open`/`toggle`/`set_open`; the devtools
    lookup duck-typed on `open`+`close`+`toggle`+`is_open`. Both were internally consistent
    and unit-tested; only the running game had both in one process. Then, once fixed:
    migration put the pre-slot save in slot 1 as `version 1, readable, metadata zeroed`, a
    fresh save wrote `version 2, level 1, radius 10` with a real timestamp, the touch SAVE
    button flipped `is_open` False -> True with the desktop toolbar hidden, and `O` toggled
    it both ways.
  - Cheaper: nothing. This is the case the ledger exists to record — two green gates and a
    feature that could not be opened.

- Gap: **a contract handed to N agents has no checker, so a seam only fails at runtime.**
  I pinned the `SaveLoad` slot API precisely and all three agents matched it exactly; the
  break was in the API I described only in prose — I told the verbs agent the panel would
  expose `open()`/`close()`, and told the panel agent to build on `PanelFrame` without
  pinning its wrapper names. It chose `set_open(bool)`. Nothing in lint, the type system or
  the tests connects a `has_method("open")` string in one file to a `func set_open` in
  another.
  - [G-098] status: open | seen: 1 | harness: 0.8.0
  - Improvement: extend `--find-orphans`-style static analysis to flag `has_method("x")` /
    `call("x")` / `connect("x", …)` string literals naming a method or signal that exists
    nowhere in the project. It is the same scan, and it would have printed this one as a
    finding before the game was ever launched.

- Note: `cmd slot_panel` with no args *toggles*, so my first two "read the state" calls
  mutated it and I misread a working tap as a failure. Read state with `run-method … is_open`
  instead. Not a harness gap — the verb documents the toggle — but a reminder that a status
  read and a state change must not share a verb.

## 2026-08-03 — Save fidelity: in-flight work, carried loads, exact drop positions

- Value: **warranted** — runtime caught a bug in the fix I had just written, after lint and
  the full suite passed on it.
  - Expected: the station/worker/pickup payloads are missing progress state, so a load
    should visibly reset work in progress; runtime should show whether persisting
    `time_left` actually resumes the item.
  - Got: with a 600s cycle started at 300s remaining, the pre-save read was
    `time_left: 299.0, wait_time: 600.0` — but the *setup* read back `wait_time: 300.0`
    after I called `start(300.0)`, which is how I learned `Timer.start(t)` **assigns**
    `wait_time = t` rather than running once for `t`. My fix called `timer.start(remaining)`,
    so a furnace saved with 0.3s left would have smelted its remaining 53 ore at 0.3s each.
    After putting the interval back: `count: 54, starting_count: 60, time_left: 285.0,
    wait_time: 600.0`. Separately, the three drops in the real pre-change `saveFile`
    reloaded fractional instead of snapping to `-9 / -50 / -49`.
  - Cheaper: nothing. The clobber passed `lint 0/0` and `359 passed, 0 failed`, and is
    invisible in the diff — `start(remaining)` reads exactly like the correct fix. Only
    reading the live Timer's `wait_time` after a load could distinguish them.

- Gap: **no gaps this turn** — the harness did what it exists for. `step-time`,
  `run-method` on a Timer and `get-state --property` were enough to set up a mid-cycle
  station and read it back across a save/load; `tilemap-cells --rect` confirmed the tile
  survived and `scene-tree` found the re-instanced node when its name changed from
  `Furnace` to `@StaticBody2D@309`.

- Note (my error, worth not repeating): I read `tilemap-cells` through `head -8` on a
  22-cell result, did not see `(-3, 0)`, and briefly concluded the load had dropped the
  furnace. The cell was there, 12 lines further down. Grep for the specific cell rather
  than eyeballing a truncated list.

## 2026-08-03 — gather-usv/xc0/x93/ce1/bdv: de-encoded payloads and the last unguarded reads

- Value: **warranted** — but the unit tests did most of the work here, and the honest
  version is that runtime confirmed rather than discovered.
  - Expected: de-encoding eight payloads is a format break; runtime should show whether a
    real pre-version, all-old-shape save still loads and whether a v3 rewrite of it
    round-trips.
  - Got: the untouched 21145-byte `saveFile` loaded as `loaded_format_version: 0` with
    `81 used cell(s)` and `radius: 10`; re-saving produced
    `{"land_radius":10,"level":1,"save_format_version":3,"saved_at":...}` with
    `first entry type: dict -> {'type': 27, 'x': 2, 'y': -1}`; reloading that reported
    `loaded_format_version: 3` and the same cell count. The strongest signal was quieter:
    all 359 pre-existing tests passed unchanged, and several of them (island_manager,
    enemy_spawner) build **old-shape** payloads by hand — so the suite was already a
    compatibility test for this change without being written as one.
  - Cheaper: `test_save_decoding.gd` covers `decode_entries` over both shapes, mixed lists
    and every drop path, and would have caught any decoder bug on its own in 4s. Runtime's
    unique contribution was narrower than usual: that a real 21KB legacy file end-to-ends.

- Gap: **no gaps this turn.** `tilemap-cells --rect`, `get-state --property` and reading the
  slot file off disk covered everything; nothing had to be worked around.

- Note on a measurement I nearly reported wrongly: the v3 file came out *larger* than the
  v2 one (25943 vs 21145 bytes), which looks like the de-encoding backfired. It is not —
  the tile count went 490 -> 890 because ambient resources respawned during the session.
  Per entry the escaping really was the overhead: 50 bytes -> 42 for one tile. Comparing
  whole-file sizes across a live session measures the world, not the format.

## 2026-08-03 — Gameplay bead batch: gather restart guard, highlight decoupling, enemy signal

- Value: **warranted** — three of these live only on the gameplay path and no unit test in
  the repo can reach them.
  - Expected: these are gameplay-path fixes that unit tests cannot reach: the gather restart
    guard, the highlight decoupling and the enemy signal reconnect all only manifest in a
    running game.
  - Got: the gather guard is the clean one. With `wait_time` inflated to 60 on the *running*
    HoldTimer, a second press left `time_left` going `1.608 -> 0.923` instead of snapping to
    60 — a restart would have been unmissable. `clear-nodes --group Enemy` answered
    `Cleared 3 node(s)`, which proves the new group is populated rather than merely declared.
    3 enemies lived through ~60 game-seconds with **0** `already connected` on stderr.
  - Cheaper: nothing for the gather guard — `is_holding_e` is only meaningful in a live
    session, and the inflate-the-running-timer trick is what made a restart distinguishable
    from an ordinary countdown at CLI latency.

- **Could not verify, recorded as blocked:** both highlights on layer 3 in the same frame,
  which is the literal claim of gather-3zg.6. Every staging order defeated itself —
  `goto_resource` walks away from the station, `place_station` interrupts the gather, and on
  one attempt the resource and the station resolved to the *same cell* (-2,-1), so "1 used
  cell" looked like a failure when it was two coincident highlights. I verified the halves
  instead: the selector draws during a gather, the interact highlight clears exactly its own
  cell, and grep confirms nothing calls the wholesale `remove_highlight()` any more.

- Gap: **no way to stage two interacting world states without the setup verbs undoing each
  other.** `place_station` puts a station at the nearest free cell *to the player* and
  `goto_resource` teleports the player to a resource; there is no "put the player somewhere
  that satisfies both predicates at once". Every attempt cost a launch-to-assert cycle and
  the run still ends with a blocked check.
  - [G-099] status: open | seen: 1 | harness: 0.8.0
  - Improvement: let the project's own setup verbs take an explicit target cell
    (`place_station --args '{"cell":{"x":-8,"y":3}}'`, `goto_cell` already does) so a test
    can compose a scene deliberately instead of hoping two nearest-free-cell searches
    happen to cooperate. That is a `devtools_ext` change, not a harness one, but the gap is
    the harness's: nothing in it makes composing world state any easier than by hand.

- Note: `cmd spawn_resource` takes `name`, not `type`, and answered
  `"no resource named ''"` — a well-formed success-shaped failure. Worth reading messages,
  not just `success`.

## 2026-08-03 — Retired the orphan-leak bead by measurement; regenerated the demo fixture at v3

- Value: **warranted** — one bead was closed purely on runtime evidence, and the fixture
  regeneration produced the first honest measurement of the de-encoding.
  - Expected: the demo fixture predates two format bumps and the fidelity work; regenerating
    it should exercise build -> save -> load end to end and show whether the de-encoding
    actually shrank the payload.
  - Got: gather-jjg (2 orphans per save/load roundtrip) **does not reproduce** — four
    consecutive roundtrips reported `Orphan growth: +0 (baseline 0, absolute 0)` with total
    nodes steady at 1033. And the fair size comparison finally exists: the v3 fixture is
    59599 bytes carrying 2129 tiles against v1's 71067 bytes carrying 2016 — ~16% smaller
    with ~6% more content. Last time I compared these I got it backwards, because the tile
    counts differed in the other direction.
  - Cheaper: nothing. An orphan count is only observable in a running game, and a fixture
    cannot be produced without one.

- Gap: **a stale instance from an earlier turn silently took the bus, and the failure looked
  like a JSON parse error in my own script** — `scene-tree` returned nothing parseable, and
  only re-running it surfaced `Foreign instance on the bus: the reply to 'scene_tree' came
  from pid 22412, but ... devtools_owner.json says pid 11968 owns this bus`. The detection
  is good and it is exactly what the owner file is for; the problem is that the *first*
  call failed opaquely and the diagnosis only appeared on the retry.
  - [G-100] status: open | seen: 2 | harness: 0.8.0
  - Improvement: check the owner file before writing the command rather than when reading a
    crossed reply, so the very first call fails with the pid mismatch instead of with an
    empty response the caller has to interpret.

- Note: the ledger row is `partial` again, for `ExternalInventory`'s new centre anchor. It is
  a `visible = false` panel, so putting it on screen needs an interaction I did not stage;
  the anchor change is arithmetic (594/1152 = 51.6% -> anchor 0.5) and wants a human eye on
  it regardless, which is what gather-t9x said in the first place.

## 2026-08-03 — Installed the demo fixture into slot 3; a user-reported crash it exposed

- Value: **warranted** — the run found a crash that no gate had any way to see, and the
  fixture I generated was itself the thing that triggered it.
  - Expected: installing the fixture into a slot and loading it should exercise the whole
    slot + v3 + fidelity chain against a real file.
  - Got: `Invalid access to property or key 'product' on a base object of type 'Nil'`,
    reported by the user from a real load. `crafting_station.save()` writes
    `selected_recipe: -1` whenever the recipe is null and `timer_status: false` whenever the
    timer runs, and nothing stopped both being written together — so **the save format can
    express a state the load path cannot survive**. My generated fixture happened to be
    exactly that (the demo furnace had no unlocked recipe). Fixed on both sides; the fixture
    now carries a real IronBar recipe at 52/60.
  - Cheaper: nothing, and that is the uncomfortable part — lint, 369 tests and four of my
    own runtime passes all went green over this. Nothing asserted that `save()` cannot emit
    a payload `load()` chokes on, which is a different question from "does a round-trip
    preserve state".

- Gap: **three stale game instances accumulated across the session and silently fought over
  the bus** — [G-100] again, and worse than the first sighting. Symptoms this time were a
  `ping` that reported "No response" immediately before a `get-state` that worked, a
  `screenshot` that answered `Another Godot instance owns this bus`, and slot 3 growing from
  53218 to 61461 bytes because some other instance saved over it. `Get-Process | Where-Object
  ProcessName -like 'Godot*'` showed pids 5348, 13788 and 19148 alive at once. My `quit` had
  been landing on whichever instance owned the bus, leaving the rest running.
  - [G-100] status: open | seen: 2 | harness: 0.8.0
  - Improvement: as well as the pre-write owner check already proposed, `launch` should
    record its pid and `quit` should offer `--all` (or at least report how many instances of
    this project are alive), so a session cannot silently accumulate them. A stale instance
    that *writes save files* is not a read-only nuisance.

- Note: I lost the reach figure for this run by deleting the scene-tree and scripts-seen
  captures before writing the row, then trying to pipe `--run /dev/stdin`, which does not
  exist on Windows. Recorded with `--no-reach` rather than skipping the row. Capture, record,
  then clean up — in that order.

## 2026-08-03 — gather-uem and the audits it triggered: a dropped physics write and a silent enemy

- Value: **warranted** — both headline bugs are invisible to every static gate, and one of
  them produces no error at all.
  - Expected: the reported error is a physics-locked write that is silently dropped, so
    runtime should show both that it stops appearing AND that the net now consumes exactly
    one net per catch.
  - Got: throwing the net at a bone enemy took the inventory from `{'count': 3, 'type': 20}`
    to `{'count': 2, 'type': 20}` with a `{'count': 1, 'type': 21}` skull acquired, and
    **zero** `Function blocked` on stderr. Separately, driving `EnemyLunge.enter -> exit ->
    EnemyAttack.enter` and stepping 1.4s left the shared AttackTimer at `time_left: 0.616`
    after having fired — i.e. still repeating. Before the fix the stale `_on_lunge_end` would
    have stopped it for good. The player also dropped to `hp: 4` from live enemies during
    the session, which is the same claim from the other direction.
  - Cheaper: nothing. The dropped write is invisible in a diff — the assignment is *there*,
    it just does not happen — and the enemy timer leak emits no error whatsoever, only an
    enemy that quietly stops hitting after its first lunge.

- The audits earned their keep, and in a specific way worth recording: the physics-callback
  audit found the project otherwise clean (one site, already known) but turned up the real
  prize as a *side observation* — `player.gd:388` wrote `net.monitorable` where five other
  writes in the project use `monitoring`. That was the missing backstop, and no amount of
  staring at `player_net.gd` would have surfaced it. The state-machine audit then found a
  live P1 nobody had reported: bone and elite enemies going permanently quiet after their
  first lunge.

- Gap: **no gaps this turn.** `step-time`, `run-method` onto state nodes, `key`, `input tap`
  and reading `saveObject()` back were enough to drive a full lunge->attack transition and a
  net catch without waiting on emergent AI behaviour.

- Note on method: the decisive enemy assertion came from calling `enter()`/`exit()` on the
  state nodes directly rather than trying to get an enemy to walk into the player. Waiting
  for the AI produced six samples of `hp 10 | live_enemies 0..3` and proved nothing; driving
  the transition took one command and produced a number that could only mean one thing.
  When a bug is about a state transition, drive the transition.

- Note: ledger row is `partial` — the PlayerAttack and PlayerGather current-state guards are
  covered by reasoning and by the suite, but I did not stage a sword-swing-interrupted-by-
  gather-release in a live session, which is the case gather-kkz is actually about.

## 2026-08-03 — gather-dvw: workers idling with trees in the world (slot 3)

- Value: **warranted** — the report was "there are trees nearby and he should be heading for
  them", and the whole question was whether the worker was broken or correctly seeing
  nothing. Only the running game can answer that, and the answer inverted the fix.
  - Expected: a logic bug in the errand — a stale `_target_cell`, or a path that never
    plans. I went in looking for a defect in `_look_for_work`.
  - Got: `run-method --method _find_tree_cell` on both bone workers returned **`{}`** — the
    scan was correct and the world was empty *within the window*. `tilemap-cells --layer 1`
    then put numbers on it: the two bone workers' nearest trees were 19.4 and 20.6 cells from
    their home tiles, and the loaded stone worker's nearest stone 13.5, against
    `SEARCH_CELLS = 10`. A 24-sample `step-time` trace showed the actual failure mode —
    `IDLE tgt=(-20,-14) path=0` repeating with `_target_cell` frozen on a tree it had
    already felled, wandering between the same six cells for four minutes of game time.
    After the fix, on a clean load of the same save: `_find_tree_cells(6)` on the bone worker
    returns `['(-7, -5)', '(-4, -7)', '(-7, -2)', '(-3, -5)')]` where the old call returned
    `{}`; forcing `_state = 5` (WANDER) and firing one `_on_work_timeout` gives `_state: 1`
    with a 17-waypoint path, where the old routing left it at 5; and both loaded workers run
    `CHOP -> TO_CHEST c=1 -> TO_TREE -> CHOP -> TO_CHEST c=2` continuously over 60
    game-seconds with no IDLE-holding-a-path frames.

- The radius landed at 24, not 20, and runtime is the only reason. At 20 the two bone
  workers — two cells apart — split, one working and one starving, because their nearest
  trees measure 19.4 and 20.6 cells. A boundary that fine reads as a broken worker rather
  than as a range limit, and no amount of reasoning about the constant would have surfaced
  it; it took `run-method --method _find_tree_cells` on each worker in turn.
  - Cheaper: nothing static. The diff-level reading of `_look_for_work` looks correct,
    *because it is* — the bug was a constant being smaller than the world it was deployed
    into, which is only visible with a real save loaded. Parsing the save file got me close
    (it gave the 12.5-cell figure) but could not distinguish "worker is starving" from
    "worker is stuck", and trees respawn, so the file is stale the moment it is read.

- Method note worth keeping: `place_worker` defaults to `require_tree: true` and put a fresh
  worker beside a tree, which let me watch a *working* worker clear its window and then fall
  into the reported state. Reproducing the transition into the bug was far more informative
  than inspecting the bug at rest — the frozen `_target_cell` is what told me the worker had
  once had work and had run out, rather than never having found any.

- Gap: **`worker_state` indices are not stable across calls, and the trace silently lies.**
  `devtools_ext/commands.gd:1896` sorts `_bone_machines()` by live `position`, so as workers
  walk they swap places in the array. A per-index trace across `step-time` steps therefore
  attributes one worker's state to another: my first 24-sample run showed `W0` with
  `tgt=(-17,-11)` and then `tgt=(0,0)` two samples later, which is impossible for one node
  (`_target_cell` is never reset). I lost a trace to it before spotting it. The sort's own
  docstring promises stability ("in a stable order so `--args '{\"station\": 1}'` means the
  same thing across calls") — true for stations, which do not move, false for workers.
  - [G-101] status: open | seen: 1 | harness: 0.8.0
  - Improvement: sort walkers by an identity that does not move — `_home_position` when
    anchored, else the placed cell — or have `_worker_report` carry a stable `id` field
    (`get_instance_id()`) so a caller can key on something other than array position. The
    workaround was re-keying every sample on `_home_position` client-side.

## 2026-08-03 — gather-dvw follow-up: workers clipping the corners of walls

- Value: **warranted** — the report was "workers move through walls, or the collision box is
  too small", and both readings are wrong in a way that matters: these walkers have no
  collision box at all (`bone_worker.tscn` is authored on `collision_layer = 0`), so nothing
  about collision could be the cause and tuning a shape would have fixed nothing.
  - Expected: if the reported wall-walking is corner-cutting, a path past a SINGLE solid cell
    will come back as a bare diagonal under `AT_LEAST_ONE_WALKABLE`, and switching to
    `ONLY_IF_NO_OBSTACLES` will lengthen it without breaking the doorway or sealed-wall cases.
  - Got: exactly that. `find_path((0,0) -> (1,1))` with only `(1,0)` solid returned a
    two-cell path — a bare diagonal whose segment runs through the corner of the wall cell,
    and the sprite is a full tile wide. `AT_LEAST_ONE_WALKABLE` permits it because the *other*
    shared neighbour `(0,1)` is open. After the change the same query rounds the corner, the
    pre-existing sealed-pair and doorway tests still pass, and 40 game-seconds of live worker
    errands around the walled house produced **zero** occupancy of any wall cell.
  - Cheaper: the unit test alone settled the mechanism in ~4s, and `TilePathFinder.for_cells`
    is the reason — no TileMap, no autoloads, no game. The running game was still needed for
    the louder hypothesis (that walls were not blocking at all, which would have been a far
    worse bug) and to confirm the fix on a real house with a real door.

- Method note: the runtime check flagged two apparent wall overlaps and both were false
  positives with different causes — one was the worker standing on **its own** tile (a worker
  *is* a layer-1 scene tile, so its own cell is in any blocking set by construction), the
  other a cell that held a stone node when the blocking set was snapshotted and was empty by
  the time the worker walked onto it, because the worker had mined it. A blocking set read
  once and compared against many later samples is stale by construction in a world with
  destructible tiles; re-read it per sample, or subtract what the walker has cleared.

- Gap: **reach cannot see a `RefCounted`, so a class that plainly ran reports as unreached.**
  `verify_ledger.py reach` returned `reached 1/4 ... NOT reached: world/tile_path_finder.gd`
  for the very file this run was about. `TilePathFinder` is held as a plain field on the
  worker (`_finder`) and deliberately never added to the tree — CLAUDE.md requires that of
  `RefCounted` helpers after `HealthManager` leaked one object per enemy — so neither
  `scene-tree` nor `scripts-seen` can observe it, and the ledger downgrades a run that
  exercised it for 40 game-seconds and produced 17-waypoint paths out of it.
  - [G-102] status: open | seen: 1 | harness: 0.8.0
  - Improvement: let a project declare non-Node scripts that a reached Node owns — e.g. a
    `reach_aliases` map in `devtools_config.json` (`world/tile_path_finder.gd` credited when
    `world/tile_scenes/bone_worker.gd` is reached) — or credit them the way autoloads are
    already credited as `implicit`. Without it, every `RefCounted` helper in the project is
    permanently unreachable by the metric, which trains readers to discount the number.

## 2026-08-03 — the door opens for workers too

- Value: **warranted** — the first fix I tried was wrong, and only the running game said so.
  - Expected: putting the worker on a collision layer the door masks will be enough for
    `body_entered` to fire; if it is not, the cause is `StaticBody2D` transform writes never
    re-entering the area broadphase.
  - Got: the layer alone was **not** enough. With the worker parked dead centre on the door
    tile, `run-method --method get_overlapping_bodies` on the door's Area2D returned
    `['Player:<CharacterBody2D#...>']` and no worker — while the same call with the player
    moved onto the tile flipped the door to `animation: Open, _occupants: 1`, so the rig was
    provably fine and the body was the problem. Godot does not re-check the broadphase for a
    static body moved by assigning `position`, which is exactly how this worker walks. As an
    `AnimatableBody2D` the same call returns
    `['TileMap:<TileMap#...>', 'BoneWorker:<AnimatableBody2D#...>']`.
  - Cheaper: nothing. The wrong hypothesis looked completely correct in the diff — layer set,
    mask set, shape present, `monitoring: true` — and reads as working code.

- The follow-on catch belongs to the unit suite, not the harness, and is worth the credit:
  `AnimatableBody2D` defaults `sync_to_physics = true`, which drives the node transform from
  the physics body and silently swallows `position = ...`. Nothing in-game looked wrong —
  workers still walked, still delivered, still opened the door — but
  `test_save_round_trips_through_json` went red with `Expected 112.000000 but got 0.000000`,
  because `save()` reports `_home()` and `_home()` is that position. A worker would have
  reloaded at the origin. `sync_to_physics = false` keeps detection and restores the writes.
  Runtime found the bug; the headless suite found the fix's own bug. Neither would have done
  on its own, which is the argument for running both rather than picking one.

- Gap: **no new gaps this turn.** `get_overlapping_bodies` via `run-method`, `wait-frames`
  and a `get-state` on the door's `_occupants` were enough to isolate a physics-detection
  failure to the body type in about four commands, and the `[G-101]` worker-index instability
  logged earlier did not bite again because every read here was keyed on a node path.

## 2026-08-03 — extensibility review of the whole repo (read-only)

- Value: **overkill** — nothing was changed, and both gates confirmed what a read already
  showed. Logged anyway, because a clean gate on a review turn is exactly the entry that
  goes unwritten.
  - Expected: lint and the unit suite would come back clean, since the working tree is a
    finished worker/door fix that /verify already covered last turn.
  - Got: `lint: 0 error(s), 0 warning(s) -> exit 0` and `Total: 392 | Passed: 392 |
    Failed: 0 | Skipped: 0`. stderr carried only the deliberate corrupt-payload fixtures
    (`Parse JSON failed`, `skipping an entry with no filepath`), which are the assertions of
    `test_save_load.gd` rather than errors. Neither run told me anything about the review's
    actual subject — the shape of the extension points.
  - Cheaper: reading the eight registry files (`items/`, `crafting/recipes.gd`,
    `systems/skill_tree.gd`, `enemies/enemy_spawner.gd`, `world/island_manager.gd`) and
    grepping `Types.Item.` by file, which is what produced every finding. ~2 minutes, no
    Godot. The suite run was worth its 40s only as a baseline to hand the user, not as
    evidence.

- Gap: **no gaps this turn.** A design review has no runtime claim to make, so the harness
  had nothing to be missing for. Worth stating plainly rather than leaving blank: the
  absence here is the task's, not the tooling's. One note for the record — `harness-version`
  requires a live game (`game not running: 'harness_version' was never picked up`), so a
  read-only turn cannot fill the `harness:` field from the tool; 0.8.0 is carried forward
  from the previous entry. That is a known property of the bus, not a new gap.

## 2026-08-03 — StateMachine gains an exit() hook (gather-rcm)

- Value: **warranted** — runtime produced a connection count no reading of the diff could.
  - Expected: leaving PlayerAttack by any route other than its own animation_finished will
    now leave Player/Attack.monitoring false and drop the state's animation_finished
    connection — the old code disarmed only inside the handler, so an interrupted swing
    stayed armed and connected.
  - Got: exactly that, read off the live player. Holding the swing open with
    `set-game-speed 0.02`, `get_signal_connection_list("animation_finished")` on
    `/root/Main/World/Player/AnimationPlayer` returned
    `[{'callable': 'Node(player_attack.gd)::animation_finished', ...}]` with
    `monitoring: true`; one `change_to PlayerGather` later the same two reads were `Result: []`
    and `monitoring: false`. The net case is the stronger one, because its `monitoring` write
    is deferred: after `change_to PlayerIdle` + `wait-frames 3`, `Net.monitoring` was false,
    `visible` false and `body_entered` connections `[]` — the free-second-catch window from
    gather-uem, closed at the source rather than guarded around.
  - Cheaper: nothing. The claim is about signal connections on a node the states do not own,
    accumulated across transitions; the unit suite can assert that `exit()` is *called* (and
    now does, in test_state_machine.gd) but cannot see the player's shared AnimationPlayer.

- The headless half earned its place separately, and by failing: `run_tests.gd` reported
  `Total: 392 | Passed: 392 | Failed: 0` **and** printed
  `SCRIPT ERROR: Invalid assignment of property or key 'state' with value of type 'Node' on a
  base object of type 'Node (StateMachine)'` to stderr. Typing `StateMachine.state` as
  `PlayerState` broke `test_player_net.gd:150`, which assigned a bare `Node`, and the suite
  stayed green because a runtime error inside a `-> String` test still returns `""`. This is
  gather-1t9 exactly as documented, hit for real — the green count would have shipped it.

- Gap: **reach cannot see a base class that owns no node of its own** — the same shape as
  [G-102], so bumping that rather than filing a new one. `verify_ledger.py reach` reported
  `worktree: reached 5/8 ... NOT reached: player/states/player_state.gd`, while all four
  states that extend it were loaded and driven. A `scene-tree` node reports only its leaf
  `script` path, so a `class_name` base is structurally invisible to the metric even when
  every one of its subclasses ran.
  - [G-102] status: open | seen: 2 | harness: 0.8.0
  - Improvement: unchanged from the original entry — credit a script when a reached node's
    script inherits from it, or let `devtools_config.json` declare `reach_aliases`. The
    inheritance case is the cheaper half: the harness already has the script path of every
    reached node, and `GDScript.get_base_script()` walks the chain without any project config.

## 2026-08-03 — Recipes becomes station-keyed (gather-uaq)

- Value: **warranted** — the running game produced a defect the suite structurally could not.
  - Expected: the station-keyed rewrite preserves the by-reference binding a placed station
    holds, and a pre-change save still restores its unlocks.
  - Got: both, and then a third thing nobody was looking for. `run-method --node /root/Recipes
    --method get_recipes --args "[7]"` returned `Result: []` while the sawmill on screen was
    holding `['Plank', 'Stone Pickaxe', 'Chest']`. The bus marshals arguments as JSON, JSON has
    one number type, and Godot compares Dictionary keys by TYPE as well as value — so `7.0`
    missed `7` and `get_recipes` did not merely fail to find the list, it created a second
    empty one beside it and returned that. Every station id in a save file is a float. The
    game only ever passes `Types.Item` ints, so no unit test could reach it; after `_key()`
    normalisation the same call returns three recipes.
  - Cheaper: nothing for that one. The rest — the legacy-payload migration, the by-reference
    binding, the empty-station accessor — the suite could cover and now does, including a test
    that reads the two committed fixtures off disk rather than reconstructing a payload.

- The fixture test was mutation-checked before being trusted: deleting the legacy-key branch
  of `loadObject` turned it red (`Total: 400 | Passed: 0 | Failed: 1`), so it is asserting the
  migration rather than passing alongside it. Worth the extra minute — a save-compat test that
  cannot fail is the most expensive kind of green.

- Gap: **no new gaps this turn.** The float-key surprise is Godot semantics meeting JSON, not a
  missing harness capability — and it is arguably the harness working exactly as intended, since
  marshalling through JSON is what exposed a hazard the save format shares. `place_station`,
  `learn_skill`, `add_xp` and `craft_state` composed into an end-to-end unlock/save/load check
  without a single workaround, and copying a fixture into `user://saves/slot_2.save` and calling
  `load_from_slot` was enough to exercise a v3 file in a live world.

## 2026-08-03 — GameItem super(), the turret's save bugs, source-aware resource keying

- Value: **warranted** — runtime confirmed a save-fidelity fix that only a real scene tile
  re-instanced by a load can exercise, and cleared the riskiest half of the main.gd change.
  - Expected: source-aware resource keying leaves the gather path and census working on a
    cross-source resource, and a turret with no bullets in flight now survives a save/load
    assembled.
  - Got: both. `gather_stats` reported `census: {Coal: 1, Copper: 3, Stone: 13, Tree: 11}` —
    Copper is registered on tileset source 10, i.e. the case the old coordinate-only match
    would have collided on — and after `goto_resource Copper` + a held gather, `target: Copper`
    then `Copper: 2`. The turret is the better catch: `run-method save` returned
    `{'data': {}, 'filepath': '343', 'loaded': True, ...}` — no bullets in flight and the
    assembly flag still present, where the old payload carried `loaded` ONLY inside the
    per-bullet dictionaries and so wrote nothing at all. After a live `_save`/`_load` the
    re-instanced turret read `loaded: true` with `LoadedSprite.visible true` and
    `UnloadedSprite.visible false`.
  - Cheaper: nothing for that round trip — a turret is a TileMap scene tile, so the load path
    destroys and re-instances the node, and the assembly flag has to survive a node that is
    not the one that saved it. The bullet-restore and payload-shape halves did not need the
    game and are now headless tests.

- Both new test groups were mutation-checked before being trusted: removing the top-level
  `loaded` and the position/rotation restore turned `test_save_fidelity.gd` red on exactly
  two tests (`Total: 404 | Passed: 13 | Failed: 2`), and deleting the recipes legacy branch
  turned the fixture test red earlier. A save-compat test that cannot fail is the most
  expensive kind of green, and these two are cheap to make honest.

- Gap: **reach still cannot see a RefCounted script**, now hit a third time — same shape as
  [G-102], bumping rather than filing again. The run reported
  `NOT reached: items/game_item_pickaxe.gd, items/game_item_sword.gd` while a wooden pickaxe
  had just been held down through a complete gather, which runs `GameItemPickaxe.use()` and
  reads its `power`. Every `GameItem` subclass is RefCounted and owned by an inventory slot,
  so none of them will ever appear in a `scene-tree` snapshot or in `scripts-seen` — and the
  item registry is precisely where this project's content lives, so the metric will keep
  under-reporting exactly the files a content change touches.
  - [G-102] status: open | seen: 5 | harness: 0.8.0
  - Improvement: as before — credit a script when a reached node's script inherits from it,
    and additionally allow `devtools_config.json` to name directories whose scripts are
    known-RefCounted (`items/`, here) so they are reported as `implicit` rather than as
    misses. The inheritance half is free; the RefCounted half needs the project to say so.

## 2026-08-03 — one enemy registry, and loot tables (gather-33f)

- Value: **warranted** — the reconstruction path can only be exercised by a real save written
  by a live spawner, and that is where the bug this replaces used to live.
  - Expected: routing the three hand-matched type strings through one registry leaves ambient
    spawning and reconstruction working, and a non-empty loot table actually pays out on death.
  - Got: all of it. Sixty game-seconds of ambient spawning produced
    `{'res://enemies/bone_enemy.tscn': 3}` and never an elite, which is the flag doing its job
    — the old `enemies` array happened to hold the right two, but nothing said so. A Bone kill
    gave exactly 2 pickups (its `drop` plus the base coin, empty table — the regression check).
    Retyping a live enemy to Elite and killing it gave 12, inside the 7-14 the elite table can
    produce. And the one that matters: an Elite-typed enemy whose SCENE was still
    `bone_enemy.tscn` was saved and reloaded, and came back as
    `{'elite_enemy.tscn': 1, 'bone_enemy.tscn': 1, 'spider_enemy.tscn': 1}` — reconstructed
    from the registry rather than silently demoted, which is the exact failure the old
    `match`'s `_:` arm caused.
  - Cheaper: `set-state --property type --value Elite` on a live enemy is the trick that made
    this cheap — it drove the boss's loot table and the elite reconstruction path without
    needing the boss island, which is 34 tiles of bought land away. The loot arithmetic itself
    is pure and takes its samples as an argument, so all of that is covered headless.

- Gap: **reach under-reports RefCounted scripts**, hit again and now the dominant reason this
  project's reach numbers look bad. `NOT reached: enemies/enemy_registry.gd,
  items/game_resource.gd` — while the run had just proved the registry works by watching it
  reconstruct an elite and pay out a loot table. `EnemyRegistry` is a static RefCounted class
  and `GameResource` is a RefCounted item, so neither will ever own a node a snapshot can see.
  Between this, the `GameItem` subclasses and `PlayerState`, the metric now misses most of
  what a content change touches in this codebase.
  - [G-102] status: open | seen: 5 | harness: 0.8.0
  - Improvement: as logged — credit a script when a reached node's script inherits from it
    (free; the harness already has every reached node's script path and
    `GDScript.get_base_script()` walks the chain), plus a `devtools_config.json` list of
    directories whose scripts are known-RefCounted so they report as `implicit` rather than as
    misses. Four sightings in one session is the argument for doing the inheritance half now.

## 2026-08-03 — chunk payloads carry the kind of node that wrote them (gather-34n)

- Value: **warranted** — the risk in this change is the opposite of the bug it fixes, and only
  a world containing all four chunk types can show it.
  - Expected: adding a kind tag narrows chunk matching without breaking any real restoration —
    every chunk type in the demo world still comes back with its state.
  - Got: `build_demo_world` then a `_save`/`_load` left 2 CraftingStations, 3 TestChests,
    4 BoneTurrets and 4 BoneWorkers in the tree, and the chest that matters read back
    `{'data': [{'count': 40, 'type': 31}, {'count': 8, 'type': 36}, {'count': 12, 'type': 10}],
    'kind': 'TestChest', ...}` — contents intact and the tag present in what save() writes.
    A tag that over-refused would have emptied exactly that chest and reported nothing, which
    is the same silent shape as the bug it guards against.
  - Cheaper: the matcher itself is pure and is covered headless, including the backward-compat
    case that an untagged payload still applies to anything. What needed the running game was
    that the tag does not accidentally refuse a LEGITIMATE payload, and that is only visible
    against a world with every chunk type in it — which `build_demo_world` builds in one verb.

- Mutation-checked: replacing the kind comparison with `return true` turns
  `test_a_payload_is_refused_by_a_different_kind_of_node` red on its own
  (`Total: 415 | Passed: 10 | Failed: 1`), so the guard is asserted rather than assumed.

- Gap: **no new gaps this turn.** `build_demo_world` is the verb that made this cheap — one
  call for a world containing every persistent node type, which is precisely the fixture a
  save-format change wants and precisely the thing that is tedious to assemble by hand. Worth
  recording as a case where a project-registered verb did the work a generic primitive could
  not. [G-102] was not re-hit here: every file in this change owns a node.

## 2026-08-03 — boss state becomes per-island (gather-302)

- Value: **warranted**, but the run is recorded **partial** and the reason matters more than
  the verdict.
  - Expected: making boss state per-island keeps the persisted flag working, with a pre-keyed
    save still reading as defeated.
  - Got: the half I could reach, cleanly. `set-state --property boss_defeated --value true`
    on the live IslandManager produced `bosses_defeated: {"boss": true}`, so the compatibility
    property writes through rather than shadowing. Saving, clearing `bosses_defeated` to `{}`
    in memory (`boss_defeated: false`), then `_load` brought back `{"boss": true}` — and the
    file on disk carries both `bosses_defeated: {'boss': True}` and the legacy scalar
    `boss_defeated: True` for a rolled-back build. `island_census` still reads
    `{"alive": false, "chest": [], "defeated": true}` through the compat property.
  - Cheaper: the migration itself and the negative cases are pure and are covered headless,
    mutation-checked by deleting the scalar-promotion branch. What genuinely needed the game
    was the property setter/getter — a `var x: bool: get/set` that silently shadowed a field
    would look identical in the diff.

- **The blocked check, stated plainly:** I never saw a boss spawn, fight or die. That path is
  gated on `_connected_state(BOSS_ID)`, which needs the home coastline bought out to ~36
  tiles, and I could not get there (see the gap below). So `_populate_boss`, `_spawn_boss` and
  the `.bind(island_id)` on the death signal are covered by reading and by the unit tests
  only. The ledger downgraded the row to `partial` on the strength of that one `blocked`
  entry, which is exactly what it is for.

- Gap: **a project verb can kill the game, and the bus cannot tell you it was the verb.**
  `cmd give_item --args '{"name":"Gold Coin","count":9000}'` — intended to fund the land
  purchases that open the boss island — took the process down. The next call reported
  `game not running: 'buy_land' was never picked up`, and `logs --tail` ended on
  `[15:53:13] [command] Executing: give_item` with no error line after it, so the log shows
  what was running when it died but nothing about why. Worse, the relaunch then failed its
  precheck against a STALE `devtools_owner.json` (`says pid 7080 ... has likely exited`) while
  a fresh instance was in fact up, and `tasklist` showed two live Godot processes — the
  crashed one had not fully exited, which is the multi-instance cross-talk hazard arriving by
  accident rather than by choice. Recovery was `taskkill //F`, delete the owner and
  command/result files, relaunch.
  - [G-103] status: open | seen: 1 | harness: 0.8.0
  - Improvement: two small things. (1) Have the bus write a `last_command` breadcrumb that
    survives the process, so "the game died during verb X" is readable rather than inferred
    from the last log line. (2) Make the ping precheck notice that the owner pid is dead AND
    a bus file is being consumed, and clear the stale owner itself instead of refusing — a
    stale owner file after a crash is the normal case, not an anomaly, and right now it makes
    the recovery path look like a second failure.

## 2026-08-03 — give_item batches, and that unblocks the boss (gather-639, closing gather-302's blocked check)

- Value: **warranted** — it retired a `blocked` check from the previous run, which is the one
  kind of follow-up the ledger can prove was needed.
  - Expected: batching give_item stops it killing the game, and that unblocks the boss
    spawn/death path left unverified in gather-302.
  - Got: the exact call that killed the process — `give_item {"count": 9000}` — returned
    `added 9000 of 9000 Gold Coin` instantly with the game still answering `ping`. Then the
    whole path that had been unreachable: `buy_land {"count": 40}` bought 12 parcels, took the
    radius `10 -> 34` and reported `opened ["boss", "ore", "forest"]`; `island_census` showed
    the elite `alive: true, hp: 90, damage: 6, scale: 1.7` with its chest holding
    `["Gold Coin x40", "Gold Ore x8", "Iron Ore x12"]` — filled from `BOSSES[id]["reward"]`,
    i.e. the per-island table rather than the old constant. Killing it moved
    `bosses_defeated` from `{}` to `{"boss": true}`, which is the `.bind(island_id)` on the
    death signal doing its job, and a save/load left it `alive: False, defeated: True`.
  - Cheaper: nothing. The previous run recorded these same checks as **blocked** precisely
    because no headless test can stand up a connected arena, a live elite and a death signal.
    Worth noting what the fix cost: the loop was walking the inventory and emitting
    `inventory_updated` once per item, so the UI relaid itself 9000 times. One SlotData
    carrying the count is equivalent — stacks here are unbounded — and the verb went from
    fatal to instant.

- **A note on the ledger, since it now reads oddly:** the gather-302 row stays `partial`
  forever, and it should. This run is a separate row that covers what that one could not.
  Rewriting history to make an old row green would defeat the point of keeping one.

- Gap: **no new gaps this turn**, and one to downgrade. [G-103] was filed last turn against a
  verb killing the game; the verb was the bug, not the harness, and the harness's behaviour
  (a `game not running` on the next call) was correct. What remains genuinely harness-side is
  only the second half of that entry — the stale `devtools_owner.json` making the recovery
  relaunch look like a second failure — so the gap is narrowed to that rather than closed.
  - [G-103] status: open | seen: 1 | harness: 0.8.0
  - Improvement: narrowed. Drop the "breadcrumb for which verb was running" half — `logs
    --tail` already ended on `Executing: give_item`, which was enough to identify it. Keep
    only: when the owner pid is dead, `ping` should clear the stale owner file and proceed
    rather than reporting it as an error, because a stale owner after a crash is the normal
    case and right now it masks a perfectly healthy relaunch.

## 2026-08-03 — retire the no-op AttackTimer handler (gather-1sb)

- Value: **warranted** — deleting a method that two scene files connect to is exactly the
  change where lint's "it parses" and the game's "it works" come apart.
  - Expected: removing a no-op handler and its two authored connections leaves enemies
    attacking exactly as before; a missed connection would show as a missing-method error on
    every AttackTimer tick.
  - Got: enemies still attack. Walking a spider back into range took it through
    `EnemyFollow -> EnemyAttack` and the player went `10 -> 0` hp. No missing-method error,
    and reach was 3/3 — both scenes and enemy.gd were loaded.
  - Cheaper: lint proves the scenes still parse but cannot prove an enemy still attacks; the
    damage lands through `attack_range.body_entered -> Transitioned -> EnemyAttack._on_attack`,
    a signal chain no headless test in this project stands up.

- **The run's own false alarm is the useful part.** My first attempt teleported the enemy on
  top of the player and it sat in `EnemyFollow` at 8px for 15 game-seconds doing nothing,
  which read exactly like "the change broke attacking". It was the test, not the code:
  `EnemyFollow` transitions only on `attack_range.body_entered`, and a body that is ALREADY
  overlapping when the handler connects never generates an entry event. Moving the enemy away
  and letting it walk back in worked first time. Worth writing down because `set-state` on a
  position is the obvious way to stage a fight and it silently produces a false negative for
  anything driven by area entry — filed as gather-83d for the game-side edge case.

- Gap: **no new gaps this turn.** `step-time` in 4-second slices with a `current_state` read
  between them is a good shape for watching a state machine progress, and it needed nothing
  the harness did not already have.

## 2026-08-03 — EnemyFollow checks the bodies already in the area (gather-83d)

- Value: **warranted** — the defect is entirely about which physics events the engine does and
  does not generate, and the fix was confirmed by making the bug happen first.
  - Expected: checking get_overlapping_bodies in enter() makes an enemy attack a player who is
    already inside the area, where body_entered can never fire.
  - Got: the reproduction is the good part. With the enemy teleported onto the player,
    `run-method --node .../AttackRange --method get_overlapping_bodies` returned
    `['Player:<CharacterBody2D#...>', 'SpiderEnemy:<CharacterBody2D#...>']` — the player
    demonstrably inside the area — while `current_state` sat at `EnemyFollow` across three
    4-second steps. Calling `enter()` on the follow state then moved the machine to
    `EnemyAttack` immediately and the player went `10 -> 7`. The natural walk-in chain still
    goes `Idle -> Follow -> Attack` and still kills.
  - Cheaper: nothing. "Is the player in the area" and "did the engine send an entry event" are
    different questions, and only a running physics server answers the second one.

- Worth noting for the next person staging a fight: `set-state` on an enemy's `position` does
  NOT generate `body_entered` for its own areas — the same broadphase behaviour that made the
  bone worker invisible to the door until it became an AnimatableBody2D. That is what turned a
  teleport into a false negative last turn; this turn it is what made the bug reproducible on
  demand. Teleporting is a fine way to CREATE an overlap and a useless way to trigger one.

- Gap: **no new gaps this turn.** `get_overlapping_bodies` over `run-method` is the read that
  made this diagnosable in one call — it separated "the geometry is wrong" from "the event
  never came", which is the whole question.

## 2026-08-03 — comment the two latent physics-callback add_child paths (gather-im1)

- Value: **overkill** — and correctly so: this is a comments-only diff, which /verify's own
  triage puts in tier (b), lint-only. No runtime run, no ledger row.
  - Expected: nothing. The change adds no behaviour; there is no runtime claim to make.
  - Got: `lint: 0 error(s), 0 warning(s)` and the suite unchanged at 419. Exactly what a
    24-line comment addition should produce.
  - Cheaper: this WAS the cheaper thing — lint alone, ~15s, no game launched. Recording it
    because the log's honest ratio matters more than its highlights, and a stretch of entries
    with no `overkill` in it should make a reader suspicious of the log rather than impressed
    by the tool.

- Gap: **no gaps this turn.** Nothing was asked of the harness beyond a parse check.

## 2026-08-03 — crafting content phase 2 (gather-cte)

- Value: **warranted** — and this run is the one that tested the morning's refactors rather
  than the content.
  - Expected: six new items, three recipes' worth of unlocks and a new enum tail all work
    without touching anything structural — the registries take content as data now.
  - Got: exactly that, and the shape of the diff is the evidence. Each recipe is one
    `_register` call; each unlock is one line appended to a skill's `recipes` array; no new
    skill node, no new accessor, no format change. At runtime the sword ladder read
    `Sword 4 -> Bone 6 -> Iron 9 -> Gold 13` straight off `player.damage` as each was
    equipped; the sawmill showed `['Plank', 'Stone Pickaxe', 'Chest', 'Bone Sword', 'Bandage']`
    after two Combat skills; the furnace showed all five of its recipes with `GoldSword` still
    `False` as a negative control; and a Stone Brick crafted end to end and turned up in the
    save as `{"count": 1, "type": 50}`, surviving a load and re-save.
  - Cheaper: the ladder monotonicity, the "each sword costs its own bar" rule and the "a sword
    never outprices the pickaxe of its tier" balance rule are pure and are covered headless —
    mutation-checked by dropping the iron sword to 5 power, which fails with
    `Iron Sword (5) does not hit harder than Bone Sword (6)`. Runtime was needed for the equip
    path, the unlock tiers on a live station, and that an appended enum value survives a real
    save.

- **Two of today's fixes paid off directly here.** The placeholder sheet's rows 0-2 were
  reserved with a comment saying they could not be used because main.gd matched resources by
  atlas coordinate alone; that was fixed this morning (gather-54s), so row 1 is now usable and
  this content went there instead of growing the sheet. And `GameItemSword` calling `super()`
  (gather-q6t) is what makes three new sword tiers a three-line edit rather than three copies
  of eight field assignments.

- One self-inflicted detour worth recording: `queue_craft` refused, and the cause was
  `give_item` reporting `added 0 of 4 Coal Ore` — the bag was full of the six items I had just
  handed myself to check registration. Not a content bug and not a harness bug; the honest
  read is that a test which hands the player everything cannot then test crafting, and the fix
  was to relaunch and give exactly the two stacks the recipe needed.

- Gap: **[G-102] again, seen 5.** `NOT reached: items/types.gd, systems/skill_tree.gd` — the
  first is a bare `class_name` holding an enum, the second is the RefCounted SkillTree that
  `learn_skill` had just been driving through three purchases. Both are content registries,
  which is precisely the category this project adds to most often, so the metric is at its
  least informative exactly where the work is. `tools/generate_placeholder_art.gd` is also
  listed and should not be: it is a build-time generator the game never loads by design.
  - [G-102] status: open | seen: 6 | harness: 0.8.0
  - Improvement: unchanged and now overdue — credit a script when a reached node's script
    inherits from it, and let `devtools_config.json` name known-RefCounted directories.
    Additionally: a `reach_exclude` glob for build-time tooling, so `tools/` stops counting
    against a diff it can never be part of.

## 2026-08-03 — read-only tech-debt review of the repo (no code changed)

- Value: **inconclusive** — the harness was not run; this was a static read of the tree
  (line counts, comment density, naming greps, `bd stats`), and none of it needed a
  running game.
  - Expected: nothing predicted at runtime — the question was about shape of the code,
    not behaviour.
  - Got: n/a. The measurements that mattered came from `wc -l`, `grep -c "^\s*#"` and
    `bd stats` (11 open / 180 closed).
  - Cheaper: this *was* the cheap path. Running `/verify` on a zero-line diff would have
    produced a clean row that said nothing about the question asked.

- Gap: **no gaps this turn** — nothing was attempted that the harness failed to cover,
  because nothing runtime was attempted. Worth noting for later, though: there is no
  harness verb that answers "how much of this file is comment vs code", and comment
  density turned out to be the single largest finding of the review. Not filing an id
  for it — a lint metric, not a devtools-bridge gap.

## 2026-08-03 — gather-zxl was already fixed; measuring said so and found the real one

- Value: **warranted** — the run's product was a decision NOT to change anything, which is
  the outcome a stale bug report most needs and the one reading code alone would not have
  settled.
  - Expected: the bead claims the hotbar sits at a fixed `offset_left=686` and falls off a
    ~390px phone viewport, and proposes switching `window/stretch/mode` to `canvas_items` —
    which contradicts the documented window-size decision in CLAUDE.md. Check whether the
    premise still holds before touching a global render setting.
  - Got: it does not hold. `main.tscn` has no offset override on HotBarInventory at all; the
    scene anchors bottom-centre and `_apply_layout()` re-solves on `size_changed`. Measured
    rather than inferred: at 390x844 `node-bounds` gives the hotbar `8, 778, 375x58` — right
    edge 383 of 390, bottom 836 of 844, fully inside. Landscape 844x390 gives
    `214, 324, 415x58`, also inside. The camera HUD reports `49x106` in WORLD units, which at
    the camera's zoom 8 is 392x848 — i.e. sized to the viewport, exactly as camera_hud.gd
    claims. At 320x640 the row does overhang (`-28, 574, 375x58`), and that is the behaviour
    hot_bar_inventory.gd:75 documents as the deliberate last resort below ~340px rather than
    shrink slots under a thumb-sized target.
  - Cheaper: nothing, and reading alone would have been actively misleading here — the bead
    named a property that no longer exists, so a code-only check could have concluded "fixed"
    without knowing whether the replacement actually holds at 390px. `set-resolution` plus
    three `node-bounds` reads settled it in under a minute and produced numbers to close the
    bead with.

- **The screenshot earned its place**, which is unusual — this project's guidance is to prefer
  `node-bounds` over pixels, and that was right for the hotbar. But it is what showed the
  thing nobody had reported: the diegetic HP/XP bars run underneath the BAG/SKILLS/LAND
  toolbar at 390px. Every element was individually "on screen" and no bounds read would ever
  have said they collide, because one is world-space under Camera2D and the other is
  screen-space in the UI layer — there is no common rect to compare. Filed separately rather
  than folded into gather-zxl, which was about clipping and is genuinely fixed.

- Gap: **no new gaps this turn.** `set-resolution` reporting the honest read-back
  (`Resized (1920, 1080) -> (390, 844)`, `visible rect: 390.0x844.0`) is what made the
  measurements trustworthy; a silent clamp would have made this whole investigation wrong.

## 2026-08-03 — collapse the UI scaling round trip onto a factor currency (gather-snn)

- Value: **warranted** — the A/B against the stashed baseline is a claim no diff could make,
  and the guard I added to `connect_resize` was live code on a path no test reaches.
  - Expected: the panels render at the same pixel sizes as before the refactor, and a resize
    re-derives them exactly once per panel — the connect_resize guard is new code on a path
    unit tests don't reach.
  - Got: pixel-identical, verified by stashing the diff and re-measuring the same nodes on
    unmodified code. Every `PanelFrame` close button `51x51` at 1920x1080 and `48x48` at
    390x844 on **both** trees; `HotBarInventory` `Rect: 631, 965, 658x100` and the skill card
    `Rect: 297, 312, 318x111` identical to the byte on both. The load-bearing one is the
    resize round trip 51 → 48 → 51 across all five panels: `UiTheme.connect_resize()` adds an
    `is_inside_tree()` check the six inline copies never had, so a panel that connected before
    entering the tree would have silently stopped resizing — invisible to lint, to 426 unit
    tests, and to anyone not dragging a window. Also confirmed `solve_metrics` still budgets
    off the real width (`375 = 0.96 x 390`), which is the one place I deliberately kept the
    viewport rather than the factor.
  - Cheaper: nothing for the resize-connection check — it needs a live window changing size.
    The pixel A/B could have been one panel instead of five; four of them told me nothing the
    first did not.

- Two defects, both caught before runtime, worth recording because of *which* gate caught them:
  - The GDScript type checker caught `apply_scale(Vector2.ZERO)` in `recipe_card.gd:94` —
    `Cannot pass a value of type "Vector2" as "float"`. Changing the parameter type is what
    made 95 call sites self-checking; a `Vector2`-shaped helper that silently accepted a
    factor would have shipped.
  - The unit suite caught my own `apply_typography` casting a freed object before testing it
    (`SCRIPT ERROR: Trying to cast a freed object. at: apply_typography (ui_theme.gd:183)`)
    — **while reporting `[PASS]`**. That is `gather-1t9` exactly: the error aborted the method,
    the `-> String` signature still yielded `""`, and stderr was the only signal. A green
    suite genuinely is not sufficient.

- Pre-existing, verified as such rather than assumed (both reproduced on the stashed tree):
  `validate-ui` reports 4x `ui_zero_size: Control 'Tail' ... (318x0)` whenever the skill panel
  is open, and `crafting_panel --args '{"open": true}'` reports `open: true` then reads back
  `open: false` two seconds later. Neither is mine; both cost a stash-and-relaunch to prove.

- Gap: **[G-025] again, seen 2 — and its `fixed-in: 0.8.0` does not hold for paths without a
  `/root` prefix.** `scene-tree` prints node paths as `/Main/UI/SkillTreeUI/...`, so that is
  what you copy into `--node`; git-bash then mangles it and the echo is still raw:
  ```
  Failed: Node not found: C:/Program Files/Git/Main/UI/SkillTreeUI/PanelFrame/.../CloseButton
  ```
  `MSYS_NO_PATHCONV=1` fixes the mangling but the path then genuinely needs `/root` prepended,
  so the same error text covers two unrelated causes and you fix them one at a time.
  - [G-025] status: open | seen: 2 | harness: 0.8.0
  - Improvement: normalize a leading `C:/.../Git` off *any* absolute node path, not only one
    continuing with `/root`, and resolve a path starting `/<RootSceneName>` by prepending
    `/root` — that is the form the tool's own `scene-tree` output hands you.

- Gap: **[G-102] again, seen 6.** `NOT reached: ui/ui_theme.gd` — the file the whole change is
  *about*. It is a `class_name` RefCounted of nothing but `static func`s, called by all twelve
  reached files, and it owns no node for a snapshot to see. The metric reads "unreached" for
  the single most-exercised file in the diff.
  - [G-102] status: open | seen: 6 | harness: 0.8.0
  - Improvement: unchanged and now overdue — credit a script when a reached script references
    its `class_name`, which for a static-only utility is the only evidence that can exist.

## 2026-08-03 — diagnosed the bare demo world (gather-3m9), no code changes

- Value: **warranted** — the diff was clean at HEAD and the bug is invisible in source; only a
  running game separated "islands broken" from "the devtools verb that builds the demo world
  never fires `land_purchased`".
  - Expected: some regression in `IslandManager._stock` / `refresh_connections`, since the
    report named the islands and the last commits touched world code.
  - Got: the opposite. A fresh world stocks correctly (`home land=96 nodes=28`, then after 12
    real `buy_land` parcels `home 274/315`, `forest 21`, `ore 21`, boss + chest placed). Then
    `build_demo_world` on a fresh world: `home land=1312 nodes=28 cap=328 | forest/ore/boss
    opened=false, 0 nodes` — the mainland grows 13x and the node count does not move. One
    save/load later: `forest 32, ore 30, boss chest present, home still 34/413`, which is
    exactly the shape of the two committed fixtures.
  - Cheaper: nothing. Reading `_max_out_land` alone shows it writing the same three fields
    `loadObject` writes, which is what its comment argues and which *looks* right; the census
    is what makes the missing signal a number.

- Gap: **`island_census` reports `opened`, but nothing reports what last called
  `refresh_connections` or `seed_island`.** The census told me *that* home was starved and the
  islands closed at radius 34, which is already the useful half. Attributing it still meant
  grepping every writer of `parcels_bought`/`_expand` by hand to find the one path that skips
  the signal. A verb-level "who stocked this region, and when" — even just a frame counter and
  the caller — would have gone from symptom to `_max_out_land` in one call.
  - [G-104] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `LandRegion` record `stocked_at_frame` and `opened_at_frame`, and surface
    both in `island_census`. A region that is open with `stocked_at_frame == -1` is this bug,
    stated rather than inferred.

- Gap: **[G-057]-family again — the shared bus cost a user their running game.** Three Godot
  instances were live (editor, the user's game, mine). `python tools/devtools.py quit` has no
  target: it went to the foreign instance and closed the window the user was looking at, and
  the owner-file check only reported the crossed reply *afterwards*:
  ```
  Foreign instance on the bus: the reply to 'screenshot' came from pid 21108, but
  devtools_owner.json says pid 17916 owns this bus.
  ```
  Detection is there for reads; `quit` is the one verb where detect-after-the-fact is not
  recoverable.
  - [G-057] status: open | seen: 2 | harness: 0.8.0
  - Improvement: make `quit` refuse when the owner file names a pid other than the one that
    answers, and give it a `--pid` it verifies against the reply. A destructive verb should
    check ownership *before* it acts, not report the mismatch in the response.

## 2026-08-03 — planned a rain + day/night system (no code changed)

- Value: **inconclusive** — planning only; the harness was never run, so it neither helped
  nor failed. Logged so the absence is deliberate rather than forgotten.
  - Expected: nothing from runtime. Every question this turn was answerable from the scene
    file and the scripts — which canvas each node sits in, what `Ocean` is, whether a
    `rain()` already existed.
  - Got: the three load-bearing facts came from `main.tscn:395/624` and `main.gd:191/971`
    by reading, not by running: `World` is a bare `Node2D` (so a `CanvasModulate` there
    catches the HUD), `Ocean` is a `CanvasLayer` at `-100` (so it does *not*), and a dead
    `func rain()` painting 19 tiles from source 7 already squats the name.
  - Cheaper: nothing cheaper existed — this was reading, and it was the right tool. The
    harness has no verb that answers "which canvas is this node in", which is the one
    question the whole lighting design turns on. See the gap below.

- Gap: **no verb reports a node's effective canvas / `CanvasLayer` ancestry.** The plan's
  central risk is that `CanvasModulate` tints exactly one canvas, so `Ocean` (layer -100)
  and `UI` (layer 1) are missed while the diegetic `HUD` is hit. Establishing that meant
  grepping `main.tscn` for every `type="CanvasLayer"` and hand-walking parents; `scene-tree`
  reports `script` and `scene_file` per node but nothing about which canvas it renders into.
  `canvas-scale --node PATH` is adjacent — it already walks the canvas chain to accumulate
  scale — and stops one field short.
  - [G-105] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `canvas-scale` also return `canvas_layer_path` and `canvas_layer` (the
    `layer` int, or `0` for the root canvas). Then "will this CanvasModulate reach that node"
    is one call per node instead of a manual read of the scene file.

## 2026-08-03 — post the end-of-day devlog to itch.io

- Value: **warranted** — the harness produced the deliverable itself; a screenshot of
  today's crafting work cannot come from a diff.
  - Expected: `build_demo_world` then `crafting_panel` would drop me into a dense
    homestead with the tier-2 recipes on screen, one or two calls.
  - Got: neither. `build_demo_world` answered `"no clear 7x5 site near the player"`
    with `"success": false`, and the furnace panel it was supposed to set up rendered
    every recipe greyed at `0/1 Coal Ore` with `Not enough Ore` under a dead CRAFT
    button. That frame is indistinguishable from a broken game, and I would have
    shipped it unseen if the plan had been "screenshot whatever comes up". What
    actually worked was quickloading slot 1 (level 12), `learn_skill` x6,
    `give_item` x8 and opening station 0 — the sawmill, where Bone/Iron/Gold Sword
    all read affordable in green.
  - Cheaper: nothing. A devlog screenshot needs the running game by definition.

- Gap: **[G-100] again — the shared bus ate a capture mid-workflow.** `run-method`
  + `screenshot` returned
  `Foreign instance on the bus: the reply to 'screenshot' came from pid 19672, but ...
  devtools_owner.json says pid 10476 owns this bus.` A second instance (not mine) had
  claimed the bus between two calls in one workflow. Detection worked, which is the
  point of the owner file — but there is still no way to *finish* a capture once it
  fires short of relaunching with `--session`. Workaround: kept the screenshot taken
  before the collision and abandoned the refinement (selecting the Iron Sword card so
  the detail pane matched the shot).
  - [G-100] status: open | seen: 3 | harness: 0.8.0
  - Improvement: unchanged from the earlier sightings — `launch` should claim a session
    by default rather than sharing the unnamed bus.

- Gap: **[G-106] no way to discover the item names `give_item` accepts.** Eight calls,
  four of them wasted: `Iron`, `Gold`, `Coal`, `IronBar`, `GoldBar` each answered
  `"no item named 'IronBar'"`. The verb keys off the display name, so the working
  strings are `"Iron Ore"`, `"Gold Ore"`, `"Iron Bar"`, `"Gold Bar"` — with spaces —
  while `Types.Item` spells them `IronOre`/`IronBar`. Nothing in the reply says which
  space it wants, and `list-commands` describes the verb, not its vocabulary. Had to
  read `items/types.gd` and infer the display-name mapping.
  - [G-106] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have the failure reply carry candidates —
    `"no item named 'IronBar' (did you mean 'Iron Bar'?)"` — built from a fuzzy match
    over `GameItems.item_list`. A bare `items` verb listing registered names would
    close it outright and costs about ten lines.

- Gap: **[G-107] `build_demo_world` mutates the world, then fails.** Its `data` shows
  `"land": {"parcels_granted": 0, "radius_after": 34, ...}` — it runs `_max_out_land`
  *before* searching for a house site, so the refusal leaves land already bought. On a
  fresh world that is a one-way change to the thing being set up, reported under
  `"success": false` where it reads like nothing happened. It also gives no hint where
  a clear 7x5 site does exist, so there is no retry short of walking the player somewhere
  and guessing.
  - [G-107] status: open | seen: 1 | harness: 0.8.0
  - Improvement: search for the site first and bail before granting land, or return the
    nearest viable corner in `data` so the caller can `goto_cell` and retry.

## 2026-08-03 — fixed the bare demo world and split the island gate (gather-3m9)

- Value: **warranted** — every claim that mattered came from the running game; the diff and
  the unit suite could each only show half of it.
  - Expected: Runtime should say whether a closed island now carries resources but no
    enemies, and whether growing the island through the demo builder stocks the mainland and
    opens the islands - neither is visible in the diff, because both depend on a signal fired
    during generation and on region flags read by three separate systems.
  - Got: exactly that, as numbers. Closed islands: `forest opened=False nodes=18 res=True
    enemy=False`, `ore ... nodes=19`, `boss nodes=0 res=False enemy=False`, boss unspawned.
    Then `build_demo_world` -> `home land=1441 nodes=232 cap=360 (64%)`, all three islands
    `opened=True`, `boss alive=True chest=['Gold Coin x40','Gold Ore x8','Iron Ore x12']`,
    and `enemy_cap 3 -> 25`. Before the fix the same call gave `home land=1312 nodes=28`,
    three islands `opened=False nodes=0`, and no boss.
  - Cheaper: nothing. `test_land_manager` asserts `grant_parcels` emits `land_purchased` and
    `test_island_gating` asserts the two predicates, but neither can show that the emit
    actually stocks 232 nodes and opens three islands — that is four systems downstream of
    the signal.

- Gap: **`island_census` says `connects_at_max_land: True` for an island the live flood fill
  refuses to open, and nothing reconciles them.** On a maxed island the same reply carried
  `boss opened=False connects_at_max_land=True`. The two answers come from different sets —
  the promise from `land_cells_for_radius` (raw noise cells), the refusal from
  `walkable_cells_from_home` (grass only, coastline excluded) — so the census can promise a
  reachable boss arena that the seed never delivers. Filed as gather-37z; it cost a
  regenerated fixture, because the first world I built had an unreachable arena and the
  census said it was fine.
  - [G-105] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have the census compute both predicates and report them side by side, or
    report the walkable one under the name that reads as a promise. A single field that is
    right in one sense and wrong in the sense the reader needs is worse than two fields.

- Gap: **`launch --isolated` prints a session id it does not pass to the game.** It reported
  `session: 5a476098` and `Subsequent calls: ... --session 5a476098`, but the command line it
  echoed on the line above was `--path ... --mute` with no `-- --devtools-session`, so every
  call then failed with `This client is on session '5a476098'; the game must have been
  launched with -- --devtools-session 5a476098`. Worked around by launching by hand via
  `Start-Process ... '--','--devtools-session','isoA'`, which worked first time.
  - [G-106] status: open | seen: 1 | harness: 0.8.0
  - Improvement: append `-- --devtools-session <id>` to the argv `--isolated` builds. The
    instructions it prints are already correct; only the spawn is missing them.

- Gap: **[G-057] again, seen 2 — `quit` has no target and closed a session it did not own.**
  Three Godot instances were live (the user's game, the editor, mine). `quit` went to the
  foreign one and closed the window the user was working in; the ownership check reported the
  mismatch only on the *next* call, as `Foreign instance on the bus: the reply to 'screenshot'
  came from pid 21108, but devtools_owner.json says pid 17916 owns this bus.` Detection after
  the fact is fine for a read and unrecoverable for a quit. For the rest of the session I
  stopped my own instances by pid through `Stop-Process` rather than through the bus.
  - [G-057] status: open | seen: 2 | harness: 0.8.0
  - Improvement: make `quit` check the owner file *before* sending, and refuse when the pid
    that answers is not the one that owns the bus unless `--force` is passed.

- Gap: **[G-102] again, seen 7.** `NOT reached: world/land_region.gd` — the file the whole
  behavioural change lives in. It is a `class_name RefCounted` held as a plain field, so it
  owns no node a scene-tree snapshot can see, yet `island_census`'s `stocking.resources` /
  `stocking.enemies` fields are literally `accepts_ambient_resources()` /
  `accepts_ambient_enemies()` and every runtime assertion above went through them.
  - [G-102] status: open | seen: 7 | harness: 0.8.0
  - Improvement: unchanged and now well past due — credit a script when a reached script
    references its `class_name`. For a RefCounted or a static-only utility that is the only
    evidence that can exist.

## 2026-08-03 — cleared layer 0 on load (gather-mcl)

- Value: **warranted** — the shape of the evidence was the whole point; a totals number could
  not have distinguished the bug from a wrong assumption about the save.
  - Expected: The startup world's islands should stop surviving the load. Counting connected
    grass components is the only thing that can show it - the node census reports totals, and
    a totals number cannot distinguish "the saved world is bigger than I thought" from "there
    is a second world underneath it".
  - Got: `tilemap-region --atlas 9,17 --layer 0` on a booted world gave `282 cells in 4
    component(s)` — the startup home island plus its three islands. Loading the fixture
    before the fix left `1871 cells in 3 components`, two of them byte-for-byte the startup
    islands (`63 cells at x=11 y=18`, `43 cells at x=32 y=-3`). After the fix: `1654 cells in
    1 component`, and `grass total: 1654` against the 1654 the save recorded — home back to
    1384 from 1586. Loading a second, different world over it gave `1561 cells in 1
    component` at entirely different bounds, so the stacking is gone too.
  - Cheaper: nothing. The load path needs a real TileMap so there is no headless seam, and
    the census I had already been reading all session reports totals — it showed +202 tiles
    and I could not tell from it whether the saved world was simply bigger than I assumed.
    `tilemap-region` turning that into "four landmasses, two of which are still here" is what
    made it a bug rather than a suspicion.

- Gap: **no gaps this turn.** `tilemap-region` is the verb this needed and it did the whole
  job in one call; the connected-component framing is what made an ambiguous scalar into an
  unambiguous one. Worth recording as the counter-example to the three gaps logged earlier
  today: the harness was not merely adequate here, it was the only tool that could answer the
  question, and the answer was legible enough to paste into a bead unedited.

## 2026-08-03 — Proposed replacement titles for the game

- Value: **inconclusive** — no harness involvement; this was a naming question answered from
  `project.godot`, `README.md` and `itch/`, none of which need a running game.
  - Expected: nothing from runtime — a title is not a runtime property.
  - Got: n/a. The only repo facts that mattered were `config/name="Gather"` and the fact that
    saves key on `get_path()`, so a rename is save-safe.
  - Cheaper: exactly what was done — two greps and a `ls itch/`.

- Gap: **no gaps this turn.** The harness has no role in naming and correctly wasn't reached
  for; logging it only so an absent entry isn't mistaken for a forgotten one.

## 2026-08-03 — balance pass: tiered skill costs, gated gold, dearer crafting

- Value: **warranted** — runtime produced the one claim the diff and the unit suite both
  could not: the skill panel *builds* correctly around a branch that is no longer the same
  length as its neighbours.
  - Expected: runtime should show (a) `purchase()` deducting a capstone's full 4 points
    rather than 1, (b) `gold_rush` refused while `light_step` is untaken even with points
    banked, and (c) the live panel building Industry's new 5th card without breaking the
    per-column connector/scale layout — the unit tests never construct the panel.
  - Got: all three, and (c) was the one worth launching for. `scene-tree` reported
    `Branch_Industry cards=5 links=4` against `cards=4 links=3` for the other three, and all
    17 cards carried a resolvable `Cost` label reading `1/2/3/4` down each column and `5` on
    Minting. The gate: with `points=99` and the whole Industry chain bought,
    `is_available("gold_rush")` → `False` and `purchase` → `False`; after `light_step` it
    went `True` and the bank moved `90 → 86`, then `86 → 81` for the 5-point mint. The
    detail pane rendered `Costs 4 points — requires Smelting, Light Step`, which is the
    *only* place that cross-branch edge is visible, since the panel draws connectors down a
    column and cannot draw this one.
  - Cheaper: nothing for the panel build and the cost-label states — headless pumps no
    frames and `SkillNodeButton` is built in `_init`/`_ready`. The purchase arithmetic alone
    (1/2/4/5 point deductions, refusal on an unaffordable node) could have been a unit test
    on `LevelUpManager` and did not need a running game.

- Gap: **`get-state` cannot address a Control that Godot auto-named** — the new price label
  was initially unnamed, like the three siblings already on that card, so it landed under
  `@Label@249`. Feeding that path straight back from `scene-tree` gives
  `Failed: Node not found: …/@MarginContainer@243/@HBoxContainer@244/@Label@249`, so a node
  the snapshot had just listed was unreadable. Worked around in the project rather than the
  harness (`_cost_label.name = "Cost"`), which is the right fix here but does not help
  anyone reading a Control they did not write — the parent `@MarginContainer@243` and
  `@HBoxContainer@244` in that same path are still unaddressable.
  - [G-108] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `get-state`/`node-bounds` accept the `@Name@id` segments that
    `scene-tree` emits — they are stable for the life of the node, and round-tripping a path
    the harness itself just printed should never 404. Failing that, have `scene-tree` mark
    such nodes as unaddressable so the dead end is visible before it is hit.

- Gap: **[G-050] again, seen 4.** `NOT reached: systems/skill.gd, systems/skill_tree.gd` —
  the two files carrying the entire pricing model. Both are `RefCounted` by design (so tests
  can build the tree without a SceneTree), so they are never any node's `script` and cannot
  register, yet the run drove them decisively: `cost_of("minting")` → `5` resolves through
  `SkillTree.get_skill()` into `Skill.cost()`, and there is no other code path that produces
  a 5. The verdict machinery correctly refused to call this a full pass, but for the wrong
  reason — it discounted the files that were exercised hardest.
  - [G-050] status: open | seen: 4 | harness: 0.8.0
  - Improvement: as filed — credit a changed file as reached when a `run-method`/`cmd` call
    in the session returned through it, or let projects declare RefCounted registries as
    `implicit` the way autoloads already are.
## 2026-08-03 — built the rain + day/night cycle (gather-bqn), verification deferred

- Value: **inconclusive** — the user explicitly asked that nothing be run this turn, so the
  harness was not used. Logged rather than skipped, because "the gate did not run" and "the
  gate ran and passed" have to be distinguishable in this file.
  - Expected: nothing, by instruction. `gather-bqn.6` is filed to carry the run, and it
    names the one assertion no headless gate can make (below) so the deferral does not
    quietly become a skip.
  - Got: nothing from runtime. What the *reading* produced is the design's load-bearing
    fact — `main.tscn:395` makes `World` a bare `Node2D`, so the root canvas holds the
    diegetic HUD, while `Ocean` is a `CanvasLayer` at `-100` and `UI` at `1`. One
    `CanvasModulate` therefore hits the HUD (wrong) and misses the sea (also wrong), which
    is why `SkyLighting` makes three writes instead of one.
  - Cheaper: n/a — nothing was run. Had it been, the cheap half (lint + the new
    `test_world_clock.gd`) would have settled the tint curve's continuity and the save
    round-trip on its own; only the three-canvas agreement needs the game up.

- Gap: **no verb reports a node's effective canvas, so the central risk of this change was
  unaskable.** Repeat of what I filed last turn; hitting it again while actually building
  against it is what confirms it is worth upstreaming rather than a one-off. `scene-tree`
  gives `script` and `scene_file` per node and says nothing about which canvas a node
  renders into; `canvas-scale --node PATH` already walks the canvas chain to accumulate
  scale and stops one field short of the answer. I worked around it by hand-reading every
  `type="CanvasLayer"` in `main.tscn` and walking parents — and then by writing the
  read-back into a project verb, which is the tell: `world_clock` returns `world_tint`,
  `ocean_color` and `hud_modulate` side by side precisely because the generic bridge cannot
  express "do these three canvases agree".
  - [G-105] status: open | seen: 2 | harness: 0.8.0
  - Improvement: have `canvas-scale` also return `canvas_layer_path` and `canvas_layer` (the
    `layer` int, `0` for the root canvas). "Will this CanvasModulate reach that node" then
    becomes one call per node instead of a manual read of the scene file, and every 2D
    project with a HUD hanging off a camera hits this exact question eventually.

## 2026-08-03 — verified the rain + day/night cycle at runtime (gather-bqn.6)

- Value: **warranted** — the run found two real defects that lint and all 464 unit tests
  passed clean over, and neither was visible in the diff.
  - Expected: at night the three canvases will disagree unless all three writes actually
    landed — specifically `hud_modulate` must be the reciprocal of `world_tint`, and
    `ocean_color` must be `OCEAN_COLOR * tint`. Both the HUD counter-modulate and the ocean
    base-colour capture resolve lazily by node path, so either could silently no-op and the
    diff cannot show it.
  - Got: the prediction was *wrong about where the bug was* — all three canvases agreed to
    six decimal places on the first try (`hud 2.38095 == 1/0.42`, `ocean.g 0.27420 ==
    0.596078 * 0.46`). The defects were elsewhere, and both are the kind only a running game
    reports:
    1. **The rain-to-regrowth coupling was dead.** `wait_time: 24.0` during a storm that was
       visibly falling. `run-method _apply_weather [1]` returned `wait_time: 13.2`, which
       isolated it to the wiring: `ResourceTimer` lives under `World`, `WorldClock` under
       `Systems`, and `Systems` is declared last — so the group lookup in `ResourceTimer._ready`
       ran before `WorldClock._ready` had joined the group and silently got null. Fixed by
       registering the group in `_enter_tree` (the whole `_enter_tree` pass precedes every
       `_ready`), plus a `push_warning` so it can never be silent again. This is the same
       ordering hazard CLAUDE.md documents for `Systems` vs `UI`, hit from the other side.
    2. **The lantern erased the night.** Every property read said the tint was correct — and
       it was. The screenshot showed a pale green blob over a third of the screen: `light.png`
       is 256px, so the dead scene node's `scale = 0.365` meant 93 world units (748 screen px
       at zoom 8), and a Light2D blends additively, so at `energy 0.9` the middle saturated.
       Now 0.16 / 0.40.
  - Cheaper: nothing. Defect 1 is purely a property of node order in `main.tscn` and no
    static read reveals it; defect 2 needed a rendered frame. The `world_clock` verb's
    read-back of all three canvases is what made defect 1 *diagnosable* in two calls rather
    than by bisecting the signal chain.

- Gap: **`quit` is still not ownership-checked, and it cost a mid-run session.** A foreign
  instance appeared on the bus part-way through: `Foreign instance on the bus: the reply to
  'screenshot' came from pid 13640, but ... devtools_owner.json says pid 4316 owns this bus.`
  Only one process was actually alive, so the owner file was a stale claim from an instance
  that had already exited. Detection fired only *after* several reads had already been taken,
  so I could not tell which instance had answered them and had to kill everything, clear the
  owner file by hand, relaunch under `-- --devtools-session vfy`, and re-run the two load-
  bearing assertions to be able to report them honestly.
  - [G-057] status: open | seen: 3 | harness: 0.8.0
  - Improvement: as filed — check ownership *before* acting, not after. Additionally: treat
    an owner file whose pid is no longer alive as stale and reclaim it automatically, rather
    than reporting a conflict against a process that does not exist.

- Gap: **no verb reports a node's effective canvas.** Third sighting; this run is the one
  that shows it was worth the workaround. `canvas-scale` already walks the canvas chain and
  stops one field short of the answer.
  - [G-105] status: open | seen: 3 | harness: 0.8.0
  - Improvement: have `canvas-scale` also return `canvas_layer_path` and `canvas_layer` (the
    `layer` int, `0` for the root canvas).

## 2026-08-03 — planned grass-tuft decoration on plain-grass tiles (plan only, no code)

- Value: **overkill** — no runtime was used and none was warranted; the whole plan came
  out of reading four files, and the user explicitly deferred `/verify`.
  - Expected: nothing — this turn produced a design, not a diff, so there was no claim a
    running game could have settled.
  - Got: n/a. The three facts the plan hinges on were all settled statically:
    `GRASS_ATLAS := Vector2i(9, 17)` at `main.gd:664` distinguishes plain grass from every
    coastline variant; `is_occupied()` at `main.gd:576` reads only layers 0/1/2 and never
    enumerates layers, so a new layer cannot block spawning; and
    `Resources.get_item_or_resource` at `items/resources.gd:119` compares `tile_source_id`
    as well as atlas coords, so a decor cell on an unregistered source 14 returns null and
    `saveObject`'s all-layers walk skips it.
  - Cheaper: nothing cheaper existed — this was `Read` + `Grep` over `main.gd`,
    `world/tile_map.tscn`, `world_tile_set.tres` and `items/resources.gd`, roughly 6 tool
    calls. The one open question the plan names (does a `z_index = -1` layer 6 draw above
    layer 0, also `-1`, under a y-sorted TileMap?) is genuinely a runtime question and is
    flagged as such rather than guessed at.

- Gap: **no gaps this turn** — the harness was not invoked, so it had no opportunity to
  fall short. Recording this explicitly so the absence reads as deliberate rather than
  forgotten.

## 2026-08-03 — boss island never opened (gather-37z); reward chest now falls from the sky

- Value: **warranted** — runtime produced two claims the diff could not, and a headless
  sweep produced a third that no amount of reading would have.
  - Expected: on a max-land world the census's `connects_at_max_land` and the live `opened`
    flag agree and a live Elite exists; killing it yields a 600-coin chest placed via
    `falling_chest.gd`. Neither is visible in the diff, since placement is seeded per-world
    and the reward now arrives through an animation callback.
  - Got: `boss opened=True now=True at_max=True` with
    `boss: {"alive": true, "hp": 90, "chest": []}` — the chest correctly absent while the
    boss lives, which is the guard the whole feature turns on. After
    `_on_boss_died("boss")`: `chest: ["Gold Coin x600", "Gold Ore x8", "Iron Ore x12"]`,
    and `scripts-seen` lists `res://world/vfx/falling_chest.gd`, so the reward arrived
    through the animation's `landed` callback rather than the direct fallback. Survived a
    real `[`/`]` round trip unchanged. `Orphan growth: +4` over three separate drops, so
    the self-freeing `_linger` countdown holds.
  - Cheaper: the 200-seed headless sweep alone settled the *placement* half and was far
    cheaper than the game — but only after its predicate was corrected, and that correction
    is the finding. The pre-existing sweep flooded raw land and therefore agreed with the
    placement code's own optimistic answer: `raw_stranded=0, grass_stranded=39 of 600`
    from a throwaway diagnostic run before any fix. 200 seeds had been passing green for
    months while real playthroughs dead-ended. The *reward* half genuinely needed the
    running game — `FallingChest.landed` reaching the ground and the chest surviving a
    quicksave is not a thing any unit test observed.

- Gap: **no way to find a node by a property value; auto-named siblings must be probed one
  at a time, and their names churn between calls.** The boss is an `Enemy` among the
  EnemySpawner's children, and persisted/ambient enemies get engine names:
  `scene-tree` returns `@CharacterBody2D@385`, `@CharacterBody2D@388`, `@CharacterBody2D@416`,
  `@CharacterBody2D@419`, `Enemy`, `SpiderEnemy` — none of which says which one is the
  Elite. Finding it costs one `get-state --property type` round trip per child (6 calls,
  twice over), and by the time the loop finished the ids had rotated as the spawner
  trickled enemies in: `Failed: Node not found:
  /root/Main/World/EnemySpawner/@CharacterBody2D@1015 (also tried under /root)` on a path
  that had answered 20 seconds earlier. Workaround: drove `IslandManager._on_boss_died`
  directly instead of killing the real node, which tests the reward path but not the
  `health_manager.died` wiring that reaches it.
  - [G-109] status: open | seen: 1 | harness: 0.8.0
  - Improvement: let `scene-tree` take a `--property NAME` to include that property on
    every node it emits (`--property type` would have answered this in one call), or add a
    `find-nodes --class Enemy --where type=Elite` verb returning matching paths. The
    existing `clear-nodes --group/--class/--method` already does this matching internally
    to *free* nodes; exposing the same predicate as a read would cost little.

## 2026-08-03 — Added a skills-recap instruction to the global CLAUDE.md

- Value: **inconclusive** — no game code changed; this turn only created
  `C:\Users\gotmi\.claude\CLAUDE.md`, which the harness has no view of and no way to
  assert on.
  - Expected: nothing — the harness verifies `res://` scripts and scenes at runtime, and
    the edited file is outside the project entirely.
  - Got: n/a, no harness command was run.
  - Cheaper: nothing to run; a `Read` of the target path (which did not exist) was the
    whole verification.

- Gap: no gaps this turn — the change was outside the harness's scope, not beyond its reach.

## 2026-08-03 — scattered grass tufts and wildflowers over plain grass (gather-5z0)

- Value: **warranted** — runtime produced two claims the diff could not, one of which was a
  latent bug in a design that looked finished on the page.
  - Expected: that layer 6 at `z_index = -1` actually draws above layer 0 (also `-1`) under a
    y-sorted TileMap — equal-z ordering by layer index is an engine detail no amount of
    reading settles. And that the real generated island gets ~18% of its grass cells tufted,
    rather than zero because source 14 failed to resolve at runtime.
  - Got: both, plus the one that mattered. `grant_parcels(3)` took the map from 51 to 85
    tufts and **8 of the new ones landed on cells that were coastline before the purchase** —
    the exact cells an incremental "paint only the new ring" repaint would have left bare
    forever, in a band at every radius the island ever stopped at. Nothing in the diff says
    that; it only shows up because a purchase re-solves old coastline into plain grass. Also
    `0 of 51` tufts on a non-grass atlas with 19 distinct ground atlases present, `14` tufts
    sharing a cell with a layer-1 resource (the user's actual requirement, as data rather
    than as an argument), and a quickload reproducing the scatter **cell-for-cell, 85/85**,
    which is what the no-persistence design rests on.
  - Cheaper: nothing. The 13 unit tests cover the pure scatter function and the `is_occupied`
    invariant on a synthetic TileMap, and they are what caught nothing here — the coastline
    promotion needs the real terrain solver, the round trip needs the real save path, and the
    draw order needs pixels.

- Value (second run, the art pass): **warranted** — `screenshot` was the only instrument that
  could answer the question asked.
  - Expected: that the redrawn sheet reads as grass rather than as the flat off-palette V it
    replaced, and that the weighted variant table puts all six columns on the map rather than
    starving the low-weight flowers.
  - Got: all six columns live (`21/23/17` grass, `5/5/7` flowers, no stray source or column),
    `18.7%` of grass decorated and flowers at `4.1%` of grass. The art itself took four
    iterations that only a rendered preview could adjudicate — vertical bars read as a bar
    chart, adjacent full-height columns read as a solid block, and a linear lean read as a
    staircase. None of that is visible in a pixel array.
  - Cheaper: for the *distribution*, the unit test `test_every_variant_is_reachable` would
    have done it headless. For whether it looks like grass, nothing but the screenshot.

- Gap: **no gaps this turn.** One thing worth noting rather than filing: `tilemap-cells`
  returns `atlas` as `{"x":..,"y":..}` while `run-method get_used_cells` returns Vector2i
  already stringified to `"(x, y)"`, so a script consuming both needs two parsers. That is
  the harness faithfully reporting what Godot handed it, not a defect — recording it so the
  next person writing a cross-layer probe expects it.

## 2026-08-03 — four candidate decoration art styles, compared in-game (gather-5z0)

- Value: **warranted** — the run overturned a judgement made from static previews, which is
  the only kind of finding that justifies launching the game for an art change.
  - Expected: that showing all four candidate styles in the running game would mostly confirm
    the ranking already visible in the scattered-field mock-ups, and let a style be picked.
  - Got: it contradicted them. Every style is **too large at the camera's 8x zoom** — a 16px
    tile is 128px on screen and the flower blooms span ~11 of those 16 pixels, so in-game a
    daisy is bigger than a rock and reads as an interactable pickup sitting next to the ore
    nodes. The 2x field previews I ranked the styles on could not show this, because the
    thing that fails is the sprite's size *relative to the other sprites*, and a preview over
    bare grass has no other sprites in it. Four screenshots, one per style, at
    `decor_style` 0..3.
  - Cheaper: nothing that was actually tried. In principle a mock-up compositing the
    candidates against a real screenshot would have caught it for no launches — worth doing
    first next time an art change is judged. The scattered-field-over-flat-colour preview is
    the thing that was too cheap.

- Gap: **no gaps this turn.** Worth recording rather than filing: putting all four candidate
  styles on one 24-column atlas and selecting between them with a `static var` made this one
  import and four 8-second relaunches instead of four imports (~30s each). The harness did
  not need to change for that — but a `set-state` on a `static var` followed by
  `run-method refresh_grass_decor` would have made it one launch, and that failed only
  because the repaint reads the var at paint time and the atlas columns are baked per style.
  Noting the pattern because "put every candidate in one atlas and index it" is reusable for
  any future art bake-off in this project.

## 2026-08-03 — planned lightning strikes and blue skull enemies (no code written)

- Value: **inconclusive** — a requirements-and-design turn; nothing was built, so no runtime
  claim was available to make or to miss.
  - Expected: nothing from runtime. The open questions were product decisions (strike
    targeting, damage model, capture rule, rarity) and structural ones answerable by reading
    — where weather lives, how the net decides what it catches, how a loaded machine stores
    what is in it.
  - Got: reading settled every structural question and changed the plan twice. `loaded` is a
    bare `bool` on both `bone_turret.gd:11` and `bone_worker.gd:60`, so blue variants are a
    save-format change rather than a new scene; `bullet.gd:28` hardcodes
    `receive_hit(Vector2.ZERO, 3)`, so "turret hits harder" reaches the bullet and not the
    turret; `enemy_spawner.gd:280-330` already persists `type`/`max_hp`/`damage` through
    `EnemyRegistry`, so a new enemy type needs no new persistence at all. Also found that
    nothing in `enemies/` draws a health bar, which makes the chosen "nettable below 50%"
    rule illegible without added feedback — a design flag raised back to the user.
  - Cheaper: nothing. Eight greps and six file reads is already the floor for this, and
    launching the game would have told me less than `enemy_registry.gd` did.

- Gap: **no gaps this turn.** The harness was not exercised — no lint, no tests, no bridge
  call — because there is no diff to verify. Recording that explicitly so the absence reads
  as "not applicable" rather than as a skipped gate; `/verify` is owed at the end of each
  implementation phase, starting with the lightning VFX node.

## 2026-08-03 — flat top-down decoration, occupancy gating, and an is_occupied hot-path fix

- Value: **warranted** — two findings the diff and the unit suite both had no way to produce.
  - Expected: that gating decoration on `is_occupied` would hold at runtime for both spawned
    resources and player placements, and that the half-size blooms would stop reading as
    interactable.
  - Got: both, and a cost nobody had asked about. `refresh_grass_decor` measured **38 ms over
    1878 grass cells** at max land, because `is_occupied` calls `get_item_or_resource` — a
    linear scan of both registries — unconditionally, and an EMPTY cell reads back as source
    `-1` / atlas `(-1, -1)`, which no entry is registered under. So it scanned everything to
    conclude nothing, on every empty cell. Guarding that call on `source_id != -1` took the
    repaint to below the measurement floor. That function is also the spawn loop's retry test
    (up to 100 calls per node placed) and the pathfinder's neighbour test, so the fix is worth
    more than the feature that exposed it. Also confirmed: `0` of 258 decorated cells overlap
    layer 1 or 2 at max land, and placing a wall on a decorated cell cleared exactly that cell.
  - Cheaper: for the occupancy rule, nothing — but the unit tests do cover it, and they were
    written first and passed first. The 38 ms is the part only the running game could say, and
    only because the timing was taken at max land rather than on the starting island.

- Gap: **`tools/run_tests.gd` joins the DevTools bus and can seize ownership from a live
  game.** Mid-session, `run-method` started returning empty replies; the client correctly
  reported `Foreign instance on the bus: the reply to 'run_method' came from pid 16300, but
  devtools_owner.json says pid 20584 owns this bus`. Listing processes found the culprit was
  not another *game* but a headless `Godot --headless --script res://tools/run_tests.gd`
  instance — the DevTools autoload loads under the test runner too, so a test run concurrent
  with a live game fights it for the bus. The ownership check caught it, which is the good
  news; what it cost was one silently wrong measurement (a 359 ms "repaint" that was two
  instances answering) that I nearly wrote down as a result.
  - [G-109] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `run_tests.gd` and `lint_project.gd` opt out of the bus entirely — they
    are not interactive sessions and have no reason to register as its owner. Failing that,
    give them an automatic private session id so they cannot collide with a running game.

## 2026-08-03 — Held pickaxe sprite did not match the selected hotbar slot (gather-g92)

- Value: **warranted** — the running game produced the mismatch as two numbers I could put
  side by side, which is precisely what the diff could not do: the two halves that disagree
  live in different files and neither is wrong on its own.
  - Expected: that at boot, with zero input, `World/Player/Gather` would still carry
    main.tscn's authored texture rather than the equipped item's — because
    `PlayerManager.show_slot_data()` is reachable only through
    `HotBarInventory.hot_bar_selected`, and that signal is emitted only from `select_slot()`,
    which only real player input calls. Read statically, the authored region `(96, 16)` is
    tile `(6, 1)` = the **iron** pickaxe while `items.gd:54` starts the player on the wooden
    one at `(12, 0)`.
  - Got: exactly that, and then the fix confirmed against the same read. With the fix stashed:
    `gather_region {x: 96, y: 16}`, `item_region {x: 192, y: 0}`, `matches: false`,
    `selected_item: "Wooden Pickaxe"` — the player swinging a tier-5 tool they could not have
    crafted. With it restored, `matches: true` on a clean boot. The second half was worth more
    than the first: selecting the *empty* slot 4 and then `give_item Gold Pickaxe` — an item
    appearing **under** a selection that never moved — took the gather sprite onto
    `placeholder_tiles.png (80, 64)`, a different sheet entirely. Same for a real save/load
    round trip: `use_slot {"slot": 3, "action": "load"}` with no input after it came back
    `selected_item: "Gold Pickaxe"`, `matches: true`. That is the `Player.loadObject()` →
    `inv_updated()` path, and it is a save-fidelity bug of the shape CLAUDE.md already warns
    about — a load that succeeds and quietly hands the player back the wrong thing.
  - Cheaper: reading `player_manager.gd:16-23` and `hot_bar_inventory.gd:208-215` together
    found the bug — that part cost two file reads. What needed the running game was the
    *confirmation*, because the fix's whole claim is "a push now happens that did not before",
    and an added call site is exactly the kind of change that looks obviously correct in a
    diff and still fires at the wrong time or not at all.

- Gap: **`get-state` cannot see inside a Resource, so the one field that identifies a sprite
  never crosses the bus.** `get-state --node /root/Main/World/Player/Gather --property texture`
  answered `texture: ():<AtlasTexture#-9223371914985075739>` — an object id. Which *picture* a
  Sprite2D is showing lives in `texture.region`, one hop down, and there is no node path for a
  sub-resource, so no generic verb can reach it. Worked around by registering an
  `equipped_sprite` project verb that flattens the AtlasTexture to its base image plus an
  absolute rect. Flattening was not optional: main.tscn authors textures straight over
  `tiles.png` while `GameItem.get_atlas()` wraps `game_items_atlas.tres` (an AtlasTexture whose
  own atlas is that same png), so comparing the wrapper reports a mismatch between identical
  pictures, and comparing the rect alone can match two different ones across the three sheets.
  - [G-110] status: open | seen: 1 | harness: 0.8.0
  - Improvement: let `--property` walk one level into a Resource — `--property texture.region`,
    `--property texture.atlas.resource_path` — falling back to the object id when the path does
    not resolve. Sprite regions, StyleBox colors, Shape2D extents and Timer sub-resources all
    sit exactly one hop past what `get-state` can currently say.

- Gap: **`launch --isolated` prints a `--userdata` the game does not poll.** The gap it was
  built for is [G-057], now shipped in 0.8.0 — but it does not work. `launch --isolated`
  reported `session: cda33b18`, `userdata: …\Temp\devtools_userdata_5_4b1mjg` and the exact
  follow-up command to use; the process started and reached `Entering state: PlayerIdle` in
  `launch_stdout.log`, yet `--session cda33b18 --userdata …` answered `game not running:
  'ping' was never picked up … polling: …\Temp\devtools_userdata_5_4b1mjg`. So the client
  watches the isolated dir and the game does not write to it — the session id reaches the game
  but the userdata override does not. Fell back to serialising on the default bus, which cost
  a run: two instances ended up live and the client caught it with `Foreign instance on the
  bus: the reply to 'use_slot' came from pid 19256, but devtools_owner.json says pid 19472
  owns this bus`.
  - [G-111] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `--isolated` pass the userdata dir to the game the way it passes the
    session id (`--userdata`/`GODOT_USERDATA` on the child process), and have `launch` verify
    the new instance answers a `ping` on its own bus before printing the follow-up command —
    printing a command that cannot work is worse than failing, because it reads as success.

- Gap: **`quit` is not reliably fatal, and nothing notices the survivor until it corrupts a
  read.** Three separate times a `quit` followed by a relaunch left the old process alive
  (`tasklist` showed two Godot PIDs, once at 1.4 GB), and the only symptom was verbs returning
  empty output. `python tools/devtools.py ping` then said `No response`, which reads as *no*
  game rather than *two*. Had to `taskkill //IM` and start over.
  - [G-112] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `quit` wait for the process to actually exit and report if it did not,
    and have `launch` refuse to start when another instance already owns the bus — the owner
    file it already writes has everything needed to detect it.

- Note, not a gap: running the game rewrites `assets/art/ground_decor.png` on boot, so any
  runtime verification leaves a modified tracked binary behind. Caught it twice with
  `git status` and reverted; worth knowing before a commit picks it up as an intended change.

## 2026-08-03 — Berry bush: a resource that survives being harvested (gather-j2n)

- Value: **warranted** — runtime produced three claims the diff and the unit suite could not,
  and one of them was a bug in my own code.
  - Expected: the unit tests already pinned the state machine, the 900s clock and the
    save/load round trip, so I expected the running game to confirm generation and nothing
    more.
  - Got: three things the headless side could not reach. (1) `island_census` on the first
    world reported `home: {Coal 2, Copper 1, Stone 19, Tree 7}` with **no bushes at all** —
    which sent me looking for a placement bug for twenty minutes before a second world came
    back `forest: {Berry Bush: 3, ...}, home: {Berry Bush: 2, ...}`; the first seed was
    genuinely a ~1% draw, and only a second run could say so. (2) The full loop, which no
    unit test spans: `3 bush(es): 3 fruiting` → hold gather → `2 fruiting, 1 picked;
    carrying 1 berries` with `regrow_left: 897.68` — the bush is still standing and paying
    out, which is the entire feature. (3) The real `SaveLoad` path, not `save()`/`load()`
    called directly: quicksave, force every bush to refruit, quickload, and the bush at
    (2,7) came back `fruiting: False, regrow_left: 880.4` — a part-finished regrow that had
    survived position-matching and `CHUNK_KIND` filtering.
  - Cheaper: nothing. The unit tests cover the node in isolation and were written first;
    what runtime added was the wiring between eight files — hotbar → gather state →
    ResourceManager2's new branch → PickUpManager → inventory → consumable — plus the
    engine's one-frame delay on instancing a scene tile, which is exactly where the
    equivalent chest bug (gather-74z) lived.

- Gap: **`goto_resource` cannot reach a scene-backed resource by name** — the verb CLAUDE.md
  tells you to run before any gather test. `cmd goto_resource --args '{"name":"Berry Bush"}'`
  answered `no live 'berry bush' node on the island` while the census in the same reply said
  `"Berry Bush": 5`. Cause: `_cmd_goto_resource` builds its lookup from
  `if not resource.is_scene_tile`, so scene-backed types are excluded from the named search
  and only reachable through the unnamed `for node in ... if node is GameSceneResource`
  fallback — i.e. "any scene resource, whichever comes first". This was already true for
  StoneResourceTest; adding a second scene resource is what made it matter. Fixed in
  `devtools_ext/commands.gd` by walking the TileMap's `GameSceneResource` children and
  matching `resources.get_item_or_resource_by_type(node.resource_type).name` when the atlas
  walk finds nothing.
  - [G-110] status: fixed | seen: 1 | harness: 0.8.0
  - Improvement: project-side fix, already applied. The generic lesson for the harness is
    that a "find me one of these to test against" verb should never silently exclude a whole
    representation — it reported a confident negative next to its own contradicting census.

- Gap: **`launch --isolated` prints a session id it does not pass to the game.** With another
  Godot instance contending for the shared bus, `python tools/devtools.py launch --isolated`
  reported `session: abc1afa3` / `userdata: ...devtools_userdata_vovu1e7k` and printed the
  command it ran — `Godot.exe --path <project> --mute`, with no `-- --devtools-session`
  and no userdata override. Every subsequent call with those flags failed with
  `game not running: 'ping' was never picked up`, pointing at the temp userdata nothing was
  polling. Workaround: launched by hand with
  `Godot.exe --path . --mute -- --devtools-session bb1` and called with `--session bb1`,
  which worked first try.
  - [G-111] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `--isolated` actually append `-- --devtools-session <id>` (and the
    userdata override) to the launched command line, or fail loudly if it cannot.

- Gap: **a dead instance's `devtools_owner.json` blocks the live one, and the error blames
  concurrency.** Twice mid-session, every verb started returning
  `Foreign instance on the bus: the reply to 'island_census' came from pid 22232, but ...
  devtools_owner.json says pid 8620 owns this bus` — while `Get-Process Godot*` listed pid
  22232 as the only Godot running. The named owner had already exited (headless lint/test
  runs load the autoload, claim the bus and quit). The reply that arrived was correct and
  from the right game; the client discarded it. Workaround: `rm devtools_owner.json`.
  - [G-112] status: open | seen: 1 | harness: 0.8.0
  - Improvement: check whether the recorded owner pid is still alive before refusing —
    a dead owner should be reclaimed with a note, not reported as contention. Failing that,
    have headless `--script` runs skip the ownership claim entirely; they are not
    interactive sessions and nothing ever addresses them over the bus.

## 2026-08-03 — suggested alternative names for the game

- Value: **inconclusive** — no code, scene or gameplay changed, so the harness was never
  the right instrument; the only tool call was a `grep` of `[application]` in
  `project.godot` to read the current `config/name="Gather"`.
  - Expected: nothing from runtime — a naming question is answered from the design, and
    the design is already written down in CLAUDE.md.
  - Got: `config/name="Gather"`, confirming the name is pinned in exactly one place, which
    is what makes a future rename cheap.
  - Cheaper: nothing cheaper existed; one grep was the whole investigation.

- Gap: no gaps this turn — the harness was not exercised and nothing about this task
  wanted it.

## 2026-08-03 — drafted the itch.io devlog for the day/night + berry-bush work

- Value: **warranted** — the whole deliverable was a screenshot showing four of the six
  bullets at once, and only the running game could stage it.
  - Expected: `set_time_of_day --args '{"phase":"dusk"}'` plus `set_weather rain` plus a
    player teleport next to a fruiting berry bush would put the lantern glow, the rain,
    the scattered wildflowers and both bush states in one 1920x1080 frame.
  - Got: exactly that, and one thing the diff could not have told me — the frame is
    legible at dusk with rain, whereas the first capture at `phase: night` came back too
    dark to identify the bushes at all. `world_clock` read back
    `"phase": "night", "weather": "rain", "tint": [...]` so the retake was one call, not a
    guess.
  - Cheaper: nothing. A stale screenshot or a title-card grab would have been the
    alternative, and both are the failure mode the devlog skill names outright.

- Gap: **`goto_resource` cannot reach a scene-tile resource** — `cmd goto_resource --args
  '{"name":"berry"}'` returned `"no live 'berry' node on the island"` while
  `cmd berry_bushes` in the same session listed five, three of them in `home`.
  `_resource_cells()` builds its atlas map with `if not resource.is_scene_tile`, so the
  two scene-backed resources are invisible to the verb that exists to stand next to a
  resource. Workaround: read a cell from `berry_bushes`, derive world coords by hand
  (`cell * 16 + (8, 8)`, inferred from an earlier reply's tree position) and
  `set-state --property position`.
  - [G-113] status: open | seen: 1 | harness: 0.8.0
  - Improvement: fall back to `TileMapHandler.scene_tile_at`/the scene-tile children when
    the atlas map misses, so `goto_resource` covers both representations the way
    `resource_node_census` already does.

- Gap: **the launched instance exited with an empty stderr log and no other signal** —
  a `set-state` mid-session returned `Owner file devtools_owner.json says pid 19168 …
  that process has likely exited`, and `.devtools/launch_stderr.log` was zero bytes, so
  there is nothing to distinguish a crash from a clean exit after the fact. Workaround:
  none needed — the capture was already taken — but the run could not be resumed.
  - [G-114] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `launch` record the process exit code to `.devtools/` when the
    child dies, so a later bus failure can say "exited with 0" instead of "likely exited".

## 2026-08-03 — Repriced Cooked Food and Bandage onto berries (gather-as9)

- Value: **warranted** — but the sharpest finding came from a mutation check, not from the
  running game, and the running game then caught a wrong assumption about my own tooling.
  - Expected: a two-line data change with a test around it; I expected runtime to add
    nothing and planned to skip it.
  - Got: three things. (1) The new test PASSED with the old recipe still in place —
    `selected 1 of 507`, `[PASS]` — because Cooked Food heals 10 and 2 Food heal 8, so
    "beats its ingredients" was true and toothless. Only putting the old cost back and
    watching for red exposed that; the fix was `CRAFTED_HEAL_MULTIPLE := 2.0`, after which
    the old cost gives `[FAIL] ... Cooked Food heals 10 but is made of 2 Food (4 each),
    worth 8 eaten raw - a station recipe should pay at least 2.0x`. (2) The live craft
    confirmed the cost list is actually consumed: `carrying 8 berries` → `queued 1 Cooked
    Food` → `produced 1` → `carrying 4 berries`, and the same for the Bandage, `4` → `2`.
    (3) I had read `_station_at` as picking the nearest station; it takes an INDEX
    defaulting to 0, so three attempts to craft a Bandage answered `'Bandage' is not
    unlocked at this station` while the player stood on top of the sawmill — the furnace
    was station 0 the whole time.
  - Cheaper: for the balance change, yes — the mutation check was ~40s and found more than
    the 8-minute runtime session did. For "is the recipe actually wired", no: nothing short
    of a running station spends a cost list.

- Gap: **a green test says nothing about whether it can fail.** The one real defect this turn
  was a test that passed in both directions, and the harness has no way to say so. There is
  `--filter` to run one test, but nothing that answers "does this test still fail if I break
  what it guards". I did it by hand: `cp recipes.gd`, edit the cost back, run filtered, `cp`
  back — four steps, easy to leave a repo dirty halfway through.
  - [G-113] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `mutate` mode — `run_tests.gd -- --filter NAME --expect-fail` returning 0
    only when the named test FAILS — would make "prove the guard has teeth" a one-liner that
    is safe to run in a dirty tree. Even documenting the cp/edit/run/restore loop in the
    testing section would beat re-deriving it.

- Gap: **`craft_state` / `queue_craft` select a station by list index, and the reply reads as
  if it were proximity.** `_station_at` is `stations[int(args.get("station", 0))]`, but the
  reply prints that station's `position`, so standing beside a sawmill and being told
  `nearest: Furnace {'x': -40.0, 'y': -8.0}` looks like a targeting bug in the game. I moved
  the player three times chasing it. `craft_state --args '{"station":N}'` over 0..3 was what
  finally showed four stations in a stable order.
  - [G-114] status: open | seen: 1 | harness: 0.8.0
  - Improvement: project-side — default `station` to the one nearest the player (which is
    what every caller means and what the crafting panel itself does), and rename the reported
    key from an implied "nearest" to `station_index` so the index is visible in the reply.

- Note, not a gap: another session was editing this same checkout throughout (storm/thunder
  work in `world_clock.gd`, `sky_lighting.gd`, `sound_manager.gd`). The full suite I ran was
  therefore over a tree containing their in-flight changes, and `CLAUDE.md` and
  `log-devtools.md` both ended up holding two sessions' edits. Committing meant staging one
  hunk of `CLAUDE.md` via `git apply --cached` rather than the file. Worth knowing before
  trusting a `git status` in this repo.

## 2026-08-03 — Lightning: bolts, flash and thunder during storms (gather-j7n)

- Value: **warranted** — runtime proved two architectural claims that neither the diff nor
  the 529-test suite can reach, because both are properties of how three canvases compose
  rather than of any one function's return value.
  - Expected: that folding the flash into the tint before `SkyLighting`'s three writes would
    carry it to the ocean for free and cancel itself over the HUD. I believed it from
    reading `apply()`, but "the sea flashes too" and "the HP bar does not strobe" are
    exactly the kind of claim that reads as true in a diff and is false on screen — the
    pale-green-lantern-blob note in this same file is the precedent.
  - Got: with `set-game-speed 0.02` stretching a 0.55s envelope into something samplable,
    four consecutive `world_clock` reads gave
    `flash=0.238/0.476/0.715/0.812` with `world_tint` climbing `[0.892,0.941,0.991]` ->
    `[1.305,1.377,1.450]` and `ocean_color` climbing `[0.0,0.561,0.855]` ->
    `[0.0,0.821,1.251]` alongside it. The sea brightens with the land, above unity, on the
    same write. And multiplying the two reported tints per channel gave
    `PRODUCT=[1.0,1.0,1.0]` at every flash level — the HUD reciprocal cancels the flash
    exactly, so the bars render at authored colours through the whole bolt.
  - Cheaper: nothing for those two. The unit tests pin the envelope's shape (two peaks,
    zero at both ends) far more precisely than any runtime sample, and they are 4s — but no
    test in this project can observe a CanvasModulate, a ColorRect and a Control's modulate
    agreeing with each other. The mutation check below was cheaper than the runtime session
    and found a different, equally real thing.

- Note, not a gap: a **mutation check earned its keep again**, and this is the second
  consecutive entry saying so. `test_the_wait_for_the_next_bolt_survives_a_real_round_trip`
  passed on first write; replacing `elif stored_gap > 0.0:` with `elif false:` in
  `world_clock.gd` turned the suite to `exit 1` /
  `[FAIL] test_the_wait_for_the_next_bolt_survives_a_real_round_trip`, which is the only
  reason I trust it. Worth noting *why* the test was needed at all: the subagent's own
  tests in `test_world_clock.gd` feed `loadObject` hand-built dictionaries, so every one of
  them would still pass if `saveObject` stopped writing `lightning_time_left` entirely and
  the countdown were lost on every real save. Routing one test through `saveObject()` is
  what closes that, and it belongs in `test_save_fidelity.gd` rather than beside the others.

- Gap: **`launch --isolated` half-applies its isolation, which is worse than not applying
  it.** `python tools/devtools.py launch --isolated` printed
  `session: 73c99d1d` / `userdata: C:\...\Temp\devtools_userdata_lage9wvx` and told me to
  pass both on subsequent calls. Doing exactly that gave `game not running`, as did
  `--userdata` alone, as did the default bus. `ls` on the printed userdata dir showed it was
  never created; the game had in fact taken the session and was writing
  `devtools_log_73c99d1d.jsonl` into the DEFAULT `app_userdata/Gather`. So the session half
  works and the userdata half silently does not. Workaround: drop `--userdata` and call
  `--session 73c99d1d` against the default dir, which answered immediately.
  This matters more than an ordinary ergonomics gap because `--isolated` is the documented
  escape hatch for the one-instance-at-a-time rule: it tells you that you are isolated from
  other instances while leaving you sharing their `user://`, screenshots and baselines. A
  second Godot was in fact live in this checkout throughout this session.
  - [G-115] status: open | seen: 1 | harness: unread (bridge was down when I asked)
  - Improvement: have `--isolated` fail loudly if the child's userdata dir does not exist a
    second after launch, rather than printing a path nothing will ever write to. Passing
    `GODOT_USERDATA` through to the spawned process — or `--userdata` straight to the game —
    would fix the underlying cause.

- Gap: **`harness-version` cannot be answered without a running game, so the field it exists
  to fill is unfillable at the moment you write the log.** `python tools/devtools.py
  harness-version` after `quit` returned `game not running: 'harness_version' was never
  picked up`. Every entry in this file is written after the session is over, which is
  precisely when the bridge is down. Workaround: none — the `harness:` field above says
  "unread" rather than carrying a number I would have had to copy from a neighbouring entry
  and might have been stale.
  - [G-116] status: open | seen: 1 | harness: unread
  - Improvement: read the client-side revision from disk when the bridge is down and report
    it alone, flagged as client-only, instead of failing the whole verb.

## 2026-08-04 — reshaped the XP curve and closed the replanted-berry-bush XP faucet

- Value: **inconclusive** — this container has no Godot binary at all, so nothing in the
  harness ran; the arithmetic half was verified against a reimplementation instead.
  - Expected: `/verify` to fail two existing curve guards by design
    (`test_a_single_branch_is_reachable_in_one_run` at 400 and
    `test_the_opening_does_not_hand_out_six_points` at 160, both calibrated on the broken
    shape), pass the rest, and — at runtime — show `add_xp` advancing `next_level` to a
    threshold that matches `cost_of_level`.
  - Got: nothing from the harness. `python3 tools/devtools.py harness-version` returned
    `game not running: 'harness_version' was never picked up (2.0s grace...)` and
    `find / -iname "*godot*"` found no engine, so lint, tests and the bridge were all
    unavailable. Substituted a Python mirror of `cost_of_level` / `xp_for_level` (GDScript
    `round()` semantics included) asserting the four invariants the new tests assert:
    monotone steps, no step below `XP_FIRST_LEVEL`, `xp_for_level(L) == sum(cost_of_level)`,
    and `max marginal <= XP_STEP_CAP`. It printed `invariants OK; max marginal = 150` and the
    guard values `L7 = 291`, `L11 = 574`, `L46 = 5529`, which is how the two revised bounds
    were chosen rather than guessed.
  - Cheaper: nothing cheaper existed here. On a machine with the engine this wanted the full
    `/verify`: the curve is pure arithmetic and a Python mirror covers it, but
    `BerryBush.was_planted` surviving a real save/load through `SaveLoad.late_load` is a
    runtime claim the unit round-trip only approximates.

- Gap: **the harness cannot report that it is absent.** Every entry point fails with a
  message about the *game*, not about the toolchain: `devtools.py harness-version` says
  `game not running`, and the documented lint/test commands are `godot --headless ...`, which
  in a container without the binary is a shell `command not found` rather than anything the
  harness accounts for. Exit code `2` is documented as "the runner couldn't run", but there is
  no way to reach a runner to get a `2`. Workaround: `find / -iname "*godot*"` to prove the
  engine is missing, then a hand-written Python mirror of the arithmetic under test, and a
  handoff that says plainly which claims are unverified.
  - [G-113] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `python tools/devtools.py doctor` (or a `--check` on the existing verbs)
    that resolves the Godot binary first and distinguishes "no engine on this machine" from
    "engine present, game not running" from "wrong `user://`". It would also give `/verify` a
    single honest early exit on a CI or cloud checkout, instead of three commands that each
    fail for a different-looking reason.

## 2026-08-04 — planting a berry bush no longer pays build XP

- Value: **inconclusive** — same container, still no Godot binary, so nothing ran. The change
  is one overridable predicate and two predicate tests.
  - Expected: `--file test_build_xp` to pass, and a runtime `berry_bushes` + `player_state`
    pair before and after planting on virgin ground to show `xp` unchanged where it used to
    tick by 1.
  - Got: nothing from the harness — see G-113 in the previous entry, hit again below. The one
    thing reading the code did settle is that skipping `_award_build_xp()` also skips the
    `built_cells` write, so a cell a bush was planted on still scores for a wall put up there
    later; that is a claim about a ledger nobody writes to rather than about behaviour, so a
    test for it would have asserted only that a fresh cell pays. Wrote it, saw it could not
    fail, deleted it.
  - Cheaper: reading `game_item_placeable.gd:18-28` was the whole verification available here,
    and for the predicate half it is genuinely sufficient. The runtime run is still owed for
    the placement path, which is where the `slot_data.count` check that gates the award lives.

- Gap: **`--find-orphans` would have flagged the honest version of this change.** The new
  `awards_build_xp()` has exactly one non-test caller (`_place`) and its override has none at
  all — an override is called through the base, which a call-graph walk over `awards_build_xp()`
  cannot see. Nothing was run, so this is a prediction rather than an observation, but it is the
  second time this session a legitimate seam looked orphan-shaped: `cost_of_level()` was given
  callers in the debug panel and the devtools status partly for that reason, which is a design
  decision made to please an advisory linter.
  - [G-114] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `--find-orphans` resolve virtual dispatch — a method that overrides or is
    overridden by another in the project is reachable if any of its siblings is called. Failing
    that, let a `## @orphan-ok` doc tag suppress one finding, so the advisory can be answered in
    the code instead of by adding callers.

- Gap: **the harness cannot report that it is absent** (G-113, second hit this session). Same
  shape: the follow-up change needed the same lint + `--file test_build_xp` run and had the same
  three unrelated-looking failures available to it.
  - [G-113] status: open | seen: 2 | harness: 0.8.0

## 2026-08-04 — deleted the build-XP award and the ledger that bounded it

- Value: **inconclusive** — third change this session in a container with no Godot binary
  (G-113, third hit). Nothing ran.
  - Expected: lint to be the load-bearing check here rather than the tests, because this is a
    deletion across six files — a missed reference is a parse error, which is exactly what
    `lint_project.gd` catches and what no unit test would reach.
  - Got: nothing from the harness. Substituted a repo-wide grep for the five removed symbols
    (`XP_BUILD`, `award_build_xp`, `built_cells`, `awards_build_xp`, `_placed_tile_position`),
    which came back with three hits, all of them prose in the comment that records the removal.
    That is weaker than lint in one specific way it cannot cover: grep proves no *name*
    survives, not that every remaining call site still type-checks — `_place()` lost a
    parameter's worth of work and `place_tile_real` lost a local.
  - Cheaper: nothing available. Note that lint here would have been *more* valuable than usual
    and was the one thing unavailable, which is the opposite of the usual "tests passed,
    confirmed what I knew" shape.

- Gap: **the harness has no way to check that a deleted mechanism is actually unreachable.**
  The award was removed in six places and the only evidence available offline was grep for the
  names. `scripts-seen` says which scripts entered the tree, and `place_tile_real` reports an
  xp delta, but neither answers "is this code path gone" — the first is too coarse and the
  second needs a running game and a hand-driven placement. What was wanted was a static
  reachability question: does any path still reach `LevelUpManager.add_xp` from a placement?
  - [G-115] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `python tools/devtools.py callers SYMBOL [--transitive]` that walks the same
    parsed scripts `--find-orphans` already builds a call graph over, and answers it in the
    other direction. `--find-orphans` has the graph and only asks "who is called by nobody";
    the inverse question is one traversal away and is what a deletion needs.

- Gap: **the harness cannot report that it is absent** (G-113, third hit this session).
  - [G-113] status: open | seen: 3 | harness: 0.8.0


## 2026-08-04 — Charged skeletons: lightning-struck skulls that upgrade workers and turrets (gather-8ft)

- Value: **warranted** — runtime found a real defect in my own test method, and settled four
  claims the suite structurally cannot reach.
  - Expected: the unit tests to cover the arithmetic and the save payload, and runtime to be a
    formality confirming the blue actually lands on a sprite.
  - Got: four things. (1) The **mutation check exposed a test with no teeth**, and it is the
    `gather-1t9` failure in the wild: replacing the `typeof` guard in
    `normalize_enemy_entry` with `raw.get("charged") == true` left the file reporting
    `Total: 540 | Passed: 11 | Failed: 0` with **two SCRIPT ERRORs on stderr and nothing
    else** — the raise aborted the static, `-> Dictionary` returned an empty one, reading the
    missing key aborted my test too, and a `-> String` abort returns `""` and counts as a
    pass. Adding `assert_true(restored.has("charged"))` first turns it into a real
    `exit 1 / [FAIL]`. (2) The tint lands on the right node: sprite `(0.55, 0.85, 1.6)`,
    enemy node `(1.0, 1.0, 1.0)` — so a charged skeleton still flashes white when hit.
    (3) The whole drop chain, as data: `ground_drops` went from `[]` to
    `['String', 'Gold Coin', 'Bone', 'Charged Skull', 'Gold Coin']`. (4) Both upgrades and
    their idempotency: worker `20.0 -> 10.0`, turret `1.0 -> 0.55`, and **still `0.55` after
    four `make_charged` calls** rather than `0.55^4`, which is the `Timer.start()`-assigns-
    `wait_time` trap that `_base_fire_interval` exists to avoid.
  - Cheaper: for the arithmetic, yes — `chop_seconds_for` is a static and the tests are 4s.
    For nothing else here. No headless test in this project can observe a sprite's modulate,
    a CPUParticles2D emitting, or a Timer's live `wait_time` after a load.

- Note, not a gap: I twice asserted against **the wrong node**, and both times the harness
  gave me the evidence to catch it rather than a false pass. First a reload left two enemies
  in the tree — `Enemy` (freshly spawned, white) and `@CharacterBody2D@292` (restored,
  charged) — and reading the stable-looking path said the restore had failed when it had not.
  Then `run-method _on_died` on the first auto-named body killed a **spider**, which
  `ground_drops` reported as `['String', 'Gold Coin']` — String is spider loot, and that one
  word is the only reason I did not record "the skull does not drop" as a finding. The lesson
  is narrow and worth keeping: after a load, an auto-named node is the restored one and the
  human-readable name is usually something else. Enumerate and check a property, never trust
  a path that looks right.

- Gap: **`get-state` cannot see into a `Resource`-typed property, which makes the most common
  "what is on the ground / in this slot" question unanswerable.** `get-state --node
  .../PickUps/PickUp --property slot_data` returns
  `slot_data: ():<Resource#-9223371682201202966>`, and the same for the sprite's
  `texture: ():<AtlasTexture#...>`. Every inventory slot, every pickup and every AtlasTexture
  in this project is behind that wall. Workaround: I added a project verb
  (`charged_state` -> `ground_drops`) that walks the pickups and reports `slot_data.item.name`
  — which works, but it is a bespoke verb per Resource-shaped question, and the generic
  primitive should not need one.
  - [G-117] status: open | seen: 1 | harness: 0.8.0
  - Improvement: let `--property` take a dotted path (`--property slot_data.item.name`), or
    have `get-state` expand a Resource one level into its script variables instead of
    printing an object id. One level would have answered this without a new verb.

- Gap: **`step-time` caps at 60s, and the cap is not discoverable before you hit it.**
  `step-time --seconds 90` returned `Failed: step_time refuses 90.000s; the maximum is 60.0s`.
  The message is good; the problem is that spawning enough enemies to test against needs
  minutes of game time, so this is two or three calls where the caller thinks in one. Not
  a bug — the bus serves one command at a time and a long block would look like a hang.
  - [G-118] status: open | seen: 1 | harness: 0.8.0
  - Improvement: mention the 60s ceiling in the `step-time` row of the CLAUDE.md
    cheat-sheet, so it is read before it is discovered.

## 2026-08-04 — Charged skeletons reworked to a netted enemy; visible bolt; darker storms (gather-8ft)

- Value: **warranted**, and decisively — a screenshot caught a defect that every property read
  in the session called correct.
  - Expected: the rework to be verifiable from `charged_state` and `get-state`, and the new
    bolt to be confirmed by the node existing with the right z_index and alpha.
  - Got: the node checks all passed and the bolt was still **wrong on screen**. `get-state`
    reported `z_index: 400`, two `Line2D` children and `modulate.a: 0.76` — every one of those
    correct — while the actual frame showed a near-straight vertical line that read as a laser.
    `BOLT_JAG` was 9.0 across a 260-unit drop, under four degrees. Worse, the first fix (tripling
    the jag) still looked straight over the lower half, because the taper `* (1.0 - f)` spent
    the wander at the top of the arc, mostly above the visible area. Neither is observable from
    any property: the geometry was in `points`, which reads back as a `PackedVector2Array` of
    plausible numbers. Only the PNG showed it.
  - Cheaper: nothing. This is the case the "only open a screenshot when a genuine visual
    regression is suspected" rule is about, and the suspicion came from the user, not the
    harness — no gate in this project can assert "reads as lightning".

- Note, not a gap: the same run confirmed the darker-storm change as **data before pixels**,
  and that ordering was worth it. `world_clock` gave `world_tint [0.5, 0.55, 0.66]` against a
  clear day's `[1,1,1]` and an ocean tracking it from `0.596` to `0.328`, with `flash: 0.0` so
  nothing was being confounded by a bolt still fading. The screenshot then only had to answer
  "does that read as a storm", not "did the number apply". Reading the tint first is what made
  the screenshot a one-question check.

- Note, not a gap: **a subagent's tool-call markup ended up inside a source file.**
  `test/unit/test_charged_skeleton.gd` was written with a trailing literal `</content>` and
  `</invoke>`, which lint caught immediately as `Parse Error: Unexpected "<" in class body` at
  line 288. Worth recording because the failure was loud and instant — lint named the file and
  line — and because the same class of corruption inside a comment or a string would not have
  been. The fix was two lines; the lesson is that the parse gate is what makes fanning out
  safe, not the agents' care.

- Gap: **there is no way to press a UI button from the harness, so panel wiring is verified one
  layer below what ships.** I added weather / bolt / strike-a-skull controls to
  `ui/debug_panel_ui.gd` and verified them by calling `_on_set_weather`, `_on_strike` and
  `_on_charge_skeleton` through `run-method` — which proves the actions, not the buttons.
  `scene-tree` truncates before the World tab's children, so I could not even enumerate the
  Buttons to confirm `_build_world_tab` had produced them, let alone emit `pressed`. Workaround:
  test the callables directly and accept that a mis-wired `pressed.connect` would ship green.
  - [G-119] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `press --node PATH` verb that finds the nearest `BaseButton` and emits
    `pressed`, plus a `--filter`/`--depth` on `scene-tree` so a deep UI subtree can be listed
    without returning the whole scene.

- Gap: **`step-time` caps at 60s.** Hit again while waiting for skeletons to spawn so there was
  something for a bolt to strike; needed three calls where the task was one wait.
  - [G-118] status: open | seen: 2 | harness: 0.8.0
  - Improvement: unchanged — document the ceiling in the cheat-sheet row.

## 2026-08-04 — Visible bolt on a skull strike, instant thunder, and a shader that ate `modulate`

- Value: **warranted** — a pixel sample overturned a conclusion that four separate property
  reads had all confirmed, and found a bug older than this feature.
  - Expected: the charged skeleton's blue to be a tuning problem. `get-state` reported
    `Sprite2D.modulate` as exactly the authored `(0.28, 0.58, 1.85)`, `visible: true`, one
    Sprite2D child, no code writing modulate anywhere in `enemies/`. Every reading said applied.
  - Got: it was never rendering. Sampling the brightest pixel inside each skull's computed
    screen rect gave **`B-R = +41` for the charged one and `B-R = +41` for a plain one** —
    identical hue, the charged one merely brighter because it stood in the lantern. That
    number is what turned "the tint is too subtle" into "the tint is not being drawn", which
    no property read in this project can distinguish. The cause was
    `assets/shaders/solid_color.gdshader` doing `COLOR = mix(texture(...), ...)` — overwriting
    COLOR and discarding the vertex colour Godot puts `modulate` in. **It also silently broke
    `Enemy._death_pop`**, which tweens `modulate:a` to 0 so corpses fade; they have been
    popping out at full opacity, which is the exact thing that tween was written to fix.
  - Cheaper: nothing, and I tried the cheaper things first — four `get-state` reads and three
    screenshots, all of which I misread. What settled it was arithmetic on pixels, not looking.

- Note, not a gap, and the reason this entry exists: **I asserted against the wrong node three
  times in one session** and twice reported it as a finding before checking. A reload leaves the
  restored enemy auto-named `@CharacterBody2D@NNN` while the human-readable `Enemy` is a freshly
  spawned one; `run-method _on_died` on the first auto-named body killed a spider; and a skull
  standing next to the player was a plain skeleton while the charged one was 130 units off
  screen. The habit that actually works is the one used at the end: enumerate the candidates,
  read a discriminating property off each (`type`), and compute the screen position from
  `global_position` and the camera's zoom rather than trusting which sprite looks adjacent.

- Note, not a gap: `charge_skeleton` returning `success: false / "no live plain skeleton to
  strike"` was mistaken for a broken bolt because the message was piped to /dev/null while
  grepping the scene tree for a node. The verb was right and the reading was wrong. Suppressing
  a verb's `message` to grep its `data` throws away the half that explains the other half.

- Gap: **`node-bounds` is Control-only, so there is no way to ask where a world sprite is on
  screen.** `node-bounds .../Sprite2D` returns `Failed: Node is not a Control`. Every visual
  check on a game object therefore needs the camera transform reconstructed by hand
  (`(world - player) * zoom + viewport/2`), which is three devtools calls and an assumption
  that the camera is centred on the player. Workaround: exactly that, scripted.
  - [G-120] status: open | seen: 1 | harness: 0.8.0
  - Improvement: make `node-bounds` accept any `CanvasItem` and return its screen-space rect
    via `get_global_transform_with_canvas()`. That one change turns "is this thing drawn, and
    what colour is it" from a scripted reconstruction into two calls.

- Gap: **no way to sample the framebuffer, so colour claims need a PNG decoder.** Confirming
  "this sprite renders blue" meant writing a zlib/PNG reader inline to read pixels back. It
  worked and it is what caught the shader, but it is ~30 lines of scanline defiltering that
  every visual assertion would have to carry.
  - [G-121] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `sample-pixels --rect X,Y,W,H` verb returning mean/brightest/dominant RGB
    from the same capture path `screenshot` already uses. Colour regressions become assertable
    instead of eyeballed.

## 2026-08-04 — Blue skeleton as real art, and backing out a shader fix's side effect

- Value: **warranted** — a pixel A/B proved a regression the user had spotted and I would
  otherwise have argued was correct behaviour.
  - Expected: the report "the player looks different" to be unrelated to my change, since I had
    only touched a shader to make `modulate` work and the player's material sets
    `flash_intensity = 0.0`, which passes the texture straight through.
  - Got: it was mine, and measurably. Sampling the most blue-dominant pixel on the player at a
    fixed hour, with only the shader body swapped between runs: **old `(0, 152, 220)` day /
    `(0, 129, 236)` night, new `(0, 91, 190)` / `(0, 77, 204)`.** `COLOR` carries the
    canvas-wide `CanvasModulate` as well as the node's `modulate`, so `texture * COLOR` put the
    player and every enemy under the day/night tint for the first time — they had never been,
    because the shader had always discarded COLOR. That is a change to how the whole cast is
    lit, not a bug fix, and it arrived as a side effect of fixing a corpse fade.
  - Cheaper: no. Three screenshots across this session all failed to tell me the player had
    changed — I looked at several and never noticed. Two numbers did it immediately.
  - The fix that survived is `tex_color.a *= COLOR.a` rather than `tex_color *= COLOR`: alpha
    only, so `Enemy._death_pop`'s `modulate:a` tween works and RGB is untouched. Verified by
    re-running the same sample: **`(0, 152, 220)` / `(0, 129, 236)`, pixel-identical to the
    original.** That equality is the whole argument that the regression is gone, and no
    screenshot could have supplied it.

- Note, not a gap: the charged skeleton is a **generated sprite** now rather than a `modulate`,
  after the user said the tint read wrong. Worth recording because the two approaches failed
  differently and the harness only caught one: the tint not rendering at all was findable by
  sampling pixels, but "this tint reads as a skeleton behind blue glass rather than as a blue
  skeleton" is a judgement no assertion in this project can make. The generator's existing
  `_recolour_cell` multiplies a tint into the source, which preserves the source's hue
  relationships and is exactly wrong for a near-white skull; the new `_ramp_cell` remaps
  luminance through three stops instead. That distinction is aesthetic and was decided by
  looking, correctly.

- Gap: **[G-121] a `sample-pixels` verb** — hit again, and it is now the single highest-value
  missing verb in this harness. Three separate findings this session came from reading pixels
  back (the bolt reading as a laser, the charged tint never rendering, and this regression),
  and each one needed the same ~30 lines of inline zlib/PNG scanline defiltering pasted again.
  - [G-121] status: open | seen: 2 | harness: 0.8.0
  - Improvement: unchanged — `sample-pixels --rect X,Y,W,H` returning mean/brightest/dominant
    RGB from the capture path `screenshot` already uses. Every one of the three findings above
    becomes a one-line assertion instead of a script.

## 2026-08-04 — three README clips: workers, weather, charged skulls

- Value: **warranted** — the dry run is the entire reason two of the three clips are usable,
  and it produced two claims no diff could have.
  - Expected: that the already-written `workers` clip would record as-is (it was committed and
    lint-clean), and that two freshly authored clips would need only a framing check.
  - Got: `workers` reported `the action press did not open the chest` on a beat whose input
    path was correct — `ui/inventory_interface.gd:266` force-closes a container more than 15px
    from the player, and `_walk_to` parks the player on the tile centre 16px away, so the bag
    opened and shut inside two frames. And `charged` passed one dry run between two failures,
    failing them *differently*: once `never got within net reach of the charged skeleton`,
    once `the net beat finished without a charged skull in the inventory`. One run of either
    clip would have been read as a pass.
  - Cheaper: nothing. Both are behaviours of a running game against a moving target; neither
    lint nor the 540 unit tests can reach a coroutine that only exists to be filmed.

- Note, not a gap: **one clean dry run is not evidence for a clip that touches an enemy.** The
  three-in-a-row rule this session adopted is what turned `charged` from 1/3 to 3/3, and the
  fix it forced (`_chase`, re-choosing direction every frame and re-closing after a miss) is
  better choreography as well as more reliable — a single held direction against something
  whose whole behaviour is that it moves was the bug in both failures.

- Note, not a gap: two agents authoring clips in parallel both wrote `_beat_storm`, and
  GDScript surfaced the duplicate as `Could not parse global class "DemoDirector"`. The error
  names the class, never the collision. Beat helpers in a multi-clip file want a clip prefix.

- Gap: **[G-121] a `sample-pixels` verb** — hit a third time. The claim "the sea failed to dim
  with the land at dusk" looked true in a scaled-down frame and was false: sea and land dimmed
  by 0.457 vs 0.459 at dusk and 0.338 vs 0.337 in the storm. Getting that answer meant
  extracting frames with ffmpeg and sampling them with PIL, outside the harness entirely.
  - [G-121] status: open | seen: 3 | harness: 0.8.0
  - Improvement: unchanged — `sample-pixels --rect X,Y,W,H` returning mean/brightest/dominant
    RGB from the capture path `screenshot` already uses.

- Gap: **[G-122] no way to dry-run a director clip without owning the single-instance bus** —
  both clip-authoring subagents ended their reports with the same six-to-eight item list of
  "things only a runtime run can confirm", because the bus is one command/result file pair and
  a recording was live on it. Their lint-and-tests pass proved the file compiled and nothing
  else; every framing, pacing and reach claim came back to the orchestrator unverified.
  - [G-122] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a headless `clip-preview --clip NAME --at 2,6,13,24` that runs the director
    offscreen and writes a handful of PNGs, with no bus and no `--write-movie` pass. Framing
    and reach are most of what a clip author cannot check, and neither needs a window, audio,
    or the ~10 minutes a real take costs.

## 2026-08-04 — design brainstorm: replayability and feature ideas (no code changed)

- Value: **inconclusive** — no harness run at all; this turn produced ideas, not a diff, so
  there was nothing for lint, tests or the bridge to assert against.
  - Expected: nothing — the question was "what is this game missing", which runtime cannot answer.
  - Got: n/a. Grounding came from reading `systems/skill_tree.gd` and `items/resources.gd`
    directly (~4s of Read) plus the architecture notes in CLAUDE.md.
  - Cheaper: nothing cheaper existed. Reading the two tuning files was already the minimum.

- Gap: **no gaps this turn** — the harness was not exercised, so it could not fall short.
  One observation for later: none of the existing verbs answer "how long does a run last"
  or "what does the player have at day N", which is the kind of question the proposed
  run-ending/score feature (idea 5) would immediately want. Not filing it as a numbered gap
  until that feature is approved and the need is real rather than hypothetical.

## 2026-08-04 — wrote docs/idea.md (design ideas doc; no game code changed)

- Value: **inconclusive** — nothing executable changed, so lint, tests and the bridge had
  nothing to assert. A markdown file cannot be verified by the harness.
  - Expected: nothing. The turn was a Write plus two `ls` calls.
  - Got: n/a.
  - Cheaper: nothing — this was already the minimum.

- Gap: **no gaps this turn.** Noting once, without filing a number, that the per-idea
  "touches" notes in the new doc were assembled by reading CLAUDE.md and two registry files
  by hand for the second turn running. If that becomes a third time it is a real gap and
  gets an id — but it is a skill-shaped gap, not a harness-shaped one, so it likely does not
  belong in this log at all.

## 2026-08-04 — implemented docs/idea.md section B: night raids, run-end score card, quest board

- Value: **warranted** — three runtime bugs that lint and 585 unit tests all passed clean on,
  and one of them was the core mechanic of the feature not working at all.
  - Expected: that the raid would spawn the right enemies with the right stats (which lint and
    the new curve tests already covered), and that the card and panel would look roughly right.
  - Got: three claims no diff could make.
    1. `get-state` on a raider twice, eight seconds apart: `global_position` went from
       `{"x": 205.359, "y": 3.474}` to `{"x": 205.494, "y": 3.496}` — 0.13px while
       `velocity` read `{"x": -9.997, "y": 0.215}`. Raiders were spawning on land not walkably
       connected to the player and pushing into the sea forever. Right type, right toughness,
       right velocity, and a raid that could never arrive or be cleared.
    2. After fixing placement, one raider in seven still never moved: this project has no baked
       navigation (`world_tile_set.tres` declares source groups, nothing is a
       `NavigationRegion2D`), so `get_next_path_position()` returns a straight line and the
       enemy jams on the first tree. Invisible until now because `EnemyIdle` only chases inside
       30px.
    3. The score card rendered `Enemies slain 0` for the very boss whose death produced it,
       while `run_summary` reported `enemies_killed: 1`. `Enemy._on_died` awaits 0.2s of
       particles, so the run-ending listener on the same `died` signal finished first.
  - Cheaper: nothing. (1) and (2) need a physics world and a real tilemap; (3) needs two
    listeners on one signal in a live frame. The screenshot alone would have caught (3) but not
    (1) or (2) — raiders standing still off-screen look identical to raiders walking.

- Value note on the headless half: the unit suite was **not** overkill either, but for a
  different reason than usual — `test_hud_toolbar.gd`'s existing width budget caught the fifth
  toolbar button overflowing a 390px phone by 2.2px, which is a thing no runtime session at
  1920x1080 would ever have shown.

- Gap: **[G-123] no verb kills an enemy through its real death path** — `clear-nodes --group
  Enemy` frees nodes with `queue_free()`, which skips `HealthManager.died`: nothing drops, no xp
  is paid, `RunStats` never counts it and the boss's own `died` connection never fires. Testing
  "the boss ends the run" was therefore impossible with the shipped verbs — a test built on
  `clear-nodes` proves the nodes are gone and nothing else. Worked around by writing a project
  verb, `kill_enemy --args '{"type":"Elite"}'`, which drives `take_damage`.
  - [G-123] status: open | seen: 1 | harness: 0.8.0
  - Improvement: this is arguably project-specific (it needs to know about `HealthManager`), but
    the *shape* is not: `clear-nodes` is the only generic way to remove a node and it is always
    the wrong one when the node's removal has game meaning. A generic
    `clear-nodes --via-method <name>` — call this method instead of `queue_free()` — would have
    covered it with no game knowledge at all.

- Gap: **[G-124] `get-state` on a String property is unreadable through the CLI** — reading a
  Button's `text` back to confirm the two-step NEW RUN confirm returned
  `Binary file (standard input) matches` from grep, because the reply carries embedded nulls.
  `tr -d '\000'` worked around it. Small, but it turns a one-line assertion into a pipeline.
  - [G-124] status: open | seen: 1 | harness: 0.8.0
  - Improvement: strip or escape non-printable bytes in the CLI's text output path.

- Non-gap worth recording: `start_raid` was written to force a raid without touching the clock,
  and the game correctly refused to let it — `RaidDirector._process` ends any raid running in
  daylight, so the verb reported a cheerful "night 9 raid started: 7 raiders" for a raid that was
  over one frame later with nothing spawned. The harness did not miss this; the harness is how it
  was found, one `raid_state` call after the "successful" one. It is now the `strike_lightning`
  pattern: the verb moves the clock to night first and says so in its message.

## 2026-08-04 — merged feature/run-shape into main, re-ran the gate on the merged tree

- Value: **overkill** — everything passed and confirmed what the pre-merge runs already said.
  A `--no-ff` merge of a branch that was never diverged from cannot change behaviour, and the
  three features had each been driven at runtime on the branch an hour earlier.
  - Expected: nothing new. This was a merge-commit sanity pass, not an investigation.
  - Got: exactly that — lint 0/0, 585/585, 0 SCRIPT ERROR, and a clean boot answering
    `7 offered`, `no raid running`, `run in progress` at 120 FPS with `+0` orphan growth.
  - Cheaper: `git log --oneline` and the branch's own green run, ~0s. The one thing the launch
    genuinely added over that is proof the three new `Systems` nodes still `_ready()` in a tree
    assembled from the merged `main.tscn` — worth about 20 seconds once, and not worth
    repeating per merge.

- Gap: **no gaps this turn.** Both gaps from the previous entry ([G-123], [G-124]) were hit
  during that session and are already filed; nothing new surfaced here.

## 2026-08-04 — three README clips for raids, the quest board and the run's ending

- Value: **warranted** — the dry-run loop produced four claims the diff could not, and one of
  them was a real game bug rather than a clip bug.
  - Expected: choreography errors — a swing mistimed, a panel opened a frame early. The clips
    were expected to be the hard part and the game underneath them to be fine.
  - Got: (1) `island_census` + `run_summary` after a `boss` dry run answered
    `defeated: False, run_ended: False` while `enemies_killed: 1` — a boss restored from a save
    is never wired to `_on_boss_died`, so killing it ended nothing: no reward chest, no
    `bosses_defeated`, and since gather-1zv no run summary at all. `_populate_boss` skips
    `_spawn_boss` for a boss already standing, and `_spawn_boss` is the only place `died` was
    connected. Filed and fixed (`_watch_boss`). (2) `_chase` closing to NET_REACH (13px) asks for
    a distance the physics refuses — enemy bodies are the hurtbox AND are solid to the player, so
    the elite rests at ~14px and a raider at 16-22. The beat's `continue` meant the player never
    swung once, with `damage` reading 13 the whole time. (3) The sword only swings sideways, so a
    raider standing directly above the player is inside any distance envelope and unhittable.
    (4) `QuestUi._refresh` frees and rebuilds cards in one frame, and `add_child` resolves the
    resulting name collision by DISCARDING the wanted name — the live card comes in as
    `@PanelContainer@426`, so exact, prefix and containment matches all fail identically.
  - Cheaper: nothing. Every one of these is invisible to lint and to the unit suite, and three of
    the four are invisible to a screenshot as well — the boss one especially, where the fight
    looks completely normal and the only symptom is a card that does not appear.

- Gap: **a dry run does not reproduce the recording's timestep, and the skill's "three clean dry
  runs" rule is not sufficient because of it.** `capture_clip.py` passes `--fixed-fps 30`; a dry
  run launched per the skill (`godot --path . --mute`) runs uncapped. The player therefore moves
  in sub-pixel steps in a dry run and 1.7px steps in the recording, and a chase settles at a
  different distance in each. Three clean dry runs of the `raid` clip were followed by a recording
  whose fight never finished — ten minutes of wall time to learn something a one-minute run could
  have told me.
  - [G-125] status: open | seen: 1 | harness: 0.8.0
  - Improvement: launch dry runs with `--fixed-fps 30` (the workaround used here, and it
    reproduced the failure on the first run). Worth putting in the skill directly, and worth
    `capture_clip.py` growing a `--dry-run` that launches with the recording's flags minus
    `--write-movie` so the two can never drift apart.

- Gap: **the notes array is a pass/fail flag with no denominator, and a stochastic clip needs
  one.** The raid clip fails roughly one run in eight, because `RaidDirector._pick_spawn_cell` is
  random and a raider can land somewhere it cannot path out of. Deciding whether that rate was
  acceptable meant hand-rolling a bash loop and eyeballing eight lines; `demo_state` has no notion
  of "run this clip N times and report the failure rate", and `verify-runs.jsonl` records gate
  runs rather than clip takes.
  - [G-126] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `demo_clip --args '{"name":"raid","repeat":8}'` that re-runs in-process and
    returns per-run notes, or a `capture_clip.py --dry-run --repeat N` that prints the rate. Either
    turns "is this clip stable" from a judgement call into a number.

- Non-gap worth recording: the fix that actually made both fight beats reliable was to stop
  reasoning about hitbox geometry and read `health_manager.current_health` before and after each
  swing. Three separate corrections to the geometry — a bigger reach, a swing envelope, a
  vertical alignment band — were each *nearly* right and each still lost a take. Checking the
  outcome instead is two lines and is correct regardless of which of the four attack animations
  played. The director can do this only because it runs inside the game: over the bus a
  RefCounted comes back as an opaque object id, which is the same limitation `charged_state` was
  written to work around.

## 2026-08-04 — planned the raid escalation / defense / boss arc (no code changed)

- Value: **inconclusive** — a pure design turn: four read-only research agents over
  `raid_director.gd`, the turret/wall stack, `island_manager.gd` + `land_manager.gd`, and the
  XP/gold curves, then nine beads filed. Nothing was edited, so no gate ran and the harness was
  never invoked.
  - Expected: n/a — no diff to assert against.
  - Got: n/a. Worth recording *why* the harness was not reached for: every question this turn was
    "what is the current constant and which test pins it", which source and `test/unit/` answer
    directly and more cheaply than a running game. `/verify` on a zero-line diff would have been
    the definition of overkill.
  - Cheaper: nothing — reading the files *was* the cheap path, and it is what happened.

- Gap: **no way to ask the running game for a difficulty curve as data.** Calibrating the raid
  ramp meant hand-evaluating `size_for_day` / `health_mult_for_day` / `cost_for_parcel` /
  `xp_for_level` across 20+ days in prose arithmetic, and the same tables get recomputed by hand
  every time anyone touches these constants. `raid_state` reports `tonight_size` and
  `tonight_health_mult` for exactly one day, and `land_state` reports one parcel price; there is
  no verb that sweeps a pure static across a range. Two arithmetic slips in this session were
  caught only by a second pass.
  - [G-127] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a generic `curve --node PATH --method NAME --from N --to M` verb that calls a
    static/pure method over an integer range and returns the series, so "what does this ramp
    actually look like" is one call rather than a transcription. It generalises past raids —
    `cost_for_parcel`, `xp_for_level`, `cap_for_land_tiles` and `reward_for_size` all have the
    same shape, and all four are things a design change has to re-read.

- Gap: **the test suite pins tuning constants in bands, but nothing reports which band a proposed
  constant lands in without running the suite.** `test_island_manager.gd:297` gates the boss chest
  against `cost_for_parcel(MAX_PARCELS-1) * [0.15, 0.6)`, and `test_raid_director.gd:160` gates the
  days-3..22 reward sum to `(500, 5000)`. Both are the right shape of test, and both are invisible
  until a full `run_tests.gd` — so exploring "what if MAX_PARCELS were 16" is a 40-second round
  trip per candidate rather than a read.
  - [G-128] status: open | seen: 1 | harness: 0.8.0
  - Improvement: `run_tests.gd --json` already carries pass/fail; if band assertions also emitted
    the computed value and the bounds, a failing tuning sweep would say "894 not in [372, 1489)"
    instead of a message. That is a convention for `_T.assert_*` (an `assert_between`) more than a
    harness feature, but the harness is where it would have to live to be uniform.

## 2026-08-04 — the quest board was unreachable on a phone; renamed TASKS -> QUESTS

- Value: **warranted** — a real `InputEventScreenTouch` on the new button flipped
  `quest_state.panel_open` false -> true, which is the whole chain (`_button_at` hit test ->
  `send_action` -> `InputManager._input` -> `QuestUi.toggle`) and the one thing no headless test
  reaches, because both strips decide their own visibility from `DisplayServer`.
  - Expected: with a touchscreen reported, the overlay should build an eighth button
    (QuestsButton) whose rect lands on screen in the top-right cluster, and a synthesized touch on
    its centre should open the quest panel — the path headless can't exercise, since both the
    toolbar and the overlay read visibility from DisplayServer. Panel title should read QUESTS.
  - Got: `set-feature --touchscreen true` -> `MobileControls.visible: true` /
    `HudToolbar.visible: false`, i.e. the exact state the bug lived in. `QuestsButton` at
    `Rect: 1533, 162, 101x101, In viewport: True`, column-aligned under LAND with SAVE and BREAK
    beside it. Touch press+release at its centre: `panel_open = True`, title reads `QUESTS`. Two
    guards also held: a tap on SKILL with the board open left `SkillTreeUI/PanelFrame.visible:
    false` and fell through to the backdrop (closing the board) rather than firing underneath it,
    and with `disable_input` forced true the button still opened the board — `MENU_ACTIONS`
    working, not merely declared.
  - Cheaper: the two unit tests added this turn get most of it headlessly — table membership
    against `HudToolbar.BUTTON_SPECS`, `MENU_ACTIONS`, and every button's rect inside 390x844.
    What only the running game gave was the touch -> InputManager -> panel chain and the
    DisplayServer handoff between the two strips.

- Gap: **nothing can answer "what can the player reach right now" in one read, which is exactly
  the question this bug was.** The board had a key, a desktop button, a passing suite and no way
  in on a phone; finding that took forcing the feature flag, reading `visible` on two nodes,
  looking up a button path in `scene-tree`, computing a rect centre, and sending two `touch`
  events. Every one of those is available and none of them is the question. `validate-ui` reports
  0 issues for a UI whose only affordance is invisible on the current device, because an
  unreachable panel is not a layout fault.
  - [G-129] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a generic `reachable-ui` verb that walks visible `Control`s with a `pressed`
    signal or a registered input action and reports `{action, node, rect, on_screen}` — the set a
    finger or cursor could actually hit this frame. Diffing that between `--touchscreen true` and
    `false` would have named this bug outright ("`quests` reachable on desktop, not on touch")
    instead of it shipping. It generalises past touch: the same read catches a button laid out
    off-screen, one under a full-rect `MOUSE_FILTER_STOP` sibling, and one whose whole strip is
    hidden behind a device check.

## 2026-08-05 — advice-only: serverless multiplayer options

- Value: **inconclusive** — no harness verbs were run; the question was architectural and
  answered by reading `export_presets.cfg`, `player_manager.gd`, `input_manager.gd`,
  `save_load.gd` and `run_stats.gd`. Nothing changed, so there was nothing to verify.
  - Expected: that the answer would hinge on how player identity is threaded through the code.
  - Got: static reads settled it — `PlayerManager` holds one `var player: Player` with 78
    call sites across 42 files, `InputManager` emits global signals with no actor, and the
    Web export preset rules out ENet. No running game could have said this better.
  - Cheaper: nothing cheaper existed; grep + four file reads was the floor.

- Gap: no gaps this turn — the harness was not the right tool for an advice-only response,
  and its absence was not a limitation.

## 2026-08-05 — advised on multiplayer transport for the itch.io web build

- Value: **inconclusive** — no code changed and the harness was not run; this was an
  architecture question answered from `export_presets.cfg` and the browser sandbox's
  constraints, neither of which a running game can tell you.
  - Expected: nothing from runtime — the question is "what can a browser on static hosting
    do", which is settled before the game boots.
  - Got: two static reads instead. `export_presets.cfg:86-87` gives
    `variant/extensions_support=false` and `variant/thread_support=false`, which is what
    rules the GDExtension WebRTC path out of the web build and rules the itch
    SharedArrayBuffer checkbox out of the discussion.
  - Cheaper: nothing cheaper existed — two greps, ~3s, and launching the game would have
    added nothing.

- Gap: **no gaps this turn** — the harness was not exercised, so it had no opportunity to
  fall short. Filing a gap here would be noise.

## 2026-08-05 — staged a raid in the running game to screenshot an itch.io devlog draft

- Value: **warranted** — the harness was the only way to reach the frame the post needed, and
  it corrected the post's premise twice before a single pixel was captured.
  - Expected: launch, `build_demo_world`, `start_raid`, screenshot — a dense night-raid frame
    in three calls.
  - Got: `start_raid` refused with `"night 1 is a quiet night (raids start on night 3)"`, which
    is the feature's own gate telling me the demo world starts on day 1. Writing the day
    straight onto `WorldClock` and re-running gave `"night 9 raid started: 7 raiders, 1.48x
    health"`, and `raid_state` then read `live_raiders: 10, banner_showing: true` — ten, not
    seven, because the ambient trickle keeps running underneath a raid. The screenshot shows
    `RAID · NIGHT 9` with a counter of `10`, two skeletons on the player and a spider inbound;
    a day-3 shot would have been one skeleton and a `3`.
  - Cheaper: nothing. A stale screenshot or a fresh-boot grab would have shown daylight grass
    with no banner, which is exactly the "generic title-screen grab" the devlog skill warns
    reads as padding. `world_clock` also settled a question the image itself could not: the
    grass looks bright green at night, and `hud_modulate: [2.38, 2.17, 1.47]` — the reciprocal
    of the `0.42` floor — proved the tint *was* applied rather than the clock having stalled.

- Gap: **no verb sets the day, so staging any day-gated feature means writing engine state raw**
  — `python tools/devtools.py list-commands | grep -iE "day|time|clock"` returns
  `set_time_of_day`, `step_time`, `world_clock`, and none of them moves `day`. `set_time_of_day`
  takes a phase within one day; `step_time` is real-time-bounded (`--seconds 1200` for two days
  is 20 minutes of wall clock). The workaround was
  `set-state --node /root/Main/Systems/WorldClock --property day --value 9`, which is precisely
  the raw-property write CLAUDE.md warns about: it bypasses setters and signals, so it cannot
  fire `night_started`, and it only worked because `start_raid` re-reads `day` and moves the
  clock itself. A feature gated on the day that listened for a *transition* would have been
  unreachable this way.
  - [G-014] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `set_day --args '{"day": 9}'` verb in `devtools_ext/commands.gd` that
    advances the counter through `WorldClock`'s own path and emits the day/night signals a real
    rollover emits — the "a setter verb must leave the game in a state the game itself can
    reach" rule, applied to the one axis that currently has no setter. `set_time_of_day` growing
    an optional `day` field would do equally well and adds no new verb.

- Gap: **the first launch died silently and both logs were clean** — `ping` succeeded, three
  verbs answered, then `list-commands` returned `game not running` with
  `"Owner file devtools_owner.json says pid 12672 ... that process has likely exited"`.
  `.devtools/launch_stderr.log` was **0 bytes** and `launch_stdout.log` ended at
  `"Entering state: PlayerIdle"` — no error, no stack, nothing to distinguish a crash from a
  clean shutdown. A relaunch worked and the session was fine, so this cost one relaunch rather
  than an investigation, but there was no evidence available to investigate *with*.
  - [G-015] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have the owner file record the exit — a `quit`-initiated shutdown stamping
    `exit: clean` versus a `pid` that vanished without one. The client already reads the file to
    produce "has likely exited"; distinguishing "exited cleanly" from "died" is one field, and
    it is the difference between "relaunch and carry on" and "something in the diff kills the
    game after ~30 seconds".

### Skill note — `itch-devlog`

The skill's framing did the real work here: **translate, don't transcribe**. `git log` for the
session ran to 16 commits, of which 7 were docs/devtools/demo-clip commits and 3 were art and
shader fixes to features shipping in the same session. Four bullets survived. The skill's own
warning — that the failure mode is a wall of bullets including "refactored the state machine" —
is what stopped the two flash-shader fixes (`db0843d`, `2eb8923`) from becoming bullets; they
are real fixes but only to code that shipped hours later the same day, so no player ever saw the
broken version.

Two concrete improvements to the skill:

1. **It should say to check the previous devlog before writing.** The prior post
   ("Night falls, storms roll in, and berry bushes grow back") covered storms and lightning, and
   this session's charged-skeleton work is a *second* lightning feature. Without reading the
   previous post I could not tell whether "lightning charges skeletons blue" read as news or as
   a repeat. Fetching the last post's body took one call and is the only way to know where the
   last one stopped — especially when devlogs are daily and features land in related clusters.
2. **The auto-attached build needs a sharper rule than "leave it if the user pushed a build
   today".** itch had pre-attached `gather-html5.zip` v44 from "a day ago". Whether that build
   contains the work being described is not answerable from the dashboard — and here it
   provably does *not* contain all of it, since the last commit of the session sits on an
   unmerged branch (`fix/mobile-quests-button`). The skill should say to compare the build's
   upload time against the commits being written up and surface the mismatch to the user, rather
   than making it a yes/no on the calendar date.

## 2026-08-05 — answered whether the harness can stress-test game balance

- Value: **inconclusive** — question-only turn, no code changed and nothing was run; the
  answer is about what the harness *could* reach, which is settled by reading its verb list
  and CLAUDE.md rather than by exercising it.
  - Expected: nothing from runtime.
  - Got: nothing from runtime. The three tiers described (headless math on the tuning
    tables, seed/roll Monte Carlo, driving the live game) were derived from the existing
    precedents `test_ore_chain.gd:CRAFTED_HEAL_MULTIPLE` and `test_island_manager.gd`'s
    200-seed sweep, plus the single-bus constraint.
  - Cheaper: nothing — answering from the repo's own docs was the cheapest path.

- Gap: **no verb answers "what would this cost the player", so balance questions have no
  runtime primitive at all.** Every tuning read is indirect: `gather_stats` reports a gather
  in progress, `player_state` reports current totals, `run_summary` reports one finished run.
  Asking "how long to the first furnace at each pickaxe tier" means reading five files and
  recomputing by hand what the game already knows. Noting it rather than filing it as a
  harness gap, since it is project-shaped (a `devtools_ext` verb) rather than generic.
  - Improvement: a project verb `balance_table` returning the derived economy — per-resource
    xp/sec and yield/sec at each pickaxe tier, recipe cost in gather-seconds, and the level
    curve in nodes-per-level — so a balance claim is one read instead of a spreadsheet, and
    so a tuning edit can be asserted against in a unit test rather than eyeballed.

## 2026-08-05 — consolidated three stray branches and the working tree onto main

- Value: **overkill** — the running game was never launched, and it should not have been. This
  was a merge turn: the only question was whether four independently-authored changes still
  compile and pass together, and the two headless runners answer that without a bridge.
  - Expected: the `fix/mobile-quests-button` and log-only merges to be clean; the real risk was
    `worktree-agent-a7a8e6e340fa679a3`, whose `_seeded_veins_report` names
    `IslandManager.SEEDED_VEINS`, `SEEDED_VEIN_ISLAND` and `ore_veins_seeded` — a branch tagged
    `wip` that would not compile if `gather-frv` had not already landed on main.
  - Got: `lint: 0 error(s), 0 warning(s) -> exit 0` and `Total: 587 | Passed: 587 | Failed: 0`,
    with `grep -c "SCRIPT ERROR"` = 0 on the runner's stderr (the `gather-1t9` check, since a
    green suite alone is not sufficient). That settles the compile question the text merge could
    not: `git merge` resolved `commands.gd` cleanly and would have done so identically had the
    symbols been absent.
  - Cheaper: nothing meaningfully cheaper — lint alone (~10s) covered the compile risk, and the
    test suite was the incremental cost of confirming the UI merge did not regress
    `test_mobile_controls.gd`. `/verify` would have been the overkill here, not this.

- Gap: **a committed generated artifact has no link to its generator, so nothing reports it
  stale.** This turn committed `tools/balance_model.gd` alongside `.devtools/balance_model.json`,
  which is that script's output captured against some earlier tree. Lint checks scripts, the
  test runner checks tests, and `verify-runs.jsonl` records reach against the diff — none of them
  knows that a JSON file in `.devtools/` is downstream of a `.gd` file and may now disagree with
  it. Verified by hand instead: re-ran the generator and diffed
  (`resources=8 recipes=30 skills=17 quests=14 findings=19`, output byte-identical), which is a
  step that is easy to skip and silent when skipped — a stale committed model would read as
  authoritative balance data.
  - [G-130] status: open | seen: 1 | harness: 0.8.0
  - Improvement: let `devtools_config.json` declare `generated_artifacts: [{script, output}]` and
    have `lint_project.gd` re-run each generator into a temp path and compare, failing when the
    committed output differs. It generalises past this one file — the same shape covers any
    checked-in fixture with a builder, including `test/fixtures/demo_homestead_save` and the
    `build_demo_world` verb that produces it, which has already been baked wrong twice
    (`gather-3m9`).

- Improvement to the harness's own workflow, per the skill-reflection rule: the DEVELOPMENT RULE
  in `CLAUDE.md` says run `/verify` after "any gameplay, script, or scene change", which reads as
  covering a merge that touches `ui/` and `devtools_ext/`. It should not. A merge of already-
  verified branches is a *composition* check, not a behaviour change, and the honest gate is lint
  plus the suite. Worth stating the exception in the rule rather than leaving each session to
  decide it silently — the current wording makes the correct cheap choice look like a skipped gate.

## 2026-08-05 — stress-tested the balance and reported it

- Value: **warranted** — runtime produced the number the whole audit turned on, and it was not
  the number the code reads like.
  - Expected: that the mainland refills at one node per `ResourceTimer.wait_time` (24s), since
    that is the only cadence anywhere in `resource_spawn_timer.gd`. Predicted before the run
    that ~600 game-seconds would add ~19 nodes to a home island with 24 nodes of headroom.
  - Got: `island_census` twice around a timed `set-game-speed 20` window: home 195 -> 218
    (+23), forest +3, ore +1, over 611 game-seconds — **23 of 27 placements to home against a
    predicted 84.9% tile share**. The 24s tick is GLOBAL and `pick_ambient_region()` splits it
    by land tiles, so a fresh mainland gets one node per 57.7s, not per 24s. The first model
    was wrong by 2.4x at the start of the run, and every milestone derived from it was wrong
    with it.
  - Cheaper: nothing. `island_census` alone gives tile counts but not flow; the flow needed two
    reads separated by known game-time, which is the one thing no static read produces.

- Gap: **nothing reports resource FLOW, only the instantaneous census, so "is the player
  supply-bound?" takes two timed reads and hand arithmetic.** Both analysis subagents
  independently hit this and neither could answer it from the bridge. Worse, the first attempt
  produced a contaminated measurement — home gained 1 node where 19 was predicted — and there
  was no way to tell whether `set-game-speed` had applied for the whole window, because no reply
  carries elapsed game time. It took re-running with `world_clock` reads bracketing the sleep to
  get a trustworthy number.
  - [G-130] status: open | seen: 1 | harness: 0.8.0
  - Improvement: two things, both small. (a) Put `game_time` (or the frame count and
    `time_scale`) in the status provider merged into every reply, so any two replies can be
    differenced into a known elapsed interval — this is exactly the liveness argument the
    harness already makes for `status`, applied to time. (b) A generic `watch <verb> --for N`
    that samples a verb twice around a timed advance and returns both readings plus the delta,
    so "what changed over N game-seconds" is one call instead of a five-call ritual whose
    failure mode is a silently wrong denominator.

- Gap: **`run-method` replies in plain text, not the JSON envelope every other verb uses.**
  `python tools/devtools.py run-method --node ... --method add_random_resource --args "[]"`
  prints `Result: True`, so piping it to a JSON parser — which works for every `cmd` verb —
  dies with `JSONDecodeError: Expecting value: line 1 column 1`. Five parallel calls produced
  five stack traces and no data before I noticed the verb itself had worked fine.
  - [G-131] status: open | seen: 1 | harness: 0.8.0
  - Improvement: give `run-method` the same `{action, success, message, data}` envelope as the
    registered verbs, with the return value under `data.result`, or accept `--json` on it. A
    client that has to special-case one verb's output format cannot be scripted uniformly.

- Note on skills: `artifact-design` and `dataviz` both earned their load — the latter's
  `validate_palette.js` turned a guess into a check (the three-series set passes in both modes;
  one light-mode slot is sub-3:1 and needs the direct labels the charts already carry). The
  `dataviz` skill would be improved by saying plainly that plain-HTML bars are a first-class
  output and not a degraded one; the whole reference set reads as SVG-first, and for a
  report-shaped page the HTML bars were both more robust and more responsive.

## 2026-08-05 — committed the balance tests and pushed main

- Value: **overkill** — the gates were re-run before committing and told me exactly what the
  subagent had already reported an hour earlier. No code changed between the two runs except
  `tools/balance_model_impl.gd`, which no test loads.
  - Expected: the same 594/592/2 and a clean lint, since the only edit since the last green run
    was to a headless tool script outside the test path.
  - Got: exactly that — `Total: 594 | Passed: 592 | Failed: 2`, `lint: 0 error(s), 0 warning(s)`,
    no `SCRIPT ERROR`. The two failures are `test_no_loadout_wastes_extra_drop_chance` and
    `test_the_foraging_capstone_still_does_something`, both red by design.
  - Cheaper: trusting the subagent's report, which quoted the same totals line verbatim. Re-running
    cost ~40s and bought only the confirmation that my own `_points_for` edit had not broken a
    parse. Worth it as a pre-push habit, not because anything was in doubt.

- Gap: **no gaps this turn.** The harness did what it says: two commands, two honest exit codes,
  output redirected to files because the Windows build prints nothing to the console. Exit 1 from
  a suite with deliberately-red gates is the one rough edge, and it is not a harness fault — it
  means `/verify` can never be green on this repo until `roll_yield` is fixed. Noting it here so
  the next person to see a red gate does not assume a regression.

## 2026-08-05 — split tileset collision onto Structure/Prop layers; gave the door a collider

- Value: **insufficient** — headless lint and the unit suite were the only gates available to me
  (the orchestrator owns the shared devtools bridge this session), and neither can reach the thing
  the change is actually about: whether a skeleton now walks past a tree and stops at a wall.
  - Expected: `--import` would reject the hand-edited `.tres` if `physics_layer_2/3` entries inside
    a `sub_resource` were unparseable before the `[resource]` block declares those layers, and that
    a new test loading the TileSet as a resource would tell me the split landed on the right tiles.
  - Got: import exit 0, `lint: 0 error(s), 0 warning(s) -> exit 0`, and 14/14 on the new file —
    `Selected: 14 of 623 discovered  (file 'test_collision_layers')`. The assertion that earned its
    keep was `test_every_wall_tile_is_solid_and_a_structure`: it sweeps both wall sources for tiles
    carrying the terrain index `main.gd:WALL_TYPES` names and requires **47** of them per wall, which
    is what proves the rewrite caught every blob state rather than only the base cell. The full suite
    is exit 1 with 3 failures, all pre-existing or another agent's: two in the untracked
    `test_balance_curves.gd` (red by design) and `test_mine_and_hit_are_now_one_button` (`Expected 8
    but got 9`) from concurrent mobile-controls work.
  - Cheaper: nothing cheaper would have done. What is *missing* is more expensive, not less — a
    running game with an enemy walked into a tree and then into a wall. Every assertion I could write
    headlessly is about the data file; none of them is about a body being stopped.

- Gap: **no headless way to assert that a collision layer/mask pair actually blocks a body** — the
  suite can read `collision_layer`, `collision_mask` and `TileData.get_collision_polygons_count()`
  and infer the intersection by hand (which is exactly what `_layers_matching(ENEMY_MASK)` in
  `test/unit/test_collision_layers.gd` does), but "would this body be stopped by this tile" is a
  physics-server question and there is no primitive for it. The workaround is a test that restates
  the bitmask arithmetic, which passes if the arithmetic and the data agree *and I got the
  arithmetic right*.
  - [G-132] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `collides(--node PATH --against PATH)` style helper, or headlessly a
    `PhysicsServer2D`-backed assertion in the runner — `_T.assert_blocked(body_scene, tile_source,
    coords)` that builds a one-tile TileMapLayer in the hosted SubViewport, does a
    `move_and_collide` toward the cell and reports whether it was stopped. That turns the whole
    Structure/Prop contract from arithmetic into an observation.

- Gap: **`--import` reports exit 0 while printing another agent's parse error**, so an import that
  "succeeded" left `res://items/items.gd` unloadable. Output was `import exit=0` alongside
  `SCRIPT ERROR: Parse Error: Cannot infer the type of "walk" variable ... at: GDScript::reload
  (res://player/player.gd:446)` and `ERROR: Failed to load script "res://items/items.gd" with error
  "Parse error"`. In a single-agent session that is a broken game reported as a clean import; here
  it was a concurrent edit mid-save, and only re-reading the log distinguished the two.
  - [G-133] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have the harness wrap `--import` the way it wraps lint — a `tools/import.py`
    (or a lint phase flag) that greps the import log for `SCRIPT ERROR` / `Failed to load script`
    and exits 1, so "the class cache was regenerated" and "the project still parses" stop being the
    same exit code.

## 2026-08-05 — atomic sword swings, an input buffer, and a dodge roll

- Value: **warranted** — headless lint caught a real compile break the diff read as fine, and the
  new pure seams turned four "you would have to play it" claims into assertions.
  - Expected: lint would be clean (this is all new script plus one scene node) and the only test
    fallout would be `test_mobile_controls.gd`'s hardcoded button count.
  - Got: `--import` refused the whole project on `Parse Error: Cannot infer the type of "walk"
    variable because the value doesn't have a set type` — `Player.v` is an untyped field, so
    `var walk := v * MOVE_SPEED * ...` does not compile. That cascaded into `Failed to load script
    "res://items/items.gd"`, i.e. a game that would not boot, from a one-character annotation. The
    test fallout was as predicted (`the overlay draws eight buttons: Expected 8 but got 9`), and
    38 new assertions in `test/unit/test_player_combat.gd` pass, including
    `rolling on repeat travels at 1.000x walking` and `a shorter recovery really would outrun
    walking` — the negative case that stops the first one passing by trivial arithmetic.
  - Cheaper: nothing. Lint alone (4s, no game) was the whole win here, and I was barred from the
    bridge this turn anyway — the orchestrator owns runtime.

- Gap: **no headless way to assert that a state's active window survives an external
  `AnimationPlayer.stop()`** — the entire bug being fixed is "something outside the state machine
  ended a swing early", and the closest a headless test can get is asserting the *predicate*
  (`Player.release_may_stop_animation(state)` is false mid-swing) rather than the *behaviour* (the
  animation is still playing and `$Attack.monitoring` is still true after the stop). I had to
  factor four static predicates out of `player.gd` purely so the rules were reachable at all,
  because `Player` is scene-backed and `_T.instantiate_ui` cannot stand one up — its `@onready`
  fields resolve `../../Systems` and `../../UI`.
  - [G-134] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a runner helper that hosts an arbitrary *scene fragment* with stubbed external
    node paths — `_T.instantiate_fragment("res://main.tscn", "World/Player", {"../../Systems": ...})`
    — so a scene-backed node with upward `@onready` paths can be brought up headlessly. Today the
    only way to test one is to extract statics from it, which is a real design tax: `player.gd` now
    carries four static predicates that exist for the test harness rather than for the game.

- Gap: **`run_tests.gd` prints no `Selected: N of M` line on an unfiltered run**, so a full-suite
  run cannot be distinguished from one whose discovery silently found fewer files than it should.
  `--file test_player_combat` reports `Selected: 38 of 662 discovered`; the bare run reports only
  `Total: 662 | Passed: 660 | Failed: 2`. The two numbers are the same fact, but only the filtered
  form states the denominator explicitly, which is the form worth quoting in a handoff.
  - [G-135] status: open | seen: 1 | harness: 0.8.0
  - Improvement: always emit the `Selected:` line, with `(no selector)` where the filter would go.

## 2026-08-05 — combat pass: full swings, dodge roll, and only walls block enemies

- Value: **warranted** — runtime produced the one claim no diff and no headless test could:
  that the LOS gate has teeth rather than being vacuous, and that the prop split moved
  collision to exactly the right side of two different masks.
  - Expected: three agents each reported "not verifiable headlessly" for the same reason —
    the bug is defined by a wall, and headless stands up no physics world. I expected to be
    confirming feel (does the roll look right) and instead expected the collision work to be
    settled by its unit test.
  - Got: the unit test reads the tileset *file*; it cannot see what the running game loaded,
    and it cannot see the seven scene-tile props whose colliders live in unrelated `.tscn`s.
    Probing the live space state with the game's own masks is what actually closed it:
    `mask=3145729` (the enemy's real `collision_mask`) across a stone node → `clear`;
    `mask=1048705` (the player's real mask) across the same stone → `blocked by TileMap`;
    `mask=3145729` across a closed door → `blocked by Door/Blocker`. Three reads, three
    different subsystems, one segment. And `structure_polygons: 94` off the loaded TileSet is
    the number that says the whole LOS feature is not a no-op.
  - Cheaper: nothing. The unit test was already written and already green while two genuine
    holes were open — the scene-tile props, and "is layer 7 populated in the build that is
    running". Both are invisible to every static read.

- Gap: **no generic verb for a space-state query, so "what would collide along this segment"
  had to be added as a project verb before the contract could be checked at all.** The harness
  has `tilemap-cells` and `tilemap-region`, which answer what tiles are *where*, and
  `node-bounds`, which answers where a node is — but nothing answers what a given
  `collision_mask` would actually hit, which is the only form the question takes once a project
  has more than one physics layer. I wrote `los_probe` (segment + mask → clear/blocked + hit
  path + hit position) and it immediately did work I had not planned for: reading `hit_position`
  back from two opposite-facing probes located a wall's faces at x=-256 and x=-240 exactly,
  after five short bisecting probes had all returned `clear` because a Godot ray originating
  inside a shape reports nothing.
  - [G-136] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a generic `raycast --from X,Y --to X,Y [--mask N] [--areas]` verb, reporting
    `clear`, the collider's node path, and the hit position. It is ~20 lines against
    `direct_space_state`, needs nothing project-specific, and is the direct read for any
    question about layers, masks, walls, sight lines or reachability. Pair it with a
    `--mask-names` flag that resolves `[layer_names]` from `project.godot`, since the whole
    class of bug here is a number nobody can read.

- Gap: **`set-state --value` takes no Vector2 in the form the error message asks for.**
  `--value "-200,-296"` fails argparse (reads as two args), `--value "(-200,-296)"` fails with
  `cannot convert String ("(-200,-296)") to Vector2`, and `--value '[-200,-296]'` works. The
  error names the type it wanted and not the syntax that produces it, so the working form is
  found by guessing. This is the same coercion hole as `run-method`'s documented `gather-6sp`,
  one layer up.
  - [G-137] status: open | seen: 1 | harness: 0.8.0
  - Improvement: accept `x,y` and `(x,y)` as well as the JSON array, and on failure print the
    accepted forms rather than only the rejected type.

- Gap: **`harness-version` reports `game not running`**, so the `harness:` field on every gap
  above is copied from the previous entry rather than read. The client half of the version is
  knowable with no game at all — it is the installed revision on disk.
  - [G-138] status: open | seen: 1 | harness: 0.8.0
  - Improvement: print the client revision unconditionally and mark the game half `unknown`
    when the bridge is cold, instead of failing the whole verb.

- Note on the three-agent fan-out: the one-instance rule for the bridge held, because the
  orchestrator owned every launch and the subagents were restricted to `--import`, lint and
  `run_tests.gd`. That restriction is worth making a first-class thing rather than prose in
  three prompts — see G-134's neighbourhood. The concrete cost of not having it: two agents
  independently hit a *transient* lint failure caused by a third agent's mid-save
  (`player.gd:446 Cannot infer the type of "walk"`), and each spent a re-run establishing it
  was not theirs.

## 2026-08-05 — shipped the supply and land-cost retunes

- Value: **warranted** — the runtime run is what turned "the code now loops over regions" into
  "the mainland actually receives one node per tick", and those are different claims.
  - Expected: written before the run. Home starts at 28 of a cap of 40 (12 headroom); ~240
    game-seconds is ~10 ticks; under the new per-region tick home should gain ~10 where the old
    global tick would have given it ~4 (its 41.6% land share).
  - Got: over 262.7 game-seconds (t 0.122 -> 0.5598, ~10.9 ticks) home went **28 -> 39, +11**,
    i.e. 1.0 node per tick, while forest went 18 -> 26 and ore 19 -> 28, both to their caps. 28
    nodes placed in 11 ticks against a hard ceiling of 11 under the old behaviour. The three
    regions now fill concurrently instead of competing for one node.
  - Cheaper: the two new unit tests (`test_a_full_region_does_not_eat_another_regions_respawn_tick`,
    `test_the_respawn_tick_never_offers_a_node_to_a_region_that_opted_out`) prove the eligibility
    filter and the no-starvation property headlessly, and the agent verified both go red against
    the old one-liner. What they cannot show is the RATE against wall-clock game time, which is
    the number the whole retune exists to move — that needed the running game and a bracketed
    clock read.

- Gap: **[G-130] status: open | seen: 2 | harness: 0.8.0** — same gap as last session, hit again
  and in exactly the predicted way. Measuring a regrowth rate still takes launch -> census ->
  `world_clock` -> `set-game-speed` -> sleep -> `set-game-speed` -> `world_clock` -> census, seven
  calls, of which two exist purely to establish how much game time passed. The improvement filed
  last time (put `game_time` in the status provider merged into every reply) would have cut this
  to three calls and removed the only step that can silently invalidate the result.

- Note on subagents: fanning out two authors over disjoint files worked, but the ONE file both
  touched (`test/unit/test_balance_curves.gd`) is what nearly broke the iterative-commit property
  — agent B lowered `KILLS_FOR_THE_WHOLE_MAP` to a value that only passes against agent A's
  sibling change, so committing A alone would have shipped a red gate. Splitting it took a
  hand-revert of two lines, a stash, and two verification runs. Next time: give each agent its own
  test FILE, not just its own source files, or accept a single combined commit.

## 2026-08-05 — Reviewed CLAUDE.md size and where its weight actually sits

- Value: **inconclusive** — no harness verb was run this turn; the question was about the
  instruction file, not about game behaviour, and nothing in the answer needed a live game.
  - Expected: that the devtools/harness block was the bulk of the file, since that is the part
    the user was worried about losing.
  - Got: the opposite, from `wc -l` and a heading scan. Harness + devtools is 196 of 1080 lines
    (18%); Architecture Overview is 715 (66%), and the weather/night cluster alone
    (lighting, lightning, charged skeleton, raids) is ~210 lines — larger than the whole harness
    section it was being defended against.
  - Cheaper: nothing cheaper existed; `wc -l` plus one `grep -n '^## '` was the whole
    investigation, ~2s.

- Gap: **no gaps this turn** — the harness was not exercised, so it had no opportunity to fall
  short. Recording the entry anyway, because the rule requiring it is itself the example the
  answer turned on: an unconditional per-response obligation only fires if it is in the file that
  is always loaded. Moved into a skill, this entry would not exist.

## 2026-08-05 — Split the subsystem essays out of CLAUDE.md into the files they describe

- Value: **overkill** — for verifying *this* diff, which is markdown plus three comment-only
  lines in `demo_director.gd`. Nothing I touched can change runtime behaviour, and lint alone
  settles the only real risk (a malformed comment block breaking a parse).
  - Expected: lint green, tests green, and the run tells me nothing the diff did not.
  - Got: lint `0 error(s), 0 warning(s) -> exit 0` as predicted. The suite came back
    `Total: 664 | Passed: 662 | Failed: 2` — `test_the_foraging_capstone_still_does_something`
    and `test_no_loadout_wastes_extra_drop_chance`, both red at HEAD and neither caused by this
    change. Real find, but an accidental one: it is the balance retune in cda710c/30f9f92
    landing on a saturated extra-drop roll, filed as `gather-54ze`. Attribution took a
    `git stash` + `--filter` re-run against clean HEAD, which is the one genuinely necessary
    runtime step here and only necessary because the full suite had been run at all.
  - Cheaper: `lint_project.gd` alone, ~20s, would have given the same confidence in the diff.

- Gap: **no gaps this turn** — nothing was missing from the harness; it did exactly what it
  claims and the only surprise was a pre-existing red gate, which is the harness working.

- Note on the change itself: the premise going in was that ~700 lines of subsystem rationale had
  to be *moved* out of CLAUDE.md. It did not — a grep of 20 distinctive facts against the source
  found 19 already documented verbatim in the `##` doc header of the file that implements them.
  CLAUDE.md was carrying a second copy, which is the anti-pattern the file itself preaches about
  save state and quest counters. The twentieth ("the charged skeleton's blue is `Sprite2D.modulate`
  and the hit flash is the root's") was **stale**: `charged_bone_enemy.tscn` sets no modulate at
  all — it swaps the atlas region and adds a sparks emitter — and the hit flash is a shader
  parameter at `enemy.gd:370`. A duplicated fact drifted from its original and nothing reported
  it, which is the concrete argument for the index-plus-one-home shape this change leaves behind.

## 2026-08-05 — Renamed the starter station Sawmill -> Workbench across the project

- Value: **warranted** — the diff is 24 mechanical files, but two of the claims I had to make
  about it (the enum ordinal did not move; the pre-v4 save key still reads) are runtime facts a
  diff cannot settle, and one of them is a rename the task explicitly asked for and I refused.
  - Expected: lint green after `--import`, the suite unchanged from HEAD, and
    `test_crafting`'s two legacy-payload tests still passing to prove the v1/v3 fixtures
    were not collateral.
  - Got: `lint: 0 error(s), 0 warning(s) -> exit 0` with `res://crafting/workbench.tscn: OK`
    (the scene rename resolved through the tileset's `uid://1ka6xlmaapop`, which is the thing
    a grep cannot check). `--file test_crafting` -> `Selected: 20 of 664 discovered`, 20/20,
    including `[PASS] test_a_pre_station_keyed_save_still_restores_both_stations` and
    `[PASS] test_the_committed_save_fixtures_still_restore_their_unlocks` — the assertion that
    `"sawmill_recipes"` in `LEGACY_SAVE_KEYS` is a *string on disk* and not a straggler.
    Full suite `Total: 664 | Passed: 662 | Failed: 2`, the same two as HEAD (`gather-54ze`).
  - Cheaper: nothing. `grep` proved the identifiers were gone; only a run proved the bytes
    still matched.

- Gap: **attributing a pre-existing red gate still costs a full second project build** —
  the same friction logged at [G-138] one entry above, hit again from the other direction.
  `git stash` was unavailable here (a concurrent agent shares the tree), so the fallback was
  `git worktree add <scratch>/baseline HEAD --detach` plus a second
  `--headless --import` (~90s, a fresh `.godot/` cache) before
  `run_tests.gd -- --file test_balance_curves` could confirm `Failed: 2` at HEAD too.
  - [G-139] status: open | seen: 1 | harness: 0.8.0
  - Improvement: a `run_tests.gd --baseline <git-ish>` flag, mirroring `lint_project.gd`'s
    existing `--baseline PATH` split into `NEW` vs `PRE-EXISTING`. Lint already refuses to
    re-triage repo debt by hand; the test runner makes you do it, and does it by rebuilding
    the whole project. Even a cached per-commit results file keyed on `git rev-parse HEAD`
    would turn the 90s worktree build into a lookup.

- Note on the change itself: the task listed `"sawmill_recipes"` in `Recipes.LEGACY_SAVE_KEYS`
  as in scope. It is not renameable — it is the top-level key in `demo_homestead_save_v1` and
  `_v3`, both of which "must never be regenerated", and renaming the identifier does not rename
  the bytes it has to match. The failure would have been silent: `loadObject` falls through the
  legacy branch, finds nothing, and returns a save with its unlock list quietly emptied. Left
  as-is with a comment at `recipes.gd:33` saying why, so the next reader does not "finish" the
  rename. Same for the three `"sawmill_recipes"` literals in `test_crafting.gd`, which
  construct v3 payloads on purpose.

## 2026-08-05 — Added the world-space interact prompt (gather-rlf3) and generalized the interaction

- Value: **insufficient** — the headless half reached and settled every rule that could be
  wrong *silently*, and reached none of the feature's actual point, which is what it looks
  like on screen at zoom 8.
  - Expected: lint + tests would confirm the new `class_name` resolves and the three
    resolutions (key name, caption, `has_method("player_interact")` predicate) answer
    correctly; nothing about the pop, the bob or the on-screen size.
  - Got: exactly that, plus two findings the diff alone would not have produced. (1)
    `SCRIPT ERROR: Invalid type in function 'is_interactable' ... argument 1 (previously
    freed) is not a subclass of the expected argument class` — a parameter typed `Object`
    raises *at the call boundary* when handed a freed instance, and `player.gd`'s `chests`
    array genuinely holds freed objects (gather-3zg.6), so the predicate would have raised
    in the real game on the exact case it was written for. Now `Variant` + `typeof()`.
    (2) `ERROR: Not supported by this display server. at:
    keyboard_get_keycode_from_physical` — the headless DisplayServer pushes an engine error
    for the physical→layout translation, so every headless run touching the prompt would
    have printed four of those into the one log that carries this project's real failure
    signal. Guarded on `keyboard_get_layout_count() > 0`. Both were invisible in the test
    *results*: all 22 passed through both of them (gather-1t9 again).
  - Cheaper: nothing. Neither finding is visible in a diff, and both came from stderr of a
    run whose exit code was 0. Reading the file back would have shown a green suite.

- Gap: **[G-057] again — a purely visual feature shipped with zero runtime verification, by
  instruction.** Third consecutive occurrence, same cause: the bridge is one shared
  command/result file pair, a sibling agent was live on the same repo, so `godot --path .`,
  `/verify` and every `devtools.py` verb (including `harness-version`) were out of bounds.
  The harness version below came from lint's banner, `lint: godot-selftest-harness 0.8.0`.
  This diff's whole acceptance criterion is "does a child notice the prompt and press the
  key", and nothing run here can speak to it.
  - [G-057] status: open | seen: 3 | harness: 0.8.0
  - Improvement: unchanged — `devtools.py launch --isolated` doing the project copy, the
    session id and `GODOT_USERDATA` in one command. Three turns of un-runtime-verified
    visual work is now the case for it.

- Gap: **no headless way to assert a world-space indicator's on-screen footprint.** The one
  thing that decides whether this feature works or covers the station it points at is
  `size_in_world_px * camera.zoom`, and a headless `instantiate_scene` has no camera: the
  node reports `scale` and a `_draw()` nobody rasterizes. `node-bounds` and `canvas-scale`
  answer exactly this question and both need a running game — i.e. they are unavailable in
  precisely the situation ([G-057]) where they are most needed. Workaround: sized the cap
  from `Font.get_string_size` and asserted only `global_position == target + Y_OFFSET`,
  which pins the anchor and says nothing about the extent.
  - [G-140] status: open | seen: 2 | harness: 0.8.0
  - Improvement: a headless assertion helper that hosts a Node2D under a SubViewport with a
    `Camera2D` at a caller-given zoom and returns the node's rasterized screen rect —
    `_T.screen_rect(node, zoom)`. It would turn "is this element tile-sized or panel-sized"
    from a runtime eyeball into a unit test, for this prompt and for `GatherProgress`,
    `DamageNumber` and `SplashText` alike, all four of which currently justify their font
    sizes in a comment and assert none of them.

## 2026-08-05 — Workbench rename + the interact prompt, verified against the running game

- Value: **warranted** — the run produced the one claim the diff could not, and it was a
  *failure*: the prompt was built to spec, passed lint and 22 unit tests, and was unreadable
  on screen. Nothing short of a rasterized frame could have said so.
  - Expected: runtime will settle whether the prompt actually appears and where —
    specifically whether `Y_OFFSET = -16` places the bubble over the station or a full tile
    above it, and whether the key cap resolves to a real `F` from the live InputMap rather
    than the headless fallback.
  - Got: both of those, and the thing I had not thought to predict. The cap resolved `F`
    correctly and anchored correctly, but the screenshot next to the gather selector showed
    why it did not read: the selector is a 16px tile of white corner brackets — **128 screen
    px at zoom 8** — and the cap was under 30. Two different visual languages, and the eye
    took the brackets every time. The user's words were "too hard to read. Make it look like
    the selector", which is the same finding arrived at from the other side. The rework
    (white corner brackets, dark plate, `KEY_FONT_SIZE` 22 -> 64, `Y_OFFSET` -16 -> -22)
    is a direct consequence. Also confirmed the generalization end to end: the panel that
    opened on `F` was titled `WORKBENCH`, and the identical prompt captioned itself `Chest`
    over a `TestChest` — two unrelated classes through one `has_method` predicate.
  - Cheaper: nothing. Lint was `0 error(s)`, the 22 new unit tests passed, and reading the
    diff shows a well-argued `KEY_FONT_SIZE := 22`. The defect exists only on a rendered
    frame beside another element, which is the one artifact none of those produce.

- Gap: **a stale harness install fails as "runner could not run", not as "your install is
  old".** `python tools/import_check.py` — Phase 1's mandated import gate — exited 2 with
  `can't open file '...\tools\import_check.py': [Errno 2] No such file or directory`, which
  is the same exit code the contract reserves for a real runner failure. The install is a
  clean, unmodified **0.8.0**; the plugin ships **0.9.0**, and `import_check.py` is a 0.9.0
  addition. Two more 0.9.0 features were missing the same silent way: `find-nodes` (argparse
  rejected it mid-run, costing a fallback to grepping `scene-tree`) and reach's exclusion of
  `test_dir` from the denominator — 9 of my 14 "NOT reached" files are test scripts that can
  never appear in a scene tree. Workaround: substituted the bare `--import` plus lint's
  `class_cache_stale` check, which did not fire (`169 scripts compiled OK`).
  - [G-141] status: open | seen: 1 | harness: 0.8.0
  - Improvement: have `/verify` Phase 0 read `harness-version` against the plugin's
    `harness_history.json` and print one line — `install 0.8.0, plugin 0.9.0: import_check,
    find-nodes and test_dir reach-exclusion unavailable this run` — *before* Phase 1 uses
    them. The drift check already computes exactly this bearing; it just runs as a separate
    block whose result nothing downstream consumes. Failing that, `import_check.py` missing
    should exit with its own code, not 2.

## 2026-08-06 — Refreshed the harness 0.8.0 -> 0.10.0 via `/scaffold-godot-harness`

- Value: **warranted** — the headless smoke check separated "the refresh broke something"
  from "these two were already red", which the diff alone could not have settled.
  - Expected: lint clean (only harness files changed, no game code), and the unit suite
    green as it was at `4907ff6`.
  - Got: lint `0 error(s), 0 warning(s)`, `Scripts: 169 compiled OK`, `UIDs: OK`. But the
    suite came back `Total: 686 | Passed: 684 | Failed: 2` —
    `test_no_loadout_wastes_extra_drop_chance` and
    `test_the_foraging_capstone_still_does_something` in `test_balance_curves.gd`. Restoring
    `main`'s pre-refresh `run_tests.gd` and re-running `--file test_balance_curves` gave the
    identical `Passed: 7 | Failed: 2`, so the 0.10.0 runner did not surface them and did not
    cause them — they are pre-existing balance debt (Gold Pickaxe 0.75 + full Foraging branch
    puts extra-drop chance past 1.00, and `roll_yield` spends it on one `randf()`).
  - Cheaper: nothing. `git diff` shows zero game files touched, which *argues* the failures
    are unrelated but cannot demonstrate it; only running the old runner against the same
    file did, and that took one 40s invocation.

- Gap: **`scaffold_install.py config` silently reset `godot_bin` to `""`** — step 7's merge
  is `--set` driven, and any scaffold-owned key not passed reverts to the shipped default.
  `godot_bin` is scaffold-owned, so `config --set main_scene=... --set hud_layer_name=...`
  printed `^ godot_bin: "C:/Users/gotmi/Documents/Godot_v4.7.1-stable_win64.exe" -> ""` while
  the two keys I *did* pass were correctly kept as project-owned. Step 11 re-detects it
  afterwards, which hides the reset — except its Windows glob
  `~/Documents/Godot_v*_win64.exe` returned `Godot_v4.5.1-stable_win64.exe` on this machine,
  the wrong engine for a `4.7` project. Workaround: re-ran step 11's `--set godot_bin=` with
  the 4.7.1 path read out of the config *before* the merge clobbered it.
  - [G-142] status: open | seen: 1 | harness: 0.10.0
  - Improvement: two independent fixes, either sufficient. (a) Treat an owned key that is
    absent from this invocation's `--set` list as "not being re-detected" and carry the
    existing value forward, rather than reverting it to the shipped default — a merge should
    only move keys it was actually given. (b) Have step 11's glob sort matches by version
    descending and cross-check the winner against `config/features` in `project.godot`, so a
    stale 4.5 binary next to a 4.7 one is never the one recorded.

- Gap: **`log-devtools.md` seeded before 0.8.0 can never receive a format refresh** — 9a
  reported `= log-devtools.md has no format markers (seeded before 0.8.0) - left untouched`,
  which is the correct conservative call but means this project's Format section is frozen at
  whatever 0.7.x wrote, permanently. Every future verdict or status field the harness adds
  will reach new installs and skip this one. Workaround: none applied; the section is still
  accurate enough to follow.
  - [G-143] status: open | seen: 1 | harness: 0.10.0
  - Improvement: give `format-block` a `--adopt` mode that locates the legacy section by its
    `## Format` heading and the first `## <date>` heading after it, wraps that span in the
    markers *without changing its content*, and reports the span it claimed. That is a
    one-time, reviewable diff the user can reject, and it converts every pre-0.8.0 log into
    one that tracks the format from then on.

## 2026-08-06 — Four pixel-art UI direction mockups (HTML pitch board, no game code touched)

- Value: **overkill** — deliberately ran nothing; the deliverable is an HTML page and the diff
  contains no `res://` code, so there was nothing for the runtime to reach.
  - Expected: predicted before starting that the harness had no role here — the inputs are
    `ui/ui_theme.gd`, `ui/panel_frame.gd`, the PNGs under `assets/art/`, and the committed
    screenshots in `itch/`, all of which are static reads.
  - Got: n/a — no bridge command issued, no runner invoked.
  - Found: nothing in the game. (Two authoring defects in my own output, both caught without
    the harness: a corrupted CSS declaration `color: #4d5costs` in the slate block, and a
    generated pixel font that needed rasterizing to prove its descenders and punctuation were
    right — checked with a PIL render rather than by eye on the glyph tables.)
  - Cheaper: what I did. Reading `ui_theme.gd` (255 lines) plus the four committed
    `itch/screenshot_*.png` gave the entire current-UI picture in two tool calls; launching the
    game to screenshot the skills panel would have reproduced `itch/screenshot_2_skills.png`
    exactly and cost a launch, a `goto_resource`, a panel open and a 0.5s settle.

- Gap: **no gaps this turn** — no harness command was run, so there is no evidence to file one
  from. Noting for the next turn that the read this task *would* have wanted, had the restyle
  been implemented rather than pitched, is the flat, effective style values a Control is
  actually drawing with (`bg_color`/`border_width`/`corner_radius` off the resolved StyleBox,
  not the `theme_override_styles/panel` object reference). That will be filed with real output
  the first time it actually blocks something.

## 2026-08-06 — Endesga Arcade UI repaint: palette, geometry, and a generated bitmap font

- Value: **overkill** — for *this* `/verify` run only. It confirmed the last commit's
  three-line change and caught nothing; the runs earlier in the same session were a
  different story (see Found).
  - Expected: the running game will show whether `NewSlot._ready()`'s stylebox override
    actually survives to the bag/chest grids — an override set in `_ready()` can be
    silently replaced by the scene's authored theme or by a later `apply_metrics()`, and
    the diff cannot tell me which.
  - Got: it survives. `get-state --property theme_override_styles/panel.bg_color` on the
    live `GrabbedSlot` returned `{r:0.149, g:0.169, b:0.267}` (#262b44 = COLOR_INSET),
    `border_width_left: 3`, `border_color` #1b1023, `corner_radius_top_left: 0`,
    `anti_aliasing: false`. The guard held too: the hotbar slot kept its own overlay fill
    at alpha 0.94 and its gold `shadow_color` #fee761, so the new `_ready()` override does
    not clobber the per-slot styling the hotbar applies afterwards.
  - Found: nothing in this run. Earlier runs this session found four things the diff could
    not have, all of which are why the session is worth logging at all:
    (1) `StyleBoxFlat.anti_aliased` does not exist — the property is `anti_aliasing`. The
    wrong name compiles AND passes lint, then raises at runtime, aborting `_flat()` so it
    returns **null**; every style factory silently produced nothing and the whole game fell
    back to Godot's default theme. Only `test_save_slot_ui.gd` caught it, and only
    indirectly, by noticing a button had stopped clearing the 48px touch floor.
    (2) `project.godot`'s `[gui]` section takes `theme/custom_font`, not
    `gui/theme/custom_font` — the section header supplies the prefix. The long form parses,
    sets `gui/gui/theme/custom_font`, and leaves the real setting empty. A **completely
    green 686-test run** told me the font was in when the game was still rendering Open
    Sans. Caught by loading the setting and printing `get_font_name()`.
    (3) `validate-ui` found the skill-point badge hanging 45px off a 1920 screen
    (`ui_overflow: PanelContainer 'PointsBadge' ... -> 1965,135`) once the wider glyphs
    outgrew its hardcoded BADGE_WIDTH.
    (4) `sample-pixels`-style pixel reads showed the XP bar's fill (#0099db) was within
    three points of `main.gd`'s OCEAN_COLOR (#0098dc) — the bar vanished over water. By eye
    it read as "washed out", which looks like a tint bug, not a collision.
  - Cheaper: nothing cheaper existed for this run — no test in the suite asserts a StyleBox,
    so a runtime property read was the only way to settle it. For (2) specifically, the
    cheapest sufficient check was the six-line `SceneTree` script that printed
    `get_font_name()`; a screenshot was NOT sufficient and actively misled me, because
    Open Sans at a small size reads as "pixelly" in a 1920-wide screenshot.

- Gap: **`validate-ui`'s `button_text_overflow` fires when the text exactly fits** —
  reported `text 'QUESTS  [J]' (116px) exceeds button width (128px)` three times. 116 is
  *less* than 128; the difference is exactly `2 * UiTheme.BUTTON_PAD` (6). So the check is
  comparing `text + content_margins` against the width with a `>=` where it wants `>`, and
  a button sized precisely to its own content — which is what an HFlowContainer of Buttons
  produces by construction — is reported as overflowing forever. Workaround: cropped a
  screenshot of the toolbar and confirmed by eye that nothing is clipped, then ignored all
  three. That is exactly the manual step the verb exists to remove, and it makes a real
  overflow indistinguishable from the permanent noise.
  - [G-144] status: open | seen: 1 | harness: 0.10.0
  - Improvement: make the comparison strict (`text_width > content_width`), or subtract the
    stylebox's content margins from the button width before comparing and report the slack
    (`text 116px, content box 116px, slack 0px`) so "exactly fits" is visibly distinct from
    "overflows by 12px".

- Gap: **reach counts a `RefCounted` constants class as unreached with no way to say why** —
  `ui/ui_theme.gd` is the file this entire session was about, and the ledger reports it in
  `NOT reached` because `UiTheme` extends `RefCounted`, is never instantiated, and therefore
  owns no node any `scene-tree` snapshot can see. Every one of its colours was verified at
  runtime, through the nodes that consume it. `reach_aliases` in `devtools_config.json`
  exists for exactly this and I did not use it, because an alias is recorded as a project
  *declaration* rather than an observation — which is the right call for a helper nobody
  looked at, and the wrong one here, where a live node's `theme_override_styles/panel`
  literally carries the class's constants.
  - [G-145] status: open | seen: 1 | harness: 0.10.0
  - Improvement: let `scripts-seen` credit a script whose *constants or statics* were
    observed through a property read, or add a `--reached-via` flag to `verify_ledger.py
    record` that takes `script=node_path,property` and records the observation that vouches
    for it — so the credit is evidence from this run rather than a standing config claim.
