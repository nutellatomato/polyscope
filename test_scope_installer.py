#!/usr/bin/env python3
"""End-to-end sandbox test for the HectorScope checksum-gated installer.

Builds a fake /home/debian/UI from the pristine baseline/firmware-407 files,
points the installer at it, and exercises every path:
  1. fresh baseline install      -> success, files become patched
  2. idempotent re-run           -> success, no changes
  3. drift on a critical file    -> abort in preflight, nothing changed
  4. failure after preflight     -> full rollback to baseline
  5. uninstall                   -> baseline restored
"""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.abspath(__file__))
UI_SRC = os.path.join(REPO, "source", "polyeffects-src", "digit_ui")
PAYLOAD = os.path.join(REPO, "dist", "hector-scope-usb-v2", "hector-scope-patch", "payload")
INSTALLER = os.path.join(REPO, "dist", "hector-scope-usb-v2", "hector-scope-patch", "install_scope.py")

BASELINE_FILES = ["module_info.py", "show_widget.py", "ingen_wrapper.py",
                  "headless.py", "qml/PatchBayEffect.qml"]
PASS = []
FAIL = []


def check(name, cond):
    (PASS if cond else FAIL).append(name)
    print(f"  [{'PASS' if cond else 'FAIL'}] {name}")


BASELINE_DIR = os.path.join(REPO, "baseline", "firmware-407")


def git_baseline(rel, dst):
    """Copy the pristine firmware-407 file (baseline/firmware-407) to dst."""
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(os.path.join(BASELINE_DIR, rel), dst)


def fresh_sandbox():
    root = tempfile.mkdtemp(prefix="hector_test_")
    ui = os.path.join(root, "home/debian/UI")
    lv2 = os.path.join(root, "usr/lib/lv2")
    os.makedirs(os.path.join(ui, "qml"), exist_ok=True)
    os.makedirs(lv2, exist_ok=True)
    for rel in BASELINE_FILES:
        git_baseline(rel, os.path.join(ui, rel))
    shutil.copy2(os.path.join(UI_SRC, "effect_proto_to_js.py"),
                 os.path.join(ui, "effect_proto_to_js.py"))
    subprocess.check_call([sys.executable, "effect_proto_to_js.py"], cwd=ui)
    with open(os.path.join(ui, "qml", "Settings.qml"), "w") as f:
        f.write('// FIRMWARE 407\n')
    return root, ui, lv2


