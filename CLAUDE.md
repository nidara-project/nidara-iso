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

## How to Build

Building the ISO requires `archiso` (from Arch `extra`) and `root` privileges (for mounting and loop-mounting filesystems):

```bash
sudo ./build.sh [-o OUTPUT_DIR] [-w WORK_DIR]
```

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

4. **`custom_repositories` must NOT be duplicated in `base.json`:**
   The live environment's `pacman.conf` already registers `[nidara]`. Adding it to `custom_repositories` in archinstall's JSON creates duplicate sections on the target system and breaks pacman invocations with database registration errors.

5. **`SUDO_USER` rewriting in `custom_commands`:**
   `base.json` contains `SUDO_USER=nidara nidara-setup`. The installer front-end must rewrite `SUDO_USER` to the user account created during installation so first-boot configuration targets the correct user.

6. **What NOT to touch without explicit user alignment:**
   - The repository signing key fingerprint (`80B0AC8C36A43611A8619959B06B716279F755A9`).
   - The boot UUID scheme or volume label.
   - Default application choices or product packages (refer to `PRODUCT.md`).
