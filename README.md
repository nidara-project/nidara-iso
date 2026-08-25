# nidara-iso

The Nidara live/install medium: an [archiso](https://gitlab.archlinux.org/archlinux/archiso)
profile that produces a bootable image of the
[Nidara desktop](https://github.com/nidara-project/nidara-desktop).

It is Arch. The base system comes from Arch's own mirrors, `pacman` stays
`pacman`, and nothing is frozen or forked. Two packages on the image do not come
from Arch — `nidara` (the desktop) and `nidara-apps` (the curated application
set) — plus a third, `nidara-release`, that the installer puts on the TARGET and
never on the medium (see "Identity" below). All three are served signed from
[nidara-repo](https://github.com/nidara-project/nidara-repo). "Based on Arch
Linux" is the whole claim — the name and the look are ours, the system is
theirs, and `/etc/os-release` says both.

## Building

```bash
sudo pacman -S archiso
sudo ./build.sh            # → out/nidara-$(cat VERSION)-x86_64.iso
```

`build.sh` imports and locally signs the `nidara-repo` key first: the profile
registers that repo with `SigLevel = Required`, so an unsigned build host
refuses to pull the desktop. CI (`.github/workflows/build-iso.yml`) runs the
same script in an Arch container and uploads the ISO as an artifact.

The image's version is the PRODUCT's, and it is **declared, not derived**: it
lives in `VERSION` at the root of this repo, `profiledef.sh` reads it for the
ISO filename, and `packages/nidara-release/PKGBUILD` carries the same number
into `/etc/os-release` on the system that gets installed. `PRODUCT.md` says why
that number is not the desktop's and why neither derives from the other.

## Identity: the installed system says "Nidara", the live one says "(live)"

`nidara-release` is a package with one file in it, `/etc/os-release`, and it is
**not on the image** — the installer puts it on the target. That split is on
purpose, and both halves are load-bearing:

- **On the target**, identity has to arrive as a package so it can be *updated*.
  A version written into a file by an installer names the image somebody
  downloaded and is stale the day after; this one moves with `pacman -Syu`.
- **On the live medium**, `profile/airootfs/etc/os-release` says
  `PRETTY_NAME="Nidara (live)"` and carries no version at all. If the package
  were on the image too, the overlay would overwrite a file the package owns and
  `pacman -Qkk` would report the medium as tampered with, forever — the exact
  flaw of the pacman-hook approach the package's own comments describe. And the
  live file carries no number so that there is only ONE place a version is
  written down.

⚠️ Installing that package the first time needs `--overwrite /etc/os-release`,
and that is not carelessness: systemd's `tmpfiles.d/etc.conf` leaves a symlink at
that path on any system that has booted, no package owns it, and pacman's
file-conflict check runs before any scriptlet could clear it. Afterwards the file
is ours and upgrades need no flags — measured, along with the fact that the
tmpfiles line is `L` and not `L+`, so it never takes the path back.

## What booting it gives you

Firmware logo → black → the Nidara desktop. No login screen, no distro splash:
the first thing with Nidara's identity on it is the desktop itself.

- **User `live`, password `nidara`.** Login is automatic. The password exists so
  a deliberate lock screen or a `sudo` prompt is recoverable — not as a gate on
  the way in. `sudo` is passwordless for that user.
- **Nothing is written to your disks** until you choose to install.
- **Networking is NetworkManager**, not archiso's iwd + networkd: Nidara's shell
  reads NetworkManager's `libnm` directly, so on any other stack its network
  panel would be blind.
- **The idle lock is removed** — see "The trap" below.
- **The clock is UTC.** archiso's own medium does the same; picking a timezone is
  a question the installer asks, not something a live session should guess.

### Installing, today

`archinstall` (Arch's own installer, in `extra`) ships on the image and works
from a terminal. Its config accepts a custom signed repository, a package list
and post-install commands, which is exactly the shape of a Nidara install:
register `[nidara]`, install `nidara`, run `nidara-setup`.

**The graphical installer is an open decision** — Calamares (configured, never
forked; it costs ~661 MiB of Qt6 on the image and will look like a Qt app on a
GTK desktop) versus a GTK4 installer of our own driving `archinstall` as a
library. The live half of this repo is identical either way, which is why it was
built first.

## The trap this profile exists to avoid

`config/hypr/hypridle.conf` locks the session after ten minutes of inactivity,
and Nidara's lock card **refuses to submit an empty password** — it grabs focus
and returns. On a live medium, where the user never chose a password, that
combination means: leave the machine for a coffee, come back to a screen with no
way out but a hard reset.

`nidara-live-setup` strips that one listener from the seeded per-user config
(the screen still blanks; only the credential prompt goes) and `logind` is told
to ignore the lid switch for the same reason.

## How it is put together

```
packages/                our own packages (built and signed by nidara-repo)
  nidara-release/        /etc/os-release: the product's name and version
profile/                 an ordinary archiso profile
  profiledef.sh          image identity, boot modes, compression
  packages.x86_64        releng's list, minus the rescue DVD, plus the desktop
  pacman.conf            Arch's repos + [nidara]
  airootfs/              the overlay: identity, systemd, the live setup script
  syslinux/ efiboot/     BIOS and UEFI boot entries
VERSION                  the product's version — declared here, read by both
build.sh                 key trust + mkarchiso
```

The one file worth reading is
`profile/airootfs/usr/local/bin/nidara-live-setup`. It runs once, before
`greetd`, and its whole design rule is **never reimplement `nidara-setup`** —
the desktop's own first-run script, shipped by the `nidara` package, which reads
the running machine (keyboard layout, timezone, locale, battery, active display
manager) to decide what it writes. Baking its output into the image would freeze
the build container's answers onto every machine that boots this ISO. So the
live medium runs the same script every real install runs, at first boot, against
the real hardware; the live script only adds what is specific to being live:
trust the repo key, create the user, drop the idle lock, autologin. CI fails the
build if it starts enabling services on its own.

## Hidden app entries

`profile/airootfs/usr/local/share/applications/` contains no applications. Each
file there hides one `.desktop` entry that a transitive dependency drops into
`/usr/share/applications`, where it then shows up in the app grid as if the user
had installed it.

On a Nidara installed over somebody's existing Arch these are lost among their
own apps. On a freshly booted ISO they **are** the app grid: before this, the
first screen of a brand-new Nidara offered three Avahi browsers, two Qt V4L2
utilities and a hardware-topology viewer, and only then Firefox. Measured in a
VM: fourteen entries became seven.

None of them come from a package this image asks for by name — they arrive
behind nautilus (avahi), ffmpeg (v4l-utils, hwloc) and uwsm (uuctl), all of them
dependencies of `nidara` itself, so the same entries appear on every ordinary
Nidara install too. Hiding them upstream rather than here is a change worth
making; this directory is the evidence that the mechanism works.

## Watching a boot from outside

The **verbose** boot entry also puts the console on the serial port, so a VM host
reads the whole boot — kernel, systemd, and `nidara-live-setup`'s own output —
without needing a way into the guest:

```bash
qemu-system-x86_64 ... -serial file:boot.log     # then pick the verbose entry
```

That matters more here than on a normal image: the medium ships with `sshd`
installed but not enabled, and QEMU's `screendump` does not work with the
`virtio-gpu-gl` device Hyprland needs. Without the serial line, a boot that ends
in a black screen tells the host nothing at all.

## Known gaps

- **No graphical installer yet** (see above).
- **No accessibility boot entry.** archiso's `releng` ships one that starts the
  `espeakup` screen reader; a graphical session needs a different answer (Orca),
  and shipping the console one would be a promise the desktop does not keep.
- **Not yet measured:** the ISO's size. `nidara` pulls the CJK font pack (~330
  MiB installed) through its dependencies, and a GitHub release asset is capped
  at 2 GiB. The build prints the number; the package list gets trimmed against
  it, not against a guess.
