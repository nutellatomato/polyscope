# Firmware-407 baseline

Pristine copies of the five Poly Effects `digit_ui` files that the installer
replaces, exactly as they ship on a Hector running firmware 407. They were
taken from the `originals/` folder of the upstream v2.0.0 release payload and
match the `baseline` checksums in that release's `manifest.json`.

`build_scope_usb_v2.sh` reads baseline checksums and the recovery copies from
here, so the installer can be rebuilt without access to the original
firmware-407 git history. The build refuses to run if any file here stops
matching `SHA256SUMS`.

These files are Poly Effects source, redistributed under their original
open-source license (see `source/polyeffects-src/COPYING`).
