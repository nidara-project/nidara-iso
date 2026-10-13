# The release gate: what every ISO must pass before it ships

Green CI is not evidence that an image installs. In this repository CI runs `lint` and
skips the build. In nidara-desktop the smoke test boots the shell on a virtual GPU. Neither
installs a machine. So before an image is published (the first one built around Hyalo,
nidara-desktop #685, and every one after it), the **candidate** passes the walks below, end to
end, on the image itself rather than on a development checkout. The gate is tracked in
nidara-desktop #791.

## What a candidate carries

`build.sh` writes `<image>.record` beside every image it hands over (see the README). The
gate adds two more files beside it:

| File | What it says |
|---|---|
| `<image>.record` | What the medium was built from: the commits of nidara-iso, nidara-repo and nidara-desktop, the `[nidara]` database, every package and its version |
| `<image>.gate` | Each walk, PASS / FAIL / PENDING, with where its evidence is kept |
| `<image>.installed-packages` | What a fresh install from this image actually downloaded |

The third file exists because **the medium does not pin the installed system**. The target
downloads its packages when it is installed (offline install is #20), so two installs from the
same image a week apart can differ. The record describes the medium and the installed list
describes one real install.

A record that says `kind: TEST IMAGE` comes from `-L` and is never a candidate.

## The walks

### In a VM (automated, on every candidate)

| Walk | What it must show |
|---|---|
| **Blank disk** | install onto an empty disk, reboot without the medium, the login screen comes up |
| **Encrypted** | a wrong passphrase is refused, the right one unlocks, the system boots to the login screen |
| **Beside another OS** | a Windows-shaped EFI partition and an existing `/home` are kept: the other loader stays in the boot menu, the files are still readable |
| **Network lost mid-install** | the connection dies while packages are downloading: the install fails, **and the page says the connection was lost** rather than "an error occurred"; once reconnected, a new install over the leftovers succeeds and boots |

Each walk prints one PASS/FAIL line per check. A test that has only ever passed proves
nothing, so each walk should be seen to fail on the defect it is there to catch. The
encrypted walk has been (a wrong passphrase is typed first and must be refused), and so has
the beside-another-OS walk (against an installer older than nidara-desktop #559). The
network walk passed on its first run (2026-10-13, 47/0) and has **not yet** been seen to
fail: an installer that reported the old "an error occurred" text should fail it.

### On real hardware (by hand, on every candidate)

A VM says nothing about GPUs, monitors or suspend, and neither does the virtual GPU in CI.

| Walk | What it must show |
|---|---|
| **Suspend with the lock** | comes back locked, also when the lock screen itself fails to start (nidara-desktop #789) |
| **Update → reboot** | the *previous* candidate, installed, updates to this one and reboots; a way back exists (nidara-desktop #368) |
| **Screen sharing** | a portal request from Firefox, Chromium, OBS and a Flatpak: pick a screen, video arrives, stopping works, locking does what it should (nidara-desktop #683) |
| **GPUs and monitors** | every machine this release says it supports: boots, logs in, monitors plugged in and out |

The machines and features each release supports are written down with that release. A
hardware walk that was not done stays `PENDING` in the gate file, and **a gate with a PENDING
line has not passed**.

## Out of scope for this gate

HDR, VR, a universal extension system and further visual work. Offline install (#20) can wait
for a first alpha, provided the alpha says it needs a network.
