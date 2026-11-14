#!/bin/sh
# Builds the downloadable asset packs of the browser build into build/web/ next to index.pck:
#   zeroad.pck        the 0 A.D. art (assets/zeroad, about nine tenths of the data), exported by the preset "Web zeroad"
#   asset-packs.json  name, file, size and SHA-256 of every pack (read by scripts/asset_packs.gd)
# The page starts from the small index.pck and the game downloads the packs in the background (scripts/asset_packs.gd), keeps them
# in the browser's storage under a name with the hash, and mounts them. Run after `--export-release Web` (Makefile build-web, debian/rules).
#   GODOT=godot4 tools/web-packs.sh
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot4}"
mkdir -p build/web
python3 - <<'PY'
import pathlib, re
files = sorted(str(p) for p in pathlib.Path("assets/zeroad").rglob("*") if p.is_file() and p.suffix not in (".import", ".uid"))
listing = ", ".join('"res://%s"' % f for f in files)
cfg = pathlib.Path("export_presets.cfg")
text = cfg.read_text()
head, sep, tail = text.partition('name="Web zeroad"')
assert sep, "preset Web zeroad is missing"
tail = re.sub(r"export_files=PackedStringArray\([^)]*\)", lambda m: "export_files=PackedStringArray(%s)" % listing, tail, count=1)
cfg.write_text(head + sep + tail)
PY
"$GODOT" --headless --path . --export-pack "Web zeroad" build/web/zeroad.pck
python3 - <<'PY'
import hashlib, json, pathlib
packs = {}
for name in ("zeroad",):
    f = pathlib.Path("build/web/%s.pck" % name)
    packs[name] = {"file": f.name, "bytes": f.stat().st_size, "sha256": hashlib.sha256(f.read_bytes()).hexdigest()}
pathlib.Path("build/web/asset-packs.json").write_text(json.dumps({"version": 1, "packs": packs}, indent=1) + "\n")
print(json.dumps(packs, indent=1))
PY
