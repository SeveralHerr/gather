#!/usr/bin/env python3
"""Record a README clip: run the in-game demo director under Godot's movie writer, then
trim and encode the result with ffmpeg.

Why the movie writer rather than a screen recorder: it renders a fixed timestep and writes
one file per frame regardless of how long the frame took, so the footage is smooth even
though a 1920x1080 PNG per frame is far slower than real time to produce. Nothing in the
clip depends on the machine keeping up.

Why PNG rather than the MJPEG .avi Godot also offers: every sprite in this game is drawn
with a NEAREST filter at 8x zoom, and MJPEG's DCT rings visibly along those hard pixel
edges. The sequence is lossless and ffmpeg does the only lossy step, once.

The trim is exact rather than a stopwatch guess. Under the movie writer
`Engine.get_frames_drawn()` is the frame index in the output, so the director records it at
the start and end of the performance (`demo_state` -> `marks`) and this script cuts on
those numbers. Everything before them — engine boot, world generation, staging the arena —
never reaches the file.

    python tools/capture_clip.py                     # the turret clip, mp4 + gif
    python tools/capture_clip.py --clip turrets --fps 30 --keep-frames
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
CONFIG = PROJECT / "addons" / "godot_selftest" / "devtools_config.json"

# Where winget's ffmpeg lands. Checked after PATH, because a machine with its own ffmpeg
# should use that one.
WINGET_FFMPEG = Path.home() / "AppData/Local/Microsoft/WinGet/Links/ffmpeg.exe"


def fail(message: str) -> "None":
    print(f"capture_clip: {message}", file=sys.stderr)
    sys.exit(2)


def resolve_godot() -> str:
    override = os.environ.get("GODOT_BIN")
    if override:
        return override
    try:
        config = json.loads(CONFIG.read_text(encoding="utf-8"))
    except OSError:
        config = {}
    godot = config.get("godot_bin", "")
    if not godot or not Path(godot).is_file():
        fail("no Godot binary; set $GODOT_BIN or godot_bin in devtools_config.json")
    return godot


def resolve_ffmpeg() -> str:
    found = shutil.which("ffmpeg")
    if found:
        return found
    # winget installs a shim under Links/ that is not on PATH until the shell restarts,
    # which is exactly the situation the first run of this script is in.
    if WINGET_FFMPEG.is_file():
        return str(WINGET_FFMPEG)
    for candidate in (Path.home() / "AppData/Local/Microsoft/WinGet/Packages").glob(
            "Gyan.FFmpeg*/**/bin/ffmpeg.exe"):
        return str(candidate)
    fail("no ffmpeg found. Install it (winget install Gyan.FFmpeg) or put it on PATH.")


def devtools(session: str, *args: str, check: bool = True) -> dict:
    """One devtools CLI call, returning the parsed reply envelope."""
    cmd = [sys.executable, str(PROJECT / "tools" / "devtools.py"), "--session", session, *args]
    proc = subprocess.run(cmd, cwd=str(PROJECT), capture_output=True, text=True)
    if check and proc.returncode != 0:
        fail(f"devtools {' '.join(args)} failed:\n{proc.stdout}\n{proc.stderr}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"_raw": proc.stdout, "_err": proc.stderr, "_rc": proc.returncode}


def wait_for_bridge(session: str, timeout: float = 90.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        proc = subprocess.run(
            [sys.executable, str(PROJECT / "tools" / "devtools.py"), "--session", session, "ping"],
            cwd=str(PROJECT), capture_output=True, text=True)
        if proc.returncode == 0 and "DevTools is running" in proc.stdout:
            return
        time.sleep(2.0)
    fail("the game never answered on the devtools bus")


def record(clip: str, fps: int, frames_dir: Path) -> dict:
    """Runs the game under the movie writer and returns the director's final state."""
    frames_dir.mkdir(parents=True, exist_ok=True)
    session = uuid.uuid4().hex[:8]

    env = os.environ.copy()
    env["GODOT_DEVTOOLS_SESSION"] = session

    # Deliberately NOT --mute: the PNG writer emits a .wav of the audio bus alongside the
    # frames, and a muted run records silence into it.
    cmd = [
        resolve_godot(), "--path", str(PROJECT),
        "--write-movie", str(frames_dir / "frame.png"),
        "--fixed-fps", str(fps),
    ]
    print(f"capture_clip: recording at {fps}fps into {frames_dir}")
    log = (frames_dir / "godot.log").open("w", encoding="utf-8")
    proc = subprocess.Popen(cmd, cwd=str(PROJECT), env=env, stdout=log, stderr=subprocess.STDOUT)

    try:
        wait_for_bridge(session)
        start = devtools(session, "cmd", "demo_clip", "--args", json.dumps({"name": clip}))
        if not start.get("success", False):
            fail(f"the director refused to start: {start.get('message')}")

        # No fixed sleep: under the movie writer a 25-second clip can take minutes of wall
        # time, and how many is a property of the machine rather than of the clip.
        state = {}
        deadline = time.time() + 1800
        while time.time() < deadline:
            reply = devtools(session, "cmd", "demo_state")
            state = reply.get("data", {})
            if not state.get("running", True):
                break
            print(f"  beat: {state.get('beat')}  frame {state.get('frames_drawn')}", flush=True)
            time.sleep(5.0)
        else:
            fail("the clip never finished")

        state["frames_drawn_at_quit"] = state.get("frames_drawn", 0)
        devtools(session, "quit", check=False)
    finally:
        for _ in range(30):
            if proc.poll() is not None:
                break
            time.sleep(1.0)
        if proc.poll() is None:
            proc.terminate()
        log.close()

    if state.get("beat") == "failed" or state.get("notes"):
        print(f"capture_clip: director notes: {state.get('notes')}")
    return state


