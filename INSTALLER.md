# The installer

The decision record for how Nidara gets onto a disk, and the shape that follows
from it. `installer-prototype/` is the evidence underneath it; `PRODUCT.md`
decides *what* gets installed, and this decides *how*.

## Decided 2026-08-25: our own GTK4 front-end, driving `archinstall`

Not Calamares. The reasoning is worth keeping, because the recommendation on
file until this day was the opposite one — Calamares for the alpha, on the
grounds that it is configuration rather than code, and that a first installer
should not be the thing that eats somebody's disk while it learns.

Three things moved, and all three are measurements rather than preferences:

1. **The hard half is done and it is not ours.** The prototype installed against
   a real disk, unattended, and the disk booted to the greeter. Partitioning,
   `pacstrap` and the bootloader — the parts that can destroy data — are
   `archinstall`'s code, the same code the official Arch medium runs. What is
   left for us is the part that cannot corrupt anything: asking questions.
2. **The front-end already has a worked example.** `gen-disk.py` collects an
   answer, calls `archinstall` as a *library* to compute the layout, and prints
   JSON. That is the whole architecture in sixty lines. And the schema is not a
   dead end: `DiskLayoutType` has `default_layout`, `manual_partitioning` and
   `pre_mounted_config`, so "wipe one disk" is where we start, not where we are
   stuck.
3. **Size changed sides.** Calamares costs ~661 MiB installed — 282 of them
   `qt6-webengine`, a Chromium, for the slideshow — or roughly 250 MiB of squashfs
   on an image that already measures 2.14 GiB and has just been declared not
   trimmable to fit a host's limit. Spending that margin on software that runs
   once and never reaches the disk is the worst placement available.

Prior art agrees, and it is recent: **Omarchy** — the most visible new
Arch-derived product — installs with its own configurator plus `archinstall`, and
its ISO repo contains no Qt and no GTK at all (Shell and Python only; the
configurator is a bash TUI). Every Arch derivative that uses Calamares —
EndeavourOS, Garuda, Manjaro, CachyOS — chose it *before* `archinstall` was a
library worth driving.

**What this costs, accepted with the decision:** weeks rather than days; manual
partitioning, dual-boot and encryption are not in the first version (see the
escape hatch below); and `archinstall`'s JSON schema breaks between releases, so
the version has to be pinned — the prototype already caught its own project's
sample config being rejected by the installed version.

## The line the installer does not cross

It never partitions, never formats, never `pacstrap`s and never writes a
bootloader. It collects answers, produces a JSON document, and runs one process.
Every failure mode that ends with somebody's data gone lives on the other side of
that line, in Arch's code, where a bug is an upstream bug.

## Where the code lives

The UI is a **fourth bundle in `nidara-desktop`** (`ui/installer/`, beside the
shell, the greeter and the lockscreen), shipped as its own package,
**`nidara-installer`**, which only `packages.x86_64` in this repo ever lists. The
installed system does not get it: a desktop should not carry code that formats
disks, and an ISO-only package is how that is enforced rather than promised.

The two halves of that are independent, and it is worth saying which is which.
*Shipping* it separately is free — an Arch split package builds once and emits
two. *Writing* it in the desktop's repo is the part that was argued, and it comes
down to one fact: everything that makes it look like Nidara is in there, reachable
only from inside the tree. The kit is imported by relative path
(`../../lib/nidara-kit/…`) with no package name and no version; the bundler is
`scripts/bundle.sh`; the greeter and the lockscreen do not even have npm trees of
their own, they reuse the shell's. A fourth surface costs four lines in `build()`.
The same surface in another repo costs a submodule or a vendored copy, a second
SCSS pipeline, and a kit that can break its consumer silently because nothing
versions it.

`install.sh` does **not** build it. It puts the desktop on an Arch somebody
already runs, and it must not build — let alone install — an installer.

If the kit is ever published as a library (NTK), moving `ui/installer/` out is a
code move and not a rewrite, because the seam below does not change.

## Two owners, one JSON

The prototype already found the boundary, and the front-end keeps it:

| Piece | Owner | Where it lives |
|---|---|---|
| Screens, widgets, wording, translations | the desktop's toolkit | `nidara-desktop/ui/installer/` |
| What Nidara installs: packages, `custom_commands`, trusting the repo key | the product | this repo, `profile/airootfs/usr/share/nidara-installer/base.json` |
| The disk layout | the machine | computed at run time by `archinstall`'s own library |

The base config is airootfs content, not a package, for the same reason
Calamares' branding would have been: one consumer, ISO-only, and a package would
only add a version to keep in step. It means the app hardcodes no product
decision — the day `nidara-apps` changes contents, nothing about the installer is
rebuilt.

