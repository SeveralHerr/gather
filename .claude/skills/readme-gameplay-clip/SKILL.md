---
name: readme-gameplay-clip
description: >
  Author and record the scripted gameplay clips (mp4 + gif) that go in this project's
  README, using the in-game demo director (devtools_ext/demo_director.gd) and
  tools/capture_clip.py. Use this whenever someone asks to make, record, re-record, retime
  or fix a gameplay clip, video, GIF, demo footage or trailer shot — for the README, a
  store page, or to "show off" or "demo" a feature as video — and whenever a new clip is
  being added to the demo director. Not for still screenshots (the harness `screenshot`
  verb covers those on its own), and not for writing an itch.io devlog or setting up a
  store page (those have their own skills).
---

# README gameplay clips

The clips in this README are not screen recordings. They are **scripted performances that
run inside the game**, filmed by Godot's own movie writer and trimmed on frame numbers the
performance chose for itself. Two files do all of it:

| File | What it is |
|---|---|
| `devtools_ext/demo_director.gd` | The choreography. One coroutine per clip, driving real input actions. |
| `tools/capture_clip.py` | The recorder. Launches the game under `--write-movie`, polls the director, trims and encodes. |

Read the header comment of each before changing either. They explain the design decisions
(why a coroutine and not CLI-driven input, why a PNG sequence and not MJPEG, why the trim
is exact) and this skill does not repeat them.

`references/director-vocabulary.md` in this skill has the helper API, the framing
constants, and the anatomy of an existing clip. Read it when you are writing or editing a
beat.

## The workflow, and why it is shaped this way

**A recording costs about 10 minutes of wall time. A dry run costs about 60 seconds.**
Under `--write-movie` the engine renders a 1920x1080 PNG per frame and writes it to disk,
far slower than real time, and it does that for the whole run including world generation
and staging. At normal speed the same choreography plays out in roughly the length of the
finished clip.

So the loop is: **dry-run until the director reports a clean take, then record once.**

```
edit the clip  ->  dry run  ->  notes empty?  ->  no: fix, repeat
                                             ->  yes: dry run twice more
                                                      ->  record  ->  check the file
                                                      ->  README + log-devtools.md
```

### 1. Dry run

Launch the game normally on its own devtools session, start the clip, poll until it
stops. Do not use `capture_clip.py` for this — it is the movie-writer path.

```bash
# The Godot binary is not on PATH; it is godot_bin in the harness config.
GODOT=$(python -c "import json;print(json.load(open('addons/godot_selftest/devtools_config.json'))['godot_bin'])")
SESSION=clip1                       # any short id; keeps this instance's bus to itself

GODOT_DEVTOOLS_SESSION=$SESSION "$GODOT" --path . --mute &
sleep 8
python tools/devtools.py --session $SESSION ping

python tools/devtools.py --session $SESSION cmd demo_clip --args '{"name":"charged"}'
# poll every few seconds until data.running is false
python tools/devtools.py --session $SESSION cmd demo_state
python tools/devtools.py --session $SESSION quit
```

`--mute` is right for a dry run and **wrong for a recording** — the movie writer emits a
`.wav` of the audio bus alongside the frames, and a muted take records silence into it.
`capture_clip.py` already omits it deliberately; don't add it.

Only one Godot instance may touch a given devtools bus at a time (one command file, one
result file). If someone else is recording, your launch corrupts their take and theirs
corrupts your reads. Give every instance its own `GODOT_DEVTOOLS_SESSION`, and check
before launching at all.

### 2. `notes` is the gate, not `success`

`demo_state` returns `{running, clip, beat, marks, notes, frames_drawn}`. **Record only
when `notes` comes back empty.**

Every degradation path in a well-written beat calls `_note()` and carries on to the next
beat, because a beat that placed nothing still has to hand over control. That means a clip
can run to `beat: "done"`, report `success: true`, and have filmed nothing of what it
promised — a net that swung at air, a chest that never opened, a turret nobody loaded. The
notes array is the only place that shows up.

`beat: "failed"` plus a note means staging refused outright — usually the search found no
patch of world matching what the clip needs. That is a real outcome on a real seed, not
necessarily a bug in your beat.

### 3. One clean dry run is not evidence. Do three.

