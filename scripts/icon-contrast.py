#!/usr/bin/env python3
"""Report how well icons read on the surface they sit on.

An icon disappears into a near-black surface when *every* channel of its visible
pixels is low. Brightness alone is the wrong metric: a saturated red has a low
luminance and reads perfectly, while a black glyph has no contrast at all. So
the number reported here is the share of "real black" pixels (max channel below
--threshold), not luminance.

The light direction is the same measurement mirrored, because the desktop's
paper palette hit the same bug from the other side: brand marks shipped as pure
white artwork (the Nous and OpenCode marks were 100 % and 78 % `#ffffff`) vanish
on a light card while every dark-surface check said they were fine. With
--background light the share counted is "real white" (min channel above
255 - --threshold), which is what a light surface swallows.

Usage:
  icon-contrast.py [--background dark|light] [--threshold N] [--limit PCT] <file-or-dir>...

Exit code: 0 when every icon reads on the chosen surface, 1 when at least one
does not, 2 on a usage or decoding error.
"""

import argparse
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

RASTER_SUFFIXES = {".png", ".webp", ".jpg", ".jpeg"}
VISIBLE_ALPHA = 8


class DecodeError(RuntimeError):
    pass


def ffmpeg_binary() -> str:
    binary = shutil.which("ffmpeg")
    if binary is None:
        raise DecodeError("ffmpeg not found: install ffmpeg to decode icons")
    return binary


def rgba_pixels(path: Path) -> bytes:
    """Decode any raster icon to raw RGBA bytes, whatever its pixel format."""
    done = subprocess.run(
        [ffmpeg_binary(), "-v", "error", "-i", str(path),
         "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
        capture_output=True,
    )
    if done.returncode != 0:
        message = done.stderr.decode("utf-8", "replace").strip().splitlines()
        raise DecodeError(message[0] if message else "ffmpeg could not decode the file")
    if not done.stdout:
        raise DecodeError("no pixels decoded")
    return done.stdout


def measure(path: Path, threshold: int, limit: float, background: str) -> dict:
    pixels = rgba_pixels(path)
    total = len(pixels) // 4
    rgb = [(pixels[i], pixels[i + 1], pixels[i + 2])
           for i in range(0, len(pixels) - 3, 4) if pixels[i + 3] > VISIBLE_ALPHA]
    if not rgb:
        return {"name": path.name, "coverage": 0.0, "vanishing": 0.0, "saturation": 0.0,
                "luminance": 0.0, "verdict": "empty (no visible pixels)"}

    # The same question from both sides: how much of the artwork is the colour of
    # the surface behind it. Dark: near-black pixels. Light: near-white ones.
    if background == "light":
        white_floor = 255 - threshold
        vanishing = sum(1 for r, g, b in rgb if min(r, g, b) > white_floor) / len(rgb)
    else:
        vanishing = sum(1 for r, g, b in rgb if max(r, g, b) < threshold) / len(rgb)
    saturation = statistics.mean(
        0.0 if max(r, g, b) == 0 else (max(r, g, b) - min(r, g, b)) / max(r, g, b)
        for r, g, b in rgb
    )
    luminance = statistics.mean(0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in rgb)

    surface = "paper" if background == "light" else "black"
    if vanishing * 100 >= limit:
        verdict = f"DISAPPEARS on {surface}"
    elif saturation > 0.25:
        verdict = "brand color, fine"
    elif background == "light":
        verdict = "dark artwork, fine"
    else:
        verdict = "light artwork, fine"

    return {"name": path.name, "coverage": len(rgb) / total, "vanishing": vanishing * 100,
            "saturation": saturation, "luminance": luminance, "verdict": verdict}


def collect(targets: list[str]) -> list[Path]:
    found: list[Path] = []
    for target in targets:
        path = Path(target).expanduser()
        if path.is_dir():
            found.extend(sorted(p for p in path.iterdir()
                                if p.suffix.lower() in RASTER_SUFFIXES))
            continue
        if not path.is_file():
            print(f"icon-contrast: no such file or directory: {path}", file=sys.stderr)
            continue
        if path.suffix.lower() not in RASTER_SUFFIXES:
            print(f"icon-contrast: {path.name}: not a raster icon "
                  f"({path.suffix or 'no suffix'}); rasterise it first", file=sys.stderr)
            continue
        found.append(path)
    return found


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Check icon contrast on its surface.")
    parser.add_argument("targets", nargs="+", help="icon files or directories")
    parser.add_argument("--background", choices=("dark", "light"), default="dark",
                        help="surface the icons sit on (default dark)")
    parser.add_argument("--threshold", type=int, default=60,
                        help="channel bound outside which a pixel counts as the surface "
                             "(black below it, white above 255-N; default 60)")
    parser.add_argument("--limit", type=float, default=None,
                        help="share of surface-coloured pixels that makes an icon unreadable "
                             "(default 80 on dark, 50 on light)")
    args = parser.parse_args(argv)
    # Two defaults, one per direction, because black and white are not symmetric in
    # artwork: near-black pixels are also the outlines and shadows that give a dark
    # logo its shape, so only a nearly all-black icon is gone. Nothing white belongs
    # in a mark on paper except the mark's own disappearance, so half is already too
    # much -- the OpenCode frame is 78 % white and reads as a grey block only.
    if args.limit is None:
        args.limit = 50.0 if args.background == "light" else 80.0

    icons = collect(args.targets)
    if not icons:
        return 2

    column = "white" if args.background == "light" else "black"
    print(f"{'icon':34s} {'cover':>7s} {column:>7s} {'sat':>5s} {'lum':>6s}  verdict")
    unreadable = 0
    for icon in icons:
        try:
            row = measure(icon, args.threshold, args.limit, args.background)
        except DecodeError as error:
            print(f"{icon.name:34s} {'--':>7s} {'--':>7s} {'--':>5s} {'--':>6s}  "
                  f"unreadable file: {error}")
            unreadable += 1
            continue
        print(f"{row['name']:34s} {row['coverage']:7.1%} {row['vanishing']:6.1f}% "
              f"{row['saturation']:5.2f} {row['luminance']:6.1f}  {row['verdict']}")
        if row["verdict"].startswith("DISAPPEARS"):
            unreadable += 1

    surface = "a light" if args.background == "light" else "a dark"
    print(f"\n{unreadable} of {len(icons)} icons disappear on {surface} surface.")
    return 1 if unreadable else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