def load_installer(ui, lv2):
    spec = importlib.util.spec_from_file_location(
        f"inst_{os.path.basename(os.path.dirname(os.path.dirname(ui)))}_{id(ui)}", INSTALLER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.UI_DIR = ui
    mod.LV2_DIR = lv2
    mod.BACKUP_DIR = os.path.join(ui, ".hector_scope_backup_v2")
    mod.PAYLOAD_DIR = PAYLOAD
    mod.MANIFEST_PATH = os.path.join(PAYLOAD, "manifest.json")
    mod.MARKER_PATH = os.path.join(ui, ".hector_scope_v2_done")
    mod.PRISTINE_DIR = os.path.join(PAYLOAD, "originals")
    return mod


def sha(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()


MANIFEST = json.load(open(os.path.join(PAYLOAD, "manifest.json")))


# Refuse to validate stale dist artifacts. The installer tests intentionally
# exercise the generated USB tree, not a historical checked-in dist package.
SRC_INSTALLER = os.path.join(REPO, "install_scope.py")
SRC_QML = os.path.join(UI_SRC, "qml", "Polyscope.qml")
STAGED_QML = os.path.join(PAYLOAD, "files", "qml", "Polyscope.qml")
if not os.path.isfile(INSTALLER) or not os.path.isfile(STAGED_QML):
    raise SystemExit("Build the new USB installer before running installer tests")
if open(SRC_INSTALLER, "rb").read() != open(INSTALLER, "rb").read():
    raise SystemExit("Stale dist installer: rebuild before testing")
if open(SRC_QML, "rb").read() != open(STAGED_QML, "rb").read():
    raise SystemExit("Stale dist QML: rebuild before testing")

if sha(STAGED_QML) != MANIFEST["new"]["qml/Polyscope.qml"]:
    raise SystemExit("Stale or corrupt manifest: rebuild before testing")

for rel, info in MANIFEST["replace"].items():
    if sha(os.path.join(UI_SRC, rel)) != info["patched"]:
        raise SystemExit("Stale replacement source: " + rel)
    if sha(os.path.join(PAYLOAD, "files", rel)) != info["patched"]:
        raise SystemExit("Corrupt staged replacement: " + rel)
    if sha(os.path.join(PAYLOAD, "originals", rel)) != info["baseline"]:
        raise SystemExit("Corrupt staged baseline: " + rel)
for rel, expected in MANIFEST["new"].items():
    if sha(os.path.join(UI_SRC, rel)) != expected or sha(os.path.join(PAYLOAD, "files", rel)) != expected:
        raise SystemExit("Stale or corrupt new file: " + rel)
for bundle, files in MANIFEST["lv2"].items():
    for name, expected in files.items():
        if sha(os.path.join(PAYLOAD, "lv2", bundle, name)) != expected:
            raise SystemExit("Corrupt staged LV2 file: " + name)

print("\n=== Test 1: fresh baseline install ===")
root, ui, lv2 = fresh_sandbox()
inst = load_installer(ui, lv2)
rc = inst.install(dry_run=False)
check("install returns 0", rc == 0)
for rel, info in MANIFEST["replace"].items():
    check(f"{rel} == patched sha", sha(os.path.join(ui, rel)) == info["patched"])
for rel, exp in MANIFEST["new"].items():
    p = os.path.join(ui, rel)
    check(f"{rel} installed + sha", os.path.isfile(p) and sha(p) == exp)
for bundle, files in MANIFEST["lv2"].items():
    for name, exp in files.items():
        p = os.path.join(lv2, bundle, name)
        check(f"lv2/{bundle}/{name} installed + sha", os.path.isfile(p) and sha(p) == exp)
check("Polyscope.qml installed", os.path.isfile(os.path.join(ui, "qml", "Polyscope.qml")))
check("legacy Scope.qml NOT installed", not os.path.isfile(os.path.join(ui, "qml", "Scope.qml")))
js = os.path.join(ui, "qml", "module_info.js")
check("module_info.js has scope", os.path.isfile(js) and "scope" in open(js).read())
check("backups created", os.path.isdir(os.path.join(ui, ".hector_scope_backup_v2")))
for rel in ["module_info.py", "show_widget.py", "ingen_wrapper.py", "headless.py"]:
    r = subprocess.run([sys.executable, "-m", "py_compile", os.path.join(ui, rel)],
                       capture_output=True)
    check(f"{rel} compiles after install", r.returncode == 0)
shutil.rmtree(root)


print("\n=== Test 2: idempotent re-run ===")
root, ui, lv2 = fresh_sandbox()
inst = load_installer(ui, lv2)
inst.install(dry_run=False)
snap = {rel: sha(os.path.join(ui, rel)) for rel in MANIFEST["replace"]}
inst2 = load_installer(ui, lv2)
rc = inst2.install(dry_run=False)
check("second install returns 0", rc == 0)
check("no files changed on re-run",
      all(sha(os.path.join(ui, rel)) == snap[rel] for rel in snap))
shutil.rmtree(root)


print("\n=== Test 3: drift abort (critical file) ===")
root, ui, lv2 = fresh_sandbox()
with open(os.path.join(ui, "show_widget.py"), "a") as f:
    f.write("\n# local device modification\n")
sw_before = sha(os.path.join(ui, "show_widget.py"))
mi_before = sha(os.path.join(ui, "module_info.py"))
inst = load_installer(ui, lv2)
rc = inst.install(dry_run=False)
check("drift install returns 2 (preflight abort)", rc == 2)
check("show_widget.py untouched", sha(os.path.join(ui, "show_widget.py")) == sw_before)
check("module_info.py untouched (no partial patch)",
      sha(os.path.join(ui, "module_info.py")) == mi_before)
check("Scope.qml NOT created", not os.path.isfile(os.path.join(ui, "qml", "Scope.qml")))
check("LV2 NOT created", not os.path.isdir(os.path.join(lv2, "poly_scope.lv2")))
shutil.rmtree(root)


print("\n=== Test 4: mid-install failure -> rollback ===")
root, ui, lv2 = fresh_sandbox()
baseline_shas = {rel: sha(os.path.join(ui, rel)) for rel in MANIFEST["replace"]}
with open(os.path.join(ui, "effect_proto_to_js.py"), "w") as f:
    f.write("import sys\nsys.exit(3)\n")
inst = load_installer(ui, lv2)
rc = inst.install(dry_run=False)
check("install returns 1 on mid-failure", rc == 1)
check("all replaced files rolled back to baseline",
      all(sha(os.path.join(ui, rel)) == baseline_shas[rel] for rel in MANIFEST["replace"]))
check("Polyscope.qml removed on rollback", not os.path.isfile(os.path.join(ui, "qml", "Polyscope.qml")))
check("LV2 removed on rollback", not os.path.isdir(os.path.join(lv2, "poly_scope2.lv2")))
shutil.rmtree(root)


print("\n=== Test 5: uninstall ===")
root, ui, lv2 = fresh_sandbox()
baseline_shas = {rel: sha(os.path.join(ui, rel)) for rel in MANIFEST["replace"]}
inst = load_installer(ui, lv2)
inst.install(dry_run=False)
inst2 = load_installer(ui, lv2)
inst2.uninstall(dry_run=False)
check("files restored to baseline",
      all(sha(os.path.join(ui, rel)) == baseline_shas[rel] for rel in MANIFEST["replace"]))
check("Polyscope.qml removed", not os.path.isfile(os.path.join(ui, "qml", "Polyscope.qml")))
check("LV2 removed", not os.path.isdir(os.path.join(lv2, "poly_scope2.lv2")))
shutil.rmtree(root)


print("\n=== Test 6: clean reinstall from a prior version ===")
root, ui, lv2 = fresh_sandbox()
inst = load_installer(ui, lv2); inst.install(dry_run=False)
# Simulate an older version + a locally diverged show_widget.py + the
# legacy Scope.qml that pre-v3a installs shipped
open(os.path.join(ui, ".hector_scope_v2_done"), "w").write("OLD")
with open(os.path.join(ui, "show_widget.py"), "a") as f:
    f.write("\n# stale line from older version\n")
open(os.path.join(ui, "qml", "Scope.qml"), "w").write("// legacy leftover\n")
os.makedirs(os.path.join(lv2, "poly_scope.lv2"), exist_ok=True)
open(os.path.join(lv2, "poly_scope.lv2", "poly_scope.so"), "w").write("stale")
inst2 = load_installer(ui, lv2)
rc = inst2.install(dry_run=False)
check("reinstall returns 0", rc == 0)
check("legacy Scope.qml leftover removed on reinstall",
      not os.path.isfile(os.path.join(ui, "qml", "Scope.qml")))
check("legacy poly_scope.lv2 leftover removed on reinstall",
      not os.path.isdir(os.path.join(lv2, "poly_scope.lv2")))
for rel, info in MANIFEST["replace"].items():
    check(f"{rel} == patched after reinstall", sha(os.path.join(ui, rel)) == info["patched"])
check("marker stamped to PACKAGE_VERSION",
      open(os.path.join(ui, ".hector_scope_v2_done")).read().strip() == inst2.PACKAGE_VERSION)
inst3 = load_installer(ui, lv2)
check("same-version reinstall returns 0", inst3.install(dry_run=False) == 0)
shutil.rmtree(root)


print("\n=== Test 7: failed version upgrade restores the last working install ===")
root, ui, lv2 = fresh_sandbox()
inst = load_installer(ui, lv2)
check("initial version installs", inst.install(dry_run=False) == 0)
marker = os.path.join(ui, ".hector_scope_v2_done")
# Treat the installed package as the prior working release; changing marker
# forces an upgrade, during which the code restores to firmware baseline.
with open(marker, "w") as f:
    f.write("v3f-prior")
watch = ([os.path.join(ui, rel) for rel in list(MANIFEST["replace"]) + list(MANIFEST["new"])]
         + [os.path.join(ui, "qml/module_info.js"), marker]
         + [os.path.join(lv2, bundle, name)
            for bundle, files in MANIFEST["lv2"].items() for name in files])
before = {path: sha(path) for path in watch}
# Trigger a genuine failure *after* the destructive reset_to_pristine stage.
with open(os.path.join(ui, "effect_proto_to_js.py"), "w") as f:
    f.write("import sys\nsys.exit(7)\n")
inst = load_installer(ui, lv2)
rc = inst.install(dry_run=False)
check("upgrade failure returned an error", rc != 0)
check("previous version's entire managed UI and plugin restored",
      all(os.path.isfile(p) and sha(p) == expected for p, expected in before.items()))
check("previous version marker preserved", open(marker).read().strip() == "v3f-prior")
check("temporary upgrade snapshot cleaned",
      not any(n.startswith(".polyscope-upgrade-") for n in os.listdir(ui)))
shutil.rmtree(root)

print("\n=== Test 8: invalid payload aborts before touching an older version ===")
root, ui, lv2 = fresh_sandbox()
inst = load_installer(ui, lv2)
check("initial install for payload-safety test", inst.install(dry_run=False) == 0)
marker = os.path.join(ui, ".hector_scope_v2_done")
with open(marker, "w") as f:
    f.write("v3f-prior")
original = open(STAGED_QML, "rb").read()
try:
    with open(STAGED_QML, "ab") as f:
        f.write(b"\n// simulate a damaged USB payload\n")
    inst2 = load_installer(ui, lv2)
    check("damaged staged QML rejected before reset", inst2.install(dry_run=False) == 2)
    check("prior version and UI untouched",
          open(marker).read() == "v3f-prior" and os.path.isfile(os.path.join(ui, "qml/Polyscope.qml")))
finally:
    with open(STAGED_QML, "wb") as f:
        f.write(original)
shutil.rmtree(root)

print(f"\n{'='*50}\nRESULTS: {len(PASS)} passed, {len(FAIL)} failed")
if FAIL:
    print("FAILED:")
    for n in FAIL:
        print("  -", n)
    sys.exit(1)
print("ALL TESTS PASSED")
