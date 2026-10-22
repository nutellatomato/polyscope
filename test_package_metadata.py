import shutil
from pathlib import Path

from prepare_test_packages import ROOT, hardware_report_matches, payload_files


def test_owner_report_covers_current_runtime():
    assert hardware_report_matches(ROOT / 'dist/hector-scope-usb-v2')


def test_changed_runtime_does_not_keep_hardware_claim(tmp_path):
    package = tmp_path / 'installer'
    shutil.copytree(ROOT / 'dist/hector-scope-usb-v2', package)
    plugin = package / 'hector-scope-patch/payload/lv2/poly_scope2.lv2/poly_scope2.so'
    plugin.write_bytes(plugin.read_bytes() + b'changed')
    assert not hardware_report_matches(package)


def test_package_file_list_excludes_host_files(tmp_path):
    for rel in ['debug.sh', 'payload/keep.py', 'payload/__pycache__/keep.pyc',
                'payload/.DS_Store', '._debug.sh']:
        p = tmp_path / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text('test')
    assert {str(p.relative_to(tmp_path)) for p in payload_files(tmp_path)} == {'debug.sh', 'payload/keep.py'}
