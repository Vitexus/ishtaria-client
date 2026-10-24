#!/usr/bin/env python3
"""Build a game-ready Ur III–style clay tablet and export for Godot 4.

Visual reference: Drehem (Puzriš-Dagan) livestock-receipt tablets — pillow form,
ruled cuneiform rows, rolled cylinder-seal impressions, warm ochre clay
(cf. CDLI P104761 / P407062; Reddit r/Cuneiform 1633x04).

Run: blender --background --python build_tablet.py
"""
from __future__ import annotations

import math
import os
import struct
import zlib

import bpy
import bmesh
from mathutils import Vector, Euler

OUT = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(OUT, "textures")
os.makedirs(TEX, exist_ok=True)

# Palm-sized administrative tablet (metres), slightly larger than museum pieces for readability.
W, H, D = 0.090, 0.065, 0.016


def hnoise(x: float, y: float, z: float, s: float = 1.0) -> float:
    v = math.sin(x * 127.1 * s + y * 311.7 * s + z * 74.7 * s) * 43758.5453
    return v - math.floor(v)


def snoise(x: float, y: float, z: float, octaves: int = 4) -> float:
    amp, freq, total, norm = 1.0, 1.0, 0.0, 0.0
    for _ in range(octaves):
        total += amp * hnoise(x * freq, y * freq, z * freq)
        norm += amp
        amp *= 0.5
        freq *= 2.1
    return total / norm


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for coll in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.lights,
        bpy.data.cameras,
    ):
        for block in list(coll):
            coll.remove(block)