The `charged` clip passed a dry run and failed the runs either side of it, in two
different ways: once the player never reached net range, once all three swings met air.
Same root cause both times — the choreography decided **once** where a moving enemy was
and then acted on that stale answer.

Anything that interacts with an enemy, a worker, or any other autonomous agent is aiming
at a moving target. The fix is structural: make approach-and-swing a single loop that
re-chooses direction every frame and re-closes after a miss (that is what `_chase` is).
Then dry-run at least three times in a row before spending ten minutes on a recording.

### 4. When a beat says an interaction did nothing, suspect the game's guards first

Both real bugs found while building these clips looked like input problems and were not:

- The `workers` reveal beat reported "the action press did not open the chest". The input
  path was entirely correct. `ui/inventory_interface.gd:266` force-closes an open
  container the moment its owner is more than 15 px from the player — and `_walk_to`
  parks the player on the **centre** of the tile beside it, which is exactly 16 px. The
  bag opened and shut inside two frames. The fix was `REVEAL_REACH` / `_close_in`: lean
  into the chest instead of stopping on the mark, which is also what a person does.
- Two agents adding clips in parallel both named a beat `_beat_storm`. GDScript's
  duplicate-function error surfaced as `Could not parse global class "DemoDirector"` — an
  error naming the class, not the collision. **Prefix beat helpers with the clip name**
  (`_beat_charged_storm`), because this file already holds four clips' worth of them.

So before rewriting an input call: check proximity thresholds, visibility and state
guards, and whether the game reads that key with `is_action_just_pressed` (which needs
`_tap_key_for`, not `_press`) or off polled state (which `_press` handles).

### 5. Verify visual claims by measuring

A dusk frame of the `weather` clip looked like the sea had failed to dim with the land —
which would have been exactly the bug the three-canvas write exists to prevent. Measuring
the pixels showed sea and land dimming by 0.457 and 0.459 at dusk, and 0.338 and 0.337 in
the storm. The eyeball was wrong, and would have sent a session chasing a bug that was not
there.

When the claim is about colour, brightness or tint, extract frames and sample them:

```bash
ffmpeg -i docs/media/weather-showcase.mp4 -vf "select=eq(n\,300)" -vframes 1 /tmp/f300.png
python -c "from PIL import Image; im=Image.open('/tmp/f300.png').convert('RGB'); print(im.getpixel((120,900)), im.getpixel((960,540)))"
```

Pick one sea pixel and one land pixel that stay sea and land for the whole clip, sample
the same coordinates at two times, and compare the *ratios*. A ratio is the honest
comparison; two absolute colours look different for reasons that have nothing to do with
the bug.

### 6. Record

```bash
python tools/capture_clip.py --clip charged --out docs/media/charged-showcase
```

It writes both `charged-showcase.mp4` and `charged-showcase.gif`. Reference points from
the existing set: **25-30 seconds, 1.5-3 MB per file.** Wildly outside that means the trim
went wrong — check `marks` in the state it printed.

- `--keep-frames` leaves the PNG sequence behind, and `--frames-dir <path>` re-encodes it
  without re-shooting. Reach for these when the *take* is good but the *encode* is not
  (gif width, fps, palette): re-encoding is seconds, re-shooting is ten minutes.
- `--fps`, `--gif-width` tune the output. Defaults are 30 and 720.
- ffmpeg is required. It may be installed and off PATH; the script already checks the
  winget location before giving up.
- If the director leaves notes, the script prints them and still encodes. **Read that
  line.** An encoded file is not a usable clip.

## Writing a new clip

A clip is three edits in `demo_director.gd` and nothing else:

1. one word appended to `clips()`
2. one arm in `start()`'s `match`
3. one contiguous section of the file — a header comment, constants, the `_run_*_clip`
   coroutine, its beats, and its staging

Follow the shape the existing four share:

