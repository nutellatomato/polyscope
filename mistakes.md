# Mistakes and fixes

## 2026-10-22 — build-kit validation

- The proposed patch emitted literal newlines inside Python strings. Its test guard also read `STAGED_QML` before defining it. Correct the strings and run the guard after its path definitions. Parse every emitted Python file before staging.
- The proposed 1-Hz test allowed only 2.3 seconds for a decaying midpoint to settle. Keep a separate first-reading test and measure settled accuracy after 3.3 seconds. Do not call startup and settled accuracy the same result.
- The proposed exact 10-Hz slow-window boundary could wait four cycles during startup. Allow a five-percent window margin. Test first-reading delay as well as final accuracy.
- The default Zig target produced a GLIBC 2.29 dependency. Target `aarch64-linux-gnu.2.17` and inspect the final ELF version requirements.
- The first UI test used the wrong channel-row spacing and omitted a host callback. Use the actual row layout and stub each host call. Destroy the view before its host objects.
- Bash process substitution failed at `/dev/fd/62` in the Mac sandbox. Use a plain file log in the inert USB-script harness. Check the actual firmware error text so an unrelated failure cannot pass the gate test.
- A staging whitespace check failed, but the shell continued to the commit. Use `set -e` when a failed check must stop the next Git step. Correct the space and verify the final commit.
- The evidence command ran from `test-artifacts/` but assumed the repo root. Resolve the root with `git rev-parse --show-toplevel` before reading build files.
- Copying a staged directory on FAT exposed Mac `._` side files and stopped a replacement guard. Copy only archive-listed files, then compare the payload file list and every hash. Preserve old logs and originals before replacing the installer.