def build_mesh() -> bpy.types.Object:
    mesh = bpy.data.meshes.new("SumerianClayTablet")
    obj = bpy.data.objects.new("SumerianClayTablet", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(W, H, D), verts=bm.verts)
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=12, use_grid_fill=True)

    for v in bm.verts:
        p = v.co.copy()
        nx = p.x / (W * 0.5)
        ny = p.y / (H * 0.5)
        nz = p.z / (D * 0.5)
        ax, ay = abs(nx), abs(ny)

        # Soft pillow corners (hand-pressed clay, not a brick)
        corner = (ax**2.2 + ay**2.2) ** (1.0 / 2.2)
        if corner > 0.62:
            t = min(1.0, (corner - 0.62) / 0.42)
            shrink = 1.0 - 0.14 * t * t
            v.co.x *= shrink
            v.co.y *= shrink * (1.0 - 0.03 * t)
            v.co.z *= 1.0 - 0.36 * t

        # Stronger face convexity (museum tablet "soap bar")
        bulge = 0.0055 * max(0.0, 1.0 - ax * ax * 0.5) * max(0.0, 1.0 - ay * ay * 0.5)
        if abs(nz) > 0.15:
            v.co.z += math.copysign(bulge, nz)

        # Finger-smoothed face depressions
        d1 = math.exp(-((nx - 0.12) ** 2 * 1.4 + (ny + 0.08) ** 2 * 1.3)) * 0.0014
        d2 = math.exp(-((nx + 0.18) ** 2 * 1.2 + (ny - 0.15) ** 2 * 1.6)) * 0.0011
        if nz > 0.12:
            v.co.z -= d1 + d2
        elif nz < -0.12:
            v.co.z += d1 * 0.35 + d2 * 0.2

        edge = max(ax, ay)
        if edge > 0.68:
            t = (edge - 0.68) / 0.32
            wob = snoise(p.x * 26, p.y * 26, p.z * 26) - 0.5
            v.co.z *= 1.0 + wob * 0.18 * t
            if abs(nx) > 0.01:
                v.co.x += math.copysign(wob * 0.0020 * t, nx)
            if abs(ny) > 0.01:
                v.co.y += math.copysign((snoise(p.x * 31, p.y * 31, 2.0) - 0.5) * 0.0018 * t, ny)

        v.co.x += (snoise(p.x * 5, p.y * 5, 1.0) - 0.5) * 0.0026
        v.co.y += (snoise(p.x * 6, p.y * 6, 2.0) - 0.5) * 0.0022
        v.co.z += (snoise(p.x * 8, p.y * 8, 3.0) - 0.5) * 0.0008

        # Tiny edge wear only (museum-complete tablet, not a broken shard)
        if edge > 0.92 and snoise(p.x * 48, p.y * 48, 5.0) > 0.88:
            depth = 0.0008 + 0.0008 * snoise(p.x * 62, p.y * 62, 6.0)
            v.co.x *= 1.0 - depth * abs(nx) * 1.5
            v.co.y *= 1.0 - depth * abs(ny) * 1.5
            v.co.z *= 0.94

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    bev = obj.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.0020
    bev.segments = 3
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(28)
    sub = obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    bpy.ops.object.modifier_apply(modifier="Bevel")
    bpy.ops.object.modifier_apply(modifier="Subsurf")

    bpy.ops.object.shade_smooth()
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.mesh.mark_sharp(clear=True)
    bpy.ops.mesh.edges_select_sharp(sharpness=math.radians(30))
    bpy.ops.mesh.mark_sharp()
    bpy.ops.object.mode_set(mode="OBJECT")

    sx = W / max(obj.dimensions.x, 1e-9)
    sy = H / max(obj.dimensions.y, 1e-9)
    sz = D / max(obj.dimensions.z, 1e-9)
    obj.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    obj.location = (0.0, 0.0, 0.0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Cube-project so front/back stay readable rectangles for the inscription map.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=max(W, H, D) * 1.05, correct_aspect=True, clip_to_bounds=False, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.data.uv_layers[0].name = "UVMap"
    return obj


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png_rgb(path: str, width: int, height: int, rgb_bytes: bytes) -> None:
    raw = b"".join(b"\x00" + rgb_bytes[y * width * 3 : (y + 1) * width * 3] for y in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IDAT", zlib.compress(raw, 9)) + _png_chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _pit_field(x: float, y: float, density: float = 7.0) -> float:
    cx, cy = math.floor(x * density), math.floor(y * density)
    pit = 1.0
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            jx, jy = cx + ox, cy + oy
            if hnoise(jx * 0.17, jy * 0.17, 4.2) < 0.70:
                continue
            px = jx + hnoise(jx * 0.1, jy * 0.1, 9.0)
            py = jy + hnoise(jx * 0.1, jy * 0.1, 11.0)
            dx = x * density - px
            dy = y * density - py
            pit = min(pit, math.sqrt(dx * dx + dy * dy) * 1.45)
    return max(0.0, min(1.0, pit))


def _wedge_at(lx: float, ly: float, angle: float, head: float, length: float) -> float:
    """Depth 0..1 of one stylus wedge in local tablet UV space."""
    ca, sa = math.cos(angle), math.sin(angle)
    x = lx * ca + ly * sa
    y = -lx * sa + ly * ca
    if x < -head * 0.15 or x > length:
        return 0.0
    # Triangular head + tapering tail
    if x < head:
        half = head * 0.55 * (1.0 - x / head * 0.15)
        if abs(y) > half:
            return 0.0
        t = 1.0 - abs(y) / max(half, 1e-6)
        depth = t * t * (0.55 + 0.45 * (1.0 - x / head))
    else:
        half = head * 0.18 * (1.0 - (x - head) / max(length - head, 1e-6))
        if abs(y) > half:
            return 0.0
        t = 1.0 - abs(y) / max(half, 1e-6)
        depth = t * 0.35 * (1.0 - (x - head) / max(length - head, 1e-6))
    return max(0.0, min(1.0, depth))


def _stamp_wedge(buf: list[float], size: int, cu: float, cv: float, angle: float, head: float, length: float, strength: float) -> None:
    """Rasterize one wedge into the inscription buffer (UV space)."""
    # Bounding box in UV
    rad = length + head
    x0 = max(0, int((cu - rad) * size) - 1)
    x1 = min(size - 1, int((cu + rad) * size) + 1)
    y0 = max(0, int((cv - rad) * size) - 1)
    y1 = min(size - 1, int((cv + rad) * size) + 1)
    for y in range(y0, y1 + 1):
        v = (y + 0.5) / size
        for x in range(x0, x1 + 1):
            u = (x + 0.5) / size
            d = _wedge_at(u - cu, v - cv, angle, head, length) * strength
            if d > 0.0:
                idx = y * size + x
                if d > buf[idx]:
                    buf[idx] = d


def _stamp_ruling(buf: list[float], size: int, v_line: float, x0: float, x1: float, width: float = 0.008) -> None:
    y0 = max(0, int((v_line - width) * size))
    y1 = min(size - 1, int((v_line + width) * size))
    xi0 = max(0, int(x0 * size))
    xi1 = min(size - 1, int(x1 * size))
    for y in range(y0, y1 + 1):
        v = (y + 0.5) / size
        t = 1.0 - abs(v - v_line) / width
        if t <= 0.0:
            continue
        depth = (t * t) * 0.5
        for x in range(xi0, xi1 + 1):
            idx = y * size + x
            if depth > buf[idx]:
                buf[idx] = depth


def _build_inscription(size: int) -> list[float]:
    """Stamp ruled cuneiform + seal bands once (Ur III receipt look, not a real text)."""
    buf = [0.0] * (size * size)
    margin_x, margin_top = 0.07, 0.06

    def face_block(v0: float, v1: float, rows: int, signs: int, seed0: float, skip_top: int = 0) -> None:
        row_h = (v1 - v0) / rows
        for row in range(rows):
            ry0 = v0 + row * row_h
            ry1 = ry0 + row_h
            if row > 0:
                _stamp_ruling(buf, size, ry0, margin_x, 1.0 - margin_x)
            if row < skip_top:
                continue
            for s in range(signs):
                seed = seed0 + row * 17.3 + s * 3.7
                if hnoise(seed, 1.1, 2.2) < 0.12:
                    continue
                cu = margin_x + (1.0 - 2.0 * margin_x) * (s + 0.35 + 0.3 * hnoise(seed, 2.0, 0.5)) / signs
                cv = ry0 + row_h * (0.42 + 0.12 * hnoise(seed, 3.0, 1.0))
                n_w = 2 + int(hnoise(seed, 4.0, 0.7) * 2.5)
                for w in range(n_w):
                    ang = math.radians(-18 + 55 * hnoise(seed, w + 0.5, 8.0))
                    if hnoise(seed, w + 2.0, 9.0) > 0.55:
                        ang = math.radians(88 + 10 * (hnoise(seed, w, 1.0) - 0.5))
                    head = 0.011 + 0.007 * hnoise(seed, w + 3.0, 2.0)
                    length = 0.024 + 0.020 * hnoise(seed, w + 4.0, 3.0)
                    ox = (w - n_w * 0.5) * 0.009
                    oy = (hnoise(seed, w + 5.0, 4.0) - 0.5) * 0.005
                    _stamp_wedge(buf, size, cu + ox, cv + oy, ang, head, length, 1.0)

    # Obverse (upper atlas half) and reverse (lower) — cube UV islands share the map
    face_block(margin_top, 0.48, 9, 11, 0.0, skip_top=0)
    face_block(0.52, 1.0 - margin_top, 7, 9, 40.0, skip_top=1)

    # Cylinder-seal rolls stamped over writing
    for y0, y1, phase in ((0.28, 0.40, 0.0), (0.60, 0.72, 1.7)):
        mid = (y0 + y1) * 0.5
        half = (y1 - y0) * 0.5
        for i in range(size):
            u = (i + 0.5) / size
            for j in range(int(y0 * size), int(y1 * size) + 1):
                if not (0 <= j < size):
                    continue
                v = (j + 0.5) / size
                dy = (v - mid) / half
                t = (u * 5.5 + phase) % 1.0
                fig = 0.0
                fig = max(fig, max(0.0, 1.0 - ((t - 0.22) ** 2 * 40 + dy * dy * 8)) * 0.7)
                fig = max(fig, max(0.0, 1.0 - ((t - 0.22) ** 2 * 90 + (dy - 0.25) ** 2 * 50)) * 0.55)
                fig = max(fig, max(0.0, 1.0 - ((t - 0.62) ** 2 * 28 + (dy + 0.05) ** 2 * 14)) * 0.65)
                edge_y = min(abs(v - y0), abs(v - y1)) / (y1 - y0)
                border = max(0.0, 1.0 - edge_y * 18.0) * 0.35
                depth = fig * 0.55 + border
                idx = j * size + i
                # Seal sits on top of text
                stamped = max(buf[idx] * 0.65, depth * 0.9)
                buf[idx] = stamped
    return buf


def _sample_field(field: list[float], size: int, u: float, v: float) -> float:
    x = max(0.0, min(size - 1.001, u * size - 0.5))
    y = max(0.0, min(size - 1.001, v * size - 0.5))
    x0, y0 = int(x), int(y)
    x1, y1 = min(size - 1, x0 + 1), min(size - 1, y0 + 1)
    tx, ty = x - x0, y - y0
    a = field[y0 * size + x0]
    b = field[y0 * size + x1]
    c = field[y1 * size + x0]
    d = field[y1 * size + x1]
    return lerp(lerp(a, b, tx), lerp(c, d, tx), ty)


def generate_textures(size: int = 1024) -> tuple[str, str, str]:
    print("  stamping inscription…", flush=True)
    inscribed = _build_inscription(size)
    print("  building height field…", flush=True)
    height = [0.0] * (size * size)
    for y in range(size):
        v = (y + 0.5) / size
        for x in range(size):
            u = (x + 0.5) / size
            idx = y * size + x
            ins = inscribed[idx]
            wx = snoise(u * 2.0, v * 2.0, 0.2)
            xx = u * 3.0 + wx * 0.35
            yy = v * 3.0 + snoise(u * 2.0 + 5.0, v * 2.0, 1.7) * 0.35
            f = snoise(xx * 3.2, yy * 3.2, 3.0, 2)
            m = snoise(xx * 0.9, yy * 0.9, 2.0, 3)
            pd = max(0.0, 1.0 - _pit_field(xx, yy, 5.0)) ** 3.0
            # Smoother pressed clay; inscription carries the detail
            height[idx] = f * 0.04 + m * 0.10 + pd * 0.12 + ins * 1.65
        if y % 256 == 0:
            print(f"  height row {y}/{size}", flush=True)

    color = bytearray(size * size * 3)
    rough = bytearray(size * size * 3)
    normal = bytearray(size * size * 3)
    print("  baking color / normal…", flush=True)
    for y in range(size):
        v = (y + 0.5) / size
        for x in range(size):
            u = (x + 0.5) / size
            idx = y * size + x
            wx = snoise(u * 2.0, v * 2.0, 0.2)
            xx = u * 3.0 + wx * 0.35
            yy = v * 3.0 + snoise(u * 2.0 + 5.0, v * 2.0, 1.7) * 0.35
            broad = snoise(xx * 0.5, yy * 0.5, 0.5, 3)
            med = snoise(xx * 1.1, yy * 1.1, 2.0, 3)
            fine = snoise(xx * 3.0, yy * 3.0, 3.0, 2)
            pit_dark = max(0.0, 1.0 - _pit_field(xx, yy, 5.0)) ** 3.0
            t = max(0.0, min(1.0, broad * 0.65 + med * 0.35))
            c0 = (0.48, 0.32, 0.18)
            c1 = (0.66, 0.48, 0.28)
            c2 = (0.80, 0.62, 0.40)
            if t < 0.5:
                col = tuple(lerp(c0[i], c1[i], t * 2.0) for i in range(3))
            else:
                col = tuple(lerp(c1[i], c2[i], (t - 0.5) * 2.0) for i in range(3))

            ins = inscribed[idx]
            edge = min(u, v, 1.0 - u, 1.0 - v)
            edge_comp = max(0.0, 1.0 - edge * 5.5) * 0.08
            dark = 1.0 - 0.04 * (fine - 0.5) - 0.08 * pit_dark - edge_comp - 0.42 * ins
            col = tuple(max(0.06, min(0.88, c * dark)) for c in col)
            if ins > 0.15:
                shade = ins * 0.18
                col = (
                    col[0] * (1.0 - shade * 0.22),
                    col[1] * (1.0 - shade * 0.12),
                    min(0.85, col[2] * (1.0 - shade * 0.05)),
                )

            r = max(0.76, min(0.96, 0.90 + 0.04 * med - 0.08 * ins - 0.02 * pit_dark))

            # Finite differences on the precomputed height grid (fast)
            xm = height[y * size + max(0, x - 1)]
            xp = height[y * size + min(size - 1, x + 1)]
            ym = height[max(0, y - 1) * size + x]
            yp = height[min(size - 1, y + 1) * size + x]
            hx = (xp - xm) * 0.5 * size
            hy = (yp - ym) * 0.5 * size
            strength = 0.85
            nx, ny, nz = -hx * strength, -hy * strength, 1.0
            inv = 1.0 / math.sqrt(nx * nx + ny * ny + nz * nz)
            nx, ny, nz = nx * inv, ny * inv, nz * inv
            nrgb = (nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5)

            i = idx * 3
            color[i : i + 3] = (int(col[0] * 255), int(col[1] * 255), int(col[2] * 255))
            ri = int(r * 255)
            rough[i : i + 3] = (ri, ri, ri)
            normal[i : i + 3] = (int(nrgb[0] * 255), int(nrgb[1] * 255), int(nrgb[2] * 255))
        if y % 128 == 0:
            print(f"  bake row {y}/{size}", flush=True)

    cpath = os.path.join(TEX, "T_AncientClay_BaseColor.png")
    rpath = os.path.join(TEX, "T_AncientClay_Roughness.png")
    npath = os.path.join(TEX, "T_AncientClay_Normal.png")
    write_png_rgb(cpath, size, size, bytes(color))
    write_png_rgb(rpath, size, size, bytes(rough))
    write_png_rgb(npath, size, size, bytes(normal))
    return cpath, rpath, npath


def make_material(cpath: str, rpath: str, npath: str) -> bpy.types.Material:
    if "M_AncientClay" in bpy.data.materials:
        bpy.data.materials.remove(bpy.data.materials["M_AncientClay"])
    mat = bpy.data.materials.new("M_AncientClay")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    out.location = (400, 0)
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 0)
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.0
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def load(path: str, colorspace: str) -> bpy.types.Image:
        img = bpy.data.images.load(path)
        img.colorspace_settings.name = colorspace
        img.pack()
        return img

    tex_c = nodes.new("ShaderNodeTexImage")
    tex_c.location = (-400, 200)
    tex_c.image = load(cpath, "sRGB")
    links.new(tex_c.outputs["Color"], bsdf.inputs["Base Color"])

    tex_r = nodes.new("ShaderNodeTexImage")
    tex_r.location = (-400, 0)
    tex_r.image = load(rpath, "Non-Color")
    links.new(tex_r.outputs["Color"], bsdf.inputs["Roughness"])

    tex_n = nodes.new("ShaderNodeTexImage")
    tex_n.location = (-400, -200)
    tex_n.image = load(npath, "Non-Color")
    nmap = nodes.new("ShaderNodeNormalMap")
    nmap.location = (-100, -200)
    nmap.inputs["Strength"].default_value = 1.6
    links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def setup_preview(obj: bpy.types.Object) -> None:
    world = bpy.data.worlds.new("PreviewWorld")
    bpy.context.scene.world = world
    world.use_nodes = True
    nodes = world.node_tree.nodes
    links = world.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputWorld")
    bg = nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (0.10, 0.09, 0.08, 1)
    bg.inputs["Strength"].default_value = 0.28
    links.new(bg.outputs["Background"], out.inputs["Surface"])

    def add_area(name: str, loc, rot, energy: float, size: float, color=(1.0, 0.96, 0.9)):
        data = bpy.data.lights.new(name=name, type="AREA")
        data.energy = energy
        data.size = size
        data.color = color
        ob = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = Euler(rot, "XYZ")
        return ob

    # Raking key light so wedges cast museum-style shadows
    add_area("KeyLight", (0.10, -0.18, 0.16), (math.radians(42), 0, math.radians(25)), 9.0, 0.16)
    add_area("FillLight", (-0.14, 0.08, 0.07), (math.radians(65), 0, math.radians(-45)), 1.6, 0.28, (0.88, 0.90, 1.0))
    add_area("RimLight", (0.02, 0.16, 0.07), (math.radians(70), 0, math.radians(155)), 2.2, 0.12)

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 70
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.11, -0.14, 0.085)
    direction = Vector((0, 0, 0.001)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam


def render_preview() -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = -0.15
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 768
    scene.render.filepath = os.path.join(OUT, "preview.png")
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)


