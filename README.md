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
refuses to pull the desktop.

**Images are built locally, not in CI** (decided 2026-08-25). CI keeps the `lint`
job on every push — seconds, and it catches the syntax error that would otherwise
die twelve minutes into a container — and the `build` job is `workflow_dispatch`
only, a clean-room second opinion when a local build does something odd.

The numbers behind that, from the last CI run: **12.3 min of mkarchiso, of which
only 2.4 min is `pacstrap`.** The rest is squashfs `zstd -19` — CPU, not network.
A 4-vCPU runner is the worst machine available for that, and it hands back a
2.2 GB artifact instead of a file the VM harness can boot.

And the "clean Arch" worry does not apply to the image: `profiledef.sh` sets
`pacman_conf="pacman.conf"`, so the airootfs is pacstrapped from the PROFILE's
repo list (Arch's repos + `[nidara]`). A host running an Arch derivative
contributes `mkarchiso` and a keyring — none of its own packages reach the image.

Needs ~10 GiB free for the work dir, and root.

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

### Published (2026-08-25)

`v0.1.0` is tagged here, `nidara-repo` pins that tag, and `nidara-release-0.1.0-1` is built,
signed and served from the repository. A system installed from now on answers **Nidara 0.1.0**
in `/etc/os-release`, and the desktop's About shows it beside the desktop's own version.

The recipe travels inside the tag rather than being committed in the repo that builds it, so
cutting the next product version is: bump `VERSION` and the PKGBUILD's `pkgver` in one commit,
tag, then move `NIDARA_ISO_REF`. The lockstep gate refuses to publish if those three disagree.

⚠️ **The tag is frozen now that something consumes it.** Correcting this package means cutting a
new product version — there is no `pkgrel` to bump without moving a tag people may already have.

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

**The graphical installer is decided** (2026-08-25): a GTK4 front-end of our own,
driving `archinstall`, shipped as `nidara-installer` — an ISO-only package built
from a fourth bundle in `nidara-desktop`. Not Calamares. `INSTALLER.md` is the
record, with the measurements and the prior art that turned an earlier
recommendation around. The live half of this repo was identical either way, which
is why it was built first.

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

## Looking at the live session in QEMU (2026-08-25)

It works, and the whole desktop is there — wallpaper, bar, dock, app grid. The line that matters
is the harness's canonical one, and **`-vga none` is the load-bearing part**:

```bash
qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 4 -m 6G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=$HOME/VMs/iso-vars.fd \
  -cdrom out/nidara-*.iso -boot d \
  -vga none -device virtio-gpu-gl -display gtk,gl=on \
  -device virtio-net,netdev=n0 -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -device qemu-xhci -device usb-tablet
```

⚠️ **Drop `-vga none` and you get a black screen that looks exactly like a broken image.** QEMU
adds its default VGA device, the guest ends up with TWO display devices, and the window — and
`screendump` with it — shows the emulated VGA while Hyprland renders on the virtio-gpu. The tell
is that a text console (`ctrl+alt+f2`) IS visible while the desktop is not, and that `dmesg`
mentions `simple-framebuffer` alongside `virtio-gpu-pci`. Hours were spent on that before the
harness's own README turned out to have the answer in it.

The failures chased along the way are all downstream of the same mistake and do not need fixing:
`createImageFromDmaBufs failed`, then `verifyDestinationDMABUF: FAIL, format is external-only` →
`Backend requires blit, but blit failed`, on a compositor that had been handed the wrong device.
`AQ_NO_MODIFIERS=1` does not help, and neither does forcing software GL into the session.

**A capture, though, still has to come from the guest, not from QEMU.** With `gl=on` the scanout
is a dmabuf and QMP `screendump` cannot read it (it writes nothing at all). Use `grim` inside the
session — or photograph QEMU's window from the host.

Getting a shell on the live medium without typing into the window: `sshd` is installed but not
enabled and `root` has an empty password, so drive the console over QMP `send-key` —
`ctrl+alt+f2` reaches a getty (the desktop owns tty1), log in as `root`, then authorise a key and
`systemctl start sshd`. ⚠️ It is a live medium: every reboot loses that, and `/etc/environment`
with it (which pam_env does not apply to the greetd session anyway — put session env in
`/etc/profile.d/`, which `source_profile = true` does read). ⚠️ `pgrep -f <iso name>` matches your
own shell; get QEMU's pid with `fuser` on the pflash vars file.

## Known gaps

- **No graphical installer yet** — decided but not written; `archinstall` from a
  terminal is the only way in (see above and `INSTALLER.md`).
- **No accessibility boot entry.** archiso's `releng` ships one that starts the
  `espeakup` screen reader; a graphical session needs a different answer (Orca),
  and shipping the console one would be a promise the desktop does not keep.
- **The image does not fit GitHub, and will not be trimmed to.** Measured
  2026-08-25: 3,793 MiB installed in the airootfs → **2,192 MiB of ISO**, against
  a 2 GiB cap on a release asset. The two packages big enough to close that gap
  are `noto-fonts-cjk` (299 MiB — the desktop ships ja and zh-CN) and `firefox`
  (295), and both are things the product promised. So the file goes somewhere
  without an opinion about its size; `PRODUCT.md` holds the rule and the
  candidates.
