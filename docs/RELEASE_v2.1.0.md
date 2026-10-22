# Polyscope v2.1.0 — tuner and safer USB installs

A four-channel tuner for Poly Effects Hector, with a more precise frequency detector and stronger install/recovery checks.

**Requires Hector firmware 407.** The on-device SETUP tag is **`v3f-t1-h1`**.
The repository owner confirmed successful use of this exact runtime build on their Hector.
If you already installed that build, you do not need to reinstall.

## Downloads and install

Download these release assets:

- `Polyscope-USB-installer-v2.1.0.zip`
- `Polyscope-USB-recovery-v2.1.0.zip`
- `SHA256SUMS`

Check the ZIP hashes against `SHA256SUMS`.
Back up your patches and prepare the recovery ZIP on a separate FAT32 USB stick.
Extract the installer ZIP and copy its **contents directly to the install stick's root**.
`debug.sh` and `hector-scope-patch/` must sit at the top level.
Insert it into a running Hector on firmware 407.
If it does not start, select Settings → QA CHECK → Run debug once.
Remove the USB when the screen goes black or the unit shuts down, before the next boot.
After boot, add a scope module and check **polyscope v3f-t1-h1** in SETUP.

## Changes

- Full-screen TUNE page with four channel readings, note names, cents and target Hz.
- ±50-cent meter and green ±3-cent in-tune zone.
- A4 reference from 400 to 480 Hz, with double-tap reset to 440 Hz.
- Clear frozen-reading label and RUN control.
- DC-offset-tolerant frequency detection with between-sample crossing measurement.
- Faster first readings for slow LFOs, while retaining audio-rate accuracy.
- Complete payload checks before an upgrade resets the old install.
- Managed-state restore on failed fresh installs and upgrades.
- Checked recovery baseline, verified metadata rebuild, and retained snapshots if restore fails.
- Linux ARM64 plugin built for GLIBC 2.17, with current source hashes and checksums.

The contributor's tuner controls, pitch math, plugin ports and packet layout are preserved.
A4 resets to 440 Hz when the UI reloads.

## Checks

- 58 host tests passed, zero skipped.
- 51 installer checks passed.
- 216 detector waveform/level/DC-offset/noise cases passed, plus slow-LFO and note-change checks.
- Both USB ZIPs, staged files, ARM64 binary and source hashes verified.
- All recorded runtime hashes match the owner-tested build.

The owner report covers successful installation and normal use.
Hardware recovery and power-loss behavior have not been confirmed.
The recovery ZIP restores the firmware-407 UI baseline; it is not a full firmware image.

## Thanks

Thank you **Joshua Chiet ([@jchiet](https://github.com/jchiet))** for
[Precision #1](https://github.com/nutellatomato/polyscope/pull/1) and
[Tuner #2](https://github.com/nutellatomato/polyscope/pull/2).
Your original commits, tuner controls and pitch math are preserved.
The integration and hardening are in [PR #3](https://github.com/nutellatomato/polyscope/pull/3).

[Full changelog](https://github.com/nutellatomato/polyscope/blob/v2.1.0/CHANGELOG.md) · [Install and recovery guide](https://github.com/nutellatomato/polyscope/blob/v2.1.0/HECTOR_TEST_GUIDE.md)
