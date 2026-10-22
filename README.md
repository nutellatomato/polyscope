# Polyscope

A four-channel digital oscilloscope for the **Poly Effects Hector** eurorack
module. Community firmware patch: a custom full-screen scope UI, a new LV2
scope plugin, and a checksum-gated USB installer with full backup/recovery.

> Formerly *HectorScope*. Renamed to match the module's on-device name
> (`polyscope`, shown on the SETUP page). Old GitHub links redirect
> automatically.

> **Current stable: `v2.0.0`** (on-device build tag `v3f`) — grab the
> installer from the GitHub release assets. Previous fallbacks: `v1.2.0-perf8`,
> `v1.1-perf7-stable`. See [CHANGELOG.md](CHANGELOG.md) for what's new.

## Features

- **4 input channels** with direct thru outputs (patch signals through the
  scope without losing them)
- **Views:** per-channel STACK, combined OVERLAY, and XY (CH1/2 or CH3/4)
  with live correlation readout
- **Timebase** 0.5–100 ms/div · **Scale** 0.5–10 V/div · per-channel
  **AC/DC coupling** and visibility
- **Triggering:** AUTO / RISE / FALL / **ROLL** (free-running right-to-left
  scroll — the best view for slow CV and evolving signals), adjustable level
  with optional auto-tracking, per-channel sync source, and **trigger
  holdoff** (1–500 ms) for locking onto complex, multi-edge waveforms
- **HF DETAIL anti-alias envelope:** under-sampled high-frequency content is
  drawn as an honest min/max band (recorded at full sample rate in the
  plugin) instead of a misleading aliased waveform
- **Alias-free measurements:** frequency is measured in the plugin from the
  raw full-rate signal; per-channel pp / rms / min / max / period readouts
- **Persistence** (5 levels) with afterglow envelope, **intensity** control,
  **measurement cursors** (fullscreen), **AUTOSET**, **FREEZE/RUN**, and a
  fullscreen trace viewer (tap the trace)
- **12-bit trace resolution** (4096 amplitude steps — visibly smoother
  slow CV at high zoom) at zero extra bandwidth
- Engineered for responsiveness on the Hector's CPU: threaded trace
  rendering, layered static/dynamic canvases, bulk socket ingest, and a
  constant-memory frame path — no growing stutter, no matter how long the
  session runs

## Requirements

- Poly Effects **Hector** on **firmware 407** — the installer verifies every
  file against the 407 baseline checksums and refuses to touch anything
  else, so a mismatched firmware aborts cleanly before any change
- A **FAT32 USB stick**

## Install

1. Download `Polyscope-USB-installer-…zip` from the latest release and
   unzip it.
2. Copy the **contents** of `hector-scope-usb-v2/` to the **root** of a
   FAT32 USB stick (so `debug.sh` and `hector-scope-patch/` sit at the top
   level).
3. Boot Hector normally, then insert the stick. **The installer runs
   automatically** — no menu interaction needed. (Fallback if nothing
   happens within ~30 s: Settings → QA CHECK → Run debug, pressed once.)
4. The module **reboots itself** when the install finishes.
5. ⚠️ **The moment the screen goes black, remove the USB stick.** If it
   stays inserted, the module re-runs the installer on every boot and looks
   stuck in an update/reboot loop. Nothing is damaged — remove the stick
   and let it boot normally.
6. Verify: open the scope module, go to **SETUP** — the footer must read
   **polyscope v3f**.

The installer backs up every original file on the device *and* onto the USB
stick before changing anything, verifies every write, and rolls back
completely on any failure.

### Uninstall / recovery

- The release also ships a **recovery USB** zip: prepare a stick the same
  way and insert it — it runs automatically, restores the pristine
  firmware-407 files from any state, and reboots. Same rule: remove the
  stick as soon as the screen goes black.
- The install stick keeps a copy of the original files under
  `hector_scope_originals_backup/` as an extra safety net.

## Mini manual

**Main page** — trace area (tap it for fullscreen), bottom bar with
RUN/FREEZE, CLEAR, TIME −/+, SCALE −/+, view selector (STACK / OVR / XY12 /
XY34) and SETUP. Right column: per-channel ON, SYNC (trigger source) and
OPTIONS (coupling, stats).

