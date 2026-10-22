#!/usr/bin/env python3
"""Rebuild 0 A.D. fauna GLBs with Idle/Walk skeletal clips (Wildfire Games, CC BY-SA 3.0).

    python3 -I tools/zeroad-fauna-anim.py PUBLIC_ZIP assets/zeroad/fauna

Reads compiled PSMD meshes and PSSA animations from public.zip. 0 A.D. stores absolute
(root-relative) bone poses; every joint is parented to the armature root so those absolutes
become glTF local transforms. Clips are named Idle and Walk for surface_environment.gd.
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

# name: (mesh under art/meshes/, texture under art/textures/skins/, idle psa, walk psa)
# psa paths are under art/animation/ without the .cached.psa suffix in the logical name.
ANIMALS: dict[str, tuple[str, str, str, str]] = {
    "gazelle": (
        "skeletal/deer_mesh.dae.cached.pmd",
        "skeletal/animal_gazelle_02.dds.cached.dds",
        "quadraped/deer_idle_01.dae.cached.psa",
        "quadraped/deer_walk_01.dae.cached.psa",
    ),
    "deer": (
        "skeletal/deer_mesh.dae.cached.pmd",
        "skeletal/animal_deer_02.png.cached.dds",
        "quadraped/deer_idle_01.dae.cached.psa",
        "quadraped/deer_walk_01.dae.cached.psa",
    ),
    "goat": (
        "skeletal/goat.dae.cached.pmd",
        "skeletal/animal_goat.png.cached.dds",
        "quadraped/goat_idle_01.dae.cached.psa",
        "quadraped/goat_walk.dae.cached.psa",
    ),
    "sheep": (
        "skeletal/sheep.dae.cached.pmd",
        "skeletal/animal_sheep_a.dds.cached.dds",
        "quadraped/sheep_idle_01.dae.cached.psa",
        "quadraped/sheep_walk.dae.cached.psa",
    ),
    "cow": (
        "skeletal/cattle_female_a.dae.cached.pmd",
        "skeletal/animal_cattle_black_and_white.png.cached.dds",
        "quadraped/bovidae_idle_a.dae.cached.psa",
        "quadraped/bovidae_walk_relax.dae.cached.psa",
    ),
    "bull": (
        "skeletal/bull_a.dae.cached.pmd",
        "skeletal/animal_cattle_black.png.cached.dds",
        "quadraped/bovidae_idle_a.dae.cached.psa",
        "quadraped/bovidae_walk_relax.dae.cached.psa",
    ),
    "donkey": (
        "skeletal/donkey.dae.cached.pmd",
        "skeletal/animal_donkey.dds.cached.dds",
        "quadraped/donkey_idle_01.dae.cached.psa",
        "quadraped/donkey_walk_01.dae.cached.psa",
    ),
    "pig": (
        "skeletal/pig.dae.cached.pmd",
        "skeletal/animal_pig_01.png.cached.dds",
        "quadraped/animal_pig_idle_01.dae.cached.psa",
        "quadraped/animal_pig_walk_01.dae.cached.psa",
    ),
    "chicken": (
        "skeletal/chicken.dae.cached.pmd",
        "skeletal/animal_chicken.dds.cached.dds",
        "quadraped/chicken_idle_01.dae.cached.psa",
        "quadraped/chicken_walk.dae.cached.psa",
    ),
    "fox": (
        "skeletal/fox.dae.cached.pmd",
        "skeletal/animal_fox_red.png.cached.dds",
        "quadraped/fox_idle.dae.cached.psa",
        "quadraped/fox_walk.dae.cached.psa",
    ),
    "wolf": (
        "skeletal/wolf.dae.cached.pmd",
        "skeletal/animal_wolf.png.cached.dds",
        "quadraped/wolf_idle_01.dae.cached.psa",
        "quadraped/wolf_walk.dae.cached.psa",
    ),
    "lion": (
        "skeletal/animal_lion.dae.cached.pmd",
        "skeletal/animal_lion.png.cached.dds",
        "quadraped/lion_idle_01.dae.cached.psa",
        "quadraped/lion_walk.dae.cached.psa",
    ),
    "lioness": (
        "skeletal/animal_lioness.dae.cached.pmd",
        "skeletal/animal_lioness.png.cached.dds",
        "quadraped/lion_idle_01.dae.cached.psa",
        "quadraped/lion_walk.dae.cached.psa",
    ),
    "boar": (
        "skeletal/animal_boar.dae.cached.pmd",
        "skeletal/animal_boar_01.png.cached.dds",
        "quadraped/animal_boar_idle_02.dae.cached.psa",
        "quadraped/animal_boar_walk_01.dae.cached.psa",
    ),
    # Priority 2 — marsh / Iranian fringe / settlement dogs
    "crocodile": (
        "skeletal/Croc.dae.cached.pmd",
        "skeletal/animal_crocodile.png.cached.dds",
        "quadraped/Croc_idle1.dae.cached.psa",
        "quadraped/Croc_walk.dae.cached.psa",
    ),
    "camel": (
        "skeletal/camel.dae.cached.pmd",
        "skeletal/animal_camel_a.png.cached.dds",
        "quadraped/camel_idle_01.dae.cached.psa",
        "quadraped/camel_walk.dae.cached.psa",
    ),
    "horse_persian": (
        "skeletal/horse_persian.dae.cached.pmd",
        "skeletal/horse_brown.png.cached.dds",
        "quadraped/horse_idle_01.dae.cached.psa",
        "quadraped/horse_walk.dae.cached.psa",
    ),
    "zebu": (
        # Mesh has more bones than zebu_*.psa; bovidae clips match the shared cattle rig.
        "skeletal/zebu.dae.cached.pmd",
        "skeletal/animal_zebu.png.cached.dds",
        "quadraped/bovidae_idle_a.dae.cached.psa",
        "quadraped/bovidae_walk.dae.cached.psa",
    ),
    "mastiff": (
        "skeletal/mastiff_no_spikes.dae.cached.pmd",
        "skeletal/brit/mastiff_b_01.png.cached.dds",
        "quadraped/mastiff_idle.dae.cached.psa",
        "quadraped/mastiff_run.dae.cached.psa",  # 0ad has no separate walk
    ),
    # Birds: Idle = glide, Walk = flight (ground wildlife still uses these clip names).
    "hawk": (
        "skeletal/hawk.dae.cached.pmd",
        "skeletal/animal_hawk.png.cached.dds",
        "other/hawk_glide.dae.cached.psa",
        "other/hawk_flight.dae.cached.psa",
    ),
    "crow": (
        "skeletal/crow.dae.cached.pmd",
        "skeletal/animal_crow.png.cached.dds",
        "other/crow_glide.dae.cached.psa",
        "other/crow_flight.dae.cached.psa",
    ),
    "seagull": (
        "skeletal/seagull.dae.cached.pmd",
        "skeletal/animal_seagull.png.cached.dds",
        "other/seagull_flight_02.dae.cached.psa",
        "other/seagull_flight_01.dae.cached.psa",
    ),
    "fish_generic": (
        "skeletal/fish_generic.dae.cached.pmd",
        "skeletal/animal_fish_generic.png.cached.dds",
        "other/fish_generic_idle_a.dae.cached.psa",
        "other/fish_generic_idle_b.dae.cached.psa",
    ),
}


def yup(v: np.ndarray) -> np.ndarray:
    # Compiled PMD/PSA data is already Y-up (the engine converts the Z-up .dae sources): identity.
    return v


def yup_quat(q: np.ndarray) -> np.ndarray:
    # q = (x, y, z, w) already Y-up, like the positions.
    return q


def quat_to_mat(q: np.ndarray) -> np.ndarray:
    x, y, z, w = q
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    return np.array(
        [
            [1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy), 0],
            [2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx), 0],
            [2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy), 0],
            [0, 0, 0, 1],
        ],
        dtype=np.float64,
    )


def mat_to_quat(m: np.ndarray) -> np.ndarray:
    tr = m[0, 0] + m[1, 1] + m[2, 2]
    if tr > 0:
        s = np.sqrt(tr + 1.0) * 2
        return np.array([(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s])
    if m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        return np.array([0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s])
    if m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        return np.array([(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s])
    s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
    return np.array([(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s])


def bone_matrix(trans: np.ndarray, quat: np.ndarray) -> np.ndarray:
    m = quat_to_mat(quat)
    m[:3, 3] = trans
    return m


def read_pmd(data: bytes):
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    if magic != b"PSMD" or version < 4:
        raise SystemExit("need PSMD v4+")
    (nverts,) = struct.unpack_from("<I", data, 12)
    (nuv,) = struct.unpack_from("<I", data, 16)
    stride = 24 + 8 * nuv + 20
    raw = np.frombuffer(data, dtype=np.uint8, count=nverts * stride, offset=20).reshape(nverts, stride)
    positions = raw[:, 0:12].copy().view("<f4").reshape(nverts, 3).astype(np.float64)
    normals = raw[:, 12:24].copy().view("<f4").reshape(nverts, 3).astype(np.float64)
    uvs = raw[:, 24:32].copy().view("<f4").reshape(nverts, 2).astype(np.float64)
    blends = raw[:, 24 + 8 * nuv : 24 + 8 * nuv + 20]
    bones_idx = np.frombuffer(blends[:, 0:4].tobytes(), dtype=np.uint8).reshape(nverts, 4)
    weights = blends[:, 4:20].copy().view("<f4").reshape(nverts, 4).astype(np.float64)
    off = 20 + nverts * stride
    (nfaces,) = struct.unpack_from("<I", data, off)
    indices = np.frombuffer(data, dtype="<u2", count=nfaces * 3, offset=off + 4).reshape(nfaces, 3)
    off = off + 4 + nfaces * 6
    (nbones,) = struct.unpack_from("<I", data, off)
    off += 4
    bind_t = np.zeros((nbones, 3), dtype=np.float64)
    bind_q = np.zeros((nbones, 4), dtype=np.float64)
    for i in range(nbones):
        bind_t[i] = struct.unpack_from("<3f", data, off)
        off += 12
        bind_q[i] = struct.unpack_from("<4f", data, off)  # x,y,z,w
        off += 16
    return positions, normals, uvs, indices, bones_idx, weights, bind_t, bind_q


def read_psa(data: bytes):
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    if magic != b"PSSA" or version < 1:
        raise SystemExit("need PSSA v1+")
    off = 12
    (slen,) = struct.unpack_from("<I", data, off)
    off += 4 + slen
    (frame_ms,) = struct.unpack_from("<f", data, off)
    off += 4
    (nkeys,) = struct.unpack_from("<I", data, off)
    off += 4
    (nframes,) = struct.unpack_from("<I", data, off)
    off += 4
    keys = np.frombuffer(data, dtype="<f4", count=nkeys * nframes * 7, offset=off).reshape(nframes, nkeys, 7)
    # each key: tx,ty,tz, qx,qy,qz,qw
    return frame_ms, keys


def load_png(store: zipfile.ZipFile, skin: str) -> bytes:
    image = Image.open(io.BytesIO(store.read(f"art/textures/skins/{skin}"))).convert("RGBA")
    image.thumbnail((1024, 1024), Image.LANCZOS)
    buf = io.BytesIO()
    image.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def centre_floor(positions: np.ndarray, bind_t: np.ndarray, keys_list: list[np.ndarray]):
    """Same footprint centre / floor as the static scenery converter."""
    offset = np.array(
        [
            (positions[:, 0].min() + positions[:, 0].max()) / 2,
            positions[:, 1].min(),
            (positions[:, 2].min() + positions[:, 2].max()) / 2,
        ]
    )
    positions -= offset
    bind_t -= offset
    for keys in keys_list:
        keys[..., 0:3] -= offset
    return offset


def build_glb(
    positions,
    normals,
    uvs,
    indices,
    joints,
    weights,
    bind_t,
    bind_q,
    clips: dict[str, tuple[float, np.ndarray]],
    png: bytes,
) -> bytes:
    """clips: name -> (frame_ms, keys[frames,bones,7] already Y-up)."""
    nbones = len(bind_t)
    # Inverse bind matrices (column-major for glTF).
    ibm = np.zeros((nbones, 4, 4), dtype=np.float32)
    bind_mats = []
    for i in range(nbones):
        m = bone_matrix(bind_t[i], bind_q[i])
        bind_mats.append(m)
        ibm[i] = np.linalg.inv(m).T  # store column-major via later reshape order

    # Flatten triangles (indexed mesh).
    flat_i = indices.reshape(-1)
    pos = positions[flat_i].astype("<f4")
    nor = normals[flat_i].astype("<f4")
    uv = np.stack([uvs[flat_i, 0], 1.0 - uvs[flat_i, 1]], axis=1).astype("<f4")
    jnt = joints[flat_i].astype(np.uint8)
    # Replace 0xFF with 0 and zero the weight.
    wgt = weights[flat_i].astype("<f4").copy()
    for k in range(4):
        missing = jnt[:, k] == 0xFF
        jnt[missing, k] = 0
        wgt[missing, k] = 0
    # Renormalise weights.
    sums = wgt.sum(axis=1, keepdims=True)
    sums[sums == 0] = 1
    wgt /= sums
    idx = np.arange(len(pos), dtype="<u4")

    ibm_blob = np.array([np.linalg.inv(m).T for m in bind_mats], dtype="<f4").tobytes()  # 4x4 column-major each

    # Animation blobs
    anim_blobs = []
    anim_meta = []  # (name, frame_ms, nframes, t_off, r_off, time_off)
    for name, (frame_ms, keys) in clips.items():
        nframes = keys.shape[0]
        times = (np.arange(nframes, dtype="<f4") * (frame_ms / 1000.0))
        # translations [nframes, nbones, 3], rotations [nframes, nbones, 4]
        trans = keys[:, :, 0:3].astype("<f4")
        rots = keys[:, :, 3:7].astype("<f4")
        # Ensure quaternion continuity (flip if dot < 0).
        for b in range(nbones):
            for f in range(1, nframes):
                if np.dot(rots[f - 1, b], rots[f, b]) < 0:
                    rots[f, b] *= -1
        anim_meta.append((name, frame_ms, nframes, len(anim_blobs), len(anim_blobs) + 1, len(anim_blobs) + 2))
        anim_blobs.extend([trans.tobytes(), rots.tobytes(), times.tobytes()])

    mesh_blobs = [idx.tobytes(), pos.tobytes(), nor.tobytes(), uv.tobytes(), jnt.tobytes(), wgt.tobytes(), ibm_blob, png]
    all_blobs = mesh_blobs + anim_blobs

    views, offset, body = [], 0, b""
    for number, blob in enumerate(all_blobs):
        padded = blob + b"\0" * (-len(blob) % 4)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(blob)}
        if number < 6:
            view["target"] = 34963 if number == 0 else 34962
        views.append(view)
        body += padded
        offset += len(padded)

    accessors = [
        {"bufferView": 0, "componentType": 5125, "count": len(idx), "type": "SCALAR"},
        {
            "bufferView": 1,
            "componentType": 5126,
            "count": len(pos),
            "type": "VEC3",
            "min": pos.min(0).tolist(),
            "max": pos.max(0).tolist(),
        },
        {"bufferView": 2, "componentType": 5126, "count": len(nor), "type": "VEC3"},
        {"bufferView": 3, "componentType": 5126, "count": len(uv), "type": "VEC2"},
        {"bufferView": 4, "componentType": 5121, "count": len(jnt), "type": "VEC4"},
        {"bufferView": 5, "componentType": 5126, "count": len(wgt), "type": "VEC4"},
        {"bufferView": 6, "componentType": 5126, "count": nbones, "type": "MAT4"},
    ]

    # Nodes: 0 = skinned mesh, 1 = armature, 2.. = bones (absolute poses as local children of armature).
    nodes = [{"name": "model", "mesh": 0, "skin": 0}, {"name": "Armature", "children": list(range(2, 2 + nbones))}]
    for i in range(nbones):
        nodes.append({"name": f"bone_{i}", "translation": bind_t[i].tolist(), "rotation": bind_q[i].tolist()})

    animations = []
    for name, frame_ms, nframes, t_i, r_i, time_i in anim_meta:
        t_view = 8 + t_i
        r_view = 8 + r_i
        time_view = 8 + time_i
        # Packed as [frame][bone][comp]; stride skips to the next frame of the same bone.
        views[t_view]["byteStride"] = nbones * 12
        views[r_view]["byteStride"] = nbones * 16
        duration = (nframes - 1) * (frame_ms / 1000.0)
        time_acc = len(accessors)
        accessors.append(
            {
                "bufferView": time_view,
                "componentType": 5126,
                "count": nframes,
                "type": "SCALAR",
                "min": [0.0],
                "max": [float(duration)],
            }
        )
        samplers = []
        channels = []
        for b in range(nbones):
            t_acc = len(accessors)
            accessors.append(
                {
                    "bufferView": t_view,
                    "byteOffset": b * 12,
                    "componentType": 5126,
                    "count": nframes,
                    "type": "VEC3",
                }
            )
            r_acc = len(accessors)
            accessors.append(
                {
                    "bufferView": r_view,
                    "byteOffset": b * 16,
                    "componentType": 5126,
                    "count": nframes,
                    "type": "VEC4",
                }
            )
            si = len(samplers)
            samplers.append({"input": time_acc, "output": t_acc, "interpolation": "LINEAR"})
            channels.append({"sampler": si, "target": {"node": 2 + b, "path": "translation"}})
            si = len(samplers)
            samplers.append({"input": time_acc, "output": r_acc, "interpolation": "LINEAR"})
            channels.append({"sampler": si, "target": {"node": 2 + b, "path": "rotation"}})
        animations.append({"name": name, "samplers": samplers, "channels": channels})

    document = {
        "asset": {"version": "2.0", "generator": "ishtaria-client/tools/zeroad-fauna-anim.py"},
        "scene": 0,
        "scenes": [{"nodes": [0, 1]}],
        "nodes": nodes,
        "meshes": [
            {
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": 1,
                            "NORMAL": 2,
                            "TEXCOORD_0": 3,
                            "JOINTS_0": 4,
                            "WEIGHTS_0": 5,
                        },
                        "indices": 0,
                        "material": 0,
                    }
                ]
            }
        ],
        "skins": [{"inverseBindMatrices": 6, "joints": list(range(2, 2 + nbones)), "skeleton": 1}],
        "animations": animations,
        "materials": [
            {
                "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.85},
                "doubleSided": True,
            }
        ],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "images": [{"bufferView": 7, "mimeType": "image/png"}],
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


def convert_one(store: zipfile.ZipFile, name: str, mesh: str, skin: str, idle: str, walk: str) -> bytes:
    positions, normals, uvs, indices, joints, weights, bind_t, bind_q = read_pmd(store.read(f"art/meshes/{mesh}"))
    frame_idle, keys_idle = read_psa(store.read(f"art/animation/{idle}"))
    frame_walk, keys_walk = read_psa(store.read(f"art/animation/{walk}"))
    if keys_idle.shape[1] != len(bind_t) or keys_walk.shape[1] != len(bind_t):
        raise SystemExit(f"{name}: bone count mismatch mesh={len(bind_t)} idle={keys_idle.shape[1]} walk={keys_walk.shape[1]}")

    # Y-up
    positions = yup(positions)
    normals = yup(normals)
    bind_t = yup(bind_t)
    bind_q = yup_quat(bind_q)
    keys_idle = keys_idle.copy()
    keys_walk = keys_walk.copy()
    keys_idle[..., 0:3] = yup(keys_idle[..., 0:3])
    keys_idle[..., 3:7] = yup_quat(keys_idle[..., 3:7])
    keys_walk[..., 0:3] = yup(keys_walk[..., 0:3])
    keys_walk[..., 3:7] = yup_quat(keys_walk[..., 3:7])

    centre_floor(positions, bind_t, [keys_idle, keys_walk])
    png = load_png(store, skin)
    return build_glb(
        positions,
        normals,
        uvs,
        indices,
        joints,
        weights,
        bind_t,
        bind_q,
        {"Idle": (frame_idle, keys_idle), "Walk": (frame_walk, keys_walk)},
        png,
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    archive, out = Path(sys.argv[1]), Path(sys.argv[2])
    # Accept either assets/zeroad or assets/zeroad/fauna.
    if out.name != "fauna":
        out = out / "fauna"
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as store:
        for name, parts in ANIMALS.items():
            data = convert_one(store, name, *parts)
            path = out / f"{name}.glb"
            path.write_bytes(data)
            print(f"{name}.glb: {len(data)} bytes")


if __name__ == "__main__":
    main()
