#!/usr/bin/env python3
"""Stands a converted 0 A.D. structure upright: its vertical axis is glTF +Z, it should be +Y.

    tools/stand-glb-up.py assets/zeroad/structures/pers_house_a.glb ...

The first versions of zeroad-structures.py wrote the Z-up meshes of the Persian buildings unchanged, so every house, tower,
ship and cart lay on its side (roof beams pointing up). This turns (x, y, z) into (x, -z, y) (a rotation: winding and normals
follow; the 0 A.D. floor is at the high end of Z), centres the footprint and puts the foot on y = 0 as the converter does. The file is marked (`asset.extras.stood_up`)
and left alone when run again. Lamassu are authored upright and are skipped by name.
"""
import json
import struct
import sys

import numpy as np


def stand_up(path):
    if "lamassu" in path:
        print(f"{path}: upright by origin, skipped")
        return
    with open(path, "rb") as handle:
        data = bytearray(handle.read())
    json_length = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(bytes(data[20:20 + json_length]))
    if doc.get("asset", {}).get("extras", {}).get("stood_up") == 2:
        print(f"{path}: already upright")
        return
    wrong_first_version = doc.get("asset", {}).get("extras", {}).get("stood_up") is True
    binary_start = 20 + json_length + 8
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            for key in ("POSITION", "NORMAL"):
                accessor = doc["accessors"][primitive["attributes"][key]]
                view = doc["bufferViews"][accessor["bufferView"]]
                offset = binary_start + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
                values = np.frombuffer(data, "<f4", accessor["count"] * 3, offset).reshape(-1, 3)
                if wrong_first_version:    # an earlier run used (x, z, -y): upside down; turn it over about the Z axis
                    turned = np.stack([-values[:, 0], -values[:, 1], values[:, 2]], axis=1)
                else:
                    turned = np.stack([values[:, 0], -values[:, 2], values[:, 1]], axis=1)
                if key == "POSITION":
                    turned = turned - np.array([
                        (turned[:, 0].min() + turned[:, 0].max()) / 2, turned[:, 1].min(),
                        (turned[:, 2].min() + turned[:, 2].max()) / 2])
                    accessor["min"] = turned.min(0).tolist()
                    accessor["max"] = turned.max(0).tolist()
                data[offset:offset + turned.nbytes] = turned.astype("<f4").tobytes()
    doc.setdefault("asset", {}).setdefault("extras", {})["stood_up"] = 2
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    body = bytes(data[binary_start:])
    total = 12 + 8 + len(text) + 8 + len(body)
    out = struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(text), b"JSON") + text \
        + struct.pack("<I4s", len(body), b"BIN\0") + body
    with open(path, "wb") as handle:
        handle.write(out)
    box = [a for a in doc["accessors"] if "max" in a][0]
    print(f"{path}: stood up, now {np.round(np.array(box['max']) - np.array(box['min']), 1).tolist()}")


if __name__ == "__main__":
    for name in sys.argv[1:]:
        stand_up(name)
