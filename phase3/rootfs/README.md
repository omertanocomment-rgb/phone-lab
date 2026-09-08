# phase3/rootfs/ — postmarketOS netboot rootfs for the real iPhone 6

**Scope:** produces the network-booted root filesystem that pairs with
the custom kernel built in [`../kernel/`](../kernel/README.md). See that
README for the overall safety/scope framing (no NAND writes, independent
of the device's current Activation Lock, no real device/USB/DFU touched
by any of this).

## Important correction vs. the original plan: device codename changed

The reference material (ivonblog.com's iPhone 6 writeup) used
`pmbootstrap init` → device `apple-iphone6`. **That port no longer
exists as such.** Checked directly in the freshly cloned `pmaports`
(`device/archived/device-apple-n61/APKBUILD`):

```
# Archived: Replaced by apple-idevice
```

postmarketOS consolidated all Apple iDevice support into one generic
`device-apple-idevice` port (`device/testing/device-apple-idevice/`,
currently "testing" category, not archived), covering both 4K-page
(A7-A8X, our iPhone 6) and 16K-page (A9+) variants via subpackages
(`device-apple-idevice-kernel-4k`, matches our device's A8 4K-page
requirement — same requirement `../kernel/`'s `CONFIG_ARM64_4K_PAGES=y`
already covers for our own separately-built kernel).

**Used `apple-idevice` instead of the archived `apple-n61`.** This is the
currently-maintained path, but it does introduce one real, unverified
assumption worth flagging: `device-apple-idevice`'s own kernel subpackage
is built for booting via `m1n1` (Asahi's bootloader, extended here for
iDevices) rather than via `pongo-linux-src`'s `load_linux.py` mechanism
this project is actually using. **The userspace/rootfs content itself
should be boot-mechanism-agnostic** (it's a generic aarch64 Alpine-based
system; once any kernel is running and mounts it, it doesn't care how
that kernel got loaded) — but this compatibility is reasoned from how
netboot/rootfs mounting works in general, not confirmed by an actual
successful boot. Flag this explicitly if a live test fails at the
rootfs-mount stage specifically (as opposed to earlier, at the kernel
boot stage).

## What's done: full `pmbootstrap init` config, verified

Ran `pmbootstrap init` (from a git clone at
`gitlab.postmarketos.org/postmarketOS/pmbootstrap` — see below, this
moved twice since the reference material was written) through its full
interactive wizard via scripted stdin answers — a normal automation
technique for a CLI wizard, not privilege spoofing (that boundary only
applies to `sudo`/real-device steps, see below).

**Two real, non-obvious repo-location corrections along the way:**
1. `github.com/postmarketOS/pmbootstrap` → 404, doesn't exist anymore.
2. `gitlab.com/postmarketOS/pmbootstrap` → clones fine but prints a
   moved-again notice on every run: postmarketOS migrated to its own
   self-hosted GitLab. **Actual current location:**
   `https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git`
   (cloned here, gitignored, ~confirm size below).

**Dependency gap found and fixed:** `pmbootstrap` requires `kpartx`,
not present on this box by default. Fetched via the same no-root
`apt-get download` + `dpkg-deb -x` pattern already established
(`kpartx_0.15.0-1_amd64.deb` from Kali's own repo — its shared-lib deps
were already satisfied system-wide, no extra fetching needed). Added
`$P3K_PREFIX/usr/sbin` to `PATH` in `~/.bashrc.phase3-kernel-env`
(shared with `../kernel/`'s env file, host-specific, not committed).

**Config produced** (`~/.config/pmbootstrap_v3.cfg`, outside the repo):
```
[pmbootstrap]
device = apple-idevice
is_default_channel = False
kernel = 4k
timezone = Australia/Perth
```
Also cloned `pmaports` itself during `init`
(`~/.local/var/pmbootstrap/cache_git/pmaports`, ~247MB, outside the
repo — this is `pmbootstrap`'s own cache location, not something this
project vendors).

## The real blocker: pmbootstrap's chroot operations need sudo

`init`'s last step ("Zap existing chroots to apply configuration?")
failed:
```
ERROR: Failed to shut down all chroots. Ensure they're not doing any
work and you're not chrooted into any. (Command failed (exit code 1):
% sudo losetup --json --list)
```
Confirmed directly (`sudo -n losetup --json --list` → `sudo: a password
is required`) and confirmed this is **structural, not just this one
step** — `pmb/chroot/run.py` wraps chroot commands in `sudo` throughout,
so `install`, `initfs hook_add netboot`, and `export` would all hit the
same wall. This box has no passwordless `sudo` configured (same
limitation noted everywhere else in this project's history).

This is a genuinely different kind of `sudo` need than the live-device
steps elsewhere in this project — it's for host-side loopback/chroot
management to build the rootfs locally, nothing to do with the real
iPhone. But the fix is the same either way: a human needs to type the
password.

## Update 2026-09-08 (2): install/initfs/export all completed — DONE

With the user present to type the `sudo` password, the full chain
finished cleanly: `install` (4/4 stages: prepare native chroot, create
device rootfs, prepare install blockdevice, fill install blockdevice),
`initfs hook_add netboot`, `export`. One transient self-recovered issue
along the way — `chroot not initialized! This is a bug! Please report
it.` during the netboot hook install, which `pmbootstrap` handled itself
("initializing the chroot for you...") and continued; not a real failure.

**Verified real output** (symlinks in `/tmp/postmarketOS-export/`,
resolved and checked directly, not assumed from the log):
- `apple-idevice.img` → `~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/apple-idevice.img`, 1,258,291,200 bytes (1.2GB rootfs+boot image)
- `initramfs` → `~/.local/var/pmbootstrap/chroot_rootfs_apple-idevice/boot/initramfs`, 12,552,693 bytes
- `vmlinuz` → `~/.local/var/pmbootstrap/chroot_rootfs_apple-idevice/boot/vmlinuz`, 9,455,528 bytes (postmarketOS's own prebuilt kernel package — **not** the project's own `../kernel/linux-apple` build; for the actual live test, use our own `Image.lzma`/`dtbpack` via `load_linux.py`, and only this `initramfs` from this export, per the boot-mechanism-agnostic reasoning above)

Host stayed healthy throughout: memory never dropped below the
200-something MB-free band seen in earlier steps, disk at 34GB free
afterward.

**Everything phase3/kernel/ and phase3/rootfs/ set out to build now
exists.** The only remaining step for this whole phase3 "kernel/rootfs"
milestone is the live device test — see `../kernel/README.md`'s final
section for the exact command, now fully unblocked (kernel, dtbpack, and
initramfs all real and present).

## If this is picked up again

1. With the user present, run (from
   `phase3/rootfs/pmbootstrap/`, with `~/.bashrc.phase3-kernel-env`
   sourced first for `kpartx`):
   ```
   sudo -v   # cache credentials interactively first
   python3 pmbootstrap.py init   # will detect existing config, mostly re-confirm
   python3 pmbootstrap.py install
   python3 pmbootstrap.py initfs hook_add netboot
   python3 pmbootstrap.py export
   ```
   Watch memory closely (`free -h`) during `install` — this box has only
   3.7GB RAM and `pmbootstrap`'s cross-arch chroots are expected to be
   the most memory-hungry step attempted in this whole project so far.
2. `export` should produce an initramfs usable with
   `../kernel/pongo-linux-src/scripts/load_linux.py -r <initramfs>`, and
   `pmbootstrap netboot serve` is what serves the actual rootfs to a
   booted device over the network afterward.
3. Only then, with the user present: the actual live-device test (see
   `../kernel/README.md`'s final section).
