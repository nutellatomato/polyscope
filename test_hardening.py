import importlib.util
import os
from pathlib import Path
import shutil
from unittest.mock import patch

import pytest
import test_scope_installer as harness


def tree(root):
    result = {}
    for p in Path(root).rglob("*"):
        rel = str(p.relative_to(root))
        if p.is_symlink():
            result[rel] = ("link", os.readlink(p))
        elif p.is_file():
            result[rel] = ("file", p.read_bytes(), p.stat().st_mode & 0o777)
        else:
            result[rel] = ("dir",)
    return result


@pytest.fixture
def device():
    root, ui, lv2 = harness.fresh_sandbox()
    inst = harness.load_installer(ui, lv2)
    yield Path(root), Path(ui), Path(lv2), inst
    shutil.rmtree(root)


@pytest.mark.parametrize("installed", [False, True])
def test_dry_run_changes_no_files(device, installed):
    root, ui, lv2, inst = device
    if installed:
        assert inst.install(False) == 0
        Path(inst.MARKER_PATH).write_text("v3f-t1")
    before = tree(root)
    inst.install(True)
    assert tree(root) == before


@pytest.mark.parametrize("installed,stage", [(installed, stage)
    for installed in (False, True)
    for stage in ("reset", "preflight", "replace", "new", "lv2", "js", "compile", "marker")
    if installed or stage != "reset"])
def test_failure_restores_full_state(device, installed, stage):
    root, ui, lv2, inst = device
    if installed:
        assert inst.install(False) == 0
        Path(inst.MARKER_PATH).write_text("v3f-t1")
        (ui / "qml/Scope.qml").write_text("legacy")
        (lv2 / "poly_scope.lv2").mkdir()
        (lv2 / "poly_scope.lv2/old.so").write_bytes(b"old")
        (lv2 / "poly_scope2.lv2/extra-link").symlink_to("poly_scope2.so")
    before = tree(root)
    names = {"reset": "reset_to_pristine", "preflight": "preflight",
             "replace": "apply_replace", "new": "apply_new_files", "lv2": "apply_lv2",
             "js": "regenerate_module_info_js", "compile": "compile_check"}
    if stage == "marker":
        builtin_open = open
        def fail_marker(path, mode="r", *args, **kwargs):
            if str(path) == inst.MARKER_PATH and mode == "w":
                raise OSError("injected marker write failure")
            return builtin_open(path, mode, *args, **kwargs)
        context = patch("builtins.open", fail_marker)
    else:
        original = getattr(inst, names[stage])
        def fail_after(*args, **kwargs):
            result = original(*args, **kwargs)
            raise inst.AbortInstall("injected failure after " + stage)
        context = patch.object(inst, names[stage], fail_after)
    with context:
        try:
            result = inst.install(False)
            assert result != 0
        except (OSError, inst.AbortInstall):
            pass
    assert tree(root) == before


def test_snapshot_capture_failure_changes_nothing(device):
    root, ui, lv2, inst = device
    before = tree(root)
    with patch.object(inst.shutil, "copy2", side_effect=OSError("disk full")):
        with pytest.raises(OSError):
            inst.install(False)
    assert tree(root) == before


def test_failed_restore_retains_snapshot(device):
    root, ui, lv2, inst = device
    snapshot = inst.UpgradeSnapshot(harness.MANIFEST)
    with snapshot:
        (ui / "module_info.py").write_text("bad")
        with patch.object(inst.shutil, "copy2", side_effect=OSError("write failure")):
            with pytest.raises(RuntimeError, match="RESTORE INCOMPLETE"):
                snapshot.restore()
        snapshot.cleanup()
        assert Path(snapshot.directory).is_dir()
        index = snapshot.targets.index(str(ui / "module_info.py"))
        assert (Path(snapshot.directory) / str(index)).read_bytes() == (Path(harness.BASELINE_DIR) / "module_info.py").read_bytes()
    shutil.rmtree(snapshot.directory)


def recovery_module(inst):
    path = Path(harness.REPO) / "dist/hector-scope-recovery-usb-v2/recover_scope.py"
    spec = importlib.util.spec_from_file_location("recovery_under_test", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.installer = inst
    return mod


def test_recovery_restores_baseline(device):
    root, ui, lv2, inst = device
    assert inst.install(False) == 0
    assert recovery_module(inst).recover() == 0
    for rel in harness.BASELINE_FILES:
        assert (ui / rel).read_bytes() == (Path(harness.BASELINE_DIR) / rel).read_bytes()
    assert not Path(inst.MARKER_PATH).exists()
    assert not Path(inst.BACKUP_DIR).exists()
    assert not (ui / "qml/Polyscope.qml").exists()
    assert not (ui / "scope_util.py").exists()
    assert not (lv2 / "poly_scope2.lv2").exists()
    assert '"scope"' not in (ui / "qml/module_info.js").read_text()


def test_failed_recovery_restores_tuner(device):
    root, ui, lv2, inst = device
    assert inst.install(False) == 0
    (ui / "effect_proto_to_js.py").write_text("raise RuntimeError('injected failure')")
    before = tree(root)
    with pytest.raises(Exception):
        recovery_module(inst).recover()
    assert tree(root) == before


def test_corrupt_recovery_aborts_before_writes(device, tmp_path):
    root, ui, lv2, inst = device
    assert inst.install(False) == 0
    recovery = recovery_module(inst)
    shutil.copytree(Path(recovery.__file__).parent, tmp_path / "recovery")
    recovery.__file__ = str(tmp_path / "recovery/recover_scope.py")
    (tmp_path / "recovery/originals/module_info.py").write_text("corrupt")
    before = tree(root)
    with pytest.raises(RuntimeError, match="corrupt recovery original"):
        recovery.recover()
    assert tree(root) == before


@pytest.mark.parametrize('rel', ['module_info.py', 'qml/Polyscope.qml', 'poly_scope2.lv2/poly_scope2.so', 'originals/module_info.py'])
def test_corrupt_payload_leaves_installed_state(device, tmp_path, rel):
    root, ui, lv2, inst = device
    assert inst.install(False) == 0
    Path(inst.MARKER_PATH).write_text('v3f-t1')
    payload = tmp_path / 'payload'
    shutil.copytree(harness.PAYLOAD, payload)
    inst.PAYLOAD_DIR = str(payload)
    inst.PRISTINE_DIR = str(payload / 'originals')
    inst.MANIFEST_PATH = str(payload / 'manifest.json')
    if rel.startswith('originals/'):
        target = payload / rel
    elif '.lv2/' in rel:
        target = payload / 'lv2' / rel
    else:
        target = payload / 'files' / rel
    target.write_bytes(b'corrupt')
    before = tree(root)
    assert inst.install(False) == 2
    assert tree(root) == before
