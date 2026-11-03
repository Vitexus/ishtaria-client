#!/usr/bin/env python3
"""Reverses the triangle winding of glTF binaries whose triangles face against their vertex normals.

    tools/fix_glb_winding.py media/models/architecture/zeroad/pers_house_a.glb ...

The 0 A.D. models converted by the client's tools/zeroad-structures.py keep the clockwise winding of the game's own
engine, so the faces a viewer should see are the ones culled and the houses look hollow (seen from outside, the far
walls' insides); a renderer that shades from the geometric normal shows them black. Where the winding disagrees with
the vertex normals for most triangles, two indices of every triangle are swapped in place (the file size does not
change). A file that is already right is left alone, so the script is safe to run twice.
"""
import json
import struct
import sys

import numpy as np

COMPONENT = {5123: "<u2", 5125: "<u4"}


def fix(path):
    with open(path, "rb") as handle:
        data = bytearray(handle.read())
    json_length = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(bytes(data[20:20 + json_length]))
    binary = 20 + json_length + 8

    def view(index, dtype, columns):
        accessor = doc["accessors"][index]
        buffer = doc["bufferViews"][accessor["bufferView"]]
        offset = binary + buffer.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return np.frombuffer(data, dtype, accessor["count"] * columns, offset).reshape(-1, columns), offset

    flipped = 0
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            if "NORMAL" not in primitive["attributes"] or "indices" not in primitive:
                continue
            positions, _ = view(primitive["attributes"]["POSITION"], "<f4", 3)
            normals, _ = view(primitive["attributes"]["NORMAL"], "<f4", 3)
            accessor = doc["accessors"][primitive["indices"]]
            flat, offset = view(primitive["indices"], COMPONENT[accessor["componentType"]], 1)
            triangles = flat.reshape(-1, 3)
            face = np.cross(positions[triangles[:, 1]] - positions[triangles[:, 0]],
                            positions[triangles[:, 2]] - positions[triangles[:, 0]])
            agree = ((face * normals[triangles].sum(axis=1)).sum(axis=1) > 0).mean()
            if agree >= 0.5:
                continue
            swapped = triangles.copy()
            swapped[:, [1, 2]] = triangles[:, [2, 1]]
            dtype = np.dtype(COMPONENT[accessor["componentType"]])
            data[offset:offset + swapped.nbytes] = swapped.astype(dtype).tobytes()
            flipped += len(triangles)
    if flipped:
        with open(path, "wb") as handle:
            handle.write(data)
    print(f"{path}: {'flipped %d triangles' % flipped if flipped else 'already right'}")


if __name__ == "__main__":
    for name in sys.argv[1:]:
        fix(name)
