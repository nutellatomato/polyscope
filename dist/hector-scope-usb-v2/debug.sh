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
  echo "Read the log for rollback status. Keep the recovery USB ready."
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
[ "$FW" -eq 407 ] || { echo "ERROR: this test package requires firmware 407; found $FW."; exit 1; }
echo "Firmware: $FW"

PATCH="/usb_flash/hector-scope-patch"
[ -f "$PATCH/install_scope.py" ] || { echo "ERROR: $PATCH/install_scope.py not found."; exit 1; }

# Single-instance guard (the QA debug runner tends to launch this twice).
LOCKDIR="/tmp/hector_scope_install.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "Another HectorScope install run is already in progress; exiting to avoid a conflict."
  exit 0
fi
trap 'if [ "${PERSIST:-0}" = 1 ]; then sync; mount -o remount,ro "$LOWERDIR" 2>/dev/null || true; fi; rmdir "$LOCKDIR" 2>/dev/null || true' EXIT

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
  echo "Installer returned $status. Read the log for restore status and any retained snapshot."
  echo "Manually POWER OFF, REMOVE the USB, then power on to confirm normal boot."
  echo "=========================================="
fi
exit "$status"
