#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# Nidara live/install medium — archiso profile.
#
# This is a plain archiso profile, deliberately close to upstream's `releng`:
# what differs from it is listed in the repo README, and every divergence is
# commented where it lives. The image installs a genuine Arch system — the
# packages come from Arch's own mirrors, `nidara` is the single package that
# does not (see pacman.conf).

iso_name="nidara"
iso_label="NIDARA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Nidara Project <https://github.com/nidara-project>"
iso_application="Nidara live/install medium"
# The PRODUCT's version, from the one file that declares it — so the download is
# `nidara-0.1.0-x86_64.iso` and the system it installs says the same number back
# (`/etc/os-release`, shipped by `packages/nidara-release`). It used to be the
# build date, which named the build rather than the product and could not be
# said out loud: "Nidara 2026.08.25" is not a version anybody declared.
#
# `${BASH_SOURCE[0]}` because mkarchiso sources this file from wherever it was
# invoked; the profile dir is not the cwd.
iso_version="$(tr -d '[:space:]' < "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../VERSION")"

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