**SETUP page** — trigger mode/source/level (with AUTO level tracking),
**TRIGGER HOLDOFF** in ms (OFF = classic trigger; set just below your
pattern's repeat period to lock complex waveforms), persistence, intensity,
**HF DETAIL** on/off, AUTOSET, and the build tag.

**Reading tips**

- Fast audio on a slow timebase? The dim band around the trace is the
  **HF envelope** — the true amplitude of content too fast for the point
  trace. The Hz readout stays correct regardless (measured at full rate).
- Watching sequences, LFOs, envelopes evolve? Use **ROLL** trigger mode —
  the trace streams right-to-left continuously.
- Jumpy display on a complex repeating waveform? Raise **HOLDOFF** until it
  locks. Keep it OFF for simple periodic signals.
- **Cursors** live in the fullscreen view (CURSORS button, drag A/B for
  Δt / ΔV / frequency readouts).

## Performance logging (for bug reports)

Insert a FAT32 USB stick **without** `debug.sh` on it while the scope is
running: the UI appends a metrics line to `scope_perf.log` every 2 s
(receive rate, painted fps, queue depths, worst-case loop times, trigger
stability). The last ~20 minutes before insertion are included
retroactively. Attach that file to any issue.

## Experimental tuner update (not yet a stable release)

The tuner feature from community PR #2 adds a separate **TUNE** screen with
per-channel note names, cents deviation, a ±3 cent in-tune window, four
channel selector, and an adjustable A4 reference (400–480 Hz). Reference
pitch resets to 440 Hz after the UI reloads. The tuner reads raw measured
frequency from the plugin; it does not change the LV2 port contract.

The experimental `v3f-t1-h1` installer is intended for firmware-407 testing.
Always keep the separate recovery USB ready. A failed upgrade now restores
the previous install using a temporary on-device snapshot, but this is not
a guarantee against power loss during an update.

## Building from source

Everything ships in this repo: `source/` holds the patched UI
(`digit_ui/`) and the LV2 plugins (`PolyLV2/poly_scope2.lv2` is the active
scope). `build_scope_usb_v2.sh` cross-compiles the plugins (zig + lv2
headers + llvm-strip) and produces `dist/hector-scope-usb-v2/` (installer)
and `dist/hector-scope-recovery-usb-v2/` (recovery). The test suites
(`test_coalesce.py`, `test_scope_installer.py`) cover the wire protocol and
the full install/rollback state machine. The original firmware-407 baseline is now bundled in
`baseline/firmware-407/` with SHA-256 checksums. The build verifies its
contents, cross-compiles the plugin and regenerates both USB payloads.
Install Zig, LV2 headers and LLVM strip first; by default the build now
fails if it cannot cross-compile. Set `ZIG`, `LLVM_STRIP`, `LV2_CPPFLAGS`
as needed for your machine. Only use `ALLOW_PREBUILT_PLUGIN=1` knowingly;
it can package an out-of-date plugin. After rebuilding, run
`python3 test_scope_installer.py` and `python3 test_freq_detector.py`.

Engineering history — how the latency and rendering bottlenecks were found
and fixed — is documented in `docs/PERF4_CHANGES.md` and
`docs/PERF5_CHANGES.md`.

## License, attribution, disclaimer

This project modifies and redistributes source from **Poly Effects**
(`digit_ui`, `ingen` fork) under their open-source licenses; the scope LV2
plugins are original work licensed **GPL-2.0-or-later**; the patch set as a
whole is distributed under the **GPL-3.0**. See `LICENSE`.

This is a community project, **not affiliated with or endorsed by
Poly Effects**. Flashing modifies files on your device — the installer is
checksum-gated and fully reversible, but you use it at your own risk.


## Reviewed tuner test packages

The local hardening build is `v3f-t1-h1`.
It retains the contributor's tuner controls and pitch math.
Read `HECTOR_TEST_GUIDE.md` before a device test.
Read `REVIEW_REPORT.md` for the review and proof.

Build and run every test with:

```bash
python3 -m venv ".venv"
".venv/bin/python" -m pip install -r "requirements-test.txt"
LV2_CPPFLAGS="$(pkg-config --cflags lv2)" ".venv/bin/python" "prepare_test_packages.py"
```

Install Zig, LLVM, LV2 headers and pkg-config first.
Set `LLVM_STRIP` and `LLVM_READELF` if LLVM is not in PATH or the default Mac location.
The package command builds the Linux ARM64 plugin from source.
It targets GLIBC 2.17 and checks the final binary's library requirements.
It runs the installer, detector, data-path, recovery, USB-entry and Qt UI tests.
It rejects skipped tests.
It checks every file inside both ZIPs against its checksum list.
The ZIPs and their hashes go in `test-artifacts/`.
The logs and four rendered tuner screens go in `validation/`.
The Qt UI test uses Qt 6 on the Mac; it does not prove Hector's Qt runtime.
No step pushes Git changes, merges a PR, publishes a release or flashes a device.
