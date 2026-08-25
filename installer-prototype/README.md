# Installer prototype — archinstall, unattended

An experiment, not a component. It answers one question with evidence instead of
argument: **can `archinstall` install Nidara from a JSON file, unattended?** If it
can, the open decision — Calamares configured, or a GTK front-end of our own
driving `archinstall` as a library — stops being theory, because the hard part of
an installer is not the interface, it is the partitioning, the pacstrap and the
bootloader, and that half is Arch's code either way.

`archinstall` ships on the ISO, so this runs inside the live session with nothing
else installed.

## State: it installs, and what it installs boots

Run against a real disk on 2026-08-24: the live medium booted in QEMU (UEFI, blank
20 GiB `/dev/vda`), `archinstall 4.4`, `--silent`, no interaction. Result:

- the install finishes and the target carries **`nidara 0.8.1-1` + `nidara-apps`**,
  a `nidara` user, `nidara.desktop` in `wayland-sessions`, and greetd as
  `display-manager.service`;

⚠️ **The run predates `nidara-release`** (added 2026-08-25), so the system it produced still
said "Arch Linux". The config now installs it as its own step, with
`--overwrite /etc/os-release` — the flag is required, not defensive: by the time
`custom_commands` run, systemd's tmpfiles has already put a symlink at that path and pacman
refuses to write over an unowned file. That step is **not covered by the evidence above** and
is the first thing the next real-disk run should check (`cat /etc/os-release` on the target,
and About's header on the booted machine).
- **the disk boots on its own** — systemd-boot → kernel → `graphical.target` →
  `greetd` active → the greeter's layer surface **mapped and drawn**: `hyprctl
  layers` shows `namespace: nidara-greeter`, 1280x800, `a: 1`, on the overlay
  layer, over `awww-daemon`'s wallpaper on the background layer.

Two caveats about the evidence, both worth more than they look:

- the medium used was the image built at 19:28 that day, which **predates three
  profile commits** (`/etc/localtime` among them — without it the live boot stops
  at `systemd-firstboot` asking for a timezone, which is exactly what that commit
  fixed and what this run watched happen). The corrected image has not been
  rebuilt and retested.
- the greeter was verified as **running and mapped, not looked at**. With
  `virtio-gpu-gl` + `egl-headless`, QMP `screendump` returns a blank framebuffer
  and `grim` hangs waiting for a frame. Whether it looks right is still an open
  question that needs a screen.

### Findings

**1. The schema drifts, and the project's own example is stale.** The sample
config in the archinstall repo declares `"version": "2.8.6"` and a graphics
driver value — `All open-source (default)` — that 4.4 rejects outright. That one
was loud, which is the good case. **Pin the archinstall version.**

**2. A disk that does not exist is not an error — and it hides everything
downstream of it.** Handed a config naming `/dev/vda` on a machine with no such
device, archinstall exits **0** and resolves the layout to
`"device_modifications": []`. The mechanism is one line in
`DiskLayoutConfiguration.parse_arg`: device not found → `continue`. So the
partitions are never even parsed.

That is worse than a silent wrong install, because it also **manufactures a green
result**. The `disk_config` this prototype was carrying — the one an earlier dry
run had "validated" — turned out to crash the parser the moment a real disk was
in front of it (`"sector_size": null` → `TypeError`, and a missing `dev_path` key
→ `KeyError`). An empty layout parses trivially. The passing dry run was not a
weak test; it was the absence of one. **A dry run on a machine without the target
disk proves nothing at all**, and `gen-disk.py` refuses a device it cannot find
for exactly this reason (`gen-disk.py /dev/vdZ` → exit 1, message, no output).

**3. The disk half is generated, not written.** 4.4 wants a `sector_size` object
inside every size, a `dev_path` key that must be present even when it is null,
and it emits sizes as absolute byte counts of the disk it just measured
(`20398997504 B`, not `100%`). None of that survives being hand-authored and
committed. `gen-disk.py` calls the same library the installer will consume —
`suggest_single_disk_layout`, with the filesystem and the separate-`/home`
question answered so it stays non-interactive — and prints the merged config.

That is not a workaround; **it is the architecture of the GTK front-end in
miniature**: collect the answers, let archinstall compute the layout, hand
archinstall the JSON.

**4. `custom_repositories` was not merely unnecessary here — it was harmful.**
The medium already declares `[nidara]` in its own `pacman.conf`. archinstall
appends its custom repositories to the **live** `pacman.conf`, and the target's
`pacman.conf` is a **copy of the live one**, to which it appends them again.
Three `[nidara]` sections, two different `SigLevel`s, and
`error: could not register 'nidara' database (database already registered)` on
**every pacman invocation on the installed system, forever** — not just during
the install.

Removed and re-run end to end: **1 section, 0 errors, and `nidara` still
installs** — which is also the proof that the target inherits the repo from the
copied live config. What survives of the trust-model decision below is the half
that was actually forced.

**5. The boot menu of the installed system says "Arch Linux (linux)".**
archinstall writes its own loader entry. Cosmetic, and a `custom_command` away —
but it is the first thing a user sees after installing, so it should not be
discovered late.

### What the trust model still forces

`nidara` and `nidara-apps` cannot go in the `packages` list: `[nidara]` is
registered with `SigLevel = Required`, and installing from it needs the signing
key trusted in the *target* keyring — but `add_additional_packages` runs before
anything can import a key there. So the three real steps — trust the key, install
the two packages, run `nidara-setup` — stay in `custom_commands`, which run last,
as root, inside `arch-chroot`. That is the same three steps `install.sh` performs.

What is **no longer** part of that decision is declaring the repo (finding 4).

## Running it

Credentials are deliberately **not** committed. Generate a throwaway pair:

```bash
H=$(openssl passwd -6 nidara)
cat > nidara-creds.json <<JSON
{ "users": [ { "username": "nidara", "sudo": true, "enc_password": "$H" } ],
  "root_enc_password": "$H" }
JSON
```

`nidara.json` is the machine-independent half — it has no `disk_config` on
purpose. Inside the live session, on the machine being installed:

```bash
lsblk                                        # nothing else will tell you the name
python3 gen-disk.py /dev/vda nidara.json > merged.json
archinstall --config merged.json --creds nidara-creds.json --silent --dry-run
archinstall --config merged.json --creds nidara-creds.json --silent
```

### Driving the medium from the host, without typing into a VM window

The live medium ships `sshd` installed but not enabled, and `root` has an **empty
password**, so a serial console is the way in. Boot the ISO's kernel directly and
give it a serial port:

```bash
qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 4 -m 6G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=VARS.fd \
  -kernel vmlinuz-linux -initrd initramfs-linux.img \
  -append "archisobasedir=arch archisosearchuuid=<ISO UUID> console=tty0 console=ttyS0,115200" \
  -cdrom nidara-*.iso \
  -drive file=target.qcow2,if=virtio,format=qcow2 \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 \
  -display none -vga none -serial unix:serial.sock,server=on,wait=off
```

`vmlinuz-linux`/`initramfs-linux.img` come straight out of the image (`bsdtar -xf
nidara-*.iso arch/boot/x86_64/…`) and the UUID is the ISO's volume modification
date as `YYYY-MM-DD-HH-MM-SS-00`. Direct kernel boot is what makes the serial
console unconditional; the image's own verbose entry does the same, but choosing
it needs a keypress at the boot menu.

Then, on the serial console: log in as `root`, drop an SSH key into
`/root/.ssh/authorized_keys`, `systemctl start sshd`, and drive the rest over
`ssh -p 2222`. Everything above was run that way.

## What this still does not answer

- **The interface.** This is a JSON file, not an installer. It did, however,
  settle the decision it was built to inform: **`../INSTALLER.md`, 2026-08-25 —
  a GTK4 front-end of our own, not Calamares**, with this prototype's shape as
  its architecture and this prototype itself as the engine's test harness from
  here on.
- **How any of it looks.** See the second caveat above.
- Anything but this shape of machine: UEFI, one disk, no encryption, zram swap.
