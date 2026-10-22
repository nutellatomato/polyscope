#!/usr/bin/env bash
set -euo pipefail

#
# Builds the HectorScope USB installer (v2, checksum-gated).
#
# Output: dist/hector-scope-usb-v2/   <- copy contents to a FAT32 USB root
#
# The installer replaces firmware-407 UI files with verified-complete
# patched versions ONLY when their checksums match the known 407 baseline,
# backs everything up, verifies every write, compile-checks the result, and
# rolls back completely on any failure.
#

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/source/polyeffects-src"
UI="$SRC/digit_ui"
OUT="$SCRIPT_DIR/dist/hector-scope-usb-v2"

# Files replaced in place (must match a known 407 baseline).
REPLACE_CRITICAL=(module_info.py show_widget.py ingen_wrapper.py qml/PatchBayEffect.qml)
REPLACE_OPTIONAL=(headless.py)
NEW_FILES=(qml/Polyscope.qml scope_util.py)

# Pristine firmware-407 copies of the replaced files (see baseline/README.md).
BASELINE_DIR="${BASELINE_DIR:-$SCRIPT_DIR/baseline/firmware-407}"

# Cross-compile toolchain. Override any of these from the environment.
# LV2_CPPFLAGS: extra include flags for the LV2 headers, for hosts where
# pkg-config reports them in the system include dir (which a cross compiler
# does not search), e.g. LV2_CPPFLAGS=-I/path/containing/lv2-only
ZIG="${ZIG:-zig}"
if [ -z "${LLVM_STRIP:-}" ]; then
  LLVM_STRIP="$(command -v llvm-strip 2>/dev/null || echo /opt/homebrew/opt/llvm/bin/llvm-strip)"
fi

if command -v shasum >/dev/null 2>&1; then
  sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  sha() { sha256sum "$1" | cut -d' ' -f1; }
fi
sha_base() { sha "$BASELINE_DIR/$1"; }

# Refuse to build from a baseline that has drifted from its recorded checksums.
echo "Verifying firmware-407 baseline in $BASELINE_DIR..."
while read -r want rel; do
  [ -f "$BASELINE_DIR/$rel" ] || { echo "ERROR: baseline file missing: $rel" >&2; exit 1; }
  [ "$(sha "$BASELINE_DIR/$rel")" = "$want" ] || { echo "ERROR: baseline file changed: $rel" >&2; exit 1; }
done < "$BASELINE_DIR/SHA256SUMS"
echo "  baseline OK."

# The build tag must agree between the installer and the on-screen SETUP footer.
PKG_TAG="$(sed -n 's/^PACKAGE_VERSION = "\(.*\)"/\1/p' "$SCRIPT_DIR/install_scope.py")"
UI_TAG="$(sed -n 's/.*property string scopeBuild: "\([^"]*\)".*/\1/p' "$UI/qml/Polyscope.qml")"
if [ -z "$PKG_TAG" ] || [ "$PKG_TAG" != "$UI_TAG" ]; then
  echo "ERROR: build tag mismatch: install_scope.py='$PKG_TAG' Polyscope.qml='$UI_TAG'" >&2
  exit 1
fi
echo "Build tag: $PKG_TAG"

echo "=== Building HectorScope USB installer v2 (checksum-gated) ==="

# ── 1. Clean-rebuild the scope plugin ───────────────────────────────────────

PLUGIN2_BUILD="$SRC/PolyLV2/poly_scope2.lv2"
SO2_BUILD="$PLUGIN2_BUILD/build/poly_scope2.so"
echo "Rebuilding poly_scope2.so (polyscope)..."
if command -v "$ZIG" >/dev/null 2>&1 && pkg-config --exists lv2 2>/dev/null \
   && [ -x "$LLVM_STRIP" ]; then
  ( cd "$PLUGIN2_BUILD"
    make clean >/dev/null
    ZIG_GLOBAL_CACHE_DIR="${TMPDIR:-/tmp}/zig-global-cache" \
    ZIG_LOCAL_CACHE_DIR="${TMPDIR:-/tmp}/zig-local-cache" \
    make UNAME=Linux CC="$ZIG cc -target aarch64-linux-gnu" \
         CPPFLAGS="${LV2_CPPFLAGS:-}" \
         STRIP="$LLVM_STRIP" >/dev/null )
  echo "  rebuilt."
elif [ -f "$SO2_BUILD" ] && [ "${ALLOW_PREBUILT_PLUGIN:-0}" = 1 ]; then
  echo "  zig toolchain unavailable; ALLOW_PREBUILT_PLUGIN=1, using existing $SO2_BUILD"
  echo "  WARNING: this plugin may not match the current poly_scope2.c source."
else
  echo "ERROR: cannot cross-compile poly_scope2.so. Install zig, the LV2 headers and llvm-strip (or set ZIG / LLVM_STRIP)." >&2
  echo "       To package an existing build/poly_scope2.so anyway, set ALLOW_PREBUILT_PLUGIN=1." >&2
  exit 1
fi
fout2_build="$(file "$SO2_BUILD")"
case "$fout2_build" in
  *"ARM aarch64"*|*"ARM64"*) echo "  plugin2 OK: $fout2_build" ;;
  *) echo "ERROR: poly_scope2.so is not ARM64: $fout2_build" >&2; exit 1 ;;
