"""Exercise generated USB entry points with inert device-command stubs."""
import os
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parent


@pytest.mark.parametrize('kind', ['hector-scope-usb-v2', 'hector-scope-recovery-usb-v2'])
@pytest.mark.parametrize('firmware,status', [(406, 0), (408, 0), (407, 0), (407, 7)])
def test_firmware_gate_and_exit_status(tmp_path, kind, firmware, status):
    usb = tmp_path / 'usb'
    ui = tmp_path / 'ui'
    lv2 = tmp_path / 'lv2'
    tools = tmp_path / 'bin'
    for folder in [usb, ui / 'qml', lv2, tools]:
        folder.mkdir(parents=True, exist_ok=True)
    (ui / 'qml/Settings.qml').write_text('// FIRMWARE ' + str(firmware) + '\n')
    (usb / 'hector-scope-patch').mkdir()
    (usb / 'hector-scope-patch/install_scope.py').write_text('# stub')
    log = tmp_path / 'commands'
    stubs = {'id': 'echo 0', 'awk': ':', 'mount': 'echo "mount $*" >> "$COMMAND_LOG"',
             'sync': ':', 'shutdown': 'echo shutdown >> "$COMMAND_LOG"',
             'poweroff': 'echo poweroff >> "$COMMAND_LOG"',
             'python3': 'echo "python $* $HECTOR_UI_DIR $HECTOR_LV2_DIR" >> "$COMMAND_LOG"; exit "$TEST_STATUS"'}
    for name, body in stubs.items():
        p = tools / name
        p.write_text('#!/bin/bash\n' + body + '\n')
        p.chmod(0o755)
    source = (ROOT / 'dist' / kind / 'debug.sh').read_text()
    source = source.replace('/usb_flash', str(usb)).replace('/home/debian/UI', str(ui)).replace('/usr/lib/lv2', str(lv2))
    source = source.replace('/tmp/hector_scope_install.lock', str(tmp_path / 'install.lock'))
    # The macOS sandbox blocks process-substitution FDs; retain a plain log sink.
    source = source.replace('exec > >(tee -a "$LOG") 2>&1', 'exec >> "$LOG" 2>&1')
    script = tmp_path / 'debug.sh'
    script.write_text(source)
    env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
               COMMAND_LOG=str(log), TEST_STATUS=str(status))
    result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True, timeout=15)
    commands = log.read_text() if log.exists() else ''
    if firmware != 407:
        assert result.returncode != 0
        assert commands == ''
        assert 'requires firmware 407' in next(usb.glob('*.log')).read_text()
    else:
        assert result.returncode == status, result.stdout + result.stderr
        assert 'python ' in commands
        assert str(ui) in commands and str(lv2) in commands
        assert ('shutdown' in commands) == (status == 0)
        assert not (tmp_path / 'install.lock').exists()
