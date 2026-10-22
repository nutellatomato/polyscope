# Changelog

Public releases use semantic versioning. Each release also lists the
internal build tag it ships (shown on the device's SETUP page and in the
perf log), so an on-device build tag can always be matched to a release.

## Unreleased — tuner integration (build `v3f-t1-h1`)

The repository owner confirmed successful use of this build on their Hector
on 2026-10-22. This records an owner report, not a measured hardware test matrix.
The latest published release remains v2.0.0.

### Added

- Full-screen TUNE page, four channel readings, ±50-cent meter, ±3-cent green
  zone and adjustable A4 reference from 400 to 480 Hz.
- A yellow frozen-reading label and the existing RUN control.
- Bundled firmware-407 baseline files for source builds.
- Native detector accuracy tests and installer, recovery, USB-entry and Qt UI tests.
- Source hashes and an owner hardware-report record for the checked payload.

### Changed

- The frequency detector measures crossings between samples and handles DC offsets.
- Slow LFOs can produce a reading after one measured period.
- The Linux ARM64 plugin targets GLIBC 2.17.
- The README and USB guides now describe the tuner and current build.
- The committed `dist/` installer, recovery files, plugin and checksums are rebuilt together.

### Fixed

- Failed upgrades can restore the previously installed version.
- Fresh-install failures also restore generated metadata and backup state.
- Payload checks run before an upgrade resets the old install.
- Dry runs leave files unchanged.
- Recovery checks all baseline files and fails if its metadata rebuild fails.
- Installer and recovery share a lock and request read-only remount on exit.
- ZIPs exclude host Python caches and Mac metadata side files.

### Thanks

Thanks to [@jchiet](https://github.com/jchiet) for
[Precision #1](https://github.com/nutellatomato/polyscope/pull/1) and
[Tuner #2](https://github.com/nutellatomato/polyscope/pull/2).
Their original commits, tuner controls and pitch math are preserved.

## v2.0.0 — 2026-07-16 (build `v3f`)

The data-path release: higher-fidelity traces, a fixed engine-level memory
leak, and roughly half the paint cost — all on the same hardware.

### Highlights

- **12-bit trace resolution** (was 8-bit): samples travel as packed 12-bit
  base64 at exactly the same packet size as before — 16× finer amplitude
  steps, visibly smoother slow CV at high vertical zoom.
- **Growing stutter fixed for good.** Long sessions used to develop
  progressively longer UI freezes (over a second after an hour of uptime).
  Root cause was memory retained on every frame crossing the Python→QML
  bridge as a container; frame delivery was rewired (revision polling + a
  single JSON string) and the pause cost is now a constant ~20 ms
  regardless of session length.
- **Paint cost halved** (~28 ms → ~12 ms per frame): persistence ghosts
  draw with reduced vertex density while the live trace, measurements,
  trigger, and anti-alias envelope all keep full resolution. The whole UI
  reacts almost twice as fast.
- **Leaner codebase:** the legacy scope module, its UI, and all old wire
  formats are removed (~3,000 lines). The plugin and UI now speak a single
  wire format (v3) and always ship together.

### Breaking changes

- The **legacy scope module is gone** (UI file, module-browser entry, DSP
  bundle). The installer also cleans leftovers of it from older installs.
  Patches that contained a legacy scope keep loading; the module simply no
  longer exists after a fresh install.
- Old wire formats (v1/v2) are no longer decoded. Mixed old/new installs
  are not supported — always install UI and plugin together from the same
  bundle (the USB installer does this by construction).

### Internal build history (reference)

| build tag | what it was |
|---|---|
| `v3a` | 12-bit codec + GC-attribution instrumentation |
| `v3b` | ArrayBuffer frame-delivery experiment (reverted: GC fired 12× more often) |
| `v3c` | GC probe (`qgc_ms`) + scheduling experiment (rejected) |
| `v3d` | Pull-model delivery experiment (leak persisted) + yield experiment (rejected) |
| `v3e` | **Leak fixed**: revision polling + JSON-string frame delivery |
| `v3f` | **Released**: persistence-ghost decimation, paint halved |

## v1.2.0 — 2026-07-15 (build `perf8`)

Initial community release: custom full-screen scope UI, `polyscope` LV2
plugin with anti-alias envelope and alias-free measurements, trigger
holdoff, checksum-gated USB installer with full backup/recovery.
Internal build history: `perf1`–`perf8`.
