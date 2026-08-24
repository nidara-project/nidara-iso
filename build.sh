#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# build.sh — build the Nidara ISO.
#
#     sudo ./build.sh [-o OUTPUT_DIR] [-w WORK_DIR]
#
# Wraps `mkarchiso` with the one thing it cannot do for us: establishing trust
# in the [nidara] repo's signing key on the BUILD host. The profile registers
# that repo with `SigLevel = Required`, so pacstrap refuses to pull the desktop
# unless pacman's keyring here holds the key — locally signed, not merely
# imported (an imported-but-unsigned key is ignored, silently, and the failure
# reads as "signature from unknown trust").
#
# Requires: archiso (extra). Root, because mkarchiso mounts and loop-mounts.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="$REPO_DIR/profile"
OUT="$REPO_DIR/out"
WORK="$REPO_DIR/work"
KEY_FPR=80B0AC8C36A43611A8619959B06B716279F755A9

while getopts 'o:w:h' opt; do
    case "$opt" in
        o) OUT="$OPTARG" ;;
        w) WORK="$OPTARG" ;;
        h) sed -n '2,20p' "$0"; exit 0 ;;
        *) exit 1 ;;
    esac
done

[ "$(id -u)" -eq 0 ] || { echo "build.sh must run as root (mkarchiso mounts filesystems)." >&2; exit 1; }
command -v mkarchiso >/dev/null || { echo "archiso is not installed: pacman -S archiso" >&2; exit 1; }

if ! pacman-key --list-keys "$KEY_FPR" &>/dev/null; then
    echo "==> Trusting the nidara-repo signing key on this build host..."
    pacman-key --add "$PROFILE/nidara-repo.gpg"
    pacman-key --lsign-key "$KEY_FPR"
fi

mkdir -p "$OUT"
echo "==> mkarchiso: $PROFILE -> $OUT"
mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"

echo
echo "==> Done:"
ls -lh "$OUT"