def export_assets(obj: bpy.types.Object) -> None:
    blend_path = os.path.join(OUT, "sumerian_clay_tablet.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    glb_path = os.path.join(OUT, "sumerian_clay_tablet.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_yup=True,
    )


def validate_glb() -> None:
    glb = os.path.join(OUT, "sumerian_clay_tablet.glb")
    before = set(bpy.data.objects.keys())
    bpy.ops.import_scene.gltf(filepath=glb)
    after = set(bpy.data.objects.keys())
    for name in after - before:
        o = bpy.data.objects[name]
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons) if o.type == "MESH" else 0
        mats = [s.material.name if s.material else None for s in o.material_slots]
        print(
            "VALIDATE",
            o.name,
            "dims_mm",
            [round(d * 1000, 2) for d in o.dimensions],
            "tris",
            tris,
            "mats",
            mats,
        )
        bpy.data.objects.remove(o, do_unlink=True)


def main() -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    print("Clearing scene…")
    clear_scene()
    print("Building mesh…")
    obj = build_mesh()
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("Tris:", tris, "dims_mm:", [round(d * 1000, 2) for d in obj.dimensions])

    print("Generating textures…")
    cpath, rpath, npath = generate_textures(1024)
    print("Material…")
    mat = make_material(cpath, rpath, npath)
    obj.data.materials.clear()
    obj.data.materials.append(mat)

    print("Preview setup + render…")
    setup_preview(obj)
    render_preview()

    print("Export…")
    export_assets(obj)
    print("Re-import validation…")
    validate_glb()
    print("DONE")
    for root, _, files in os.walk(OUT):
        for f in files:
            p = os.path.join(root, f)
            print(f"  {p} ({os.path.getsize(p)} bytes)")


if __name__ == "__main__":
    main()
