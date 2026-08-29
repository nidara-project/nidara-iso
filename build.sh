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
    # `--init` first, and not only for the sake of a bare machine: the
    # archlinux:latest container arrives with a POPULATED keyring but no local
    # signing key, so `--lsign-key` dies there with "no secret key available to
    # sign with" — after the import has already succeeded, which is what makes
    # it read like a bad key rather than a missing one. Idempotent: on a machine
    # that has the key it does nothing.
    pacman-key --init
    pacman-key --add "$PROFILE/nidara-repo.gpg"
    pacman-key --lsign-key "$KEY_FPR"
fi

# ── the packages WE publish are the only ones that can be missing on purpose ──
#
# Everything else in packages.x86_64 comes from Arch, where a missing name means
# a typo. Ours come from [nidara], which serves whatever release nidara-repo's
# `pins.env` points at — so a package can be perfectly correct here, exist in
# nidara-desktop's tree, and still not be there, because the pinned tag predates
# it. That is not hypothetical: `nidara-installer` was added to the desktop's
# PKGBUILD (as a split package) the day AFTER the release that is pinned, so for
# five days the repo served three packages and this file named a fourth.
#
# mkarchiso does report it — as `error: target not found: nidara-installer`,
# after setup, which reads exactly like a misspelling and sends you to the wrong
# repository to look. This says which one it is, and what to do.
#
# Derived, not a fourth list: every package this project publishes is called
# `nidara*`, so the check reads the profile's own files and needs no list of its
# own to fall out of date.
NIDARA_SERVER="$(sed -n '/^\[nidara\]/,/^\[/p' "$PROFILE/pacman.conf" \
                 | sed -n 's/^Server *= *//p' | head -1)"
NIDARA_SERVER="${NIDARA_SERVER//\$arch/x86_64}"
WANT="$(grep -E '^nidara' "$PROFILE/packages.x86_64" || true)"

if [ -n "$WANT" ] && [ -n "$NIDARA_SERVER" ]; then
    echo "==> Checking [nidara] serves what this profile asks for..."
    db="$(mktemp)"
    if curl -sfL "$NIDARA_SERVER/nidara.db" -o "$db"; then
        # The db is a tarball of <pkgname>-<pkgver>-<pkgrel>/ directories.
        have="$(tar -tzf "$db" 2>/dev/null | sed 's|/.*||' | sort -u)"
        missing=""
        for pkg in $WANT; do
            printf '%s\n' "$have" | grep -qE "^${pkg}-[^-]+-[^-]+$" || missing="$missing $pkg"
        done
        rm -f "$db"
        if [ -n "$missing" ]; then
            echo >&2
            echo "  [ERR] [nidara] does not serve:$missing" >&2
            echo "        $NIDARA_SERVER" >&2
            echo "        It currently serves:" >&2
            printf '%s\n' "$have" | sed 's/^/          /' >&2
            echo >&2
            echo "        This is a PIN, not a typo. nidara-repo builds from the release" >&2
            echo "        its pins.env names, so the fix is upstream and in this order:" >&2
            echo "          1. tag nidara-desktop with the package in its PKGBUILD" >&2
            echo "          2. point nidara-repo's pins.env at that tag and let CI publish" >&2
            echo "          3. build this image" >&2
            exit 1
        fi
        echo "    ok: ${WANT//$'\n'/ }"
    else
        # A network hiccup must not fail a build that pacman's cache could serve.
        echo "    [WARN] could not read $NIDARA_SERVER/nidara.db — skipping the check." >&2
    fi
fi

mkdir -p "$OUT"
echo "==> mkarchiso: $PROFILE -> $OUT"
mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"

echo
echo "==> Done:"
ls -lh "$OUT"
