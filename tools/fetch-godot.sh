#!/bin/sh
# Download the Godot editor binary and the export templates used to build
# the Debian package (default) and, on request, the Linux arm64, Windows, macOS and browser (web) clients.
#   PLATFORMS="linux linux-arm64 windows macos web" tools/fetch-godot.sh
# Idempotent.
set -eu
VER="${GODOT_VERSION:-4.5}"
PLATFORMS="${PLATFORMS:-linux}"
BASE="https://github.com/godotengine/godot/releases/download/${VER}-stable"
DIR="$(cd "$(dirname "$0")" && pwd)/godot"
TPL="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${VER}.stable"
mkdir -p "$DIR" "$TPL"
# Every download is checked: the Godot files against the SHA512-SUMS.txt of the same release (integrity, not independent of
# GitHub), rcedit against a hash pinned below. A file that does not match is deleted and the script stops.
verify_godot() {
    name="$1"; file="$2"
    expected="$(curl -fsSL "$BASE/SHA512-SUMS.txt" | awk -v n="$name" '$2 == n || $2 == "*" n {print $1}')"
    actual="$(sha512sum "$file" | cut -d' ' -f1)"
    if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
        rm -f "$file"
        echo "checksum of $name does not match SHA512-SUMS.txt, download removed" >&2
        exit 1
    fi
}
if [ ! -x "$DIR/godot" ]; then
    curl -fsSL -o "$DIR/godot.zip" "$BASE/Godot_v${VER}-stable_linux.x86_64.zip"
    verify_godot "Godot_v${VER}-stable_linux.x86_64.zip" "$DIR/godot.zip"
    unzip -oq "$DIR/godot.zip" -d "$DIR"
    mv "$DIR/Godot_v${VER}-stable_linux.x86_64" "$DIR/godot"
    rm "$DIR/godot.zip"
fi
files="templates/version.txt"
for platform in $PLATFORMS; do
    case "$platform" in
        linux) files="$files templates/linux_release.x86_64" ;;
        linux-arm64) files="$files templates/linux_release.arm64" ;;
        windows) files="$files templates/windows_release_x86_64.exe templates/windows_release_x86_64_console.exe" ;;
        macos) files="$files templates/macos.zip" ;;
        web) files="$files templates/web_nothreads_release.zip" ;;
        *) echo "unknown platform: $platform" >&2; exit 1 ;;
    esac
done
missing=0
for f in $files; do [ -f "$TPL/$(basename "$f")" ] || missing=1; done
if [ "$missing" = 1 ]; then
    curl -fsSL -o "$DIR/templates.tpz" "$BASE/Godot_v${VER}-stable_export_templates.tpz"
    verify_godot "Godot_v${VER}-stable_export_templates.tpz" "$DIR/templates.tpz"
    # shellcheck disable=SC2086
    unzip -oqj "$DIR/templates.tpz" $files -d "$TPL"
    rm "$DIR/templates.tpz"
fi
# The Windows build puts the icon and the version resources into the .exe with rcedit (run by Wine). Godot learns where both
# are from its editor settings; they are written only into a private XDG_CONFIG_HOME (the build's), never into ~/.config.
case " $PLATFORMS " in
    *" windows "*)
        RCEDIT_DIR="$(cd "$(dirname "$0")" && pwd)/rcedit"
        mkdir -p "$RCEDIT_DIR"
        # electron/rcedit v2.0.0 (MIT), a Windows program that Godot runs under Wine to write the icon and version resources. Its
        # SHA-256 is pinned here (taken from the official release asset; the project publishes no checksum of its own) and is
        # checked on every run, before the file can be used.
        RCEDIT_SHA256="3e7801db1a5edbec91b49a24a094aad776cb4515488ea5a4ca2289c400eade2a"
        RCEDIT="$RCEDIT_DIR/rcedit-x64.exe"
        if [ -f "$RCEDIT" ] && ! echo "$RCEDIT_SHA256  $RCEDIT" | sha256sum -c - >/dev/null 2>&1; then
            echo "rcedit does not match the pinned checksum, removed" >&2
            rm -f "$RCEDIT"
        fi
        if [ ! -f "$RCEDIT" ]; then
            curl -fsSL -o "$RCEDIT.tmp" "https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe"
            if echo "$RCEDIT_SHA256  $RCEDIT.tmp" | sha256sum -c - >/dev/null 2>&1; then
                mv "$RCEDIT.tmp" "$RCEDIT"
            else
                rm -f "$RCEDIT.tmp"
                echo "downloaded rcedit does not match the pinned checksum, not used" >&2
                exit 1
            fi
        fi
        if [ -n "${XDG_CONFIG_HOME:-}" ]; then
            SETTINGS="$XDG_CONFIG_HOME/godot/editor_settings-${VER}.tres"
            mkdir -p "$(dirname "$SETTINGS")"
            if ! grep -qs 'export/windows/rcedit' "$SETTINGS"; then
                if [ -s "$SETTINGS" ]; then
                    printf 'export/windows/rcedit = "%s"\nexport/windows/wine = "%s"\n' "$RCEDIT_DIR/rcedit-x64.exe" "$(command -v wine || echo wine)" >> "$SETTINGS"
                else
                    printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/windows/rcedit = "%s"\nexport/windows/wine = "%s"\n' \
                        "$RCEDIT_DIR/rcedit-x64.exe" "$(command -v wine || echo wine)" > "$SETTINGS"
                fi
            fi
        else
            echo "Set XDG_CONFIG_HOME to a private directory to have the Windows icon written into the .exe (see README)." >&2
        fi
        ;;
esac
echo "Godot ${VER} ready: $DIR/godot"
