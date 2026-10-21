#!/usr/bin/env python3
"""Converts selected 0 A.D. flora (Wildfire Games, CC BY-SA 3.0) to GLB.

    python3 -I tools/zeroad-scenery.py PUBLIC_ZIP assets/zeroad

PUBLIC_ZIP is `binaries/data/mods/public/public.zip` of the 0ad-data package (or an extracted tree
passed as a directory). Meshes are the compiled PSMD files (`*.dae.cached.pmd`); textures are the
cached DDS/PNG skins. Output:

    assets/zeroad/flora/<name>.glb

Fauna with Idle/Walk clips is owned by tools/zeroad-fauna-anim.py — do not add fauna PARTS here
or static bind-pose exports will overwrite the animated GLBs.

Same conversion as tools/zeroad-bridges.py: Z-up to Y-up, centred on the footprint, standing on
y = 0, textures at most 1024 px and embedded. Catalogue ids are `zeroad.<name>`.
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

# name: (kind, mesh under art/meshes/, texture under art/textures/skins/, z_up)
# Priority 1 for the Gilgamesh floodplain / Epic wild places (see datadisk research/FLORA.md, FAUNA.md).
PARTS: dict[str, tuple[str, str, str, bool]] = {
    # Flora — date palms, reeds, papyrus, cattails
    "palm_date_a": ("flora", "gaia/tree_palm_date_a.dae.cached.pmd", "gaia/tree_palmdate_a.dds.cached.dds", True),
    "palm_date_b": ("flora", "gaia/tree_palm_date_b.dae.cached.pmd", "gaia/tree_palmdate_a.dds.cached.dds", True),
    "palm_date_c": ("flora", "gaia/tree_palm_date_c.dae.cached.pmd", "gaia/tree_palmdate_b.dds.cached.dds", True),
    "palm_date_d": ("flora", "gaia/tree_palm_date_d.dae.cached.pmd", "gaia/tree_palmdate_a.dds.cached.dds", True),
    "palm_date_e": ("flora", "gaia/tree_palm_date_e.dae.cached.pmd", "gaia/tree_palmdate_b.dds.cached.dds", True),
    "palm_date_new_3": ("flora", "gaia/palm_date_new_3.dae.cached.pmd", "gaia/palm_date_new_1.png.cached.dds", True),
    "palm_date_new_4": ("flora", "gaia/palm_date_new_4.dae.cached.pmd", "gaia/palm_date_new_2.png.cached.dds", True),
    "palm_date_new_1": ("flora", "gaia/palm_date_new_1.dae.cached.pmd", "gaia/palm_date_new_1.png.cached.dds", True),
    "palm_date_new_2": ("flora", "gaia/palm_date_new_2.dae.cached.pmd", "gaia/palm_date_new_2.png.cached.dds", True),
    "reed_beach_a": ("flora", "gaia/reed_beach_a.dae.cached.pmd", "gaia/reeds_beach.dds.cached.dds", True),
    "reed_beach_b": ("flora", "gaia/reed_beach_b.dae.cached.pmd", "gaia/reeds_beach.dds.cached.dds", True),
    "reed_pond_lush": ("flora", "gaia/cross_large_tall.dae.cached.pmd", "gaia/reeds_pond_lush_a.dds.cached.dds", True),
    "papyrus_1": ("flora", "gaia/papyrus_1.dae.cached.pmd", "gaia/papyrus_1.png.cached.dds", True),
    "papyrus_2": ("flora", "gaia/papyrus_2.dae.cached.pmd", "gaia/papyrus_2.png.cached.dds", True),
    "cattails": ("flora", "gaia/cattails.dae.cached.pmd", "gaia/cattails_1.png.cached.dds", True),
    "tamarix_a": ("flora", "gaia/tree_tamarix_a.dae.cached.pmd", "gaia/trunk_deciduous_b.dds.cached.dds", True),
    # Priority 2 — Cedar Forest / highlands / Susa fringe
    "cedar_atlas_1": ("flora", "gaia/cedar_atlas_1.dae.cached.pmd", "gaia/cedar_atlas_1.png.cached.dds", True),
    "cedar_atlas_2": ("flora", "gaia/cedar_atlas_2.dae.cached.pmd", "gaia/cedar_atlas_2.png.cached.dds", True),
    "cedar_atlas_3": ("flora", "gaia/cedar_atlas_3.dae.cached.pmd", "gaia/cedar_atlas_2.png.cached.dds", True),
    "cypress_med": ("flora", "gaia/tree_cypress_med.dae.cached.pmd", "gaia/prop_tree_cypess.dds.cached.dds", True),
    "cypress_tall": ("flora", "gaia/tree_cypress_tall.dae.cached.pmd", "gaia/prop_tree_cypess_b.dds.cached.dds", True),
    "acacia_01": ("flora", "gaia/trees/trunks/acacia_01.dae.cached.pmd", "gaia/acacia.png.cached.dds", True),
    "poplar_lombardy": ("flora", "gaia/lombardy_poplar_01.dae.cached.pmd", "gaia/poplar_01.png.cached.dds", True),
    "bush_desert_a": ("flora", "gaia/bush_dese_a_1.dae.cached.pmd", "gaia/bush_dese_a.dds.cached.dds", True),
    # Priority 3 — gardens, highlands, southern fringe
    "willow_a": ("flora", "gaia/trees/willow_a.dae.cached.pmd", "gaia/willow_green.png.cached.dds", True),
    "olive_01": ("flora", "gaia/tree_olive_01.dae.cached.pmd", "gaia/tree_olive.png.cached.dds", True),
    "olive_02": ("flora", "gaia/tree_olive_02.dae.cached.pmd", "gaia/tree_olive.png.cached.dds", True),
    "olive_03": ("flora", "gaia/tree_olive_03.dae.cached.pmd", "gaia/tree_olive.png.cached.dds", True),
    "aleppo_pine_1": ("flora", "gaia/tree_pine_aleppo_1.dae.cached.pmd", "gaia/aleppo_pine.dds.cached.dds", True),
    "aleppo_pine_2": ("flora", "gaia/tree_pine_aleppo_2.dae.cached.pmd", "gaia/aleppo_pine.dds.cached.dds", True),
    "aleppo_pine_3": ("flora", "gaia/tree_pine_aleppo_3.dae.cached.pmd", "gaia/aleppo_pine.dds.cached.dds", True),
    "palm_doum_1": ("flora", "gaia/palm_doum_1.dae.cached.pmd", "gaia/palm_doum_1.png.cached.dds", True),
    "palm_doum_2": ("flora", "gaia/palm_doum_2.dae.cached.pmd", "gaia/palm_doum_1.png.cached.dds", True),
    # Fig canopy only (trunk+prop merge later); stands as orchard foliage
    "fig_top_a": ("flora", "gaia/tree_fig_top_a.dae.cached.pmd", "gaia/tree_carob_a.dds.cached.dds", True),
    "fig_top_b": ("flora", "gaia/tree_fig_top_b.dae.cached.pmd", "gaia/tree_carob_b.dds.cached.dds", True),
    # Remainder — marsh cane, Cretan date variants, more Aleppo understorey
    "reed_giant": ("flora", "gaia/papyrus_1.dae.cached.pmd", "gaia/giantcane.png.cached.dds", True),
    "cretan_date_01": ("flora", "gaia/tree_cretan_date_palm_01.dae.cached.pmd", "gaia/tree_palm_senegal_a.dds.cached.dds", True),
    "cretan_date_02": ("flora", "gaia/tree_cretan_date_palm_02.dae.cached.pmd", "gaia/tree_palm_senegal_a.dds.cached.dds", True),
    "cretan_date_03": ("flora", "gaia/tree_cretan_date_palm_03.dae.cached.pmd", "gaia/tree_palm_senegal_b.dds.cached.dds", True),
    "cretan_date_04": ("flora", "gaia/tree_cretan_date_palm_04.dae.cached.pmd", "gaia/tree_palm_senegal_b.dds.cached.dds", True),
    "aleppo_pine_4": ("flora", "gaia/tree_pine_aleppo_4.dae.cached.pmd", "gaia/aleppo_pine.dds.cached.dds", True),
    "aleppo_pine_5": ("flora", "gaia/tree_pine_aleppo_5.dae.cached.pmd", "gaia/aleppo_pine.dds.cached.dds", True),
    "aleppo_pine_6": ("flora", "gaia/tree_pine_aleppo_6.dae.cached.pmd", "gaia/aleppo_pine.dds.cached.dds", True),
    "aleppo_pine_7": ("flora", "gaia/tree_pine_aleppo_7.dae.cached.pmd", "gaia/aleppo_pine.dds.cached.dds", True),
    "aleppo_pine_8": ("flora", "gaia/tree_pine_aleppo_8.dae.cached.pmd", "gaia/aleppo_pine.dds.cached.dds", True),
    # Dead / fruiting remnants
    "palm_dead_1": ("flora", "gaia/palm_dead_1.dae.cached.pmd", "gaia/palm_dead.png.cached.dds", True),
    "palm_dead_2": ("flora", "gaia/palm_dead_2.dae.cached.pmd", "gaia/palm_dead.png.cached.dds", True),
    "palm_dead_3": ("flora", "gaia/palm_dead_3.dae.cached.pmd", "gaia/palm_dead.png.cached.dds", True),
    "palm_date_fruit_1": ("flora", "gaia/palm_date_new_fruit_1.dae.cached.pmd", "gaia/palm_date_new_3_fruiting.png.cached.dds", True),
    "palm_date_fruit_2": ("flora", "gaia/palm_date_new_fruit_2.dae.cached.pmd", "gaia/palm_date_new_3_fruiting.png.cached.dds", True),
    "cedar_atlas_dead_1": ("flora", "gaia/cedar_atlas_1.dae.cached.pmd", "gaia/cedar_atlas_dead.png.cached.dds", True),
    "cedar_atlas_dead_2": ("flora", "gaia/cedar_atlas_2.dae.cached.pmd", "gaia/cedar_atlas_dead.png.cached.dds", True),
    "poplar_lombardy_dead": ("flora", "gaia/lombardy_poplar_02.dae.cached.pmd", "gaia/poplar_dead.png.cached.dds", True),
}

# Full fig trees: trunk + canopy as two materials in one GLB (same root attach as 0 A.D.).
# name: (kind, [(mesh, texture), ...], z_up)
MERGED: dict[str, tuple[str, list[tuple[str, str]], bool]] = {
    "fig_a": (
        "flora",
        [
            ("gaia/tree_fig_trunk_a.dae.cached.pmd", "gaia/trunk_baobab.dds.cached.dds"),
            ("gaia/tree_fig_top_a.dae.cached.pmd", "gaia/tree_carob_a.dds.cached.dds"),
        ],
        True,
    ),
    "fig_b": (
        "flora",
        [
            ("gaia/tree_fig_trunk_b.dae.cached.pmd", "gaia/trunk_baobab.dds.cached.dds"),
            ("gaia/tree_fig_top_b.dae.cached.pmd", "gaia/tree_carob_b.dds.cached.dds"),
        ],
        True,
    ),
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


def authored(positions, faces, normals, uvs, z_up, centre: bool = True):
    def up(points):
        return np.stack([points[:, 0], points[:, 2], -points[:, 1]], axis=1) if z_up else points

    points = up(positions)
    if centre:
        points = points - np.array(
            [
                (points[:, 0].min() + points[:, 0].max()) / 2,
                points[:, 1].min(),
                (points[:, 2].min() + points[:, 2].max()) / 2,
            ]
        )
    flat = faces.reshape(-1)
    return (
        points[flat].astype("<f4"),
        up(normals)[flat].astype("<f4"),
        np.stack([uvs[flat, 0], 1.0 - uvs[flat, 1]], axis=1).astype("<f4"),
    )


def glb(positions, normals, uvs, png: bytes) -> bytes:
    return glb_multi([(positions, normals, uvs, png)])


def glb_multi(parts: list[tuple[np.ndarray, np.ndarray, np.ndarray, bytes]]) -> bytes:
    """One mesh, one primitive+material+texture per part (e.g. fig trunk + canopy)."""
    views, accessors, primitives, materials, textures, images = [], [], [], [], [], []
    offset, body = 0, b""

    def add_blob(blob: bytes, target: int | None = None) -> int:
        nonlocal offset, body
        view = len(views)
        padded = blob + b"\0" * (-len(blob) % 4)
        entry: dict = {"buffer": 0, "byteOffset": offset, "byteLength": len(blob)}
        if target is not None:
            entry["target"] = target
        views.append(entry)
        body += padded
        offset += len(padded)
        return view

    all_pos = []
    for part_i, (positions, normals, uvs, png) in enumerate(parts):
        count = len(positions)
        indices = np.arange(count, dtype="<u4")
        i_view = add_blob(indices.tobytes(), 34963)
        p_view = add_blob(positions.tobytes(), 34962)
        n_view = add_blob(normals.tobytes(), 34962)
        u_view = add_blob(uvs.tobytes(), 34962)
        img_view = add_blob(png)
        base = len(accessors)
        accessors.extend(
            [
                {"bufferView": i_view, "componentType": 5125, "count": count, "type": "SCALAR"},
                {
                    "bufferView": p_view,
                    "componentType": 5126,
                    "count": count,
                    "type": "VEC3",
                    "min": positions.min(0).tolist(),
                    "max": positions.max(0).tolist(),
                },
                {"bufferView": n_view, "componentType": 5126, "count": count, "type": "VEC3"},
                {"bufferView": u_view, "componentType": 5126, "count": count, "type": "VEC2"},
            ]
        )
        images.append({"bufferView": img_view, "mimeType": "image/png"})
        textures.append({"source": part_i, "sampler": 0})
        materials.append(
            {
                "pbrMetallicRoughness": {
                    "baseColorTexture": {"index": part_i},
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.9,
                },
                "doubleSided": True,
                "alphaMode": "MASK",
                "alphaCutoff": 0.4,
            }
        )
        primitives.append(
            {
                "attributes": {"POSITION": base + 1, "NORMAL": base + 2, "TEXCOORD_0": base + 3},
                "indices": base,
                "material": part_i,
            }
        )
        all_pos.append(positions)
    stacked = np.concatenate(all_pos, axis=0)
    # Recompute overall mins already in accessors; keep for validation.
    _ = stacked
    document = {
        "asset": {"version": "2.0", "generator": "ishtaria-client/tools/zeroad-scenery.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": primitives}],
        "materials": materials,
        "textures": textures,
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "images": images,
        "buffers": [{"byteLength": len(body)}],
        "bufferViews": views,
        "accessors": accessors,
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


class Store:
    def __init__(self, root: Path):
        self.root = root
        self.zip = zipfile.ZipFile(root) if root.is_file() else None

    def read(self, rel: str) -> bytes:
        if self.zip is not None:
            return self.zip.read(rel if not rel.startswith("art/") else rel)
        path = self.root / rel
        if not path.is_file():
            raise FileNotFoundError(rel)
        return path.read_bytes()

    def close(self) -> None:
        if self.zip is not None:
            self.zip.close()


def load_texture(store: Store, skin: str) -> bytes:
    data = store.read(f"art/textures/skins/{skin}")
    image = Image.open(io.BytesIO(data)).convert("RGBA")
    image.thumbnail((1024, 1024), Image.LANCZOS)
    png = io.BytesIO()
    image.save(png, "PNG", optimize=True)
    return png.getvalue()


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    archive, out_root = Path(sys.argv[1]), Path(sys.argv[2])
    store = Store(archive)
    done, skipped = 0, []
    try:
        for name, (kind, mesh, skin, z_up) in PARTS.items():
            mesh_rel = f"art/meshes/{mesh}"
            try:
                positions, faces, normals, uvs = read_pmd(store.read(mesh_rel))
                png = load_texture(store, skin)
            except (KeyError, FileNotFoundError, OSError, SystemExit) as err:
                skipped.append(f"{name}: {err}")
                continue
            pos, norms, tex = authored(positions, faces, normals, uvs, z_up)
            data = glb(pos, norms, tex, png)
            dest = out_root / kind
            dest.mkdir(parents=True, exist_ok=True)
            (dest / f"{name}.glb").write_bytes(data)
            extent = np.ptp(pos, axis=0)
            print(f"{kind}/{name}.glb: {len(faces)} tris, {len(data)} bytes, extent {extent.round(2)}")
            done += 1
        for name, (kind, pieces, z_up) in MERGED.items():
            try:
                authored_parts = []
                tris = 0
                for mesh, skin in pieces:
                    positions, faces, normals, uvs = read_pmd(store.read(f"art/meshes/{mesh}"))
                    png = load_texture(store, skin)
                    # Keep shared object space; centre once after merge.
                    pos, norms, tex = authored(positions, faces, normals, uvs, z_up, centre=False)
                    authored_parts.append((pos, norms, tex, png))
                    tris += len(faces)
                stacked = np.concatenate([p[0] for p in authored_parts], axis=0)
                origin = np.array(
                    [
                        (stacked[:, 0].min() + stacked[:, 0].max()) / 2,
                        stacked[:, 1].min(),
                        (stacked[:, 2].min() + stacked[:, 2].max()) / 2,
                    ],
                    dtype=np.float32,
                )
                recentred = [(pos - origin, norms, tex, png) for pos, norms, tex, png in authored_parts]
                data = glb_multi(recentred)
            except (KeyError, FileNotFoundError, OSError, SystemExit) as err:
                skipped.append(f"{name}: {err}")
                continue
            dest = out_root / kind
            dest.mkdir(parents=True, exist_ok=True)
            (dest / f"{name}.glb").write_bytes(data)
            extent = np.ptp(np.concatenate([p[0] for p in recentred], axis=0), axis=0)
            print(f"{kind}/{name}.glb: {tris} tris, {len(data)} bytes, extent {extent.round(2)} (merged)")
            done += 1
    finally:
        store.close()
    for line in skipped:
        print(f"SKIP {line}", file=sys.stderr)
    print(f"{done} models written, {len(skipped)} skipped")
    if done == 0:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