esac

# ── 2. Sanity: every patched .py compiles on the build host ──────────

echo "Compile-checking patched sources..."
for f in module_info.py show_widget.py ingen_wrapper.py headless.py; do
  python3 -m py_compile "$UI/$f"
done
echo "  all compile."

# ── 3. Stage payload ─────────────────────────────────────────────────

rm -rf "$OUT"
PAY="$OUT/hector-scope-patch/payload"
mkdir -p "$PAY/files/qml" "$PAY/lv2/poly_scope2.lv2"

# Copy patched + new files into payload/files preserving layout.
for f in "${REPLACE_CRITICAL[@]}" "${REPLACE_OPTIONAL[@]}" "${NEW_FILES[@]}"; do
  mkdir -p "$PAY/files/$(dirname "$f")"
  cp "$UI/$f" "$PAY/files/$f"
done

# Pristine 407 baseline files carried on the install USB so a clean reinstall
# can reset even if the on-device backup is missing.
mkdir -p "$PAY/originals/qml"
for f in module_info.py show_widget.py ingen_wrapper.py headless.py qml/PatchBayEffect.qml; do
  cp "$BASELINE_DIR/$f" "$PAY/originals/$f"
done
echo "  staged pristine originals into install payload"

# LV2 bundle (polyscope)
PLUGIN2="$SRC/PolyLV2/poly_scope2.lv2"
SO2="$PLUGIN2/build/poly_scope2.so"
fout2="$(file "$SO2")"
case "$fout2" in *"ARM aarch64"*|*"ARM64"*) : ;; *) echo "ERROR: poly_scope2.so not ARM64: $fout2" >&2; exit 1 ;; esac
cp "$SO2" "$PAY/lv2/poly_scope2.lv2/poly_scope2.so"
cp "$PLUGIN2/poly_scope2.ttl" "$PAY/lv2/poly_scope2.lv2/poly_scope2.ttl"
cp "$PLUGIN2/manifest.ttl" "$PAY/lv2/poly_scope2.lv2/manifest.ttl"

# Installer entry point.
cp "$SCRIPT_DIR/install_scope.py" "$OUT/hector-scope-patch/install_scope.py"

# ── 4. Generate manifest.json (baseline from baseline/, patched from tree) ─

