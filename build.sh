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

# ── the repository's address is written in three places and they must agree ───
#
# It used to be written twice, in two files that were byte-identical, so nobody
# could get it wrong. Since the address moved into a package-owned mirrorlist
# (so it can be CORRECTED on machines that already exist) the three copies have
# three different jobs and three different shapes, and none of them can be
# derived from the others:
#
#   pacman.conf                  a literal Server =, because the BUILD HOST
#                                resolves it and has no Nidara file
#   airootfs/etc/pacman.d/…      what the LIVE system reads through its Include
#   base.json, command 1         what the INSTALLER writes on the target before
#                                its first pacman call
#
# A disagreement is silent in the worst way: the build works, the live session
# works, and the installed machine points at a repository that is not there.
# (A fourth copy lives in nidara-repo's nidara-release PKGBUILD. That one is
# deliberately NOT checked here — it is the address that WINS, by design, since
# the whole point is that a package can move it.)
ADDR_MIRRORLIST="$(sed -n 's/^Server *= *//p' \
                   "$PROFILE/airootfs/etc/pacman.d/nidara-mirrorlist" | head -1)"
ADDR_INSTALLER="$(grep -o "Server = https://[^']*" \
                  "$PROFILE/airootfs/usr/share/nidara-installer/base.json" \
                  | sed 's/^Server = //' | head -1)"
ADDR_BUILD="$(sed -n '/^\[nidara\]/,/^\[/p' "$PROFILE/pacman.conf" \
              | sed -n 's/^Server *= *//p' | head -1)"

if [ "$ADDR_MIRRORLIST" != "$ADDR_BUILD" ] || [ "$ADDR_INSTALLER" != "$ADDR_BUILD" ]; then
    echo >&2
    echo "  [ERR] the [nidara] address disagrees between the three places that carry it:" >&2
    echo "        profile/pacman.conf                       $ADDR_BUILD" >&2
    echo "        airootfs/etc/pacman.d/nidara-mirrorlist   $ADDR_MIRRORLIST" >&2
    echo "        base.json (the installer's first command) $ADDR_INSTALLER" >&2
    echo >&2
    echo "        All three must be the same string, \$arch included." >&2
    exit 1
fi

# The live medium's config must PARSE. An Include naming a file that is not
# there is not a missing repo — it is a hard error on every pacman invocation,
# `pacman-key` included, which is how the target trusts this repo's key. A live
# session where nothing involving pacman works at all is worth four lines here.
#
# ⚠️ The Include is an ABSOLUTE path, and `pacman-conf` resolves it against the
# root it is running on — THIS HOST, which has no /etc/pacman.d/nidara-mirrorlist
# and is not supposed to. Checking the file as-is would fail on every build host
# in the world. So the check rewrites the Include to point at the copy the medium
# actually ships, which is the file the live system will read at that path.
_livecheck="$(mktemp)"
sed "s|^Include *= */etc/pacman.d/nidara-mirrorlist|Include = $PROFILE/airootfs/etc/pacman.d/nidara-mirrorlist|" \
    "$PROFILE/airootfs/etc/pacman.conf" > "$_livecheck"
if ! pacman-conf --config "$_livecheck" --repo nidara >/dev/null 2>&1; then
    echo >&2
    echo "  [ERR] the LIVE pacman.conf does not parse, or has no [nidara]:" >&2
    echo "        $PROFILE/airootfs/etc/pacman.conf" >&2
    echo >&2
    pacman-conf --config "$_livecheck" --repo nidara >/dev/null || true
    rm -f "$_livecheck"
    exit 1
fi
rm -f "$_livecheck"


mkdir -p "$OUT"
echo "==> mkarchiso: $PROFILE -> $OUT"
mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"

echo
echo "==> Done:"
ls -lh "$OUT"
