#!/usr/bin/env python3
"""Converts the bridges of 0 A.D. (Wildfire Games, CC BY-SA 3.0) to GLB for the world generator.

    python3 -I tools/zeroad-bridges.py PUBLIC_ZIP assets/zeroad/bridges

PUBLIC_ZIP is `binaries/data/mods/public/public.zip` of the 0ad-data package. The sources are the public
`art/meshes/props/special/*.dae` of https://gitlab.com/0ad/0ad; the zip ships them only compiled to PSMD files
(`*.dae.cached.pmd`, format: source/graphics/ModelDef.cpp), which keep the positions, normals and UVs the
artists made, so the loader below reads those and the textures that the actors (`art/actors/props/special/
eyecandy/bridge_*.xml`) name. Each model is centred on its footprint, stands on y = 0 and keeps the game's
units (about a metre): the placer scales it to the river it crosses.
"""
import io
import json
import struct
import sys
import zipfile

import numpy as np
from PIL import Image

# name: (compiled mesh, texture, whether the mesh is Z-up like the sources (the rope bridge is already Y-up), width factor)
# The rope bridge is 4 units wide and 70 long: made for a gorge. The world generator scales a bridge uniformly to
# the river it crosses (6 to 36 m), so its width is doubled to keep a footpath wide enough on the short ones.
PARTS = {
    "bridge_edge_wooden": ("art/meshes/props/special/bridge_edge_wooden.dae.cached.pmd", "art/textures/skins/props/bridge_edge_wooden.png.cached.dds", True, 1.0),
    "bridge_edge_hele": ("art/meshes/props/special/bridge_edge_hele.dae.cached.pmd", "art/textures/skins/structural/hele_struct_b.png.cached.dds", True, 1.0),
    "broken_rope_bridge_long": ("art/meshes/props/special/broken_rope_bridge_long.dae.cached.pmd", "art/textures/skins/structural/iber_siege_ram.dds.cached.dds", False, 2.2),
}


def read_pmd(data):
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    if magic != b"PSMD" or version < 4:
        raise SystemExit("not a PSMD version 4 model")
    (count,) = struct.unpack_from("<I", data, 12)
    (uv_sets,) = struct.unpack_from("<I", data, 16)
    stride = 24 + 8 * uv_sets + 20  # position, normal, UVs, bone indices and weights
    raw = np.frombuffer(data, dtype=np.uint8, count=count * stride, offset=20).reshape(count, stride)
    offset = 20 + count * stride
    positions = raw[:, 0:12].copy().view("<f4").reshape(count, 3)
    normals = raw[:, 12:24].copy().view("<f4").reshape(count, 3)
    uvs = raw[:, 24:32].copy().view("<f4").reshape(count, 2)
    (faces,) = struct.unpack_from("<I", data, offset)
    indices = np.frombuffer(data, dtype="<u2", count=faces * 3, offset=offset + 4).reshape(faces, 3)
    return positions.astype(np.float64), indices.astype(np.uint32), normals.astype(np.float64), uvs.astype(np.float64)


def authored(positions, faces, normals, uvs, z_up, width=1.0):
    """Y-up (x, z, -y) when the mesh is Z-up, centred on its footprint and standing on y = 0."""
    def up(points):
        return np.stack([points[:, 0], points[:, 2], -points[:, 1]], axis=1) if z_up else points

    points = up(positions) * np.array([width, 1.0, 1.0])
    points = points - np.array([(points[:, 0].min() + points[:, 0].max()) / 2, points[:, 1].min(), (points[:, 2].min() + points[:, 2].max()) / 2])
    flat = faces.reshape(-1)
    return (
        points[flat].astype("<f4"),
        up(normals)[flat].astype("<f4"),
        np.stack([uvs[flat, 0], 1.0 - uvs[flat, 1]], axis=1).astype("<f4"),
    )


def glb(positions, normals, uvs, png):
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
        "asset": {"version": "2.0", "generator": "ishtaria-client/tools/zeroad-bridges.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 1, "NORMAL": 2, "TEXCOORD_0": 3}, "indices": 0, "material": 0}]}],
        "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.9}, "doubleSided": True}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "images": [{"bufferView": 4, "mimeType": "image/png"}],
        "buffers": [{"byteLength": len(body)}],
        "bufferViews": views,
        "accessors": [
            {"bufferView": 0, "componentType": 5125, "count": count, "type": "SCALAR"},
            {"bufferView": 1, "componentType": 5126, "count": count, "type": "VEC3",
             "min": positions.min(0).tolist(), "max": positions.max(0).tolist()},
            {"bufferView": 2, "componentType": 5126, "count": count, "type": "VEC3"},
            {"bufferView": 3, "componentType": 5126, "count": count, "type": "VEC2"},
        ],
    }
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(body)
    return struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(body), b"BIN\0") + body


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    archive, out = sys.argv[1:]
    with zipfile.ZipFile(archive) as z:
        for name, (mesh, skin, z_up, width) in PARTS.items():
            positions, faces, normals, uvs = read_pmd(z.read(mesh))
            image = Image.open(io.BytesIO(z.read(skin))).convert("RGB")
            image.thumbnail((1024, 1024), Image.LANCZOS)
            png = io.BytesIO()
            image.save(png, "PNG", optimize=True)
            data = glb(*authored(positions, faces, normals, uvs, z_up, width), png.getvalue())
            with open(f"{out}/{name}.glb", "wb") as handle:
                handle.write(data)
            extent = np.ptp(authored(positions, faces, normals, uvs, z_up, width)[0], axis=0)
            print(f"{name}.glb: {len(faces)} triangles, {len(data)} bytes, {extent.round(1)} (x, y, z)")


if __name__ == "__main__":
    main()