{
  echo "{"
  echo '  "replace": {'
  first=1
  for f in "${REPLACE_CRITICAL[@]}"; do
    [ $first -eq 1 ] && first=0 || echo ","
    printf '    "%s": {"baseline": "%s", "patched": "%s", "critical": true}' \
      "$f" "$(sha_base "$f")" "$(sha "$UI/$f")"
  done
  for f in "${REPLACE_OPTIONAL[@]}"; do
    echo ","
    printf '    "%s": {"baseline": "%s", "patched": "%s", "critical": false}' \
      "$f" "$(sha_base "$f")" "$(sha "$UI/$f")"
  done
  echo ""
  echo "  },"
  echo '  "new": {'
  first=1
  for f in "${NEW_FILES[@]}"; do
    [ $first -eq 1 ] && first=0 || echo ","
    printf '    "%s": "%s"' "$f" "$(sha "$UI/$f")"
  done
  echo ""
  echo "  },"
  echo '  "lv2": {'
  echo '    "poly_scope2.lv2": {'
  printf '      "poly_scope2.so": "%s",\n' "$(sha "$SO2")"
  printf '      "poly_scope2.ttl": "%s",\n' "$(sha "$PLUGIN2/poly_scope2.ttl")"
  printf '      "manifest.ttl": "%s"\n' "$(sha "$PLUGIN2/manifest.ttl")"
  echo '    }'
  echo '  }'
  echo "}"
} > "$PAY/manifest.json"

# Validate the manifest is well-formed JSON.
python3 -c "import json,sys; json.load(open('$PAY/manifest.json'))" \
  && echo "  manifest.json OK"

# ── 5. debug.sh (QA Run debug entry point) ───────────────────────────

cat > "$OUT/debug.sh" <<'DEBUGEOF'
#!/bin/bash
set -Eeuo pipefail

LOG="/usb_flash/hector_scope_install.log"
touch "$LOG" 2>/dev/null || LOG="/tmp/hector_scope_install.log"
exec > >(tee -a "$LOG") 2>&1

on_error() {
  local status=$?
  echo
  echo "=========================================="
  echo "HectorScope install ended with status ${status}."
  echo "If non-zero, the installer rolled back; the device is unchanged."
  echo "Log: ${LOG}"
  echo "Safe to power off, REMOVE the USB, then power on."
  echo "=========================================="
  sync || true
  exit "$status"
}
trap on_error ERR

echo "=== HectorScope v2 install $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: must run as root (Settings -> QA CHECK -> Run debug)."
  exit 1
fi

SETTINGS_QML="/home/debian/UI/qml/Settings.qml"
[ -f "$SETTINGS_QML" ] || { echo "ERROR: $SETTINGS_QML not found. Is this a Hector?"; exit 1; }
FW="$(sed -n -e 's|.* FIRMWARE \([0-9][0-9]*\).*|\1|p' "$SETTINGS_QML" | head -n 1 || true)"
case "$FW" in ''|*[!0-9]*) echo "ERROR: could not detect firmware."; exit 1 ;; esac
[ "$FW" -ge 407 ] || { echo "ERROR: firmware $FW < 407."; exit 1; }
echo "Firmware: $FW"

PATCH="/usb_flash/hector-scope-patch"
[ -f "$PATCH/install_scope.py" ] || { echo "ERROR: $PATCH/install_scope.py not found."; exit 1; }

# Single-instance guard (the QA debug runner tends to launch this twice).
LOCKDIR="/tmp/hector_scope_install.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "Another HectorScope install run is already in progress; exiting to avoid a conflict."
  exit 0
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT

# --- Detect overlay root and target the PERSISTENT lower layer ---
# On these units "/" is an overlay whose upper layer is tmpfs (RAM, wiped on
# every reboot) and whose lower layer is the real storage, mounted read-only.
# Writes to "/" do NOT survive a power cycle, so we write to the lower layer.
LOWERDIR="$(awk '$2=="/" && $3=="overlay"{
    for (i=1;i<=NF;i++) if ($i ~ /lowerdir=/) {
      n=split($i,a,","); for (j=1;j<=n;j++) if (a[j] ~ /^lowerdir=/) {
        sub(/^lowerdir=/,"",a[j]); split(a[j],b,":"); print b[1]; }
    }}' /proc/mounts | head -n1)"

