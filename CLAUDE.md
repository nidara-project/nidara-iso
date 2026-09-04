# CLAUDE.md

Guidance for AI agents working in the `nidara-iso` repository.

## What this repository is

`nidara-iso` builds the bootable live installation medium (ISO) for **Nidara** — a full Wayland desktop environment for Arch Linux. The ISO boots into a live Nidara desktop session from which the user can test the environment and launch the graphical installer (`nidara-installer`).

## Repository Structure

| Path | Purpose |
|---|---|
| `profile/` | The `archiso` profile definition consumed by `mkarchiso`. |
| `profile/airootfs/` | Overlay directory copied directly into the live filesystem root (contains services, desktop config, and `/usr/share/nidara-installer/base.json`). |
| `profile/packages.x86_64` | Package list installed into the live medium by `pacstrap`. |
| `profile/pacman.conf` | Pacman configuration for the live environment, declaring the `[nidara]` repository with `SigLevel = Required`. |
| `profile/nidara-repo.gpg` | Public signing key for the `[nidara]` package repository. |
| `installer-prototype/` | Prototype scripts verifying unattended `archinstall` integration (`gen-disk.py`, `nidara.json`). |
| `build.sh` | Build wrapper establishing local key trust and invoking `mkarchiso`. |
| `check-base-config.sh` | The gate that keeps `base.json` and the shipped `archinstall` compatible. Run by `build.sh` after the image is built. |

## How to Build

Building the ISO requires `archiso` (from Arch `extra`) and `root` privileges (for mounting and loop-mounting filesystems):

```bash
sudo ./build.sh [-o OUTPUT_DIR] [-w WORK_DIR]
```

### Testing an UNRELEASED change to the installer (or the desktop)

The image installs `nidara-installer` from `[nidara]`, which nidara-repo builds from the tag in
its `pins.env` — so a freshly built image carries the installer of the last RELEASE, and an
unreleased change cannot reach a medium without cutting a release first.

```bash
cd ~/Dev/Distroia && ./scripts/dev/build-installer-pkg.sh    # -> out-pkg/
cd ~/Dev/nidara-iso && sudo ./build.sh -L ~/Dev/Distroia/out-pkg
```

⚠️ **That produces a TEST image**: unsigned local packages, code in nobody's git history. Do not
publish it — on the medium it identifies itself, `pacman -Q nidara-installer` answering
`0.11.0-1.<epoch>`, which no release can produce.

⚠️ **`-L` reaches the LIVE MEDIUM ONLY — the installed machine is unaffected.** The target's
packages are not taken from the image: `base.json`'s `custom_commands` run
`pacman -Sy nidara-desktop nidara-apps nidara-system` against `[nidara]` over the network, and
that repo is built from the tag in nidara-repo's `pins.env`. So a `-L` image installs **your**
installer and the **released** desktop. Measured 2026-09-04, by installing from one and finding
a dock bug that `main` had already fixed: the desktop was `v0.11.0` because the pin says so.
A change to `ui/shell/` therefore cannot be tested this way — cut a release, move the pin, or
update the machine after installing it. Same seam as #20 (offline install): what the medium
CARRIES versus what the installation DOWNLOADS.

⚠️ **The stamped `pkgrel` is load-bearing, in two directions.** It makes the local package win on
version rather than on repository order, and it keeps its filename out of a collision with the
published package in the shared pacman cache — `pacstrap` uses `/var/cache/pacman/pkg`, and a
cached copy with the same name and different bytes makes pacman abort the pacstrap with
`is corrupted (invalid or corrupted package (checksum))`, about a cache that is fine. Same family
as trap 8. `build.sh` compares every file the local package owns against the image anyway.

Or raw `mkarchiso`:

```bash
sudo mkarchiso -v -w /tmp/archiso-tmp -o /tmp/out profile
```

