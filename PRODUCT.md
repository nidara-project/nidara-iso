# Nidara — what the product is, and what each piece is called

This file exists because the question "is this a distro or a desktop?" kept coming back,
and every time it did, the answer was reconstructed from scratch and came out slightly
different. It is a decision record, not documentation of code: the mechanics live in the
README next door and in `nidara-desktop`'s skill.

⚠️ **A decision record only works if superseded decisions stay visible**, so nothing here is
deleted when it is overtaken — it is struck through and dated, with the reason. Two entries read
that way as of 2026-08-30 (the product's version number, and "what Nidara changes about Arch"),
and in both cases the earlier text was correct when it was written. **Where this file and the code
disagree, this file is the intent and the code is the backlog** — the ordered work is in open
decision 2.

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
| System policy | `nidara-iso` | `nidara-system` | What Nidara changes about Arch itself (boot, splash, defaults) |
| Identity | `nidara-iso` | `nidara-release` | `/etc/os-release`: the product's **name** (exists since 2026-08-25) |

## Four layers, and the third one had no owner

The table above is not a list of repositories; it is four different questions, and the value of
keeping them apart is that each install path answers them with a package name instead of with
whatever happened to get typed.

| Layer | The question it answers | Where it lives |
|---|---|---|
| **1. The desktop** | What does the desktop need to RUN? | `nidara` |
| **2. The composition** | What makes a fresh machine USABLE? | `nidara-apps` |
| **3. System policy** | What does Nidara change about **Arch**? | `nidara-system` |
| **4. Identity** | What does this computer call itself? | `nidara-release` |

Layers 1, 2 and 4 were designed. **Layer 3 arrived without anyone deciding it should exist**, over
four days in August 2026 (`nidara-desktop` #284 and #285), and because it had no home it settled in
three places that were none of them right:

- `ui/installer/lib/bootloader.ts` — the kernel cmdline, the systemd-boot entry titles,
  `plymouthd.conf`, the mkinitcpio hook, `RebootWatchdogSec=off`, `modprobe.d/nowatchdog.conf`. The
  product's system policy, written as heredocs inside a step of a GTK application, in the DESKTOP's
  repository.
- `packaging/nidara/PKGBUILD` — the Plymouth theme, and (2026-08-29) `depends=(plymouth)`, which
  pushes the product's boot branding onto every Arch user who installs only the desktop.
- `install.sh` — copying that theme onto a machine that is not ours and setting it as the default.

Three consequences, all of them already true rather than predicted:

1. **The policy never updates.** Everything above is written once, at install time. A machine
   installed in August receives no improvement to its boot experience, ever. There is no route.
2. **Nobody can read what Nidara changes about Arch.** You have to read an installer step to find
   out — which is why open decision 2 below said "Today: nothing" for four days after it stopped
   being true.
3. **The desktop is acquiring opinions that are not its own.** Plymouth today; power defaults,
   NVIDIA and dual-boot tomorrow, all arriving through the same door for the same reason: it is
   where the code already was.

**The rule that decides layer 1 vs layer 3, and it is one line: if an Arch user installing only the
desktop would not want it, it does not go in `nidara`.** GNOME Shell does not depend on Plymouth;
Ubuntu ships a Plymouth theme. That is the whole distinction, and it is the one `install.sh` has
always been held to — see "What does NOT change" at the end of this file.

`nidara-system` is where layer 3 goes: a package in this repo, published by `nidara-repo` beside
`nidara-release`. It takes everything declarative — the Plymouth theme and `plymouthd.conf`,
`/etc/mkinitcpio.conf.d/nidara.conf` (the conf.d mechanism, which is how archiso already injects
its own hook, so the user's `mkinitcpio.conf` is never edited), the watchdog drop-ins, and whatever
the hardware work of rung 3 turns up. The installer keeps only what is genuinely per-machine and cannot
be packaged: the kernel parameters in this machine's loader entries, and the loader timeout that
depends on whether Windows is present.

⚠️ **A separate package from `nidara-release` on purpose.** Identity is one file and should stay
trivial to reason about; policy is going to grow. They also fail differently — a bad identity
package renames your OS, a bad policy package can stop it booting.

⚠️ **`nidara-system` is what makes the word "rolling" in the next section TRUE rather than
hopeful**, so it lands first. It owes two things the moment it exists: a pacman hook that
regenerates the initramfs when its conf.d drop-in changes, and a decision about `backup=` — a
policy file the user edited becomes a `.pacnew` and the change silently does not apply, which is
correct for configuration and wrong for policy.

## The machine is rolling, the image has a date

⚠️ **This reverses a decision this file made deliberately on 2026-08-25, and the previous text is
worth knowing because its argument was good.** It said the product carried a semver of its own,
declared and not derived, travelling by package so that "a machine installed from Nidara 0.3.0
becomes 0.4.0 on `pacman -Syu`". The reason for changing it is new information rather than second
thoughts: layer 3 did not exist when that was written, and once system policy also travels by
package, the number is left describing nothing.

**The defect, stated plainly: `VERSION` in `/etc/os-release` was the same on every machine.**
`nidara-release` carries no `backup=` on purpose — the update must win — so every Nidara machine
that has run `pacman -Syu` reports the newest number the project has published, whatever image it
came from and whatever state it is in. The old text celebrated exactly this. But a field whose
value is identical across the whole fleet carries no information: it does not say where the machine
came from, it does not say what it is, it says what the latest release is, which anybody could have
looked up.

That is the difference from the system this was borrowed from. Ubuntu's `VERSION_ID=24.04` is
informative **because it does not change** — it identifies which series that machine tracks. Nidara
has no series, and there is no honest way to have one with a single maintainer and a rolling base.
Copying the field without the series turns it into noise.

So:

| | Carries a number | Which number | Why |
|---|---|---|---|
| **A Nidara machine** | **No** | `BUILD_ID=rolling`, and that is the whole answer | It converges on the newest of every layer; nothing about it is a release |
| **A Nidara image** | **Yes** | A date: `nidara-2026.09.01-x86_64.iso` | An image never changes after it is published, so a name that fixes it can be true forever |
| **Nidara Desktop** | **Yes** | semver, unchanged | It is software with features; this is the number that was always doing real work |

**`nidara-release` survives and is still required** — without it the machine says "Arch Linux", and
renaming the OS is the product's act, which is why it lives here and not in the desktop. What it
loses is `VERSION` and `VERSION_ID`; `PRETTY_NAME` becomes `"Nidara"`. The desktop needs no change
for this: `core/SystemInfo.ts` reads `PRETTY_NAME` and nothing else.

**What About shows instead**, and it is strictly more useful for the thing About is actually for:
not one number that is the same everywhere, but the versions of `nidara`, `nidara-system` and
`nidara-apps` — which differ between machines, which is what a bug report needs.

**What this deletes:** the lockstep machinery. `VERSION` at this repo's root, `nidara-release`'s
`pkgver`, and the tag no longer have to agree, and `nidara-repo`'s `build-repo.sh` no longer needs
to refuse a "lockstep violation" for the product. ⚠️ **That gate stays for `nidara`**, the desktop,
where the three-way agreement still means something.

### What is lost, and it is not nothing

**The announcement.** "Nidara 0.4.0 picks Firefox and rewrites the installer" is a sentence you can
put on a page; "Nidara, rolling" is not. The answer is that the expressive power was in the wrong
place: Omarchy's 4.0 — the precedent the old text cited — is a number on **the thing that got
rewritten**, its shell. Nidara already has that number, on `nidara`, an artifact that genuinely is
software with features. Big news is announced there, and an image's release notes say what that
image decides. Nothing was lost; it stopped being duplicated into a second number that could not
be true.

**1.0, and this one is a real cost.** The ladder below rested on 1.0 meaning *installing this on a
machine we did not anticipate is expected to work, and updating it is expected not to break it* —
a promise about the PRODUCT, so it cannot move to the desktop's semver. **1.0 stops being a series
of versions and becomes a declared milestone**: announced in the README and in the release notes of
one specific image ("the first image that claims the 1.0 promise"). The promise is a sentence about
the project and can be made without being stamped on every artifact — but a milestone with no
version series behind it is a weaker communication device than the old scheme, and that is accepted
here rather than argued away.

### When an image is cut — and when it must not be

The old rules for moving a number become rules for cutting an image, and most of them survive
intact, because the question they answered was always *what is this computer, out of the box?* —
which is precisely the part that does **not** travel by pacman.

**Cut an image when the install-time answer changes**: the installer's behaviour, the partition
scheme, the bootloader, the first-run experience, hardware paths (NVIDIA, dual boot), or a default
that a person would otherwise have had to configure and that cannot reach an installed machine.

**Do not cut an image because a package moved.** A new `nidara`, a new `nidara-apps`, a new
`nidara-system` — those reach every existing machine on their own. That is the point of the four
layers, and it is what "rolling" means. Arch publishing new packages is not a Nidara event either.

⚠️ **The calendar is still not a trigger, with one floor.** An image older than about six months
should be refreshed, because the installer, the kernel and the baked-in packages drift away from
what a new machine needs — Arch rebuilds its own ISO monthly for this reason and no other. A
refresh is just a new date; nothing is being decided.

### What an install-time decision actually is

Worth writing down, because it is the whole boundary and it is not obvious. **Everything below
reaches an existing machine through pacman**, so it is never a reason to cut an image:

- the desktop, the curated apps, the system policy — layers 1, 2 and 3

**Everything below is decided once, at install, and no update reaches it:**

- the partition scheme and the Btrfs subvolume layout
- the bootloader, and the kernel parameters in this machine's loader entries
- the installer that made those choices

And one that is **half** of each, which is a trap: removing an application from `nidara-apps`
does not uninstall it from an existing machine. The dependency goes away and the package stays,
orphaned. Additions travel; removals do not.

⚠️ **There is no offline installation, and every install therefore produces a current machine**
(measured 2026-08-30). `base.json` configures no local repository — `custom_repositories: []`, no
`custom_servers` — archinstall pacstraps from the mirrors, and the `custom_commands` reach
`nidara-repo` over `curl`. So an image's age barely affects the machine it produces; it affects the
installer and the install-time decisions above, and nothing else. If an offline path is ever
wanted, this paragraph is what has to change first, and the image's date starts meaning much more
than it does today.

## The ladder

Where the product is, and what has to be true to climb. This is the part that answers "what do we
have to do next", which is the reason the rest of the file exists.

⚠️ **The rungs are no longer version numbers** (see "The machine is rolling, the image has a
date"). They are states the product is in, and each one is reached by an image that can install it.

- **Rung 1 — it boots, it installs, it says its own name.** *(the current rung)*
  The live image reaches the desktop; the installer produces a system that boots to the greeter;
  the identity package exists so the installed system is Nidara and not Arch.

  **Done (2026-08-25):** `packages/nidara-release` is wired end to end and published — the machine
  says "Nidara" instead of "Arch Linux", which was the whole clause.

  **Not done, and it blocks the rung:** an image without a decided application set is a build
  artifact rather than a product, so open decision 1 below is a prerequisite and not a nicety.

- **Rung 2 — what Nidara changes about Arch is a thing you can read.**
  `nidara-system` exists, the boot experience travels by package, and open decision 2 stops being
  the honest answer to "what does Nidara change" by being replaced with a package listing.

- **Rung 3 — the iteration.**
  Each image decides one more thing a product has to have decided: hardware paths (NVIDIA, dual
  boot), defaults nobody should have to configure, what the first-run experience is, what happens
  when an update goes wrong.

- **1.0 — the promise.**
  Criteria written before this series ends, not after: a list of scenarios that must install and
  update cleanly, plus a support surface (where a broken system writes to) that exists and is
  answered. Declared once, against those criteria, and attached to the image that first claims it
  — not the top of a numbered ladder any more, which is the cost recorded above.

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
2. **What Nidara changes about Arch beyond the desktop.**

   ⚠️ ~~Today: nothing.~~ **That was true when it was written and stopped being true on
   2026-08-28**, without anybody noticing, because the change happened in the other repository:
   silent boot, a Plymouth theme, systemd-boot entry titles and watchdog suppression all landed in
   `nidara-desktop` (#284, #285) and are applied by the installer. Four days of this file
   confidently answering "nothing" is the reason layer 3 now has a section of its own above.

   **What is decided:** that this layer exists, that it is called `nidara-system`, that it lives
   here, and that the boundary between it and the desktop is the one-line rule — *if an Arch user
   installing only the desktop would not want it, it does not go in `nidara`*.

   **What is open, and stays open on purpose:** what goes IN it beyond what already exists. The
   current contents are not a curated set; they are what two pull requests happened to add. Each
   further candidate — power defaults, NVIDIA, dual boot — is a decision with a maintenance cost,
   taken one at a time and written down here.

   **The work this implies, in order** (the sequence matters: removing the product's version
   before its policy travels would leave the convergence promise with nobody to keep it):
   1. `nidara-system` exists and carries the Plymouth theme, the mkinitcpio drop-in and the
      watchdog configuration, with the initramfs hook that makes it take effect.
   2. `nidara-desktop` gives them up — `depends=(plymouth)` and the theme leave the `nidara`
      package, and `install.sh` stops setting a boot theme on somebody else's machine.
   3. `bootloader.ts` shrinks to the per-machine residue: kernel parameters in the loader entries
      and the Windows-aware timeout.
   4. `nidara-release` drops `VERSION`/`VERSION_ID`, and images move to dates.
3. ~~**The version of the first public image.**~~ ~~**DECIDED 2026-08-25: `0.1.0`**~~
   **SUPERSEDED 2026-08-30: images carry a date, not a version** — see "The machine is rolling,
   the image has a date". The question this asked no longer has an answer because it no longer has
   a subject: the first public image is named for the day it is built. `VERSION` at the root of
   this repo and `nidara-release`'s `pkgver` are what the change has to remove.

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
   no fixed content, nothing a `sha256` can be published against — which is the opposite of what a
   dated, signed image is for. `build.sh` remains exactly what it is: how WE make images, and a documented option
   for an Arch user who wants to roll their own.

## What does NOT change

`install.sh` installs Nidara Desktop onto somebody's existing Arch and must keep treating
that machine as theirs: it does not rename their operating system, it does not touch their
bootloader, it does not choose their browser. On such a machine About correctly reads
"Arch Linux" for the OS and "Nidara Desktop" for the environment. Both statements are true,
and the product is the other path.

⚠️ **This is the oldest rule in this file and the one that was quietly broken first**, which is
worth noticing: nothing announced itself when `install.sh` started setting a Plymouth theme on a
machine that is not ours. The rule is not self-enforcing, and the four layers above exist so that
breaking it requires putting something in the wrong package rather than merely adding a line to a
script.
