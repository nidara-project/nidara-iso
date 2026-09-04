#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# check-base-config.sh — does the archinstall going into the image still accept
# the product configuration we hand it?
#
#     sudo ./check-base-config.sh [AIROOTFS_DIR]
#
# Run by `build.sh` after `mkarchiso`; runnable by hand against any airootfs.
#
# ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
# `profile/packages.x86_64` asks for `archinstall` with no version, and nothing
# validated what arrived. The live session cannot make it drift — squashfs, no
# `-Syu` — so the risk is not a running medium: it is BUILDING A NEW IMAGE,
# which silently takes whatever archinstall was current that day. And the
# exposure grows as the installer hands over more of the configuration (the disk
# layer is moving back to archinstall — nidara-desktop#310), so the pair has to
# be checked at the one moment both halves are in the same room.
#
# ─── WHY IT IS TWO CHECKS AND NOT ONE ────────────────────────────────────────
# `archinstall --dry-run` is the obvious gate: it parses the configuration and
# returns before touching a disk (`scripts/guided.py`, the `if
# args.dry_run: return` that sits above `perform_filesystem_operations`). It is
# necessary and it is NOT sufficient, and the reason is worth spelling out
# because it is invisible from the outside:
#
#   archinstall reads its configuration with `args_config.get('<key>', default)`
#   — every key, one at a time (`lib/args.py`, `ArchConfig.from_config`). A key
#   it no longer knows is not an error. It is SKIPPED, in silence, exit 0.
#
# So a release that renames `custom_commands` passes `--dry-run` on our config
# and produces a machine with no Nidara on it: the five commands that write the
# repository address, trust its key, install the desktop and run `nidara-setup`
# would simply never run, and the first thing anybody would learn about it is a
# stock Arch console on a finished install.
#
# What catches that is reading back what archinstall SAID, which it writes out
# by itself: `--dry-run` saves the configuration as it understood it to
# /var/log/archinstall/user_configuration.json. A key we sent that is missing
# from that file is a key this archinstall does not read any more. Same idea as
# build.sh reading its own mkarchiso log back: the wall is where a defect hides.
#
# ─── WHY IT RUNS INSIDE THE BUILT AIROOTFS ───────────────────────────────────
# Because that is the only place the exact pair exists. The build host's own
# archinstall (if it has one at all — most do not) is a different version, and
# resolving "what version WOULD pacman install" answers a number without
# answering the question. `mkarchiso` leaves the pacstrapped root behind unless
# it is given `-r`, and build.sh does not give it one, so the airootfs is right
# there with the archinstall that will ship and the base.json that will ship, at
# the path it will ship at. Costs no download and no second install.
#
# The image is already assembled by then — the squashfs was made before the ISO
# was — so nothing this does to the airootfs can reach it. build.sh quarantines
# the produced image if this fails.
#
# Requires: root, arch-chroot (arch-install-scripts, which archiso depends on),
# python (Arch has one).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIROOTFS="${1:-$REPO_DIR/work/x86_64/airootfs}"
BASE_JSON=/usr/share/nidara-installer/base.json
SAVED=/var/log/archinstall/user_configuration.json

