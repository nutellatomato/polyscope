# Polyscope

A four-channel oscilloscope and tuner for the **Poly Effects Hector**.
This community patch adds a full-screen UI and an LV2 plugin.
An LV2 plugin is the part that measures and passes the signals through Hector.

**Latest release: [v2.1.0](https://github.com/nutellatomato/polyscope/releases/tag/v2.1.0)**
(on-device build `v3f-t1-h1`). The owner confirmed successful use on their
Hector on 22 October 2026. This release targets **firmware 407**.
Download the installer and separate recovery ZIP from the release page.
The source, ARM64 plugin and ready-to-copy files are also included in `dist/`.

Formerly called *HectorScope*. The old folder names remain in the installer.
See [CHANGELOG.md](CHANGELOG.md) for the build history.

## Features

- Four inputs with direct thru outputs.
- STACK, OVERLAY and XY views, with an XY correlation readout.
- Timebase from 0.5 to 100 ms/div and scale from 0.5 to 10 V/div.
- Per-channel AC/DC coupling and visibility.
- AUTO, RISE, FALL and ROLL trigger modes, with adjustable trigger level,
  auto-level tracking, sync source and 1–500 ms trigger holdoff.
- HF DETAIL: a min/max envelope shows fast signals that the trace cannot resolve.
- Frequency, peak-to-peak, RMS, minimum, maximum and period readouts.
- Persistence, intensity, fullscreen cursors, AUTOSET and FREEZE/RUN.
- 12-bit traces with 4,096 amplitude steps.
- A full-screen **TUNE** page with four channel readings, note names,
  a ±50-cent meter and a green ±3-cent in-tune zone.
- Adjustable A4 reference from 400 to 480 Hz in 1 Hz steps.
- A frequency detector that handles DC offsets and measures between samples.

## Install the latest release

1. Open the [v2.1.0 release page](https://github.com/nutellatomato/polyscope/releases/tag/v2.1.0).
2. Download `Polyscope-USB-installer-v2.1.0.zip`,
   `Polyscope-USB-recovery-v2.1.0.zip` and `SHA256SUMS`.
3. Check the ZIP hashes against `SHA256SUMS`.
4. Extract each ZIP. Copy the installer ZIP contents directly to the root of
   the install stick. Prepare the recovery ZIP on a separate stick.
5. Follow steps 4–9 below to install and check the on-device build tag.

## Install from the repository

Use a Hector on **firmware 407** and a FAT32 USB stick.
Back up your patches and prepare a separate recovery stick first.

1. [Download the main branch ZIP](https://github.com/nutellatomato/polyscope/archive/refs/heads/main.zip) and extract it.
2. Open `dist/hector-scope-usb-v2/`.
3. Copy **all contents of that folder** to the USB root.
   `debug.sh` and `hector-scope-patch/` must sit at the top level.
4. Boot Hector normally and insert the stick.
5. If it does not start within about 30 seconds, select
   Settings → QA CHECK → Run debug once.
6. Read the result. The script requests shutdown after success.
7. Remove the USB when the screen goes black or Hector shuts down.
   If Hector stays on after success, power it off by hand.
8. Remove the USB before the next boot.
9. Add a scope module. Open SETUP and check **polyscope v3f-t1-h1**.

Keep the UI and plugin from the same package together.
The installer checks the staged files before it changes the device.
It checks the expected firmware files, saves their old state, and checks each write.
If a normal install step fails, it attempts to restore the old state.
Read the log if it reports an error. An incomplete restore retains its snapshot.
Sudden power loss during an update is not covered by those checks.

See the [install, test and recovery guide](HECTOR_TEST_GUIDE.md) for details.
The full owner-report record is in [docs/HARDWARE_VALIDATION.json](docs/HARDWARE_VALIDATION.json).

### Recovery

Prepare another FAT32 stick with the contents of
`dist/hector-scope-recovery-usb-v2/` at its root.
Use it as described in the [recovery guide](HECTOR_TEST_GUIDE.md).

Recovery checks and restores the five carried firmware-407 UI files,
rebuilds the module list, and removes the scope additions.
It leaves user patches in place.
It is **not a full firmware image** and needs Hector's USB debug runner to work.
Hardware recovery and power-loss recovery have not been confirmed by the owner report.

The install stick also keeps original files in `hector_scope_originals_backup/`.
Keep that folder and the install and recovery logs.

## Mini manual

**Main page:** tap a trace for fullscreen. Use the bottom bar for
RUN/FREEZE, CLEAR, TIME, SCALE, the view selector, TUNE and SETUP.
Use the right column for channel ON, SYNC and OPTIONS.

**TUNE:** tap a channel in the right column to make it the main reading.
The note, meter and border turn green within ±3 cents.
Use A4 minus or plus to change the reference. Double-tap the reference to reset
it to 440 Hz. It also resets to 440 Hz when the UI reloads.
FREEZE holds the last reading and shows a yellow label. RUN resumes measurement.
The tuner shows musical notes from 16 to 8,000 Hz. Slower LFOs still have a
scope frequency readout; allow about three cycles for a 1-Hz signal to settle.

**SETUP:** select trigger mode, source and level, trigger holdoff,
persistence, intensity, HF DETAIL and AUTOSET. The footer shows the build tag.

**Reading tips:** use ROLL for slow CV. Raise HOLDOFF to lock onto a complex
repeating signal. Use fullscreen cursors for time and voltage differences.
The dim HF envelope shows fast content that is too quick for the point trace.

## Build and check

The firmware-407 baseline is included in `baseline/firmware-407/`.
The build checks its hashes before use.
Install Git, Python 3, make, pkg-config, Zig, LLVM and LV2 headers first.
On a Mac with Homebrew:

```bash
brew install git python pkg-config zig llvm lv2
python3 -m venv ".venv"
".venv/bin/python" -m pip install -r "requirements-test.txt"
export LLVM_STRIP="$(brew --prefix llvm)/bin/llvm-strip"
export LLVM_READELF="$(brew --prefix llvm)/bin/llvm-readelf"
LV2_CPPFLAGS="$(pkg-config --cflags lv2)" ".venv/bin/python" "prepare_test_packages.py"
```

On another host, put `llvm-strip` and `llvm-readelf` in PATH, or set
`LLVM_STRIP` and `LLVM_READELF` to their exact paths.
Set `ZIG` or `LV2_CPPFLAGS` if the tools or headers need another path.
The target is Linux ARM64 with GLIBC 2.17, the Linux system-library baseline.

The package command rebuilds the plugin and runs the full suite.
It rejects skipped tests, checks the binary and verifies both ZIPs.
The release version comes from `VERSION`.
The installer and recovery ZIPs use that version in their filenames.
The output goes to `test-artifacts/`; logs and tuner images go to `validation/`.
For a build without the full suite, run `bash "build_scope_usb_v2.sh"`.
That command regenerates the two `dist/` folders.
The full package check must pass before those files are merged.

The owner report applies only while the recorded runtime file hashes still match.
A later code change needs another device check.
See [the tuner integration record](docs/TUNER_INTEGRATION.md) and
[the hardening review](REVIEW_REPORT.md) for the test scope and limits.

## Performance logs

Insert a FAT32 USB stick **without `debug.sh`** while the scope runs.
The UI writes `scope_perf.log` every two seconds and includes its recent history.
Attach that file to a bug report.
The earlier rendering work is documented in
[PERF4_CHANGES.md](docs/PERF4_CHANGES.md) and [PERF5_CHANGES.md](docs/PERF5_CHANGES.md).

## Credits and license

Thanks to **[@jchiet](https://github.com/jchiet)** for
[PR #1: Precision](https://github.com/nutellatomato/polyscope/pull/1) and
[PR #2: Tuner](https://github.com/nutellatomato/polyscope/pull/2).
Their work adds the tuner, the more precise DC-offset-tolerant frequency detector,
the host detector tests, and the build path that includes the firmware baseline.
Their tuner controls and pitch math are preserved.

This project modifies and redistributes **Poly Effects** source under its
original open-source licenses. The scope LV2 plugin is GPL-2.0-or-later.
The patch set is GPL-3.0. See [LICENSE](LICENSE) and the source licenses.
This is a community project, not affiliated with or endorsed by Poly Effects.