`build.sh` ensures the `[nidara]` signing key (`80B0AC8C36A43611A8619959B06B716279F755A9`) is imported and locally signed (`pacman-key --lsign-key`) on the build host keyring before running `mkarchiso`.

## Testing in QEMU / Live VM

To test the generated ISO in QEMU:

```bash
qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 4 -m 6G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=VARS.fd \
  -cdrom out/nidara-*.iso \
  -drive file=target.qcow2,if=virtio,format=qcow2 \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 \
  -display none -vga none -serial unix:serial.sock,server=on,wait=off
```

### SSH Access to the Live VM

When the test VM is running:
- **Port:** `2222`
- **SSH Key:** `~/.cache/nidara-vmtest-key/vmkey`
- **Connect:** `ssh -p 2222 -i ~/.cache/nidara-vmtest-key/vmkey root@localhost`
- **Important:** Do NOT terminate or kill the live test VM without user instruction.

## Known Traps & Invariants

1. **`nidara-release` and `/etc/os-release`:**
   ⚠️ The package no longer lives in this repository — it is in
   [nidara-repo](https://github.com/nidara-project/nidara-repo/tree/main/packages/nidara-release),
   because this repo is not tagged and a package fetched from a tag cannot be published by one.
   When installing `nidara-release`, pacman must use `--overwrite /etc/os-release`. Systemd tmpfiles creates a symlink before package installation, causing pacman to refuse overwriting unowned files without the flag.

2. **The two `pacman.conf` files are NOT interchangeable (since 2026-08-30):**
   `profile/pacman.conf` is the BUILD config — `mkarchiso` runs `pacman-conf` on it and `pacstrap`
   reads it, both on the build host — and it keeps a literal `Server =`. `profile/airootfs/etc/pacman.conf`
   is the LIVE system's, copied verbatim to the target by archinstall, and it uses
   `Include = /etc/pacman.d/nidara-mirrorlist` so `nidara-release` can correct the address later.
   They were byte-identical before that date. Do not "fix" the divergence.

3. **A missing `Include` target breaks pacman ENTIRELY, not just the repo:**
   `pacman-conf` exits 1 with "config file … could not be read" and every pacman invocation fails,
   `pacman-key` included. That is why `/etc/pacman.d/nidara-mirrorlist` is shipped in the airootfs,
   written to the target by the installer's FIRST `custom_command`, and only then adopted by
   `nidara-release` (the second `--overwrite` on that install line). `build.sh` checks the live
   config parses and that the three copies of the address agree.

4. **Three keyring errors at the END of every build are normal — do not chase them:**
   ```
   [mkarchiso] INFO: Creating a list of installed packages on live-enviroment...
   warning: Public keyring not found; have you run 'pacman-key --init'?
   error: nidara: key "80B0AC8C36A43611A8619959B06B716279F755A9" is unknown
   error: keyring is not writable
   ```
   `_make_pkglist` runs `pacman -Q --sysroot` **into the airootfs**, which has no keyring: the
   medium's `/etc/pacman.d/gnupg` is a **tmpfs mount created at boot** (`etc-pacman.d-gnupg.mount`
   + `pacman-init.service`), so at build time the directory does not exist at all. The sync dbs are
   still there at that point, `nidara.db.sig` among them, and `DatabaseOptional` means *verify the
   signature if it is present* — so pacman looks for our key in a keyring that is not there yet.
   Nothing is wrong and nothing is skipped: `pkglist.x86_64.txt` is written correctly, and the live
   session gets the key from `nidara-live-setup` after `pacman-init` has made the keyring.
   **The proof a package signature actually FAILED is the absence of an ISO** — `SigLevel = Required`
   aborts `pacstrap`, it does not warn and continue. Reproducible without root:
   `pacman -Q --config <conf with [nidara]> --dbpath <dir with nidara.db+.sig> --gpgdir <empty dir>`.

5. **`custom_repositories` must NOT be duplicated in `base.json`:**
   The live environment's `pacman.conf` already registers `[nidara]`. Adding it to `custom_repositories` in archinstall's JSON creates duplicate sections on the target system and breaks pacman invocations with database registration errors.

