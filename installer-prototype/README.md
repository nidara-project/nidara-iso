# Installer prototype — archinstall, unattended

An experiment, not a component. It answers one question with evidence instead of
argument: **can `archinstall` install Nidara from a JSON file, unattended?** If it
can, the open decision — Calamares configured, or a GTK front-end of our own
driving `archinstall` as a library — stops being theory, because the hard part of
an installer is not the interface, it is the partitioning, the pacstrap and the
bootloader, and that half is Arch's code either way.

`archinstall` ships on the ISO, so this runs inside the live session with nothing
else installed.

## State: validated, not yet run against a disk

`nidara.json` parses and resolves under `archinstall --dry-run` in a live VM.
What is left is one real run against a real disk.

### Two findings so far, both worth keeping

**1. The schema drifts, and the project's own example is stale.** The sample
config in the archinstall repo declares `"version": "2.8.6"` and a graphics
driver value — `All open-source (default)` — that 4.4 rejects outright. That one
was loud, which is the good case. **Pin the archinstall version.**

**2. A disk that does not exist is not an error.** Handed a config naming
`/dev/vda` on a machine with no such device, archinstall exited **0** and
resolved the layout to `"device_modifications": []` — the partitions silently
dropped. The JSON is not validated against the machine, so a wrong device name
degrades quietly rather than failing. Anything built on this has to check that
itself.

### One design decision, forced by the trust model

`nidara` and `nidara-apps` are **not** in the `packages` list. They cannot be:
`[nidara]` is registered with `SigLevel = Required`, and installing from it needs
the signing key trusted in the *target* keyring — but `add_additional_packages`
runs before anything can import a key there. So the repo is declared in
`custom_repositories` (which does survive into the target's pacman.conf, verified
in the resolved config) and the three real steps — trust the key, install the two
packages, run `nidara-setup` — happen in `custom_commands`, which run last, as
root, inside `arch-chroot`.

That is a genuine limit of the declarative path, and it is the same three steps
`install.sh` performs.

## Running it

Credentials are deliberately **not** committed. Generate a throwaway pair:

```bash
H=$(openssl passwd -6 nidara)
cat > nidara-creds.json <<JSON
{ "users": [ { "username": "nidara", "sudo": true, "enc_password": "$H" } ],
  "root_enc_password": "$H" }
JSON
```

Boot the ISO in a VM **with a blank disk attached** (the live session used for the
dry run had none, which is what produced finding 2):

```bash
qemu-img create -f qcow2 ~/VMs/nidara-install-test.qcow2 30G
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd ~/VMs/nidara-install-vars.fd
# then the usual QEMU line, plus:
#   -drive file=$HOME/VMs/nidara-install-test.qcow2,if=virtio,format=qcow2
```

Inside the live session:

```bash
archinstall --config nidara.json --creds nidara-creds.json --silent --dry-run  # first
archinstall --config nidara.json --creds nidara-creds.json --silent            # then
```

Check `lsblk` first and make the `device` in `nidara.json` match — nothing else
will tell you.
