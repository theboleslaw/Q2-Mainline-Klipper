# Q2 Mainline Klipper

Printer configuration for a **Qidi Q2 + Qidi Box** running
[q2-offload](https://github.com/cedbossneo/q2-offload) on a separate host.

This repository is the source of truth for the printer config. It also contains
the local q2-offload/Moonraker customizations as patches, so a reinstall can be
reproduced.

## Reinstall from scratch

On the host, as your normal user:

```sh
git clone git@github.com:theboleslaw/Q2-Mainline-Klipper.git ~/Q2-Mainline-Klipper
~/Q2-Mainline-Klipper/reinstall/install.sh 192.168.3.210
```

`reinstall/install.sh` does the following:

1. clones q2-offload at `v2026.11.25` (if it is not already there),
2. applies `reinstall/q2-offload-local.patch` — the Happy Hare pin, local MMU
   patches and overrides,
3. copies this repo to `~/printer_data/config` when that directory does not
   exist yet,
4. runs `./install.sh --printer <printer-ip>` (interactive),
5. applies the Moonraker patch and normalizes the update manager,
6. runs `./install.sh update` to install the pinned Happy Hare, then refreshes
   the update-manager pins.

> **First conversion warning:** the first install replaces Qidi's bootloader
> with Katapult on the mainboard, toolhead and Box. Keep the printer powered and
> connected, and type **FLASH** only when you are ready. A power cut during the
> first conversion needs an ST-Link to recover.

The default addresses used here are:

```text
host     192.168.3.220
printer  192.168.3.210
```

Pass a different printer IP as the first argument if yours differs.

## Reinstall when q2-offload is already installed

```sh
# If the config repo is not present yet:
git clone git@github.com:theboleslaw/Q2-Mainline-Klipper.git ~/printer_data/config

~/printer_data/config/reinstall/restore.sh
cd ~/q2-offload && ./install.sh update
~/printer_data/config/reinstall/restore.sh
```

`restore.sh` is idempotent. It:

- applies the local q2-offload patch and the Moonraker MMU-log patch if they are
  not already present,
- puts `klipper`, `moonraker`, `mainsail-config` and `moonraker-timelapse` on
  tracking branches instead of detached HEADs,
- pins Klipper and Moonraker to the installed commits in `moonraker.conf`,
- removes the q2-offload self-updater (q2-offload is updated from a terminal
  because it contains local patches),
- restarts Moonraker.

## What is local

| File | Purpose |
| --- | --- |
| `reinstall/q2-offload-local.patch` | q2-offload `VERSIONS` pin (`development@6717a8a`), local MMU patches, Box fan at 38 °C, empty-gate rotation, runout/park overrides |
| `reinstall/moonraker-mmu-log.patch` | Moonraker `MMU` log rollover and `mmu_server` component |
| `printer.cfg` | calibrated input shaper, load cell, bed mesh and machine settings |
| `mmu/base/*.cfg` | Happy Hare config generated from the pinned version + overrides |
| `moonraker.conf` | update-manager pins and local services |

The config repo **does not** restore `saved_variables.cfg` (runtime MMU state) or
`mmu.old-*` backups. Recalibrate the input shaper, bed mesh and load cell after a
fresh install if needed.

### Klipper checkout

`~/klipper` is a `blob:none` partial clone of `Klipper3d/klipper`. The working
tree is the **`q2-offload`** branch: the pinned release (`v0.14.0`, `c9559fa04`)
plus the Q2 patches applied as commits. `master` and the old `q2-klipper`
experiment were pruned on 2026-11-25, so that branch is the only authoritative
tree.

`backup-um-20261114` is the pre-update backup branch (Klipper `v0.13.0` +
patches). The retired `q2-klipper` series (19 patches, motion queuing, webhooks
msgspec, load-cell allocation work) is kept as tag
`archive/q2-klipper-ec8dc02`, with a tree tarball and the patch files in
`~/backups/pre-20261125/`.

## Updating

Update Klipper, Happy Hare, Moonraker and the web clients from a terminal:

```sh
cd ~/q2-offload
./install.sh update
```

Then refresh the update-manager branches/pins:

```sh
~/printer_data/config/reinstall/restore.sh
```

Do **not** use Mainsail's update button for Klipper or Moonraker. They carry
q2-offload/local patches and are pinned in `moonraker.conf`. q2-offload is not
listed in the update manager for the same reason.

If an update changes the Klipper or Moonraker commit, `restore.sh` updates the
pins automatically.

## Verification

```sh
cd ~/q2-offload
./install.sh check
```

Expected highlights:

```text
Klipper ready (mainboard, toolhead and Box connected)
Happy Hare enabled
load cell ready for probing
Mainsail / Fluidd / Moonraker / camera
```

Web interfaces:

```text
Mainsail  http://192.168.3.220:81/
Fluidd    http://192.168.3.220/
```

## Local changes after reinstalling

`restore.sh` applies the patches but does not overwrite your printer config. When
q2-offload updates a generated file, it may leave a `*.new` copy next to it.
Compare and merge those manually; commit the result here.
