#!/usr/bin/env python3
"""Restore the checked firmware-407 baseline, or retain the installed state."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import install_scope as installer


def recover():
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / "recovery-manifest.json").read_text())
    originals = root / "originals"
    for rel, info in manifest["replace"].items():
        src = originals / rel
        if not src.is_file() or installer.sha256(src) != info["baseline"]:
            raise RuntimeError("Missing or corrupt recovery original: " + rel)
        if rel.endswith(".py"):
            compile(src.read_bytes(), rel, "exec")
    ui = Path(installer.UI_DIR)
    script = ui / "effect_proto_to_js.py"
    if not script.is_file():
        raise RuntimeError("Missing device metadata generator; no files changed")
    snapshot = installer.UpgradeSnapshot(manifest)
    try:
        with snapshot:
            try:
                for rel, info in manifest["replace"].items():
                    dest = ui / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(originals / rel, dest)
                    if installer.sha256(dest) != info["baseline"]:
                        raise RuntimeError("Recovery write verification failed: " + rel)
                cache = ui / "__pycache__"
                installer.UpgradeSnapshot._remove(str(cache))
                subprocess.run([sys.executable, str(script)], cwd=ui, check=True)
                js = ui / "qml/module_info.js"
                if not js.is_file() or not js.stat().st_size or '"scope"' in js.read_text():
                    raise RuntimeError("Recovery metadata check failed")
                for rel in list(manifest["new"]) + ["qml/Scope.qml"]:
                    installer.UpgradeSnapshot._remove(str(ui / rel))
                for bundle in list(manifest["lv2"]) + ["poly_scope.lv2"]:
                    installer.UpgradeSnapshot._remove(os.path.join(installer.LV2_DIR, bundle))
                installer.UpgradeSnapshot._remove(installer.MARKER_PATH)
                installer.UpgradeSnapshot._remove(installer.BACKUP_DIR)
            except BaseException:
                snapshot.restore()
                raise
    finally:
        snapshot.cleanup()
    installer.log("Recovery verified: firmware-407 baseline restored")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(recover())
    except Exception as e:
        installer.log("RECOVERY FAILED: " + str(e))
        sys.exit(1)
