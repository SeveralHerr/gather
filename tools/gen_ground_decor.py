"""Generates assets/art/ground_decor.png — the scattered ground decoration sheet.

    python tools/gen_ground_decor.py                    # the chosen style, 6 tiles
    python tools/gen_ground_decor.py --catalogue        # all styles side by side, for picking
    python tools/gen_ground_decor.py --style strewn --preview out.png

Checked in as a generator rather than only as a PNG because the palette, the outline and
the light direction are rules, and a rule is easier to re-apply than to re-derive from
pixels. The palette is taken from assets/art/tiles.png and nothing else (Resurrect 64).

Three things were learned making this, all of them the hard way:

  - **The outline is the house style.** Every sprite in this game — the cliff fringe, the
    trees, the rocks — is a filled shape with a dark outline and a light top-left
    highlight. Decoration without one reads as a stain on the grass whatever its shape.
    Outlines are derived from the silhouette here rather than drawn, because a hand-drawn
    outline at 16px is always one pixel wrong somewhere and that pixel is what the eye
    finds first.
  - **Flat, not standing.** The ground is top-down, so decoration is drawn as seen from
    directly above: lobes and leaves lying on the ground, centred in the tile. An earlier
    pass drew side-view blades rooted at the tile's bottom edge; they read as grass and
    fought the perspective of everything under them.
  - **Decoration must lose to content.** Trees and ore are what the player clicks. The
    fill is #33984B, one step darker than the #5AC54F grass, and #99E65F is spent only on
    the lit edge. The very first sprite here was a flat #005D00 — a colour appearing in no
    other tile in the game — which is why it read as an insect sitting on the lawn.
"""

import argparse
import math

from PIL import Image

SIZE = 16
GRASS = (0x5A, 0xC5, 0x4F, 255)
T = (0, 0, 0, 0)

D = (0x1E, 0x6F, 0x50, 255)   # outline
M = (0x33, 0x98, 0x4B, 255)   # fill
L = (0x99, 0xE6, 0x5F, 255)   # lit edge
W = (0xFF, 0xFF, 0xFF, 255)
WS = (0x92, 0xA1, 0xB9, 255)  # white's outline - the palette's light slate
Y = (0xFF, 0xC8, 0x25, 255)
O = (0xFF, 0xA2, 0x14, 255)
R = (0xF5, 0x55, 0x5D, 255)
RD = (0xC4, 0x24, 0x30, 255)

## Relative weight of each column, grass first. Grass is the substrate and flowers are the
## punctuation: 22 parts in 100 of the decorated cells, at 18% of cells decorated, puts a
## flower on roughly one grass tile in 25. Mirrored in main.gd's DECOR_WEIGHTS.
WEIGHTS = [34, 26, 18, 8, 8, 6]


def blank():
    return [[T] * SIZE for _ in range(SIZE)]


def put(g, x, y, c):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        g[y][x] = c


def lobe(g, cx, cy, r, colour=M):
    for y in range(cy - r - 1, cy + r + 2):
        for x in range(cx - r - 1, cx + r + 2):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + r:
                put(g, x, y, colour)


def leaf(g, cx, cy, angle, half, colour=M):
    """A flat lozenge lying at `angle` — a leaf seen from directly above."""
    for i in range(-half, half + 1):
        x = int(round(cx + math.cos(angle) * i))
        y = int(round(cy + math.sin(angle) * i))
        put(g, x, y, colour)
        if abs(i) <= half - 1:          # thicken the middle so it is a leaf, not a line
            put(g, x, y + 1, colour)


def highlight(g, colour=L, into=M):
    """One lit pixel wherever the fill meets empty space up and to the left, which is the
    light direction every other sprite in the game uses."""
    for y in range(SIZE):
        for x in range(SIZE):
            if g[y][x] == into:
                above = g[y - 1][x] if y > 0 else T
                left = g[y][x - 1] if x > 0 else T
                if above == T and left == T:
                    g[y][x] = colour


def outline(g, colour=D):
    """Every empty pixel 4-adjacent to the silhouette."""
    edge = set()
    for y in range(SIZE):
        for x in range(SIZE):
            if g[y][x] == T:
                continue
            for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < SIZE and 0 <= ny < SIZE and g[ny][nx] == T:
                    edge.add((nx, ny))
    for x, y in edge:
        g[y][x] = colour


# --- the grass families -------------------------------------------------------

def clusters(lobes, radius=2, spread=3.0, phase=0.0):
    """Rounded lobes around a centre — a leafy plant seen from above."""
    g = blank()
    for i in range(lobes):
        a = phase + i * math.tau / lobes
        lobe(g, int(round(8 + math.cos(a) * spread)), int(round(8 + math.sin(a) * spread)), radius)
    highlight(g)
    outline(g)
    return g


def sprays(blades, half=3, phase=0.0):
    """Leaves splayed outward from a centre into a star."""
    g = blank()
    for i in range(blades):
        leaf(g, 8, 8, phase + i * math.pi / blades, half)
    highlight(g)
    outline(g)
    return g


def patches(radius=3):
    """A single round patch of denser grass — the quietest family."""
    g = blank()
    lobe(g, 8, 8, radius)
    highlight(g)
    outline(g)
    return g


