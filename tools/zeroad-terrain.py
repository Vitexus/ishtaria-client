#!/usr/bin/env python3
"""Exports selected 0 A.D. terrain albedo maps (CC BY-SA 3.0) as PNG for optional surface detail.

    python3 -I tools/zeroad-terrain.py PUBLIC_ZIP assets/zeroad/terrain

These are bundled for Gilgamesh / Persian-fringe variety. The client detail shader still defaults
to Poly Haven layers; swap or blend these PNGs into tex_sand / tex_soil / tex_rock when desired.
"""
from __future__ import annotations

import io
import sys
import zipfile
from pathlib import Path

from PIL import Image

# short_name: path under art/textures/terrain/types/
MAPS: dict[str, str] = {
    "desert_dirt_persia_1": "desert_dirt_persia_1.png.cached.dds",
    "desert_dirt_persia_2": "desert_dirt_persia_2.png.cached.dds",
    "desert_dirt_persia_rocks": "desert_dirt_persia_rocks.png.cached.dds",
    "desert_dirt_persia_rocky": "desert_dirt_persia_rocky.png.cached.dds",
    "desert_cliff_persia_1": "desert_cliff_persia_1.png.cached.dds",
    "desert_cliff_persia_2": "desert_cliff_persia_2.png.cached.dds",
    "desert_cliff_persia_base": "desert_cliff_persia_base.png.cached.dds",
    "desert_plants_b_persia": "desert_plants_b_persia.png.cached.dds",
    "persia_dirt_plants_01": "persia/dirt_plants_01.png.cached.dds",
    "desert_farmland": "desert_farmland.png.cached.dds",
    "desert_city_tile_pers": "desert_city_tile_pers.png.cached.dds",
}


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    archive, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as store:
        for name, rel in MAPS.items():
            image = Image.open(io.BytesIO(store.read(f"art/textures/terrain/types/{rel}"))).convert("RGBA")
            image.thumbnail((1024, 1024), Image.LANCZOS)
            path = out / f"{name}.png"
            image.save(path, "PNG", optimize=True)
            print(f"{name}.png: {image.size[0]}x{image.size[1]} {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
