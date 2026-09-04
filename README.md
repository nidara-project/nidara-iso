# nidara-iso

The Nidara live/install medium: an [archiso](https://gitlab.archlinux.org/archlinux/archiso)
profile that produces a bootable image of the
[Nidara desktop](https://github.com/nidara-project/nidara-desktop).

It is Arch. The base system comes from Arch's own mirrors, `pacman` stays
`pacman`, and nothing is frozen or forked. Two packages on the image do not come
from Arch — `nidara-desktop` (the desktop) and `nidara-apps` (the curated
application set) — plus a third, `nidara-release`, that the installer puts on the TARGET and
never on the medium (see "Identity" below). All three are served signed from
[nidara-repo](https://github.com/nidara-project/nidara-repo). "Based on Arch
Linux" is the whole claim — the name and the look are ours, the system is
theirs, and `/etc/os-release` says both.

## Building

```bash
sudo pacman -S archiso
sudo ./build.sh            # → out/nidara-2026.09.01-x86_64.iso (today's date)
```

`build.sh` imports and locally signs the `nidara-repo` key first: the profile
registers that repo with `SigLevel = Required`, so an unsigned build host
refuses to pull the desktop.

It also refuses to hand over an image whose installer would not do what the
image says. `packages.x86_64` asks for `archinstall` unpinned, so a build takes
whatever version was current that day, and `check-base-config.sh` runs that
exact archinstall — inside the airootfs the build just made — against the exact
`base.json` it ships. ⚠️ The dry-run is only half of it: archinstall reads its
config key by key with `.get()`, so **a key it no longer knows is skipped in
silence**, and a rename of `custom_commands` would install a machine with no
Nidara on it and exit 0. The other half reads back the configuration archinstall
saves for itself and checks nothing went missing. A rejected image is moved to
`out/rejected/` rather than left beside the good ones.

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

⚠️ **A successful build ends with three keyring errors, and they are the design.**

```
[mkarchiso] INFO: Creating a list of installed packages on live-enviroment...
warning: Public keyring not found; have you run 'pacman-key --init'?
error: nidara: key "80B0AC8C36A43611A8619959B06B716279F755A9" is unknown
error: keyring is not writable
```

The last step queries the image with `pacman -Q --sysroot`, and the image has no
keyring: `/etc/pacman.d/gnupg` is a **tmpfs mount made at boot**, so at build
time it does not exist. The sync databases are still there, `nidara.db.sig`
among them, and `DatabaseOptional` means *verify the signature if present* — so
pacman looks for our key in a keyring that has not been created yet. The package
list is written correctly, and the live session gets the key from
`nidara-live-setup` once `pacman-init.service` has made the keyring.

**What a real signature failure looks like is no ISO at all.** `SigLevel = Required`
aborts `pacstrap`; it never warns and continues. If `out/` has an image and
`pkglist.x86_64.txt` names the three `nidara-*` packages, every signature was
verified.

**The image carries a date and the machine carries nothing** — `profiledef.sh`
builds `nidara-2026.09.01-x86_64.iso` from `SOURCE_DATE_EPOCH`, and there is no
`VERSION` file here to bump. An image never changes after it is published, so a
name that fixes it in time stays true forever; the machine it installs converges
on the newest of every layer within a day and is not a release of anything.

`PRODUCT.md`, "The machine is rolling, the image has a date", is the record — and
the short version of why the previous scheme (a declared `0.1.0`) lasted five
days: `nidara-release` carries no `backup=`, so every machine that had run
`-Syu` reported the newest number published, and a field identical across the
whole fleet informs nobody. The announceable number did not disappear, it moved
to the thing that genuinely gets rewritten: `nidara-desktop`'s own semver.

## Identity: the installed system says "Nidara", the live one says "(live)"

`nidara-release` is a package with one file in it, `/etc/os-release`, and it is
**not on the image** — the installer puts it on the target. That split is on
purpose, and both halves are load-bearing:

- **On the target**, identity arrives as a package so it can be *corrected*.
  Nothing an installer writes has a route back to the machines it already wrote
  to; the support URLs, the logo and the ANSI colour in that file all move with
  `pacman -Syu`. (Its VERSION used to be the argument here. There is none now —
  see above — and the rest of the file is reason enough.)
- **On the live medium**, `profile/airootfs/etc/os-release` says
  `PRETTY_NAME="Nidara (live)"`. If the package were on the image too, the
  overlay would overwrite a file the package owns and `pacman -Qkk` would report
  the medium as tampered with, forever — the exact flaw of the pacman-hook
  approach the package's own comments describe.

⚠️ Installing that package the first time needs `--overwrite /etc/os-release`,
and that is not carelessness: systemd's `tmpfiles.d/etc.conf` leaves a symlink at
that path on any system that has booted, no package owns it, and pacman's
file-conflict check runs before any scriptlet could clear it. Afterwards the file
is ours and upgrades need no flags — measured, along with the fact that the
tmpfiles line is `L` and not `L+`, so it never takes the path back.

### Where Nidara comes from travels the same way

`nidara-release` carries a second file, `/etc/pacman.d/nidara-mirrorlist`, and the
live medium's `pacman.conf` reaches `[nidara]` through an `Include` of it rather
than a literal `Server =`. Same reason as the name: a `Server =` line sits in
`/etc/pacman.conf`, which no package owns, so the address was something **only a
new install could learn** — if this repository ever moved, every machine already
installed would sit on a 404 with no way to be told. It is the same shape Arch
uses for its own mirrors, and the reason `Include = /etc/pacman.d/mirrorlist` is
what every Arch machine has.

⚠️ **The two `pacman.conf` files in this repo are no longer identical, and making
them identical again breaks one of them.** `profile/pacman.conf` is the BUILD
config — `mkarchiso` and `pacstrap` read it on the build host, which has no
Nidara file in `/etc/pacman.d/` and should not — so it keeps a literal
`Server =`. `profile/airootfs/etc/pacman.conf` is the live system's, copied
verbatim onto the installed machine by archinstall, and it uses the `Include`.

⚠️ **A missing Include target is not a degraded repo — it is a hard parse error
on every pacman invocation**, `pacman-key` included, which is how the target
trusts this repo's key in the first place. So the file has to exist at every
moment, and three things make sure it does: the medium ships it in its airootfs,
the installer writes it to the target as its **first** command (before anything
runs pacman there), and `nidara-release` then adopts it — which is what the
second `--overwrite` on that package's install line is for.

`build.sh` checks both of those before `mkarchiso` starts: that the three places
carrying the address agree, and that the live config actually parses.

### The package is not in this repo (moved 2026-08-30)

⚠️ **`nidara-release` lives in
[nidara-repo](https://github.com/nidara-project/nidara-repo/tree/main/packages/nidara-release)**,
beside `nidara-apps` and `nidara-system`. It was here, and the reason was the
version: that number was the product's, so the only honest way to keep it from
drifting was to make cutting a product version mean tagging THIS repo — which
bought a second pin and a lockstep gate over there.

The version is gone, and so is the coupling. **This repo is no longer tagged at
all**, which would have left the package unpublishable where it was. What decides
its new home is the rule its two neighbours already set: *nidara-repo holds the
packages whose content must change without cutting a release of something else.*
Correcting a support URL must not require building a 2 GiB image.

The identity is still the PRODUCT's act and still never the desktop's — that part
did not change, and it is why `install.sh` will never install this package.

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
register `[nidara]`, install `nidara-desktop`, run `nidara-setup`.

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
profile/                 an ordinary archiso profile
  profiledef.sh          image identity, boot modes, compression
  packages.x86_64        releng's list, minus the rescue DVD, plus the desktop
  pacman.conf            Arch's repos + [nidara] — the BUILD host's copy
  airootfs/              the overlay: identity, systemd, the live setup script
    etc/pacman.conf        the LIVE system's, and the installed one's: Include
    etc/pacman.d/…         the mirrorlist that Include names
  syslinux/ efiboot/     BIOS and UEFI boot entries
build.sh                 key trust + mkarchiso + the base.json gate
check-base-config.sh     does the image's archinstall still accept base.json?
```

The one file worth reading is
`profile/airootfs/usr/local/bin/nidara-live-setup`. It runs once, before
`greetd`, and its whole design rule is **never reimplement `nidara-setup`** —
the desktop's own first-run script, shipped by the `nidara-desktop` package, which reads
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
dependencies of `nidara-desktop` itself, so the same entries appear on every ordinary
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