PERSIST=0
if [ -n "$LOWERDIR" ] && [ -d "$LOWERDIR/home/debian/UI" ]; then
  echo "Overlay root detected. Persistent layer: $LOWERDIR"
  if ! mount -o remount,rw "$LOWERDIR"; then
    echo "ERROR: could not remount the persistent layer ($LOWERDIR) read-write."
    echo "No changes were made."
    exit 1
  fi
  TARGET="$LOWERDIR"
  PERSIST=1
else
  echo "No overlay root detected; writing directly to /."
  mount -o remount,rw / 2>/dev/null || echo "  (already writable)"
  TARGET=""
fi

export HECTOR_UI_DIR="${TARGET}/home/debian/UI"
export HECTOR_LV2_DIR="${TARGET}/usr/lib/lv2"
echo "Target UI dir : $HECTOR_UI_DIR"

remount_ro() { if [ "$PERSIST" = 1 ]; then mount -o remount,ro "$LOWERDIR" 2>/dev/null || true; fi; }

# install_scope.py owns the versioned completion marker: it no-ops when the
# current version is already installed, and otherwise does a clean reinstall.

# Belt-and-suspenders: copy the ORIGINAL target files onto the USB before any
# change, so originals are recoverable even if on-device backups are lost.
USB_BAK="/usb_flash/hector_scope_originals_backup"
mkdir -p "$USB_BAK/qml" 2>/dev/null || true
for rel in module_info.py show_widget.py ingen_wrapper.py headless.py qml/PatchBayEffect.qml qml/module_info.js; do
  if [ -e "$HECTOR_UI_DIR/$rel" ]; then cp -a "$HECTOR_UI_DIR/$rel" "$USB_BAK/$rel" 2>/dev/null || true; fi
done
sync 2>/dev/null || true

echo
echo "Running checksum-gated installer (writing to the persistent layer)..."
echo
set +e
python3 "$PATCH/install_scope.py"
status=$?
set -e

echo
if [ "$status" -eq 0 ]; then
  sync
  remount_ro
  echo "=========================================="
  echo "SUCCESS. HectorScope installed to the PERSISTENT layer and verified."
  echo "It will now survive a power cycle."
  echo ""
  echo "IMPORTANT: this unit may NOT power itself off."
  echo "Manually POWER OFF the unit, REMOVE the USB, then power back on."
  echo "After reboot, add a 'scope' module in the patch bay."
  echo "=========================================="
  shutdown -h now 2>/dev/null || poweroff 2>/dev/null || true
else
  sync
  remount_ro
  echo "=========================================="
  echo "Installer returned $status. Changes were rolled back; unit left unchanged."
  echo "Manually POWER OFF, REMOVE the USB, then power on to confirm normal boot."
  echo "=========================================="
fi
exit "$status"
DEBUGEOF
chmod 0755 "$OUT/debug.sh"

# ── 6. Recovery USB (separate folder) ────────────────────────────────

REC="$SCRIPT_DIR/dist/hector-scope-recovery-usb-v2"
mkdir -p "$REC"
cat > "$REC/debug.sh" <<'RECEOF'
#!/bin/bash
set -Eeuo pipefail
LOG="/usb_flash/hector_scope_recovery.log"
touch "$LOG" 2>/dev/null || LOG="/tmp/hector_scope_recovery.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== HectorScope recovery $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
[ "$(id -u)" -eq 0 ] || { echo "Must run as root."; exit 1; }

# Same single-instance guard as the installer.
LOCKDIR="/tmp/hector_scope_recovery.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "Another recovery run is already in progress; exiting."
  exit 0
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT

# Target the persistent lower layer if this is an overlay-root unit.
LOWERDIR="$(awk '$2=="/" && $3=="overlay"{
    for (i=1;i<=NF;i++) if ($i ~ /lowerdir=/) {
      n=split($i,a,","); for (j=1;j<=n;j++) if (a[j] ~ /^lowerdir=/) {
        sub(/^lowerdir=/,"",a[j]); split(a[j],b,":"); print b[1]; }
    }}' /proc/mounts | head -n1)"