6. **`SUDO_USER` rewriting in `custom_commands`:**
   `base.json` contains `SUDO_USER=nidara nidara-setup`. The installer front-end must rewrite `SUDO_USER` to the user account created during installation so first-boot configuration targets the correct user.

7. **The HOOKS array is upstream's; the package list is ours — and they are COUPLED:**
   `profile/airootfs/etc/mkinitcpio.conf.d/archiso.conf` is a byte-for-byte copy of releng's,
   including the four `archiso_pxe_*` hooks. `packages.x86_64`, by contrast, is trimmed. A hook
   whose package was trimmed away fails at image build with `ERROR: file not found:
   '/usr/lib/initcpio/ipconfig'` (and friends), and mkinitcpio closes with *"errors were
   encountered during the build. The image may not be complete."* — buried in a wall of harmless
   `Possibly missing firmware for module:` warnings, which is why three images shipped that way.
   `mkinitcpio-nfs-utils`, `nbd` and `pv` exist in the list for exactly this reason. **Trimming a
   package a hook needs means curating the HOOKS array in the same change.**

8. **A `nidara-*` package can go stale in the HOST's pacman cache and read as corruption:**
   `pacstrap` shares `/var/cache/pacman/pkg` with the build host. Three of our five packages carry
   a flat-counter `pkgver` (`nidara-apps-1-1`, `nidara-system-1-1`, `nidara-release-2-1`) and
   nidara-repo's CI rebuilds every package on every run — so the same filename gets republished
   with different bytes, and a cached copy from a previous build fails the checksum:
   `File /var/cache/pacman/pkg/nidara-apps-1-1-any.pkg.tar.zst is corrupted (invalid or corrupted
   package (checksum))`. Nothing is corrupt. Delete the cached `nidara-*` copies and rebuild; it
   recurs after **any** push to nidara-repo, not just a version bump.

9. **`archinstall` is UNPINNED, and `--dry-run` alone cannot police it:**
   `packages.x86_64` names `archinstall` with no version, so every new image silently takes
   whatever was current that day. The live session cannot drift (squashfs, no `-Syu`) — the
   build is the whole risk window, and it grows as the installer hands archinstall more of the
   configuration (the disk layer is moving back to it, nidara-desktop#310).
   ⚠️ The trap is that archinstall reads its config with `args_config.get('<key>', default)`,
   one key at a time: **a key it no longer knows is skipped in silence, exit 0.** A release that
   renamed `custom_commands` would pass `--dry-run` and produce an installed machine with no
   Nidara on it. So `check-base-config.sh` runs the dry-run *and* reads back the configuration
   archinstall itself saves to `/var/log/archinstall/user_configuration.json`, which is where a
   dropped key becomes visible. It runs inside the built airootfs — the only place the exact
   pair exists — and `build.sh` moves a rejected image to `out/rejected/`.

10. **Re-running a build over an old work directory produces NOTHING, and says Done:**
   Every mkarchiso step is `_run_once` — it writes a marker into the work dir and is skipped
   when the marker exists. A second run with the same `-w` therefore does no pacstrap, no
   squashfs and no ISO, exits 0 after five lines of option validation, and leaves the PREVIOUS
   image in `out/` for the closing `ls -lh` to present as the result. Measured 2026-09-04: a
   build whose log was five lines long, with markers three hours old.
   `build.sh` now removes such a work directory before starting (and says so). ⚠️ It was found
   only because `-L`'s byte comparison noticed the airootfs was stale — nothing else in the
   pipeline would have said a word.

11. **What NOT to touch without explicit user alignment:**
   - The repository signing key fingerprint (`80B0AC8C36A43611A8619959B06B716279F755A9`).
   - The boot UUID scheme or volume label.
   - Default application choices or product packages (refer to `PRODUCT.md`).
