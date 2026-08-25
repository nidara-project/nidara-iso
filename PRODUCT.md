# Nidara — what the product is, and what each piece is called

This file exists because the question "is this a distro or a desktop?" kept coming back,
and every time it did, the answer was reconstructed from scratch and came out slightly
different. It is a decision record, not documentation of code: the mechanics live in the
README next door and in `nidara-desktop`'s skill.

## One name

To a person who wants to try it, the product is **Nidara**. That is the whole sentence.
Not "Arch with the Nidara desktop", not "the Nidara distro that ships nidara-desktop" —
a person coming from Windows is owed a name and a download, not a lineage.

The lineage is not hidden; it is simply not the pitch. `ID_LIKE="arch"` says it in the
field that exists for saying it, the README says it in prose, and anyone who asks gets a
straight answer. **Rebrand, don't appropriate** — the rule has not changed.

**"Nidara Desktop" is the name of a COMPONENT, and it is only used where components are
being discussed**: this repo's sibling `nidara-desktop`, the `nidara` package, a row in
About, a bug report. It never appears in a sentence aimed at someone deciding whether to
install anything.

| Piece | Repo | Package | What it is |
|---|---|---|---|
| **Nidara** | `nidara-iso` | — | The product: a live image that installs a system |
| **Nidara Desktop** | `nidara-desktop` | `nidara` | The desktop environment: shell, greeter, lock |
| Nidara repo | `nidara-repo` | — | The pacman repository both consume |
| Curated apps | `nidara-repo` | `nidara-apps` | The applications the product ships with |
| Identity | `nidara-iso` | `nidara-release` | `/etc/os-release`: the product's name and version (exists since 2026-08-25) |

## Two version numbers, and neither derives from the other

**Nidara** and **Nidara Desktop** are versioned independently, both semver, and the
product's number is **declared, not derived** — it marks a milestone somebody decided,
not a count of anything. That is what lets a rolling system carry a product version
honestly; it is what Omarchy does (4.0 because the shell was rewritten), and it is why a
date-based scheme is not required just because the base is rolling.

| | Cut by | Bumps when | Where it shows |
|---|---|---|---|
| **Nidara** | this repo | a milestone is declared: a new image with decided content | web, ISO filename, `os-release`, About's OS row |
| **Nidara Desktop** | `nidara-desktop` | features (minor) and fixes (patch), on its own cadence | `pacman -Qi nidara`, About's version block |

**The product version travels by package, not by image.** `nidara-release` owns
`/etc/os-release` — which nothing else owns, unlike `/usr/lib/os-release`, so no conflict
and no pacman hook is needed — and carries `VERSION`. A machine installed from Nidara
0.3.0 becomes 0.4.0 on `pacman -Syu`, without reinstalling. A version that only names the
image someone happened to download would be stale the day after they downloaded it.

**The one hard coupling:** an image pins the desktop version it installs. Every Nidara
release note therefore says which Nidara Desktop is inside — "Nidara 0.3.0, with Nidara
Desktop 0.9.2". That is the only place the two numbers appear together.

### When the number moves — and when it must not

"Declared, not derived" says who decides; it does not say what they are deciding about, and
without that the number drifts into meaning "it has been a while". So: **the product's number
answers one question, and it moves when that answer changes — *what is this computer, out of the
box?***

- **MINOR (0.3.0 → 0.4.0) — the composition changed.** An application enters or leaves
  `nidara-apps`; a default changes that a person would otherwise have had to configure; a
  hardware path starts being supported (NVIDIA, dual boot); the first-run experience changes; or
  the desktop version the image pins brings something the product wants to put its name behind.
  A minor **requires an image** cut in the same release: a composition nobody can download is a
  claim with nothing behind it.
- **PATCH (0.3.0 → 0.3.1) — nothing about the answer changed, the artifact did.** A refreshed
  image (newer kernel, newer installer, newer packages baked in), a fix in `nidara-release` or in
  the installer, a rebuild forced by a security fix. A patch may ship package-only when its
  content only reaches installed machines.
