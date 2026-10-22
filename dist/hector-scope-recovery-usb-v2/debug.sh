#!/bin/bash
set -Eeuo pipefail
LOG="/usb_flash/hector_scope_recovery.log"
touch "$LOG" 2>/dev/null || LOG="/tmp/hector_scope_recovery.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== HectorScope recovery $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
[ "$(id -u)" -eq 0 ] || { echo "Must run as root."; exit 1; }

SETTINGS_QML="/home/debian/UI/qml/Settings.qml"
[ -f "$SETTINGS_QML" ] || { echo "ERROR: $SETTINGS_QML not found. Is this a Hector?"; exit 1; }
FW="$(sed -n -e 's|.* FIRMWARE \([0-9][0-9]*\).*|\1|p' "$SETTINGS_QML" | head -n 1 || true)"
case "$FW" in ''|*[!0-9]*) echo "ERROR: could not detect firmware."; exit 1 ;; esac
[ "$FW" -eq 407 ] || { echo "ERROR: this test package requires firmware 407; found $FW."; exit 1; }
echo "Firmware: $FW"


# Same single-instance guard as the installer.
LOCKDIR="/tmp/hector_scope_install.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "Another recovery run is already in progress; exiting."
  exit 0
fi
trap 'if [ "${PERSIST:-0}" = 1 ]; then sync; mount -o remount,ro "$LOWERDIR" 2>/dev/null || true; fi; rmdir "$LOCKDIR" 2>/dev/null || true' EXIT

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
export HECTOR_UI_DIR="$UI" HECTOR_LV2_DIR="$LV2"
remount_ro() { if [ "$PERSIST" = 1 ]; then mount -o remount,ro "$LOWERDIR" 2>/dev/null || true; fi; }

set +e
python3 /usb_flash/recover_scope.py
status=$?
set -e
sync
remount_ro
if [ "$status" -ne 0 ]; then
  echo "RECOVERY FAILED. Read $LOG. Do not assume the unit is restored."
  exit "$status"
fi
echo "Recovery verified. POWER OFF, REMOVE the USB, then power on."
shutdown -h now 2>/dev/null || poweroff 2>/dev/null || true