PERSIST=0
if [ -n "$LOWERDIR" ] && [ -d "$LOWERDIR/home/debian/UI" ]; then
  echo "Overlay root detected. Persistent layer: $LOWERDIR"
  mount -o remount,rw "$LOWERDIR" || { echo "ERROR: could not remount $LOWERDIR rw"; exit 1; }
  TARGET="$LOWERDIR"; PERSIST=1
else
  echo "No overlay root; operating on /."
  mount -o remount,rw / 2>/dev/null || true
  TARGET=""
fi
UI="${TARGET}/home/debian/UI"
LV2="${TARGET}/usr/lib/lv2"
remount_ro() { if [ "$PERSIST" = 1 ]; then mount -o remount,ro "$LOWERDIR" 2>/dev/null || true; fi; }

restored_any=0

# 1) Restore from the v2 on-device backups (true originals captured pre-patch).
B2="$UI/.hector_scope_backup_v2"
if [ -d "$B2" ]; then
  ( cd "$B2" && find . -type f ! -name '_lv2_*' | while read -r rel; do
      rel="${rel#./}"; mkdir -p "$(dirname "$UI/$rel")"; cp -a "$B2/$rel" "$UI/$rel"; echo "restored (v2 backup) $rel"; done )
  restored_any=1
fi

# 2) Fall back to the originals stashed on the USB by the installer.
USB_BAK="/usb_flash/hector_scope_originals_backup"
if [ "$restored_any" = 0 ] && [ -d "$USB_BAK" ]; then
  ( cd "$USB_BAK" && find . -type f | while read -r rel; do
      rel="${rel#./}"; mkdir -p "$(dirname "$UI/$rel")"; cp -a "$USB_BAK/$rel" "$UI/$rel"; echo "restored (USB backup) $rel"; done )
  restored_any=1
fi

# 3) Last resort: pristine baseline files carried on this recovery USB.
ORIG="/usb_flash/originals"
if [ "$restored_any" = 0 ] && [ -d "$ORIG" ]; then
  ( cd "$ORIG" && find . -type f | while read -r rel; do
      rel="${rel#./}"; mkdir -p "$(dirname "$UI/$rel")"; cp -a "$ORIG/$rel" "$UI/$rel"; echo "restored (USB originals) $rel"; done )
  restored_any=1
fi

# Remove scope additions and the marker.
rm -f "$UI/qml/Scope.qml" 2>/dev/null && echo "removed Scope.qml" || true
rm -f "$UI/qml/Polyscope.qml" 2>/dev/null && echo "removed Polyscope.qml" || true
rm -rf "$LV2/poly_scope.lv2" 2>/dev/null && echo "removed LV2 bundle" || true
rm -rf "$LV2/poly_scope2.lv2" 2>/dev/null && echo "removed LV2 bundle 2" || true
rm -f "$UI/.hector_scope_v2_done" 2>/dev/null || true

# Regenerate module_info.js from whatever module_info.py is now in place.
if [ -f "$UI/effect_proto_to_js.py" ]; then ( cd "$UI" && python3 effect_proto_to_js.py 2>/dev/null ) || true; fi

sync
remount_ro
echo "=========================================="
if [ "$restored_any" = 1 ]; then
  echo "Recovery complete. Original files restored on the persistent layer."
else
  echo "Recovery ran, but no backup source was found to restore from."
  echo "If the unit still misbehaves, reflash firmware 407."
fi
echo "Manually POWER OFF the unit, REMOVE the USB, then power on."
echo "=========================================="
shutdown -h now 2>/dev/null || poweroff 2>/dev/null || true
RECEOF
chmod 0755 "$REC/debug.sh"

