#!/usr/bin/env python3
"""Build, test, verify and archive the experimental Hector USB packages."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'test-artifacts'
LOG = ROOT / 'validation'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, log):
    print('RUN:', ' '.join(command), flush=True)
    with (LOG / log).open('w') as f:
        result = subprocess.run(command, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT)
    if result.returncode:
        print((LOG / log).read_text()[-6000:])
        raise SystemExit('FAILED: ' + log)
    print('PASS:', log, flush=True)


def main():
    OUT.mkdir(exist_ok=True)
    LOG.mkdir(exist_ok=True)
    if os.environ.get('ALLOW_PREBUILT_PLUGIN') == '1':
        raise SystemExit('Test packages require a source build; unset ALLOW_PREBUILT_PLUGIN')
    run(['bash', 'build_scope_usb_v2.sh'], 'build.log')
    run([sys.executable, 'test_scope_installer.py'], 'installer.log')
    run([sys.executable, 'test_freq_detector.py'], 'frequency.log')
    run([sys.executable, '-m', 'pytest', '-q', '--junitxml=' + str(LOG / 'tests.xml')], 'tests.log')
    xml = ET.parse(LOG / 'tests.xml')
    cases = xml.findall('.//testcase')
    assert cases and not xml.findall('.//skipped'), 'No tests or skipped tests'
    assert not xml.findall('.//failure') and not xml.findall('.//error')
    install = ROOT / 'dist/hector-scope-usb-v2'
    recovery = ROOT / 'dist/hector-scope-recovery-usb-v2'
    patch = install / 'hector-scope-patch'
    manifest = json.loads((patch / 'payload/manifest.json').read_text())
    assert (ROOT / 'install_scope.py').read_bytes() == (patch / 'install_scope.py').read_bytes()
    assert (ROOT / 'recover_scope.py').read_bytes() == (recovery / 'recover_scope.py').read_bytes()
    assert (ROOT / 'install_scope.py').read_bytes() == (recovery / 'install_scope.py').read_bytes()
    assert (recovery / 'recovery-manifest.json').read_bytes() == (patch / 'payload/manifest.json').read_bytes()
    for rel, info in manifest['replace'].items():
        assert sha(patch / 'payload/files' / rel) == info['patched']
        assert sha(patch / 'payload/originals' / rel) == info['baseline']
        assert sha(recovery / 'originals' / rel) == info['baseline']
    for rel, expected in manifest['new'].items():
        assert sha(patch / 'payload/files' / rel) == expected
    for bundle, files in manifest['lv2'].items():
        for name, expected in files.items():
            assert sha(patch / 'payload/lv2' / bundle / name) == expected
    plugin = patch / 'payload/lv2/poly_scope2.lv2/poly_scope2.so'
    built = ROOT / 'source/polyeffects-src/PolyLV2/poly_scope2.lv2/build/poly_scope2.so'
    assert sha(plugin) == sha(built)
    elf = plugin.read_bytes()
    assert elf[:6] == b'\x7fELF\x02\x01' and int.from_bytes(elf[18:20], 'little') == 183
    readelf = os.environ.get('LLVM_READELF') or shutil.which('llvm-readelf') or '/opt/homebrew/opt/llvm/bin/llvm-readelf'
    info = subprocess.check_output([readelf, '-h', '-d', '--dyn-syms', '--version-info', str(plugin)], text=True)
    (LOG / 'arm64-elf.txt').write_text(info)
    versions = re.findall(r'GLIBC_(\d+)\.(\d+)', info)
    assert versions and all((int(a), int(b)) <= (2, 17) for a, b in versions)
    assert re.search(r'GLOBAL\s+DEFAULT\s+\d+\s+lv2_descriptor', info)
    tag = re.search(r'^PACKAGE_VERSION = "([^"]+)"', (ROOT / 'install_scope.py').read_text(), re.M)[1]
    assert 'scopeBuild: "' + tag + '"' in (patch / 'payload/files/qml/Polyscope.qml').read_text()
    sources = ['install_scope.py', 'recover_scope.py', 'build_scope_usb_v2.sh',
               'source/polyeffects-src/PolyLV2/poly_scope2.lv2/poly_scope2.c',
               'source/polyeffects-src/PolyLV2/poly_scope2.lv2/Makefile',
               'source/polyeffects-src/PolyLV2/poly_scope2.lv2/poly_scope2.ttl',
               'source/polyeffects-src/PolyLV2/poly_scope2.lv2/manifest.ttl']
    sources += [str((Path('source/polyeffects-src/digit_ui') / rel)) for rel in list(manifest['replace']) + list(manifest['new'])]
    sources += [p.name for p in ROOT.glob('test_*.py')] + ['prepare_test_packages.py', 'requirements-test.txt', 'HECTOR_TEST_GUIDE.md', 'README.md', 'pytest.ini']
    receipt = {'tag': tag, 'pr2_commit': 'a16aed3c2a591c3eea56cc88aec979fca476a465',
               'base_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
               'target': 'aarch64-linux-gnu.2.17', 'zig': subprocess.check_output([os.environ.get('ZIG', 'zig'), 'version'], text=True).strip(),
               'tests': len(cases), 'skipped': 0, 'hardware_tested': False,
               'plugin_sha256': sha(plugin), 'source_sha256': {rel: sha(ROOT / rel) for rel in sources}}
    for folder in [install, recovery]:
        (folder / 'BUILD_PROVENANCE.json').write_text(json.dumps(receipt, indent=2) + '\n')
        entries = sorted(p for p in folder.rglob('*') if p.is_file() and p.name != 'SHA256SUMS')
        (folder / 'SHA256SUMS').write_text(''.join(sha(p) + '  ./' + p.relative_to(folder).as_posix() + '\n' for p in entries))
    archives = []
    for kind, folder in [('installer', install), ('recovery', recovery)]:
        dest = OUT / f'Polyscope-USB-{kind}-{tag}-review.zip'
        with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED) as z:
            for p in sorted(folder.rglob('*')):
                if p.is_file():
                    z.write(p, p.relative_to(folder))
        with zipfile.ZipFile(dest) as z:
            assert z.testzip() is None and 'debug.sh' in z.namelist()
            for line in z.read('SHA256SUMS').decode().splitlines():
                expected, rel = line.split('  ', 1)
                assert hashlib.sha256(z.read(rel.removeprefix('./'))).hexdigest() == expected
        archives.append(dest)
    (OUT / 'SHA256SUMS').write_text(''.join(sha(p) + '  ' + p.name + '\n' for p in archives))
    print(f'VERIFIED: {len(cases)} tests, zero skips; ARM64 ELF; GLIBC <= 2.17; two ZIPs verified')
    print((OUT / 'SHA256SUMS').read_text())


if __name__ == '__main__':
    main()
