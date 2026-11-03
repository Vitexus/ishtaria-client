#!/usr/bin/env python3
"""Stands assets/hyper3d/ed/duck.glb up: the exported mesh lies on its side (its up is -Z, its bill points +X).

(x, y, z) -> (-y, -z, x): up becomes +Y and the bill points +Z like the other animals. The foot goes to y = 0 and the
footprint is centred. Marked in `asset.extras.stood_up`, so running it again does nothing."""
import json
import struct
import sys

import numpy as np

path = sys.argv[1] if len(sys.argv) > 1 else "assets/hyper3d/ed/duck.glb"
data = bytearray(open(path, "rb").read())
json_length = struct.unpack("<I", data[12:16])[0]
doc = json.loads(bytes(data[20:20 + json_length]))
if doc.get("asset", {}).get("extras", {}).get("stood_up"):
    raise SystemExit(f"{path}: already upright")
start = 20 + json_length + 8
for primitive in doc["meshes"][0]["primitives"]:
    for key in ("POSITION", "NORMAL"):
        accessor = doc["accessors"][primitive["attributes"][key]]
        view = doc["bufferViews"][accessor["bufferView"]]
        offset = start + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        values = np.frombuffer(data, "<f4", accessor["count"] * 3, offset).reshape(-1, 3)
        turned = np.stack([-values[:, 1], -values[:, 2], values[:, 0]], axis=1)
        if key == "POSITION":
            turned = turned - np.array([(turned[:, 0].min() + turned[:, 0].max()) / 2, turned[:, 1].min(), (turned[:, 2].min() + turned[:, 2].max()) / 2])
            accessor["min"], accessor["max"] = turned.min(0).tolist(), turned.max(0).tolist()
        data[offset:offset + turned.nbytes] = turned.astype("<f4").tobytes()
doc.setdefault("asset", {}).setdefault("extras", {})["stood_up"] = True
text = json.dumps(doc, separators=(",", ":")).encode()
text += b" " * (-len(text) % 4)
body = bytes(data[start:])
open(path, "wb").write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(text) + 8 + len(body)) + struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(body), b"BIN\0") + body)
print(path, "stood up")
