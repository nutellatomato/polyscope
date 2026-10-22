# Hector firmware-407 test

Current repository build: `v3f-t1-h1`, for Hector firmware 407.
The owner reported successful use on their Hector on 2026-10-22.
See `docs/HARDWARE_VALIDATION.json` for the exact scope and runtime hashes.
No per-case hardware measurements or recovery test results were supplied.
No tuner release has been published yet.
Keep a separate, known-working recovery USB.
Back up your patches first.
Do not use this build on another firmware version.

1. Confirm firmware **407** on Hector.
2. Download and extract the main branch ZIP, or use a checked source build.
3. Open `dist/hector-scope-recovery-usb-v2/`.
4. Copy all its contents to the root of a separate FAT32 USB stick.
5. Keep that recovery stick out of Hector during the install test.
6. Open `dist/hector-scope-usb-v2/`.
7. Copy all its contents to the root of another FAT32 USB stick.
8. Boot Hector and insert the installer stick.
9. If no install starts, use Settings -> QA CHECK -> Run debug once.
10. Read the result on the screen.
11. Remove the USB when the screen goes black or Hector shuts down.
12. If Hector stays on after success, power it off by hand.
13. Remove the USB before you power Hector on.
14. Add a scope module and check `v3f-t1-h1` in SETUP.

For a new device check, test each item and record pass or fail.
The owner's general success report does not mark each item below as tested:

- Boot after a full power cycle.
- Scope input and output on all four channels.
- STACK, OVERLAY, XY 1-2 and XY 3-4.
- Trigger, holdoff, coupling, persistence and cursors.
- TUNE opens and BACK returns to the scope.
- Each channel can become the main tuner reading.
- A4 at 440 Hz reads A4 and about zero cents.
- The note, meter and border turn green within ±3 cents.
- A4 steps from 400 to 480 Hz and resets to 440 Hz on a double tap.
- A4 resets to 440 Hz when the UI reloads, as in the contributor's version.
- FREEZE holds the last reading and shows the yellow frozen label.
- RUN resumes measurement.
- DC-offset oscillators still read correctly.
- Slow LFOs at 1, 2, 5 and 10 Hz show a scope frequency.
- Allow three cycles for the 1-Hz reading to settle.
- Slow LFOs do not show musical notes below the tuner's original 16-Hz limit.
- After signal removal, the frequency clears after the detector timeout, about two seconds.
- Leave the scope and tuner running and check for stalls.

To recover:

1. Remove the installer USB.
2. Insert the separate recovery USB into the running Hector.
3. Use QA CHECK -> Run debug once if it does not start.
4. Read the recovery result.
5. Remove the USB after shutdown, before the next boot.
6. If it reports an error, keep the log and any retained snapshot.

Recovery restores the five checked firmware-407 UI files and rebuilds the module list.
It removes Polyscope, its helper, both scope plugin bundles, and the version marker.
It leaves user patches in place.
It restores the pre-recovery state if a normal recovery step fails.
An incomplete restore keeps its `.polyscope-upgrade-*` folder beside the UI.
Do not remove that folder if a restore failed.
Power-loss recovery and recovery from a device that cannot start USB debug remain untested.

For locally built installer/recovery ZIPs, extract each ZIP directly to its USB root.
The ZIP already has `debug.sh` at the top level.
Check local ZIP hashes against `test-artifacts/SHA256SUMS`.
Each copied folder has its own `SHA256SUMS` for file checks.

Keep `/usb_flash/hector_scope_install.log` from the installer stick.
Keep `/usb_flash/hector_scope_recovery.log` from the recovery stick.
Keep the two sticks separate.
