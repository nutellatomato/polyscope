# Tuner integration

Build: `v3f-t1-h1` for Poly Effects Hector firmware 407.
Release: v2.1.0. The version is recorded in `VERSION`.
The release provides installer and recovery ZIPs plus SHA-256 checksums.
The repository contains the matching source and ready-to-copy `dist/` folders.
The older v2.0.0 release assets remain available.

## Contribution

[@jchiet](https://github.com/jchiet) supplied
[Precision #1](https://github.com/nutellatomato/polyscope/pull/1) and
[Tuner #2](https://github.com/nutellatomato/polyscope/pull/2).
PR #2 includes PR #1. The original contributor commits remain in the history.

The integration keeps their tuner controls, pitch math, four-channel readings,
A4 range and reset behavior, and separate TUNE page.
The hardening work adds restore checks, slow-LFO startup handling,
a frozen-reading label, and a checked ARM64 build and recovery package.
The LV2 ports and packet layout remain unchanged.

## Device report

On 2026-10-22, the repository owner reported that the installed build works
perfectly on their machine. The installer had been copied to a FAT32 USB,
and all its copied file hashes had passed before the device test.

[HARDWARE_VALIDATION.json](HARDWARE_VALIDATION.json) records that report and
the runtime file hashes from the tested package.
It does not invent a per-case test matrix or claim measured device accuracy.
Recovery, power loss, and other firmware versions remain outside that report.
The package command marks a rebuild as covered only if every recorded runtime
file hash still matches. A changed runtime file needs a new device check.

## Host checks

`prepare_test_packages.py` rebuilds the Linux ARM64 plugin for GLIBC 2.17.
It runs every root test module and the full installer and detector scripts.
It rejects skipped tests and verifies both ZIPs and the plugin's export.
It strips host Python caches and Mac metadata from the copied output.

The original host run passed 55 tests and 51 installer checks.
The detector run covers 216 waveform, level, DC-offset and noise cases.
See [the review report](../REVIEW_REPORT.md) for measured host results.
Qt tests use Qt 6 on the host; they are separate from the owner's Hector report.

## Git procedure

1. Check PR #2 against its expected contributor commit.
2. Build and test the combined tuner and hardening tree on a separate branch.
3. Open an integration PR with the hardening, documentation and rebuilt files.
4. Merge PR #2 with a merge commit to retain contributor history.
5. Merge the integration PR after its final tree and checks match.
6. Verify that main has both contributor commits and the checked payload.

PR #1 is included through PR #2; it does not need a second copy of its changes.
The v2.1.0 release tag selects the release preparation commit on main.
The checked ZIPs are attached to that GitHub Release.