- **NOTHING — the base moved.** Arch publishing new packages is not a Nidara release; that is
  what rolling means. Neither is a Nidara Desktop patch that changes nothing the product promises
  — the desktop has its own number precisely so it can move without asking this one for
  permission. Nor packaging churn in `nidara-repo`.

⚠️ **The calendar is not a trigger.** A number whose job is to name a decision must not be
produced by the passage of time; that is how "25.04" becomes a version people cannot reason
about. There is exactly one time-shaped rule, and it is a floor rather than a schedule: **an image
older than about six months should be refreshed** as a patch, because the installer, the kernel
and the baked-in packages drift away from what a new machine needs — Arch rebuilds its own ISO
monthly for this reason and for no other. Refreshing is a patch, never a minor: nothing was
decided, the artifact was simply brought up to date.

**1.0 is exempt from all of the above.** It is not the next rung of this ladder — it is the day
the promise in "Both start at 0.x" is claimed, and it is declared against its criteria or not at
all. A composition change on a 1.0-ready product is still a minor.

**Cutting one is two files and a tag, and all three must say the same number.** Bump `VERSION` at
this repo's root and `packages/nidara-release/pkgver` in the same commit, tag it, then write the
release note that names the desktop version inside.

The pairing is enforced, and by a script that does **not** live here — `nidara-repo`'s
`scripts/build-repo.sh`, which is what actually publishes the package. It reads the tag, the
`VERSION` file inside the tag, and the PKGBUILD's `pkgver`, and refuses to publish unless the
three agree ("lockstep violation"). It applies the identical gate to `nidara`, the desktop. So a
half-bumped release does not reach anybody: it fails at the publisher, not on somebody's machine.

### Both start at 0.x, and 1.0 is a promise

Nidara Desktop started at 0.1.0. **The product starts at 0.1.0 too**, for the same reason
and with the same meaning: everything below 1.0 is offered, publicly and honestly, as
something that still moves. Every release under 1.0 is marked as a pre-release on GitHub.

**1.0 is not "when it feels ready", it is a claim that can be checked.** The criteria are
open (below) but the shape is fixed: 1.0 says *installing this on a machine we did not
anticipate is expected to work, and updating it is expected not to break it*. Nothing else
about the project changes on that day — it is the day the promise changes.

## The ladder

Where the product is, and what each rung requires. This is the part that answers "what do
we have to do next", which is the reason the rest of the file exists.

- **0.1.0 — it boots, it installs, it says its own name.**
  The live image reaches the desktop; the installer produces a system that boots to the
  greeter; the identity package exists so the installed system is Nidara and not Arch.
  Requires the two decisions listed as open below, because an image without a decided
  application set is not a product, it is a build artifact.

  **Progress (2026-08-25): the third clause is done.** `packages/nidara-release` exists and
  is wired end to end — `VERSION` declares the number, `profiledef.sh` puts it in the ISO
  filename, the package puts it in `/etc/os-release`, the installer installs it, and the
  desktop's About shows it next to the desktop's own version. Nothing of it is published
  yet: that waits on the first `nidara-iso` tag and the pin in `nidara-repo`.

- **0.x — the iteration.**
  Each image decides one more thing that a product has to have decided: hardware paths
  (NVIDIA, dual boot), defaults nobody should have to configure, what the first-run
  experience is, what happens when an update goes wrong.

- **1.0 — the promise.**
  Criteria to be written before the 0.x series ends, not after. They will be a list of
  scenarios that must install and update cleanly, plus a support surface (where a broken
  system writes to) that exists and is answered.

## Open decisions (deliberately, not by omission)