# Stage pristine baseline originals (from baseline/firmware-407) onto the
# recovery USB as a last-resort restore source. module_info.js is regenerated
# on-device from module_info.py, so it is not carried here.
mkdir -p "$REC/originals/qml"
for f in module_info.py show_widget.py ingen_wrapper.py headless.py qml/PatchBayEffect.qml; do
  cp "$BASELINE_DIR/$f" "$REC/originals/$f"
done
echo "  staged pristine originals on recovery USB"

# ── 7. README + checksums ────────────────────────────────────────────

cat > "$OUT/README_USB_INSTALL.txt" <<'README'
HectorScope USB Installer v2 (checksum-gated)
=============================================

This installer is safe for fragile units that cannot be recovered by hand:

  * PERSISTENCE: these units use an overlay root whose writable layer is in RAM
    and is wiped on every reboot, with the real storage mounted read-only
    underneath. This installer detects that, remounts the persistent lower
    layer read-write, and writes there so the scope SURVIVES a power cycle.
    (On a non-overlay unit it writes to / directly.)
  * It only replaces a firmware-407 UI file if that file matches the exact
    407 baseline checksum it expects. If your unit runs a slightly different
    407 build, the installer ABORTS without changing anything and prints the
    checksums it saw (in the log) so the package can be re-targeted.
  * Every replaced file is backed up (on the persistent layer AND copied to the
    USB at hector_scope_originals_backup/), every write is checksum-verified,
    and the patched Python is compile-checked. If anything fails, ALL changes
    are rolled back and the unit is left exactly as it was.
  * Because writes are now permanent, recover with the recovery USB if needed;
    it restores from the on-device backup, the USB backup, or pristine baseline
    originals it carries.

USB layout (copy everything to a FAT32 USB root):
  debug.sh
  README_USB_INSTALL.txt
  SHA256SUMS
  hector-scope-patch/
    install_scope.py
    payload/
      manifest.json
      files/      (patched module_info.py, show_widget.py, ingen_wrapper.py,
                   headless.py, qml/PatchBayEffect.qml, qml/Polyscope.qml,
                   scope_util.py)
      lv2/poly_scope2.lv2/  (poly_scope2.so, poly_scope2.ttl, manifest.ttl)

Install:
  1. Boot Hector normally on firmware 407.
  2. Insert the USB drive. THE INSTALLER RUNS AUTOMATICALLY -- no menu
     interaction is needed. (Fallback if nothing happens within ~30s:
     Settings -> QA CHECK -> Run debug, pressed ONCE.)
  3. The unit REBOOTS ITSELF when the install finishes.
  4. IMPORTANT: the moment the screen goes black (reboot starting),
     REMOVE THE USB STICK. If it stays inserted, the unit re-runs the
     installer on every boot and looks stuck in an update/reboot loop.
     Nothing is damaged -- just remove the stick and let it boot.
  5. Add a "scope" module in the patch bay.

Note: the installer takes only a few seconds. It uses a lock so that even if
the runner launches it more than once, only one instance runs and the rest
exit immediately. A completion marker makes repeat launches a no-op.

If it reports a checksum mismatch and aborts:
  Your unit is untouched. Copy /usb_flash/hector_scope_install.log off the USB
  and share it so the package can be re-targeted for your exact firmware.

Recovery (separate USB: hector-scope-recovery-usb-v2):
  Same handling: insert the stick, it runs automatically, and the unit
  reboots. Remove the stick as soon as the screen goes black. Restores the
  backups and removes the plugin.
README

( cd "$OUT"
  if command -v shasum >/dev/null 2>&1; then
    find . -type f ! -name SHA256SUMS ! -name '.DS_Store' | sort | xargs shasum -a 256 > SHA256SUMS
  fi )

echo
echo "=== Build complete ==="
echo "Install USB : $OUT/"
echo "Recovery USB: $REC/"
echo
echo "Copy the CONTENTS of the install folder to a FAT32 USB root,"
echo "then insert into a booted Hector: it installs automatically and reboots."
echo "Remove the stick the moment the screen goes black, or it will loop."
