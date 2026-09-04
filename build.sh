#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# build.sh — build the Nidara ISO.
#
#     sudo ./build.sh [-o OUTPUT_DIR] [-w WORK_DIR] [-L LOCAL_PKG_DIR]
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
LOCAL_PKGS=""
KEY_FPR=80B0AC8C36A43611A8619959B06B716279F755A9

while getopts 'o:w:L:h' opt; do
    case "$opt" in
        o) OUT="$OPTARG" ;;
        w) WORK="$OPTARG" ;;
        L) LOCAL_PKGS="$(cd "$OPTARG" && pwd)" ;;
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


# ── an unreleased package can be put in front of the published one (-L) ──────
#
# The image installs `nidara-installer` (and the desktop) from [nidara], which
# nidara-repo builds from the tag in its `pins.env`. That is right for a real
# image and wrong for testing: an unreleased change to the installer cannot reach
# a medium at all without cutting a release first, which is a preposterous price
# for a change that is being tested precisely because nobody wants to release it
# yet. It is why installer changes had been tested by copying a bundle into a
# running live session by hand — faithful to the code, not to the artifact.
#
# `-L <dir>` puts locally built packages in a repository of their own, listed
# BEFORE every other repository, and hands mkarchiso a pacman.conf that has it.
#
# ⚠️ THIS PRODUCES A TEST IMAGE. It is unsigned (`SigLevel = Optional TrustAll`,
# because a locally built package is not signed by the release key), it contains
# code that is in nobody's git history, and it must not be published. The banner
# below says so and the summary at the end repeats it.
#
# ⚠️ The local package usually carries the SAME name and SAME version as the
# published one — an unreleased tree still says `pkgver=<last release>` — so
# nothing about the version distinguishes them, and only repository ORDER decides
# which lands. Order is not evidence, so it is not trusted: after the build the
# bytes are compared (below), and a mismatch fails.
PACMAN_CONF="$PROFILE/pacman.conf"
LOCAL_REPO=""
if [ -n "$LOCAL_PKGS" ]; then
    shopt -s nullglob
    local_pkg_files=("$LOCAL_PKGS"/*.pkg.tar.*)
    shopt -u nullglob
    [ "${#local_pkg_files[@]}" -gt 0 ] || {
        echo "  [ERR] -L $LOCAL_PKGS holds no *.pkg.tar.* files" >&2; exit 1; }

    LOCAL_REPO="$WORK/local-repo"
    rm -rf "$LOCAL_REPO"; mkdir -p "$LOCAL_REPO"
    cp -- "${local_pkg_files[@]}" "$LOCAL_REPO/"
    repo-add "$LOCAL_REPO/nidara-local.db.tar.gz" "$LOCAL_REPO"/*.pkg.tar.* >/dev/null

    # Inserted immediately BEFORE the first repository section, so it wins any
    # name that also exists in core/extra or [nidara] — and after [options],
    # which pacman requires first. One insertion into the profile's own file
    # rather than a reconstruction of it: a rebuilt pacman.conf is a second copy
    # of the build's repository list, and the two would drift.
    PACMAN_CONF="$WORK/pacman.local.conf"
    awk -v repo="$LOCAL_REPO" '
        /^\[/ && $0 != "[options]" && !inserted {
            print "[nidara-local]"
            print "SigLevel = Optional TrustAll"
            print "Server = file://" repo
            print ""
            inserted = 1
        }
        { print }
        END { if (!inserted) { print "pacman.conf has no repository section" > "/dev/stderr"; exit 1 } }
    ' "$PROFILE/pacman.conf" > "$PACMAN_CONF"

    echo
    echo "  ############################################################"
    echo "  #  TEST IMAGE — built with unsigned local packages:"
    for f in "${local_pkg_files[@]}"; do echo "  #    $(basename -- "$f")"; done
    echo "  #  Do not publish it and do not hand it to anybody."
    echo "  ############################################################"
    echo
fi

# ── the build keeps a copy of what it said ───────────────────────────────────
#
# mkarchiso writes to stdout and nowhere else, so until now the only record of a
# twelve-minute build was the terminal it ran in — gone with the scrollback, and
# unreadable by anyone not sitting at it. That is not a convenience: on
# 2026-09-02 three real `ERROR:` lines from mkinitcpio rode inside a wall of
# ~15 harmless `Possibly missing firmware for module:` warnings and survived
# THREE images, because nobody could re-read the wall afterwards.
mkdir -p "$OUT" "$REPO_DIR/logs"
LOG="$REPO_DIR/logs/build-$(date +%Y%m%d-%H%M%S).log"
echo "==> mkarchiso: $PROFILE -> $OUT"
echo "==> log: $LOG"
# Which images this run produced, and not "the newest one in out/": the output
# directory keeps previous builds, and the one thing the gate below must never
# do is quarantine an image it did not make.
STAMP="$(mktemp)"
#
# ⚠️ And the status is CAUGHT, not left to `set -e`. The read-back below is most
# needed on a build that FAILED, and `set -e` would kill the script before it
# ran — which is exactly what happened on the two failed builds of 2026-09-02.
set +e
mkarchiso -v -C "$PACMAN_CONF" -w "$WORK" -o "$OUT" "$PROFILE" 2>&1 | tee "$LOG"
mkarchiso_status=${PIPESTATUS[0]}
set -e

# The log belongs to whoever ran sudo, not to root — it is theirs to read, grep
# and delete without another sudo.
#
# ⚠️ The trailing colon is load-bearing. `chown user file` sets the OWNER and
# leaves the GROUP alone, so under sudo the file comes out `angel:root` — right
# owner, root group, write access unaffected, and therefore invisible until
# something reads the group. `user:` means "and that user's login group". This
# is the same defect nidara-desktop #376 fixed in nidara-setup, reproduced here
# within the week; it is worth the four lines because nothing warns you.
[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER:" "$LOG" "$REPO_DIR/logs" 2>/dev/null

# ── and then it reads it back, because the wall is where a defect hides ───────
#
# Two classes, and the whole point is that they look alike in the scrollback:
#
#   NOISE   `==> WARNING: Possibly missing firmware for module: …` — mkinitcpio,
#           on every Arch machine that regenerates an initramfs. Counted, not
#           printed.
#   NOISE   the three keyring errors of the final `pacman -Q --sysroot` step,
#           which are the design (see README / CLAUDE.md trap 4).
#   SIGNAL  everything else that says ERROR — a hook that could not find its
#           files, an initramfs closing with "the image may not be complete".
echo
fw=$(grep -c 'Possibly missing firmware for module' "$LOG" || true)
signal="$(grep -nE '==> ERROR|errors were encountered during the build|^error:' "$LOG" \
          | grep -vE 'key "[0-9A-F]{40}" is unknown|keyring is not writable' || true)"
echo "==> Read back from the log: $fw firmware warnings (harmless, expected)."
if [ -n "$signal" ]; then
    echo
    echo "  ⚠️  and these, which are NOT:"
    echo
    printf '%s\n' "$signal" | sed 's/^/      /'
    echo
    echo "      An ISO may still have been produced — mkinitcpio reports and continues."
    echo "      Do not test an image whose initramfs said it may be incomplete."
else
    echo "==> Nothing else said ERROR."
fi

if [ "$mkarchiso_status" -ne 0 ]; then
    echo
    echo "==> mkarchiso failed (exit $mkarchiso_status). The log above is kept at:"
    echo "    $LOG"
    rm -f "$STAMP"
    exit "$mkarchiso_status"
fi

# ── and the image is not handed over until archinstall accepts its own half ───
#
# `packages.x86_64` names `archinstall` with no version, so building a new image
# silently takes whatever was current that day — and the installer hands it the
# whole product configuration. `check-base-config.sh` runs the archinstall that
# is IN this image against the base.json that is in it; see its header for why
# --dry-run alone is not enough to trust the answer.
#
# ⚠️ It runs after the build because that is when the pair exists in one place.
# The ISO is therefore already written when the answer arrives, which is exactly
# why a failure MOVES it: an image whose installer would skip half of what it was
# told cannot be left sitting in out/ next to good ones, one `dd` away from a
# machine. Nothing is deleted — it goes to out/rejected/, and the path is printed.
# ── and, with -L, the local package is proved to be the one that LANDED ──────
#
# Repository order is a request, not a receipt. The local package and the
# published one share a name and a version, so if the order were ever wrong — a
# section inserted in the wrong place, a repo cached from a previous run — the
# build would succeed and produce an image of the RELEASED installer while
# everything on screen said otherwise. That is the failure this whole flag exists
# to avoid, so it is checked rather than assumed: every file the local package
# owns is compared, byte for byte, against the file of that name in the image.
if [ -n "$LOCAL_PKGS" ]; then
    echo
    echo "==> Proving the local packages are the ones in the image"
    _airootfs="$WORK/x86_64/airootfs"
    _tmpx="$(mktemp -d)"
    _mismatch=0
    for _pkg in "$LOCAL_REPO"/*.pkg.tar.*; do
        rm -rf "${_tmpx:?}"/..?* "${_tmpx:?}"/.[!.]* "${_tmpx:?}"/* 2>/dev/null || true
        bsdtar -C "$_tmpx" -xf "$_pkg"
        while IFS= read -r -d '' _f; do
            _rel="${_f#"$_tmpx"/}"
            case "$_rel" in .PKGINFO|.BUILDINFO|.MTREE|.INSTALL) continue ;; esac
            if ! cmp -s "$_f" "$_airootfs/$_rel"; then
                echo "  [ERR] /$_rel in the image is NOT the copy from $(basename -- "$_pkg")" >&2
                _mismatch=1
            fi
        done < <(find "$_tmpx" -type f -print0)
        echo "    $(basename -- "$_pkg")"
    done
    rm -rf "$_tmpx"
    if [ "$_mismatch" -ne 0 ]; then
        echo >&2
        echo "  The published package won the resolution and the local one did not land." >&2
        echo "  The image is NOT what -L asked for; do not test against it." >&2
        rm -f "$STAMP"
        exit 1
    fi
fi

echo
if ! "$REPO_DIR/check-base-config.sh" "$WORK/x86_64/airootfs"; then
    mapfile -t produced < <(find "$OUT" -maxdepth 1 -type f -name '*.iso' -newer "$STAMP")
    if [ "${#produced[@]}" -gt 0 ]; then
        mkdir -p "$OUT/rejected"
        mv -- "${produced[@]}" "$OUT/rejected/"
        [ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER:" "$OUT/rejected" 2>/dev/null
        echo >&2
        echo "  The image this build produced was moved out of the way:" >&2
        for iso in "${produced[@]}"; do
            printf '      %s\n' "$OUT/rejected/$(basename -- "$iso")" >&2
        done
        echo >&2
        echo "  It boots and it installs. What it installs is not what base.json says." >&2
    fi
    rm -f "$STAMP"
    exit 1
fi
rm -f "$STAMP"

echo
echo "==> Done:"
ls -lh "$OUT"
if [ -n "$LOCAL_PKGS" ]; then
    echo
    echo "  ⚠️  TEST IMAGE: built with unsigned local packages from $LOCAL_PKGS."
    echo "      Do not publish it. A real image is a plain \`sudo ./build.sh\`."
fi