fail() {
    echo >&2
    printf '  [ERR] %s\n' "$1" >&2
    shift
    for line in "$@"; do printf '        %s\n' "$line" >&2; done
    echo >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail "check-base-config.sh must run as root (arch-chroot mounts /proc, /sys and /dev)."
command -v arch-chroot >/dev/null || fail "arch-chroot is not installed: pacman -S arch-install-scripts"

# ⚠️ A missing airootfs is a FAILURE, not a skip. A gate that quietly stands
# aside when it cannot find its subject is worse than no gate: it reports a pass.
[ -d "$AIROOTFS" ] || fail \
    "no airootfs at $AIROOTFS" \
    "" \
    "This runs on the pacstrapped root mkarchiso leaves in the work directory." \
    "If the build was given -r, or the work directory was cleaned, there is" \
    "nothing here to check — rebuild, or point this at an airootfs by hand."
[ -x "$AIROOTFS/usr/bin/archinstall" ] || fail \
    "the image at $AIROOTFS has no archinstall" \
    "" \
    "profile/packages.x86_64 must list it: it is what the installer hands the" \
    "plan to, and without it nidara-installer can collect answers and do nothing."
[ -f "$AIROOTFS$BASE_JSON" ] || fail \
    "the image at $AIROOTFS has no $BASE_JSON" \
    "" \
    "That file is the product half of the configuration and it is airootfs" \
    "content: profile/airootfs$BASE_JSON."

echo "==> Checking that the image's archinstall accepts $BASE_JSON"

# ── 1. does it parse? ────────────────────────────────────────────────────────
#
# `--offline` is not politeness, it is what keeps the answer about the CONFIG.
# Without it `main()` runs a connectivity probe, fetches the package database and
# checks for a newer archinstall before it ever looks at the file — so a build
# host behind a proxy would fail this gate for a reason that has nothing to do
# with the pair being tested.
#
# `--silent` because there is nobody at this terminal to answer a TUI prompt, and
# `--dry-run` because the point is to stop at the line above the disk.
rm -rf -- "${AIROOTFS:?}/var/log/archinstall"
set +e
out="$(arch-chroot "$AIROOTFS" archinstall \
        --config "$BASE_JSON" --silent --dry-run --offline 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
    printf '%s\n' "$out" | sed 's/^/      /' >&2
    fail "the archinstall in this image REJECTED $BASE_JSON (exit $status)." \
         "" \
         "Its own message is above. The pair is incompatible: fix base.json to" \
         "match the archinstall being shipped, or pin the package in" \
         "profile/packages.x86_64 to a version that accepts it."
fi

# ── 2. did it read all of it? ────────────────────────────────────────────────
[ -f "$AIROOTFS$SAVED" ] || fail \
    "archinstall accepted the config but wrote no $SAVED." \
    "" \
    "That file is how this check reads back what it understood. Its absence" \
    "means the save path moved, and this gate can no longer see a silently" \
    "dropped key — which is the failure it exists for. Do not ignore it."

python - "$AIROOTFS$BASE_JSON" "$AIROOTFS$SAVED" <<'PY'
import json, sys

sent = json.load(open(sys.argv[1]))
read = json.load(open(sys.argv[2]))

# `silent` is a COMMAND-LINE flag. archinstall never reads it out of the file
# (nothing in from_config looks for it), so it can never come back — it has sat
# in base.json since the beginning doing nothing, and the installer passes
# --silent on the command line, which is what actually silences it.
IGNORED = {"silent"}

# The keys archinstall copies through untouched (`plain_cfg`, plus `script`), so
# their value can be compared and not merely their presence. The rest are parsed
# into objects and serialised back by their own `json()`, which normalises: those
# are checked for presence, and `--dry-run` above is what checks their contents,
# because a value it does not recognise is the one thing it does refuse.
VERBATIM = {"script", "kernels", "ntp", "packages", "custom_commands"}

version = read.get("version")
problems = []

# archinstall overwrites `version` with its own before saving
# (ArchConfigHandler.__init__), so the round trip answers the version question
# too, from the same file and without a second way to be wrong.
declared = sent.get("version")
if declared != version:
    problems.append(
        f'version: this image ships archinstall {version}, and base.json '
        f'declares {declared}.\n'
        f'        The pair above was accepted, so nothing is broken — but the '
        f'declaration is what\n'
        f'        the installer shows and compares at startup, and it is now '
        f'a lie. Re-read the\n'
        f'        release notes, then set "version": "{version}" in BOTH copies '
        f'of base.json\n'
        f'        (profile/airootfs/usr/share/nidara-installer/, and '
        f'nidara-desktop\'s\n'
        f'        ui/installer/base.json, which is the development fallback).'
    )

for key, value in sent.items():
    if key in IGNORED or key == "version":
        continue
    if key not in read:
        problems.append(
            f'{key}: archinstall {version} does not read this key any more.\n'
            f'        It did NOT complain — it skipped it — so everything this '
            f'key asks for\n'
            f'        would silently not happen on a finished install.'
        )
    elif key in VERBATIM and read[key] != value:
        problems.append(
            f'{key}: went in as {json.dumps(value)}\n'
            f'        and came back as {json.dumps(read[key])}.'
        )

if problems:
    print(file=sys.stderr)
    print("  [ERR] this image's archinstall and its base.json do not agree:", file=sys.stderr)
    print(file=sys.stderr)
    for p in problems:
        print(f'      · {p}', file=sys.stderr)
    print(file=sys.stderr)
    sys.exit(1)

print(f"==> archinstall {version} read every key of base.json and accepted it.")
PY

rm -rf -- "${AIROOTFS:?}/var/log/archinstall"