1. **What applications the product ships.** `nidara-apps` exists as the mechanism; its
   contents are undecided on purpose. A curated set is a product statement — it is the
   difference between "a desktop" and "a computer you can use".

   The RULES are decided (2026-08-25), which is most of the work; the list is what is left:
   - **GTK, and GTK4 where there is a choice.** Until Nidara has applications of its own —
     which waits on the kit — the product borrows GNOME's, because they are the only large
     GTK4 family that exists. An app depending on libadwaita is acceptable *as an app*; the
     ban on libadwaita is a rule about OUR code, not about what we can ship beside it.
   - **Arch's official repositories only.** Not the AUR: the product cannot ship packages
     nobody is accountable for, and `nidara-repo` is not a laundering route for them. This
     rules out Google Chrome, and — verified, not assumed — **pamac**, which is AUR-only.
   - **Flatpak is the fallback**, and only where the official repos have no equivalent.
   - Nautilus and Kitty already arrive with the desktop; they are not part of this list.

   ⚠️ **The graphical package manager has no candidate today, and that is a finding, not a
   gap in the search.** `pamac` fails the rule above. `gnome-software` is in `extra` and is
   GTK4, but on Arch it is built with the flatpak/fwupd plugins and NO PackageKit backend —
   it manages Flatpaks and firmware, and cannot install a pacman package at all. `discover`
   is Qt. So the product can ship a *Flatpak* store today and nothing that fronts pacman.
   That is precisely the hole the planned Nidara "Store" fills, and it is worth knowing that
   the alternative is not "use the existing one" but "there isn't one".
2. **What Nidara changes about Arch beyond the desktop.** Today: nothing. Candidates are
   the boot defaults already documented in the installer notes, sane power settings, and
   whatever the 0.x hardware work turns up. Each one is a decision with a maintenance cost,
   taken one at a time and written down here.
3. ~~**The version of the first public image.**~~ **DECIDED 2026-08-25: `0.1.0`** — the
   ladder starts where it says it does. It is written in `VERSION` at the root of this repo,
   which is the single place the product's number is declared; everything else reads it.
   Changing it before the first public image costs one line and a rebuild, so this is a
   default that can still be moved, not a commitment that has been shipped.

4. **Where the image is distributed from.** Open, and deliberately not answered by the
   constraint that raised it.

   **The rule, decided 2026-08-25 and not up for re-litigation: the product is not trimmed to
   fit a host's limit.** A GitHub release asset is capped at 2 GiB and the image measures
   2,192 MiB. The arithmetic says one package closes that gap, and the two packages big enough
   to matter are the two that cannot go: `noto-fonts-cjk` (299 MiB — the live session has to
   render Chinese, Japanese and Korean, and the desktop ships ja and zh-CN among its twelve
   locales) and `firefox` (295 — what makes a freshly installed machine usable at all). So the
   file goes somewhere without an opinion about its size, and a GitHub release still holds the
   notes, the `sha256` and the signature wherever it lives.

   The measurement, so the next pass does not repeat it (airootfs 3,793 MiB installed →
   2,192 MiB of ISO, i.e. it compresses to about half): firmware 487 MiB across 13 subpackages ·
   `noto-fonts-cjk` 299 · `firefox` 295 · `llvm-libs` 164 (via mesa) · kernel 148 ·
   `papirus-icon-theme` 111 · `qt6-base` 66 (pulled by `xdg-desktop-portal-hyprland`).

   Several hosts would do; none is chosen yet, and choosing one is not a technical question.

   ⛔ **Not a candidate: shipping a builder instead of an image** ("let each user build their
   own"). Considered and rejected on 2026-08-25 for two reasons. The audience for an ISO is
   precisely the people who do not have Arch — a builder needs Arch, root, `archiso`, ~10 GiB and
   a quarter of an hour. And an image built per user is not a verifiable artifact: no signature,
   no fixed content, no "Nidara 0.1.0" — which is the opposite of what `nidara-release` exists to
   establish. `build.sh` remains exactly what it is: how WE make images, and a documented option
   for an Arch user who wants to roll their own.

## What does NOT change

`install.sh` installs Nidara Desktop onto somebody's existing Arch and must keep treating
that machine as theirs: it does not rename their operating system, it does not touch their
bootloader, it does not choose their browser. On such a machine About correctly reads
"Arch Linux" for the OS and "Nidara Desktop" for the environment. Both statements are true,
and the product is the other path.
