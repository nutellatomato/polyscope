#!/usr/bin/env python3
"""Accuracy test for the plugin's frequency detector (the tuner's input).

Compiles source/.../poly_scope2.lv2/test_freq_host.c on the host, which drives
the real plugin with synthetic sine/saw/square/pulse/triangle signals from
27.6 Hz to 3.5 kHz (clean, small, DC-offset and noisy) and checks the
frequency in the notify packet is within 0.5 cents (1 cent with noise), and
that a note change settles within 200 ms. Skipped without a C compiler or
LV2 headers. Run with pytest, or directly to see the full table.
"""
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.abspath(__file__))
PLUGIN_DIR = os.path.join(REPO, "source", "polyeffects-src", "PolyLV2", "poly_scope2.lv2")


def _build():
    cc = shutil.which("cc") or shutil.which("gcc") or shutil.which("clang")
    if cc is None:
        return None, "no C compiler on host"
    cflags = subprocess.run(["pkg-config", "--cflags", "lv2"], capture_output=True, text=True)
    if cflags.returncode != 0:
        return None, "lv2 headers not found via pkg-config"
    # build outside the plugin dir so its build/ stays what the USB script makes
    exe = os.path.join(tempfile.mkdtemp(prefix="scope_freq_host_"), "test_freq_host")
    cmd = [cc, "-O2", "-o", exe, os.path.join(PLUGIN_DIR, "test_freq_host.c"), "-lm"]
    cmd += cflags.stdout.split()
    built = subprocess.run(cmd, capture_output=True, text=True)
    assert built.returncode == 0, built.stderr
    return exe, None


def test_frequency_detector_accuracy():
    import pytest
    exe, why = _build()
    if exe is None:
        pytest.skip(why)
    result = subprocess.run([exe], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, result.stdout[-3000:]
    assert "ALL FREQ TESTS PASSED" in result.stdout


if __name__ == "__main__":
    exe, why = _build()
    if exe is None:
        print("SKIP:", why)
        sys.exit(0)
    sys.exit(subprocess.run([exe]).returncode)
