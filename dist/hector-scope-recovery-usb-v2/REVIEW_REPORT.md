# Polyscope tuner review — 2026-10-22

The integration build is `v3f-t1-h1`.
The initial review and host tests ran before the device test.
The owner then installed the verified FAT USB build and reported on 2026-10-22
that it works perfectly on their machine.
See [the owner-report record](docs/HARDWARE_VALIDATION.json) for the runtime hashes.
This is an owner report; no per-case measurements were supplied.
Recovery and power-loss behavior have not been confirmed on hardware.
Release v2.1.0 ships this same checked runtime build.

## Review source

- PR #2: https://github.com/nutellatomato/polyscope/pull/2
- Exact PR #2 head: `a16aed3c2a591c3eea56cc88aec979fca476a465`.
- PR #1: https://github.com/nutellatomato/polyscope/pull/1
- PR #1 head: `69671b189190d2682501e6a3599d4b4dec2a57fa`.
- PR #1 is an ancestor of PR #2.
- Review kit: `/Users/nepanduke/Downloads/Polyscope-tuner-hardening-build-kit.zip`.

The kit was read as proposed code. Its script was not accepted as proof.

## Findings and fixes

| Risk | Finding | Result |
|---|---|---|
| High | The old upgrade reset a working install before its rollback step began. | Capture the whole managed state before reset. Restore the previous version on normal errors. Keep a snapshot if restore fails. |
| High | The kit protected upgrades but did not fully protect fresh-install metadata, caches and backup state. | Use the full snapshot on fresh installs too. Test failure after each write stage and during marker creation. |
| High | The old recovery accepted a partial backup and ignored a failed module-list rebuild. | Check all five carried baseline files before writing. Verify writes and the rebuilt list. Restore the pre-recovery state on error. |
| High | The default Zig target produced a GLIBC 2.29 requirement. | Build for `aarch64-linux-gnu.2.17`. Inspect final imports, architecture and the LV2 entry point. |
| Medium | Reusing `v3f-t1` would skip the patch on a device with the contributor's build. | Use `v3f-t1-h1` in both installer and SETUP. |
| Medium | The kit generated invalid Python strings and used `STAGED_QML` before its definition. | Correct the emitted tests and their guard order. |
| Medium | Tests could use stale dist files or check removal of only the retired plugin. | Check current source and manifest hashes. Check removal of the current plugin and UI. Rebuild before the full suite. |
| Medium | The kit's exact 10-Hz boundary still waited four cycles during startup. | Allow a five-percent window margin. Test first-reading time, settled error and silence timeout. |
| Medium | A dry run created a backup directory. | Keep dry runs free of writes. Compare the full device tree before and after. |
| Medium | Install and recovery used different locks and cleanup did not always remount the persistent layer read-only. | Share a lock and request read-only remount from the exit trap. Test the generated entry scripts with inert device-command stubs. |
| Medium | The proposed preflight did not check carried baseline originals. | Check originals, replacements, new files and LV2 files before reset. Reject unsafe manifest paths. |
| Low | A frozen valid pitch could look live. | Add the yellow `FROZEN · LAST READING` label. |

The contributor's tuner math, four-channel selection, ±3-cent zone, A4 controls,
RUN button and scope-page paint suppression are preserved.
The only tuner QML changes are the build tag and frozen label.
The plugin's ports and packet layout remain unchanged.
The original frequency detector remains in use, with the slow-window change above.
The five checksum-gated patched firmware source files remain byte-for-byte equal to PR #2.
The carried firmware-407 baseline remains unchanged.

## Proof

Run from the repository root:

```bash
LV2_CPPFLAGS="$(pkg-config --cflags lv2)" ".venv/bin/python" "prepare_test_packages.py"
```

Current integration full-suite output:

```text
58 passed, 10 warnings
VERIFIED: 58 tests, zero skips; ARM64 ELF; GLIBC <= 2.17; two ZIPs verified
```

The direct installer suite reports `RESULTS: 51 passed, 0 failed`.
The supplied kit's independent snapshot self-test also passed.
The ten warnings come from old escape sequences in pristine firmware code.

The command rebuilds the plugin and runs every root test module.
It also runs the complete installer and detector scripts directly.
It rejects skipped tests and verifies both ZIP contents against their hash lists.
See `validation/package.log`, `validation/tests.log`, `validation/tests.xml`,
`validation/installer.log`, `validation/frequency.log` and `validation/arm64-elf.txt`.

Detector results include 216 waveform/level/offset/noise cases.
The largest settled audio error is 0.173 cents without noise and 0.690 cents with noise.
Note changes settle within one cent in 61–104 ms in the four supplied cases.
Slow-LFO startup reads arrive at 1.753 s, 0.897 s, 0.367 s and 0.186 s for 1, 2, 5 and 10 Hz.
Their first readings have 4.182–17.557 cents of error.
Their settled test packets show 0.000 cents of error at the packet's 0.001-Hz precision.
The 1-Hz settled test starts at 3.3 seconds.
These are synthetic host tests, not device measurements.

The real QML screen loads in Qt 6 with a software renderer.
The tests click A4 minus/plus, double-tap reset, each channel, BACK and RUN.
Four rendered screens show live, frozen, no-signal and out-of-tune states.
See `validation/tuner-live.png`, `validation/tuner-frozen.png`,
`validation/tuner-no-signal.png` and `validation/tuner-out-of-tune.png`.

Recovery tests verify full firmware-407 restore, damaged-original rejection,
failed-rebuild rollback and retained snapshots after a failed restore.
USB-wrapper tests stub all mount, shutdown and device-Python calls.
They use a plain file log because the Mac sandbox blocks Bash process-substitution FDs.
These tests do not mount storage or shut down this Mac.

Python 3.14 warns about old escape sequences in pristine firmware source.
The baseline bytes stay intact so its checksum checks remain valid.

## Output and next step

Use the installer and recovery ZIPs in `test-artifacts/`.
Each ZIP has `BUILD_PROVENANCE.json` with source hashes and a plugin hash.
The outer `SHA256SUMS` identifies the final ZIPs.
Read `HECTOR_TEST_GUIDE.md` before another installation or device check.
Prepare the recovery stick before the test stick.

The owner confirms successful use of the installed build on their Hector.
The host checks and Qt 6 render remain separate test evidence.
Power loss during a write and a device that cannot start USB debug remain untested.
The recovery package restores the firmware-407 UI baseline; it is not a full firmware image.
Keep the known-working firmware recovery path available.
PRs #1, #2 and #3 are merged. Release v2.1.0 packages the checked integration.