def strewn(count, phase=0.0):
    """Loose leaves lying flat with no shared centre."""
    g = blank()
    spots = [(6, 6, 0.4), (10, 9, 2.1), (7, 10, 1.2), (10, 5, 2.6), (5, 9, 0.8)]
    for cx, cy, a in spots[:count]:
        leaf(g, cx, cy, a + phase, 2)
    highlight(g)
    outline(g)
    return g


def bloom(petal, centre, rim, petals=5, radius=1.6, petal_r=0):
    """A flower head seen from directly above.

    Outlined in the petal's own darker tone rather than in green: a white bloom ringed in
    dark green reads as a leaf with a hole in it, which is not what anybody wants to find
    in a meadow.

    `radius` and `petal_r` are small on purpose and were both halved after seeing the first
    version in the running game. A 16px tile is 128px on screen at the camera's 8x zoom, so
    a bloom spanning 11 of those pixels came out larger than a rock and read as something to
    walk over and pick up. Roughly five pixels across is the size at which it is plainly a
    flower and plainly scenery.
    """
    g = blank()
    for i in range(petals):
        a = i * math.tau / petals - math.pi / 2
        lobe(g, int(round(8 + math.cos(a) * radius)), int(round(8 + math.sin(a) * radius)),
             petal_r, petal)
    outline(g, rim)
    lobe(g, 8, 8, 0, centre)
    return g


BLOOMS = [bloom(W, Y, WS), bloom(Y, O, O), bloom(R, RD, RD)]

STYLES = {
    "clusters": [clusters(3, 2, 3.0, 0.5), clusters(4, 2, 3.2, 0.2), clusters(5, 2, 3.6, 0.9)],
    "sprays":   [sprays(2, 3, 0.3), sprays(3, 3, 0.0), sprays(4, 4, 0.4)],
    "patches":  [patches(2), patches(3), clusters(3, 2, 2.4, 0.3)],
    "strewn":   [strewn(2), strewn(3, 0.5), strewn(5, 0.2)],
}

## The order the catalogue lays them out in, and the order main.gd's decor_style indexes.
STYLE_ORDER = ["clusters", "sprays", "patches", "strewn"]

## The one that ships. Set by whoever picked it; --style overrides for a one-off render.
DEFAULT_STYLE = "strewn"


def tiles_for(style):
    return STYLES[style] + BLOOMS


def sheet_for(tiles):
    im = Image.new("RGBA", (SIZE * len(tiles), SIZE), T)
    for i, g in enumerate(tiles):
        for y in range(SIZE):
            for x in range(SIZE):
                if g[y][x] != T:
                    im.putpixel((i * SIZE + x, y), g[y][x])
    return im


def catalogue():
    """Every style's six tiles on one sheet, in STYLE_ORDER.

    Exists so all four can be compared inside the running game from a single reimport:
    main.gd's decor_style picks which six-column family it reads, so switching styles is a
    relaunch rather than a re-import of the atlas.
    """
    tiles = []
    for style in STYLE_ORDER:
        tiles += tiles_for(style)
    return sheet_for(tiles)


def field(tiles, cols=22, rows=8, chance=0.18, seed=5):
    """The tiles scattered the way the game scatters them. Judging a decoration tile on its
    own says nothing about the only thing that matters, which is what a field of them does."""
    import random
    rng = random.Random(seed)
    im = Image.new("RGBA", (cols * SIZE, rows * SIZE), GRASS)
    pool = []
    for i, w in enumerate(WEIGHTS):
        pool += [i] * w
    for cy in range(rows):
        for cx in range(cols):
            if rng.random() >= chance:
                continue
            g = tiles[rng.choice(pool)]
            flip = rng.random() < 0.5
            for y in range(SIZE):
                for x in range(SIZE):
                    c = g[y][SIZE - 1 - x] if flip else g[y][x]
                    if c != T:
                        im.putpixel((cx * SIZE + x, cy * SIZE + y), c)
    return im


def write_preview(tiles, path, scale=5):
    s = sheet_for(tiles)
    big = s.resize((s.size[0] * scale, s.size[1] * scale), Image.NEAREST)
    f = field(tiles)
    panel = Image.new("RGBA", (max(big.size[0], f.size[0]), big.size[1] + f.size[1] + 10), GRASS)
    panel.paste(big, (0, 0), big)
    panel.paste(f, (0, big.size[1] + 10))
    panel.resize((panel.size[0] * 2, panel.size[1] * 2), Image.NEAREST).save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default="assets/art/ground_decor.png")
    ap.add_argument("--style", default=DEFAULT_STYLE, choices=STYLE_ORDER)
    ap.add_argument("--catalogue", action="store_true",
                    help="emit every style's six columns on one sheet, for side-by-side picking")
    ap.add_argument("--preview", help="also write a magnified strip over a scattered field")
    args = ap.parse_args()

    if args.catalogue:
        sheet = catalogue()
        sheet.save(args.out)
        print("wrote %s %dx%d - catalogue of %d styles: %s" % (
            args.out, sheet.size[0], sheet.size[1], len(STYLE_ORDER), ", ".join(STYLE_ORDER)))
    else:
        tiles = tiles_for(args.style)
        sheet = sheet_for(tiles)
        sheet.save(args.out)
        print("wrote %s %dx%d - style '%s'" % (args.out, sheet.size[0], sheet.size[1], args.style))

    if args.preview:
        write_preview(tiles_for(args.style), args.preview)
        print("preview: %s" % args.preview)


if __name__ == "__main__":
    main()
