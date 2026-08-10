#!/usr/bin/env python3
"""Bake a game-icons.net SVG into a CARVE LUT via msdfgen's true SDF.

Replaces the rasterize + chamfer-distance path (TextureCarveShape.bake_lut)
for icons sourced from game-icons.net: the SVG stays vector all the way into
the signed distance field, so the LUT never sees pixel quantization.

Per icon:
  SVG paths (background rect stripped, all concatenated into ONE <path> —
  msdfgen only loads the last path, and SVG subpaths are just more M
  commands) -> msdfgen sdf -> fl32 -> numpy post-process
  (drop field + gradient + smooth SDF alpha mask) -> RGBA8 PNG.

The LUT encoding contract is identical to TextureCarveShape.bake_lut()
(DEPTH / GRAD_SCALE / TEXELS_PER_UNIT_P mirror that script; keep them in
lock-step with lighting.gdshaderinc's SN_TEXTURE_DEPTH_SCALE /
SN_TEXTURE_GRAD_SCALE). See docs/domain/emblem-bake.md.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

# Mirror TextureCarveShape.gd — do not drift.
LUT_SIZE = 256
DEPTH = 0.35
GRAD_SCALE = 3.0
TEXELS_PER_UNIT_P = LUT_SIZE * 0.5

SVG_NS = "{http://www.w3.org/2000/svg}"
BACKGROUND_D = "M0 0h512v512H0z"

# msdfgen pixel range: -4px outside (smooth alpha AA margin) .. +256px
# inside (ample for any icon's medial axis at 256px — a full-frame shape's
# center is at most ~124px from its edge). With -autoframe the frame
# shrinks by 2*|lower|, so the shape footprint is 248px — matching the old
# raster bake's ~94% fill — and the 4px exterior budget is the AA margin.
PX_RANGE = (-4.0, 256.0)
PX_SPAN = PX_RANGE[1] - PX_RANGE[0]


def extract_paths(svg_path: str) -> list[str]:
    """All <path d="..."> in the SVG, skipping the game-icons background rect."""
    tree = ET.parse(svg_path)
    paths = []
    for elem in tree.getroot().iter():
        if elem.tag != SVG_NS + "path":
            continue
        d = (elem.get("d") or "").strip()
        if not d or d == BACKGROUND_D:
            continue
        if elem.get("transform"):
            print("warning: path transform ignored by msdfgen: %s" % d[:40])
        paths.append(d)
    return paths


def write_combined_svg(paths: list[str], out_path: str) -> None:
    combined = " ".join(paths)
    with open(out_path, "w") as f:
        f.write(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">\n'
            '<path d="%s"/>\n'
            "</svg>\n" % combined
        )


def run_msdfgen(svg_path: str, out_fl32: str) -> np.ndarray:
    cmd = [
        "msdfgen", "sdf",
        "-svg", svg_path,
        "-o", out_fl32,
        "-format", "fl32",
        "-dimensions", str(LUT_SIZE), str(LUT_SIZE),
        "-apxrange", str(PX_RANGE[0]), str(PX_RANGE[1]),
        "-autoframe",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            "msdfgen failed (%d): %s" % (result.returncode, result.stderr.strip())
        )
    if result.stderr.strip():
        print("  msdfgen: %s" % result.stderr.strip())
    data = np.fromfile(out_fl32, dtype=np.uint8)
    # FL32 layout: 16-byte header ("FL32" + height + width + channels LE),
    # then width*height*channels float32s, rows already reoriented y-up.
    if data.size < 16 + LUT_SIZE * LUT_SIZE * 4:
        raise RuntimeError(
            "msdfgen returned %d bytes, expected >= %d"
            % (data.size, 16 + LUT_SIZE * LUT_SIZE * 4)
        )
    sdf = data[16:].view(np.float32).reshape(LUT_SIZE, LUT_SIZE)
    # The bitmap is y-up (row 0 = bottom row). The LUT is a y-down image
    # (PNG/Godot convention), so flip before encoding.
    return np.flipud(sdf)


def sdf_to_lut(sdf: np.ndarray) -> np.ndarray:
    # msdfgen's normalized bitmap value -> signed distance in pixels.
    d_px = sdf.astype(np.float64) * PX_SPAN + PX_RANGE[0]

    inside = d_px > 0.0
    max_interior = float(np.max(d_px[inside])) if np.any(inside) else 1.0

    # Intaglio dent: 0 at the silhouette boundary, DEPTH at the deepest
    # interior texel (the medial axis). Same formula as bake_lut().
    drop = DEPTH * np.clip(np.maximum(d_px, 0.0) / max_interior, 0.0, 1.0)

    # Central-difference gradient of the drop field, drop-per-unit-p
    # (matches _gradient_at's TEXELS_PER_UNIT_P conversion).
    gy, gx = np.gradient(drop)
    gx *= TEXELS_PER_UNIT_P
    gy *= TEXELS_PER_UNIT_P

    # Smooth alpha mask: ~1 well inside, ~0 well outside, ~2px AA ramp.
    alpha = np.clip(d_px * 0.5 + 0.5, 0.0, 1.0)

    r = np.clip(drop / DEPTH, 0.0, 1.0)
    g = np.clip(gx / GRAD_SCALE * 0.5 + 0.5, 0.0, 1.0)
    b = np.clip(gy / GRAD_SCALE * 0.5 + 0.5, 0.0, 1.0)

    rgba = np.stack([r, g, b, alpha], axis=-1)
    return (rgba * 255.0 + 0.5).astype(np.uint8)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("svg", help="source SVG path (game-icons.net)")
    parser.add_argument("output", help="output LUT PNG path")
    args = parser.parse_args()

    paths = extract_paths(args.svg)
    if not paths:
        print("warning: no non-background paths in %s — writing empty LUT" % args.svg)
        Image.new("RGBA", (LUT_SIZE, LUT_SIZE), (0, 0, 0, 0)).save(args.output)
        return 0

    tmpdir = tempfile.mkdtemp(prefix="bake_svg_sdf_")
    try:
        svg_tmp = os.path.join(tmpdir, "combined.svg")
        fl32_tmp = os.path.join(tmpdir, "sdf.fl32")
        write_combined_svg(paths, svg_tmp)
        sdf = run_msdfgen(svg_tmp, fl32_tmp)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    rgba = sdf_to_lut(sdf)
    Image.fromarray(rgba, "RGBA").save(args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