## Privilege

The window runs as the live user, never as root. The engine runs as root through
`sudo -n`, which needs nothing new: the medium already gives `live` passwordless
sudo, because that account exists for the length of one boot and administers the
machine it is about to install. So the privilege boundary is exactly the seam —
a JSON document and one process spawn — instead of a GTK4 application running as
root under Wayland, with the portal, theme and runtime-dir problems that brings.

## What it asks, and what it refuses to ask

The live session is not a waiting room: by the time somebody clicks Install, they
have a working Nidara in front of them, with Settings. So the installer's
defaults are **read from the running live session** — language, keyboard layout,
timezone — and anyone who changed them while trying the desktop has already
answered those questions. What is genuinely left is short:

1. **Disk** — which one, and what is about to be destroyed, stated plainly.
2. **Account** — name, user name, password.
3. **Summary** — every default visible and editable here, then install.

Then progress, then reboot.

Three things are deliberately not screens:

- **Network.** The live desktop has the control centre's Wi-Fi panel, and it
  works. An installer that reimplements it is building a worse second one.
- **Mirrors.** `reflector` is on the medium and picks better ones than a person
  with a list of countries.
- **Which packages.** That is `PRODUCT.md`'s decision and `nidara-apps`'
  contents, not a checklist handed to somebody who has not booted the system yet.

## Disk, and the escape hatch

Version one does one shape: **one disk, erased, `default_layout`** — which is
what the prototype installed and what the overwhelming majority of installs are.

Anything else — manual partitioning, dual-boot beside Windows, LUKS — opens
`archinstall`'s own TUI in a terminal, from a clearly-marked *Advanced* entry.
That is not a placeholder for a missing feature; it is a real, upstream-maintained
installer that covers those cases today, and offering it is more honest than a
partition editor written in a hurry. `manual_partitioning` and
`pre_mounted_config` are in the schema for when our own version of those screens
is worth building.

## Progress, and failure

`archinstall`'s output is a log, so the UI shows a coarse phase (partition →
install → configure → Nidara) with the real output behind a disclosure. No
invented percentages. A non-zero exit leaves the log on screen, offers to save it,
and leaves the live session running — a failed install must not also take away
the working desktop the user was just using.

## How it is tested

The JSON seam is what makes this testable at all, and it is the reason the
prototype is not thrown away when the UI exists:

- **The engine, without a UI** — the prototype's exact path: generate the config,
  `--silent`, against a disk in QEMU, driven over serial and SSH from the host.
- **The UI, without a disk** — it produces a JSON document; that document can be
  diffed, and `--dry-run` will parse it. ⚠️ With the caveat the prototype paid
  for: **a dry run on a machine without the target disk proves nothing** —
  `archinstall` skips a device it cannot find and exits 0 on an empty layout.

## What exists today (2026-08-25)

- **The frame**, in `nidara-desktop/ui/installer/`: the window, the step flow, the base-config
  reader, and one placeholder step that says which screens are missing rather than miming them.
  It builds and runs on any Nidara session; `packaging/nidara/PKGBUILD` emits `nidara-installer`
  beside `nidara`.
- **The product half**, here: `profile/airootfs/usr/share/nidara-installer/base.json` — the
  prototype's config with the machine's and the person's answers taken out (hostname, timezone,
  locale; the disk was never in it). What is left is what the PRODUCT decides: systemd-boot, the
  `linux` kernel, NetworkManager, zram, and the four `custom_commands` that trust the repo key,
  install `nidara` + `nidara-apps`, land `nidara-release` and run `nidara-setup`.
  ⚠️ The last of those still carries `SUDO_USER=nidara`, a hardcoded user name from the
  prototype. It keeps the by-hand path working today, and the front-end MUST rewrite it with the
  account it just created — a base config cannot know that answer.
- **Not on the image yet:** `packages.x86_64` does not list `nidara-installer`. The package is
  built from a nidara-desktop TAG by nidara-repo, so it does not exist until the next desktop
  release is cut and pinned; naming it earlier would fail every ISO build in between.

## Not decided yet

- What the installer's version number is. It is built from a desktop tag but it
  is a product piece; `PRODUCT.md` has the two-number rule, and this does not
  obviously fall on either side.
- Whether the first version offers encryption at all, given the escape hatch.
- What happens after a successful install: reboot immediately, or return to the
  live desktop with the option.
- The boot menu of the installed system still says "Arch Linux (linux)" —
  `archinstall` writes that entry, and it is the first thing a user sees after
  installing. One `custom_command` away, but it needs deciding what it should say.
