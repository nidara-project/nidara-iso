#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# Nidara live/install medium — archiso profile.
#
# This is a plain archiso profile, deliberately close to upstream's `releng`:
# what differs from it is listed in the repo README, and every divergence is
# commented where it lives. The image installs a genuine Arch system — the
# packages come from Arch's own mirrors, and the ones that do not are ours:
# `nidara-desktop`, `nidara-apps` and `nidara-installer` (see pacman.conf).

iso_name="nidara"
iso_label="NIDARA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Nidara Project <https://github.com/nidara-project>"
iso_application="Nidara live/install medium"
# The build DATE, which is what an image is: `nidara-2026.09.01-x86_64.iso`.
#
# This was the product's version for five days (`0.1.0`, read from a VERSION file
# at the root of this repo) and the version is gone — PRODUCT.md, "The machine is
# rolling, the image has a date". The short form of the argument: an image never
# changes after it is published, so a name that fixes it in time can stay true
# forever, while the MACHINE it installs converges on the newest of every layer
# within a day and is not a release of anything.
#
# ⚠️ Not "just the build date", which is what this was BEFORE 0.1.0 and what the
# objection to it was: a name that says which build it is, and nothing a person
# could quote. That objection was answered the other way round — by moving the
# announceable number onto the thing that genuinely is rewritten (the desktop's
# `nidara-desktop` semver), not by minting one for the image.
#
# SOURCE_DATE_EPOCH so the name matches `iso_label` above and a reproducible
# build gets a reproducible name; mkarchiso exports it.
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"

# `install_dir` stays "arch": it is the directory name inside the image that the
# archiso initramfs hook searches for, and the bootloader entries interpolate it
# as %INSTALL_DIR%. Renaming it is pure cosmetics on a path nobody reads, and it
# has to match in four places at once.
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd -19, not releng's xz: it decompresses several times faster (the live
# session reads the whole desktop off this image) at a size within a few percent.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')

file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/sudoers.d/10-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/usr/local/bin/nidara-live-setup"]="0:0:755"
)