```gdscript
func _run_<name>_clip() -> void:
    var handler := _handler()
    var player := _player()
    if handler == null or player == null:
        _fail("no TileMapHandler or player in the scene")
        return

    var centre = _stage_<name>(handler, player)   # returns null when the world won't do
    if centre == null:
        _fail("...say what it looked for and where...")
        return

    # Everything above is setup and is trimmed off the front of the recording.
    await _wait(<NAME>_BEAT["settle"])
    _mark("show_start")

    await _beat_<name>_one(...)
    await _beat_<name>_two(...)

    _mark("show_end")
    await _wait(<NAME>_BEAT["tail"])

    _release_all()
    _beat = "done"
    _running = false
```

**`_mark("show_start")` / `_mark("show_end")` are not optional and are not decoration.**
They record `Engine.get_frames_drawn()`, which under `--write-movie` *is* the output frame
index, so ffmpeg cuts on a frame the director chose rather than on a stopwatch guessing
how long world generation took this time. Everything before `show_start` — engine boot,
world generation, staging — never reaches the file. A clip without them cannot be trimmed
and `capture_clip.py` refuses it.

**Beat lengths go in a `<NAME>_BEAT` dictionary at the top of the section**, so the clip
can be retimed without reading the choreography. Anything else that sets pacing or framing
belongs in a named constant beside it.

**Every non-obvious constant carries a doc comment saying why *that* number.** Not what it
is — what measurement or failed take produced it. The file is exemplary about this
(`NET_REACH` records the swing geometry and the take that missed every time; `BATTLE_HALF`
records why it is smaller than `ARENA_HALF`), and a new clip that just asserts numbers
reads as noise beside it.

**Flag every deliberate departure from real gameplay at its call site.** `player.invulnerable`,
a shortened work timer, a forced RNG outcome, a parked countdown — each existing one says
what it fakes and why the clip cannot be shot without it. These are the lines a future
reader will most want explained and least able to reconstruct.

**Score the arena, never hardcode a spot.** Staging searches for ground that satisfies the
clip's needs and refuses when it finds none (see `_find_arena`, `_find_pocket`,
`_find_coast_stand`). Two reasons: island generation is noise-thresholded, so a maxed home
island is routinely a lopsided crescent with no clear rectangle where you expect one; and
a clip shot on a fresh world **generates a new world every launch**, so the framing you
saw in a dry run is not the framing the recording gets. Only the staging *logic* carries
over between runs.

## Preconditions a clip may carry

- **`workers` loads a save slot** (`WORKER_SLOT`, currently 3) and expects the demo
  homestead in it. Back up whatever is there, then copy the fixture in:

  ```bash
  cp "%APPDATA%/Godot/app_userdata/Gather/saves/slot_3.save" /tmp/slot_3.bak   # if it exists
  cp test/fixtures/demo_homestead_save "%APPDATA%/Godot/app_userdata/Gather/saves/slot_3.save"
  ```

  A clip needing a built-up base must be shot on a save — standing the mechanic up on
  empty starting grass films the feature and loses the reason anyone would want it.
- **`turrets`, `weather` and `charged` are shot on a fresh world.** Nothing about them
  needs a base, and a homestead would only put somebody's walls behind the shot.

## Finishing up

**Add the clip to the README in the existing style** — a `### Heading`, one or two
sentences of prose that say what the loop *is* rather than narrating the footage, an
`([mp4](docs/media/<name>-showcase.mp4))` link, then the GIF:

```markdown
### The worker loop

Lay out a chest and two worker bases, drop a captured skull into each, and the skeletons
fell a tree and break a rock while you watch — then open the chest and the haul is in it.
([mp4](docs/media/worker-showcase.mp4))

![Placing a chest and two worker bases, loading a skull into each, the workers felling a tree and breaking a rock, and the chest opened to show the wood and stone they delivered](docs/media/worker-showcase.gif)
```

The alt text is long on purpose: it is a beat-by-beat description of what happens, which is
the only version of the clip a reader on a text-mode or slow connection gets.

**Append the required entry to `log-devtools.md`** (the format is in CLAUDE.md's
"DEVTOOLS LOG" section). Clip work is one of the few tasks where the harness verdict is
almost always `warranted` and worth saying why: the dry-run/notes loop routinely produces
claims the diff cannot — name the note that caught the take, not just "it passed".

If code outside the director changed, run `/verify` as usual. If only the director and the
README changed, headless lint is enough to catch a parse error:

```bash
"$GODOT" --headless --path . --script res://tools/lint_project.gd
```
