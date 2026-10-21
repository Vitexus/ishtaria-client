#!/usr/bin/env python3
"""Converts selected Achaemenid / Persian 0 A.D. structures (CC BY-SA 3.0) to GLB.

    python3 -I tools/zeroad-structures.py PUBLIC_ZIP OUT_DIR

OUT_DIR is typically:
  assets/zeroad/structures
  or ../ishtaria-datadisk-gilgamesh/media/models/architecture/zeroad

Same PSMD → glTF path as tools/zeroad-scenery.py. Catalogue / place ids: `zeroad.<name>`
or `media/models/architecture/zeroad/<name>.glb` on the Gilgamesh disk.
"""
from __future__ import annotations

import io
import json
import struct
import sys
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

# name: (mesh under art/meshes/, texture under art/textures/skins/, z_up)
PARTS: dict[str, tuple[str, str, bool]] = {
    "pers_palace": ("structural/pers_palace.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_temple": ("structural/pers_temple_1.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_apadana": ("structural/pers_sb_1_new.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_fortress": ("structural/pers_fortress.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_wall_gate": ("structural/pers_wall_gate.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_tachara": ("structural/pers_civic.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_lamassu": ("structural/pers_lamassu.dae.cached.pmd", "structural/pers_lamassu.png.cached.dds", True),
    "pers_dock": ("structural/pers_dock.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_wall_tower": ("structural/pers_wall_tower.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_scout_tower": ("structural/pers_scout_tower_a.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_barracks": ("structural/pers_barracks.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_market": ("structural/pers_market_a.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_shrine": ("structural/pers_shrine.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_house_a": ("structural/pers_house_a.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_house_b": ("structural/pers_house_b.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_hall": ("structural/pers_sb2.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_storehouse": ("structural/pers_storehouse.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_farmstead": ("structural/pers_farmstead.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_workshop": ("structural/pers_workshop.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "baby_defense_tower": ("structural/baby_defense_tower.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_blacksmith": ("structural/pers_blacksmith.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_corral": ("structural/pers_corral.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_stable": ("structural/pers_stable.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_range": ("structural/pers_range.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_wooden_tower": ("structural/pers_wooden_tower.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_ballista_tower": ("structural/pers_ballista_tower.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_wall_long": ("structural/pers_wall_long.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_wall_medium": ("structural/pers_wall_medium.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_wall_short": ("structural/pers_wall_short.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_house_c": ("structural/pers_house_c.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_house_d": ("structural/pers_house_d.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_market_b": ("structural/pers_market_b.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_fortress_b": ("structural/pers_fortress_b.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_lamassu_small": ("structural/pers_lamassu_small.dae.cached.pmd", "structural/pers_lamassu.png.cached.dds", True),
    "pers_plinth": ("structural/pers_plinth.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_gardens": ("structural/pers_gardens_struct.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    # Ships and siege (harbour landmarks / military diversity)
    "pers_bireme": ("structural/pers_ship_bireme.dae.cached.pmd", "structural/pers_bireme.png.cached.dds", True),
    "pers_trireme": ("structural/pers_ship_trireme.dae.cached.pmd", "structural/pers_trireme.png.cached.dds", True),
    "pers_merchant": ("structural/pers_merc.dae.cached.pmd", "structural/pers_merc.dds.cached.dds", True),
    "pers_fishship": ("structural/pers_fishship.dae.cached.pmd", "structural/pers_fishship.dds.cached.dds", True),
    "pers_siege_ram": ("structural/pers_ram.dae.cached.pmd", "structural/assyrian_ram_2.png.cached.dds", True),
    "pers_ice_house": ("structural/pers_ice_house_01.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_stable_elephant": ("structural/pers_stable_elephant.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_scout_tower_b": ("structural/pers_scout_tower_b.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    # Ishtar Gate (Babylon landmark) and chariots
    "pers_ishtar": ("structural/pers_ishtar.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
    "pers_chariot_a": ("structural/pers_chariot_a.dae.cached.pmd", "structural/pers_chariot_a.png.cached.dds", True),
    "pers_chariot_b": ("structural/pers_chariot_b.dae.cached.pmd", "structural/pers_chariot_b.png.cached.dds", True),
    "pers_chariot_e": ("structural/pers_chariot_e.dae.cached.pmd", "structural/pers_chariot_e.png.cached.dds", True),
    "pers_ice_house_b": ("structural/pers_ice_house_02.dae.cached.pmd", "structural/pers_struct.png.cached.dds", True),
}


def read_pmd(data: bytes):
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    if magic != b"PSMD" or version < 4:
        raise SystemExit("not a PSMD version 4 model")
    (count,) = struct.unpack_from("<I", data, 12)
    (uv_sets,) = struct.unpack_from("<I", data, 16)
    stride = 24 + 8 * uv_sets + 20
    raw = np.frombuffer(data, dtype=np.uint8, count=count * stride, offset=20).reshape(count, stride)
    offset = 20 + count * stride
    positions = raw[:, 0:12].copy().view("<f4").reshape(count, 3)
    normals = raw[:, 12:24].copy().view("<f4").reshape(count, 3)
    uvs = raw[:, 24:32].copy().view("<f4").reshape(count, 2)
    (faces,) = struct.unpack_from("<I", data, offset)
    indices = np.frombuffer(data, dtype="<u2", count=faces * 3, offset=offset + 4).reshape(faces, 3)
    return positions.astype(np.float64), indices.astype(np.uint32), normals.astype(np.float64), uvs.astype(np.float64)


def authored(positions, faces, normals, uvs, z_up):
    def up(points):
        return np.stack([points[:, 0], points[:, 2], -points[:, 1]], axis=1) if z_up else points

    points = up(positions)
    points = points - np.array(
        [(points[:, 0].min() + points[:, 0].max()) / 2, points[:, 1].min(), (points[:, 2].min() + points[:, 2].max()) / 2]
    )
    flat = faces.reshape(-1)
    return (
        points[flat].astype("<f4"),
        up(normals)[flat].astype("<f4"),
        np.stack([uvs[flat, 0], 1.0 - uvs[flat, 1]], axis=1).astype("<f4"),
    )


def glb(positions, normals, uvs, png: bytes) -> bytes:
    count = len(positions)
    indices = np.arange(count, dtype="<u4")
    blobs = [indices.tobytes(), positions.tobytes(), normals.tobytes(), uvs.tobytes(), png]
    views, offset, body = [], 0, b""
    for number, blob in enumerate(blobs):
        padded = blob + b"\0" * (-len(blob) % 4)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob)})
        if number < 4:
            views[-1]["target"] = 34963 if number == 0 else 34962
        body += padded
        offset += len(padded)
    document = {
        "asset": {"version": "2.0", "generator": "ishtaria-client/tools/zeroad-structures.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 1, "NORMAL": 2, "TEXCOORD_0": 3}, "indices": 0, "material": 0}]}],
        "materials": [
            {
                "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.05, "roughnessFactor": 0.85},
                "doubleSided": False,
            }
        ],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "images": [{"bufferView": 4, "mimeType": "image/png"}],
        "buffers": [{"byteLength": len(body)}],
        "bufferViews": views,
        "accessors": [
            {"bufferView": 0, "componentType": 5125, "count": count, "type": "SCALAR"},
            {
                "bufferView": 1,
                "componentType": 5126,
                "count": count,
                "type": "VEC3",
                "min": positions.min(0).tolist(),
                "max": positions.max(0).tolist(),
            },
            {"bufferView": 2, "componentType": 5126, "count": count, "type": "VEC3"},
            {"bufferView": 3, "componentType": 5126, "count": count, "type": "VEC2"},
        ],
    }
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(body)
    return (
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<I4s", len(text), b"JSON")
        + text
        + struct.pack("<I4s", len(body), b"BIN\0")
        + body
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    archive, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as store:
        for name, (mesh, skin, z_up) in PARTS.items():
            positions, faces, normals, uvs = read_pmd(store.read(f"art/meshes/{mesh}"))
            image = Image.open(io.BytesIO(store.read(f"art/textures/skins/{skin}"))).convert("RGBA")
            image.thumbnail((1024, 1024), Image.LANCZOS)
            buf = io.BytesIO()
            image.save(buf, "PNG", optimize=True)
            pos, norms, tex = authored(positions, faces, normals, uvs, z_up)
            data = glb(pos, norms, tex, buf.getvalue())
            (out / f"{name}.glb").write_bytes(data)
            extent = np.ptp(pos, axis=0)
            print(f"{name}.glb: {len(faces)} tris, {len(data)} bytes, extent {extent.round(2)}")


if __name__ == "__main__":
    main()
