#!/usr/bin/env python3
"""
HectorScope installer (checksum-gated, verify-and-rollback).

Safety model for fragile hardware that cannot be easily recovered:

  * Every file this installer would replace is checked against a known
    firmware-407 baseline checksum FIRST. Nothing is modified until all
    critical files are recognised.
  * If a critical file does not match the expected baseline (and is not
    already the patched version), the installer ABORTS having changed
    nothing, and writes the device's actual checksums to the log so the
    package can be re-targeted for that exact firmware build.
  * Files are only ever replaced with the exact verified-complete patched
    versions. After writing, each file's checksum is re-verified.
  * Every replaced file is backed up first. Every newly created path is
    tracked. If ANY step fails (including a post-install Python compile
    check), the installer restores all backups, removes anything it
    created, and exits non-zero -- leaving the device exactly as it was.

Usage (run as root, normally via Settings -> QA CHECK -> Run debug):
    python3 install_scope.py            # install
    python3 install_scope.py --dry-run  # report only, change nothing
    python3 install_scope.py --uninstall

This avoids the wholesale, unconditional file replacement that the v1
.deb performed (which caused the restart loop).
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import sys

# On overlay-root Hectors, writes to "/" land in a RAM-backed tmpfs upper layer
# that is wiped on every reboot. The wrapper (debug.sh) detects the overlay,
# remounts the persistent lower layer read-write, and points these at it via
# the environment so the install survives a power cycle.
UI_DIR = os.environ.get("HECTOR_UI_DIR", "/home/debian/UI")
LV2_DIR = os.environ.get("HECTOR_LV2_DIR", "/usr/lib/lv2")
BACKUP_DIR = os.path.join(UI_DIR, ".hector_scope_backup_v2")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PAYLOAD_DIR = os.path.join(SCRIPT_DIR, "payload")
MANIFEST_PATH = os.path.join(PAYLOAD_DIR, "manifest.json")
PACKAGE_VERSION = "v3f-t1-h1"
PRISTINE_DIR = os.path.join(PAYLOAD_DIR, "originals")   # baseline files carried on the USB
MARKER_PATH = os.path.join(UI_DIR, ".hector_scope_v2_done")


def log(msg):
    print(f"[scope] {msg}", flush=True)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def load_manifest():
    with open(MANIFEST_PATH, "r") as f:
        return json.load(f)


# ── Rollback bookkeeping ─────────────────────────────────────────────

class Transaction:
    """Tracks file changes so they can be fully undone on failure."""

    def __init__(self):
        self.backed_up = {}     # device_path -> backup_path (restore on rollback)
        self.created = []       # paths created fresh (remove on rollback)
        self.created_dirs = []  # dirs created fresh (rmtree on rollback)

    def backup(self, device_path):
        if not os.path.exists(device_path):
            return
        rel = os.path.relpath(device_path, UI_DIR)
        # Files outside UI_DIR (LV2) get a flat backup name.
        if rel.startswith(".."):
            rel = "_lv2_" + os.path.basename(device_path)
        dst = os.path.join(BACKUP_DIR, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.exists(dst):
            shutil.copy2(device_path, dst)
        self.backed_up[device_path] = dst

    def track_created(self, path):
        self.created.append(path)

    def track_created_dir(self, path):
        self.created_dirs.append(path)

    def rollback(self):
        log("Rolling back all changes...")
        for path in reversed(self.created):
            try:
                if os.path.isfile(path):
                    os.remove(path)
                    log(f"  removed created file {path}")
            except OSError as e:
                log(f"  WARNING: could not remove {path}: {e}")
        for path in reversed(self.created_dirs):
            try:
                if os.path.isdir(path):
                    shutil.rmtree(path)
                    log(f"  removed created dir {path}")
            except OSError as e:
                log(f"  WARNING: could not remove {path}: {e}")
        for device_path, backup_path in self.backed_up.items():
            try:
                shutil.copy2(backup_path, device_path)
                log(f"  restored {device_path}")
            except OSError as e:
                log(f"  WARNING: could not restore {device_path}: {e}")
        log("File rollback finished; the outer snapshot will restore the full prior state.")


class AbortInstall(Exception):
    pass


# ── Pre-flight: classify every replace-file by checksum ──────────────

def preflight(manifest):
    """Return {rel: action} where action in {patch, already, skip}.
    Raises AbortInstall (before any change) if a critical file is unknown."""
    plan = {}
    unknown_critical = []

    for rel, info in manifest["replace"].items():
        dev = os.path.join(UI_DIR, rel)
        if not os.path.isfile(dev):
            # Missing critical file => unknown system.
            if info.get("critical"):
                unknown_critical.append((rel, "MISSING"))
            else:
                plan[rel] = "skip"
                log(f"  {rel}: not present, optional -> skip")
            continue

        cur = sha256(dev)
        if cur == info["patched"]:
            plan[rel] = "already"
            log(f"  {rel}: already patched -> skip")
        elif cur == info["baseline"]:
            plan[rel] = "patch"
            log(f"  {rel}: matches 407 baseline -> will patch")
        else:
            if info.get("critical"):
                unknown_critical.append((rel, cur))
            else:
                plan[rel] = "skip"
                log(f"  {rel}: UNKNOWN checksum, optional -> skip (scope unaffected)")

    if unknown_critical:
        log("")
        log("ABORT: one or more critical UI files do not match the expected")
        log("firmware 407 baseline. Nothing has been changed.")
        log("")
        log("This usually means the unit runs a slightly different 407 build")
        log("than this package was prepared against. Share these checksums so")
        log("the package can be re-targeted for this exact firmware:")
        for rel, cur in unknown_critical:
            log(f"  {rel}: {cur}")
        raise AbortInstall("critical file checksum mismatch")

    return plan


# ── Apply ────────────────────────────────────────────────────────────

def apply_replace(manifest, plan, tx, dry_run):
    for rel, info in manifest["replace"].items():
        if plan.get(rel) != "patch":
            continue
        dev = os.path.join(UI_DIR, rel)
        src = os.path.join(PAYLOAD_DIR, "files", rel)
        if not os.path.isfile(src):
            raise AbortInstall(f"payload file missing: {src}")
        if sha256(src) != info["patched"]:
            raise AbortInstall(f"payload file corrupt: {rel}")

        if dry_run:
            log(f"  would patch {rel}")
            continue

        tx.backup(dev)
        shutil.copy2(src, dev)
        if sha256(dev) != info["patched"]:
            raise AbortInstall(f"post-write checksum mismatch: {rel}")
        log(f"  patched {rel}")


def apply_new_files(manifest, tx, dry_run):
    for rel, expected in manifest["new"].items():
        dev = os.path.join(UI_DIR, rel)
        src = os.path.join(PAYLOAD_DIR, "files", rel)
        if not os.path.isfile(src):
            raise AbortInstall(f"payload file missing: {src}")
        if sha256(src) != expected:
            raise AbortInstall(f"payload file corrupt: {rel}")

        if dry_run:
            log(f"  would install new file {rel}")
            continue

        existed = os.path.exists(dev)
        if existed:
            tx.backup(dev)
        else:
            tx.track_created(dev)
        os.makedirs(os.path.dirname(dev), exist_ok=True)
        shutil.copy2(src, dev)
        os.chmod(dev, 0o644)
        if sha256(dev) != expected:
            raise AbortInstall(f"post-write checksum mismatch: {rel}")
        log(f"  installed {rel}")


def apply_lv2(manifest, tx, dry_run):
    for bundle, files in manifest["lv2"].items():
        dst_dir = os.path.join(LV2_DIR, bundle)
        existed = os.path.isdir(dst_dir)
        if dry_run:
            log(f"  would install LV2 bundle {bundle}")
            continue
        if not existed:
            tx.track_created_dir(dst_dir)
        os.makedirs(dst_dir, exist_ok=True)
        for name, expected in files.items():
            src = os.path.join(PAYLOAD_DIR, "lv2", bundle, name)
            dev = os.path.join(dst_dir, name)
            if not os.path.isfile(src):
                raise AbortInstall(f"payload LV2 file missing: {src}")
            if sha256(src) != expected:
                raise AbortInstall(f"payload LV2 file corrupt: {bundle}/{name}")
            if existed and os.path.exists(dev):
                tx.backup(dev)
            shutil.copy2(src, dev)
            os.chmod(dev, 0o755 if name.endswith(".so") else 0o644)
            if sha256(dev) != expected:
                raise AbortInstall(f"post-write checksum mismatch: {bundle}/{name}")
            log(f"  installed {bundle}/{name}")


def regenerate_module_info_js(tx, dry_run):
    script = os.path.join(UI_DIR, "effect_proto_to_js.py")
    js = os.path.join(UI_DIR, "qml", "module_info.js")
    if not os.path.isfile(script):
        log("  effect_proto_to_js.py not found, skipping JS regen")
        return
    if dry_run:
        log("  would regenerate qml/module_info.js")
        return
    if os.path.exists(js):
        tx.backup(js)
    subprocess.check_call([sys.executable, script], cwd=UI_DIR)
    if not os.path.isfile(js) or os.path.getsize(js) == 0:
        raise AbortInstall("module_info.js was not generated")
    with open(js, "r") as f:
        if "scope" not in f.read():
            raise AbortInstall("module_info.js missing scope entry after regen")
    log("  regenerated qml/module_info.js")


def compile_check(manifest, plan):
    """Byte-compile every .py we touched. Raises on any failure."""
    pyfiles = [
        rel for rel in manifest["replace"]
        if rel.endswith(".py") and plan.get(rel) in ("patch", "already")
    ]
    for rel in pyfiles:
        dev = os.path.join(UI_DIR, rel)
        result = subprocess.run(
            [sys.executable, "-m", "py_compile", dev],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            log(f"  COMPILE FAIL: {rel}")
            log(result.stderr.strip())
            raise AbortInstall(f"compile check failed: {rel}")
        log(f"  compiles OK: {rel}")


# ── Uninstall ────────────────────────────────────────────────────────

def uninstall(dry_run):
    log("Uninstalling HectorScope...")
    if os.path.isdir(BACKUP_DIR):
        for root, _dirs, files in os.walk(BACKUP_DIR):
            for name in files:
                src = os.path.join(root, name)
                rel = os.path.relpath(src, BACKUP_DIR)
                if rel.startswith("_lv2_"):
                    continue
                dev = os.path.join(UI_DIR, rel)
                if dry_run:
                    log(f"  would restore {rel}")
                else:
                    os.makedirs(os.path.dirname(dev), exist_ok=True)
                    shutil.copy2(src, dev)
                    log(f"  restored {rel}")

    for qml_name in ("Scope.qml", "Polyscope.qml"):
        qml_path = os.path.join(UI_DIR, "qml", qml_name)
        if os.path.isfile(qml_path):
            if dry_run:
                log(f"  would remove qml/{qml_name}")
            else:
                os.remove(qml_path)
                log(f"  removed qml/{qml_name}")

    for bundle in ("poly_scope.lv2", "poly_scope2.lv2"):
        bdir = os.path.join(LV2_DIR, bundle)
        if os.path.isdir(bdir):
            if dry_run:
                log(f"  would remove {bundle}")
            else:
                shutil.rmtree(bdir)
                log(f"  removed {bundle}")

    if os.path.isfile(MARKER_PATH):
        if dry_run:
            log("  would remove marker")
        else:
            os.remove(MARKER_PATH)
            log("  removed marker")

    # Remove a stale v1 .deb registration if present.
    try:
        subprocess.run(["dpkg", "-s", "hector-scope-patch"],
                       check=True, capture_output=True)
        if not dry_run:
            subprocess.run(["dpkg", "--remove", "--force-remove-reinstreq",
                            "hector-scope-patch"], capture_output=True)
            log("  removed old hector-scope-patch dpkg registration")
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    script = os.path.join(UI_DIR, "effect_proto_to_js.py")
    if os.path.isfile(script) and not dry_run:
        subprocess.call([sys.executable, script], cwd=UI_DIR)
        log("  regenerated qml/module_info.js")

    if not dry_run and os.path.isdir(BACKUP_DIR):
        shutil.rmtree(BACKUP_DIR)
    log("Uninstall complete." + (" (dry run)" if dry_run else ""))


# ── Main ─────────────────────────────────────────────────────────────

def reset_to_pristine(manifest, dry_run):
    """Restore managed files to the pristine 407 baseline and remove scope
    additions, so the subsequent gated install lands a clean, newest-only set.
    Pristine source: on-device backup first, else baseline files carried on the
    USB (PRISTINE_DIR). The pristine backup dir is preserved, not deleted."""
    log("Reset: restoring managed files to pristine baseline")
    for rel, info in manifest["replace"].items():
        dev = os.path.join(UI_DIR, rel)
        if os.path.isfile(dev) and sha256(dev) == info["baseline"]:
            continue  # already pristine
        src = os.path.join(BACKUP_DIR, rel)
        if not os.path.isfile(src):
            src = os.path.join(PRISTINE_DIR, rel)
        if not os.path.isfile(src):
            log(f"  no pristine source for {rel}; leaving as-is")
            continue
        if sha256(src) != info["baseline"]:
            log(f"  pristine source for {rel} is not baseline; leaving as-is")
            continue
        if dry_run:
            log(f"  would restore {rel}")
            continue
        os.makedirs(os.path.dirname(dev), exist_ok=True)
        shutil.copy2(src, dev)
        log(f"  restored {rel}")
    for rel in manifest["new"]:
        dev = os.path.join(UI_DIR, rel)
        if os.path.isfile(dev):
            if dry_run:
                log(f"  would remove {rel}")
            else:
                os.remove(dev)
                log(f"  removed {rel}")
    # The legacy scope was removed in v3a: clean up everything an older
    # install left behind — its UI file and its DSP bundle (no presets in
    # the wild reference the legacy module, per the user 2026-07-16).
    legacy_qml = os.path.join(UI_DIR, "qml", "Scope.qml")
    if os.path.isfile(legacy_qml):
        if dry_run:
            log("  would remove legacy qml/Scope.qml")
        else:
            os.remove(legacy_qml)
            log("  removed legacy qml/Scope.qml")
    legacy_bundle = os.path.join(LV2_DIR, "poly_scope.lv2")
    if os.path.isdir(legacy_bundle):
        if dry_run:
            log("  would remove legacy poly_scope.lv2")
        else:
            shutil.rmtree(legacy_bundle)
            log("  removed legacy poly_scope.lv2")
    for bundle in manifest["lv2"]:
        bdir = os.path.join(LV2_DIR, bundle)
        if os.path.isdir(bdir):
            if dry_run:
                log(f"  would remove {bundle}")
            else:
                shutil.rmtree(bdir)
                log(f"  removed {bundle}")


def _install_unprotected(dry_run):
    if not os.path.isfile(MANIFEST_PATH):
        log(f"ERROR: manifest not found at {MANIFEST_PATH}")
        return 1
    if not os.path.isdir(UI_DIR):
        log(f"ERROR: UI directory not found at {UI_DIR}")
        return 1

    manifest = load_manifest()
    try:
        validate_payload(manifest)
    except (AbortInstall, OSError) as e:
        log(f"Installer package validation failed BEFORE any changes: {e}")
        return 2

    if os.path.isfile(MARKER_PATH):
        try:
            installed = open(MARKER_PATH).read().strip()
        except OSError:
            installed = ""
        if installed == PACKAGE_VERSION and not dry_run:
            log(f"Version {PACKAGE_VERSION} already installed. Nothing to do.")
            return 0
        log(f"Prior install detected (marker '{installed}'); doing clean reinstall.")
        if not dry_run:
            os.makedirs(BACKUP_DIR, exist_ok=True)
        reset_to_pristine(manifest, dry_run)

    log("=== HectorScope install (checksum-gated) ===")
    log(f"Source: {SCRIPT_DIR}")
    log(f"Target: {UI_DIR}")
    log("")
    log("Pre-flight: verifying current UI files against firmware 407 baseline")

    try:
        plan = preflight(manifest)
    except AbortInstall as e:
        log("")
        log(f"Install aborted during pre-flight: {e}")
        return 2

    if not dry_run:
        os.makedirs(BACKUP_DIR, exist_ok=True)
    tx = Transaction()

    try:
        log("")
        log("Step 1/5: Replacing baseline UI files with patched versions")
        apply_replace(manifest, plan, tx, dry_run)

        log("Step 2/5: Installing new files (Polyscope.qml, scope_util.py)")
        apply_new_files(manifest, tx, dry_run)

        log("Step 3/5: Installing LV2 plugin bundle")
        apply_lv2(manifest, tx, dry_run)

        log("Step 4/5: Regenerating qml/module_info.js")
        regenerate_module_info_js(tx, dry_run)

        log("Step 5/5: Python compile check")
        if not dry_run:
            compile_check(manifest, plan)
        else:
            log("  (skipped in dry-run)")

    except AbortInstall as e:
        log("")
        log(f"ERROR: {e}")
        if not dry_run:
            tx.rollback()
        return 1
    except Exception as e:  # noqa: BLE001 - last-resort safety net
        log("")
        log(f"UNEXPECTED ERROR: {e}")
        if not dry_run:
            tx.rollback()
        return 1

    if not dry_run:
        with open(MARKER_PATH, "w") as f:
            f.write(PACKAGE_VERSION)
    log("")
    if dry_run:
        log("Dry run complete. No files were modified.")
    else:
        log("Install complete and verified.")
    return 0


# Check staged files before any reset can remove the installed version.
def validate_payload(manifest):
    def safe_relative(rel):
        if (not isinstance(rel, str) or not rel or os.path.isabs(rel)
                or any(part in ("", ".", "..") for part in rel.split("/"))):
            raise AbortInstall("invalid payload path: " + repr(rel))

    for section in ("replace", "new", "lv2"):
        if not isinstance(manifest[section], dict) or not manifest[section]:
            raise AbortInstall("invalid manifest section: " + section)
        for rel in manifest[section]:
            safe_relative(rel)
    for files in manifest["lv2"].values():
        for name in files:
            safe_relative(name)
    for rel, info in manifest["replace"].items():
        original = os.path.join(PRISTINE_DIR, rel)
        if not os.path.isfile(original) or sha256(original) != info["baseline"]:
            raise AbortInstall("missing/corrupt baseline original: " + rel)
        src = os.path.join(PAYLOAD_DIR, "files", rel)
        if not os.path.isfile(src) or sha256(src) != info["patched"]:
            raise AbortInstall("missing/corrupt replacement: " + rel)
    for rel, expected in manifest["new"].items():
        src = os.path.join(PAYLOAD_DIR, "files", rel)
        if not os.path.isfile(src) or sha256(src) != expected:
            raise AbortInstall("missing/corrupt new file: " + rel)
    for bundle, files in manifest["lv2"].items():
        for name, expected in files.items():
            src = os.path.join(PAYLOAD_DIR, "lv2", bundle, name)
            if not os.path.isfile(src) or sha256(src) != expected:
                raise AbortInstall("missing/corrupt LV2 file: " + bundle + "/" + name)


class UpgradeSnapshot:
    """Persistent snapshot of managed files; not power-loss recovery."""

    def __init__(self, manifest):
        targets = []
        for rel in list(manifest["replace"]) + list(manifest["new"]):
            targets.append(os.path.join(UI_DIR, rel))
        targets += [
            os.path.join(UI_DIR, "qml", "Scope.qml"),
            os.path.join(UI_DIR, "qml", "module_info.js"),
            os.path.join(LV2_DIR, "poly_scope.lv2"),
            BACKUP_DIR,
            MARKER_PATH,
            os.path.join(UI_DIR, "__pycache__"),
        ]
        targets += [os.path.join(LV2_DIR, bundle) for bundle in manifest["lv2"]]
        self.targets = list(dict.fromkeys(targets))
        self.directory = None
        self.existed = []
        self.restore_attempted = False
        self.restore_ok = False

    @staticmethod
    def _remove(path):
        if os.path.islink(path) or os.path.isfile(path):
            os.unlink(path)
        elif os.path.isdir(path):
            shutil.rmtree(path)

    def __enter__(self):
        # Capture must complete before the first device write.
        self.directory = tempfile.mkdtemp(prefix=".polyscope-upgrade-", dir=UI_DIR)
        try:
            for i, path in enumerate(self.targets):
                exists = os.path.lexists(path)
                self.existed.append(exists)
                if not exists:
                    continue
                dest = os.path.join(self.directory, str(i))
                if os.path.islink(path):
                    os.symlink(os.readlink(path), dest)
                elif os.path.isdir(path):
                    shutil.copytree(path, dest, symlinks=True)
                else:
                    shutil.copy2(path, dest)
            log("Captured complete existing installation for upgrade rollback")
            return self
        except BaseException:
            self.cleanup()
            raise

    def __exit__(self, exc_type, exc_value, traceback):
        # The caller restores failures and retains incomplete restores.
        return False

    def restore(self):
        log("Upgrade failed: restoring prior installed version and version marker")
        self.restore_attempted = True
        errors = []
        for i, path in enumerate(self.targets):
            try:
                self._remove(path)
                if not self.existed[i]:
                    continue
                src = os.path.join(self.directory, str(i))
                os.makedirs(os.path.dirname(path), exist_ok=True)
                if os.path.islink(src):
                    os.symlink(os.readlink(src), path)
                elif os.path.isdir(src):
                    shutil.copytree(src, path, symlinks=True)
                else:
                    shutil.copy2(src, path)
            except OSError as e:
                errors.append(f"{path}: {e}")
        if errors:
            # Never silently claim recovery if any restoration failed.
            raise RuntimeError("UPGRADE RESTORE INCOMPLETE: " + "; ".join(errors))
        self.restore_ok = True
        log("Previous installation restored; remove the install USB before restart")

    def cleanup(self):
        if self.restore_attempted and not self.restore_ok:
            log("CRITICAL: incomplete restore; keeping recovery snapshot at " + self.directory)
            return
        if self.directory and os.path.isdir(self.directory):
            shutil.rmtree(self.directory)


def install(dry_run):
    try:
        manifest = load_manifest()
        validate_payload(manifest)
    except (OSError, ValueError, KeyError, TypeError, AbortInstall) as e:
        log(f"Installer package is invalid: {e}")
        return 2
    if not os.path.isdir(UI_DIR):
        log(f"ERROR: UI directory not found at {UI_DIR}")
        return 1
    if dry_run:
        return _install_unprotected(True)
    if os.path.isfile(MARKER_PATH):
        with open(MARKER_PATH) as f:
            if f.read().strip() == PACKAGE_VERSION:
                return _install_unprotected(False)
    # Fresh installs also need the generated JS, caches and backup state restored.
    snapshot = UpgradeSnapshot(manifest)
    try:
        with snapshot:
            try:
                result = _install_unprotected(False)
            except BaseException:
                snapshot.restore()
                raise
            if result != 0:
                snapshot.restore()
            return result
    finally:
        snapshot.cleanup()


def main():
    parser = argparse.ArgumentParser(description="HectorScope installer")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--uninstall", action="store_true")
    args = parser.parse_args()

    if args.uninstall:
        uninstall(args.dry_run)
        return 0
    return install(args.dry_run)


if __name__ == "__main__":
    sys.exit(main() or 0)