def run_ffmpeg(cmd: list[str]) -> None:
    """ffmpeg, with its own diagnostics on failure — its exit codes say nothing on their own."""
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        tail = "\n".join(proc.stderr.strip().splitlines()[-12:])
        fail(f"ffmpeg failed ({proc.returncode}):\n{tail}")


def frame_files(frames_dir: Path) -> tuple[list[Path], str, int]:
    """The written frames in order, plus the ffmpeg pattern and its digit count."""
    files = sorted(frames_dir.glob("frame*.png"))
    if not files:
        fail(f"the movie writer wrote no frames into {frames_dir}")
    digits = len(re.sub(r"\D", "", files[0].stem[len("frame"):]))
    return files, f"frame%0{digits}d.png", digits


def encode(state: dict, frames_dir: Path, out_base: Path, fps: int, gif_width: int) -> None:
    ffmpeg = resolve_ffmpeg()
    files, pattern, digits = frame_files(frames_dir)
    marks = state.get("marks", {})
    if "show_start" not in marks or "show_end" not in marks:
        fail(f"the director left no show_start/show_end marks: {marks}")

    # frames_drawn counts from engine start; the writer's first file is not necessarily
    # frame 0. One constant offset relates the two, and the last frame written pins it.
    last_drawn = int(state.get("frames_drawn_at_quit", 0))
    first_index = int(re.sub(r"\D", "", files[0].stem))
    offset = last_drawn - (len(files) - 1) - first_index

    # Half a second of lead-in, which lands inside the director's settle beat: the player
    # is already standing on his mark, so it reads as a held shot rather than as a cut.
    start = max(first_index, int(marks["show_start"]) - offset - fps // 2)
    end = min(first_index + len(files) - 1, int(marks["show_end"]) - offset)
    count = end - start + 1
    if count < fps:
        fail(f"the trim came out to {count} frames, which is not a clip")

    out_base.parent.mkdir(parents=True, exist_ok=True)
    mp4 = out_base.with_suffix(".mp4")
    gif = out_base.with_suffix(".gif")
    print(f"capture_clip: {len(files)} frames written, keeping {count} "
          f"({count / fps:.1f}s) from index {start}")

    # Input options only. `-frames:v` belongs with the OUTPUT: left in here it attaches to
    # whatever input follows it, and ffmpeg rejects it against the .wav.
    frames_in = [ffmpeg, "-y", "-framerate", str(fps), "-start_number", str(start),
                 "-i", str(frames_dir / pattern)]

    wav = next(iter(frames_dir.glob("*.wav")), None)
    audio_in: list[str] = []
    audio_out: list[str] = []
    if wav is not None and wav.stat().st_size > 1024:
        # The audio track starts at engine boot exactly as the frames do, so it takes the
        # same cut, expressed in seconds instead of frames.
        audio_in = ["-ss", f"{(start - first_index) / fps:.3f}", "-i", str(wav)]
        audio_out = ["-c:a", "aac", "-b:a", "128k", "-shortest"]

    # yuv420p, or the mp4 will not play in a browser.
    run_ffmpeg(frames_in + audio_in + [
        "-frames:v", str(count),
        "-c:v", "libx264", "-crf", "18", "-preset", "slow",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", *audio_out, str(mp4),
    ])

    # Two passes for the gif: one palette built from the whole clip, then applied with
    # dithering off. A single pass quantises per frame and the flat grass crawls. `neighbor`
    # scaling for the same reason everything in this game uses a NEAREST filter.
    palette = frames_dir / "palette.png"
    gif_fps = min(fps, 20)
    scale = f"fps={gif_fps},scale={gif_width}:-1:flags=neighbor"
    run_ffmpeg(frames_in + ["-frames:v", str(count),
                            "-vf", f"{scale},palettegen=stats_mode=diff", str(palette)])
    run_ffmpeg(frames_in + ["-i", str(palette), "-frames:v", str(count), "-lavfi",
                            f"{scale}[x];[x][1:v]paletteuse=dither=none", str(gif)])

    for path in (mp4, gif):
        print(f"capture_clip: wrote {path} ({path.stat().st_size / 1_000_000:.1f} MB)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--clip", default="turrets", help="clip name the director knows")
    parser.add_argument("--fps", type=int, default=30, help="fixed capture fps")
    parser.add_argument("--out", default="docs/media/turret-showcase",
                        help="output path without an extension")
    parser.add_argument("--gif-width", type=int, default=720)
    parser.add_argument("--keep-frames", action="store_true",
                        help="leave the PNG sequence behind for a manual re-encode")
    parser.add_argument("--frames-dir", default="",
                        help="encode an existing sequence instead of recording a new one")
    parser.add_argument("--state", default="",
                        help="with --frames-dir: the demo_state JSON saved by that run")
    args = parser.parse_args()

    out_base = (PROJECT / args.out) if not Path(args.out).is_absolute() else Path(args.out)

    if args.frames_dir:
        frames_dir = Path(args.frames_dir)
        state = json.loads(Path(args.state).read_text(encoding="utf-8")) if args.state \
            else json.loads((frames_dir / "state.json").read_text(encoding="utf-8"))
    else:
        frames_dir = Path(tempfile.mkdtemp(prefix="gather_clip_"))
        state = record(args.clip, args.fps, frames_dir)
        (frames_dir / "state.json").write_text(json.dumps(state, indent=2), encoding="utf-8")

    try:
        encode(state, frames_dir, out_base, args.fps, args.gif_width)
    finally:
        if not args.keep_frames and not args.frames_dir:
            shutil.rmtree(frames_dir, ignore_errors=True)
        else:
            print(f"capture_clip: frames kept at {frames_dir}")


if __name__ == "__main__":
    main()
