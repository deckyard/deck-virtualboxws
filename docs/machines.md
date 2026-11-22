<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Machines

## Looking around

```jennifer
use io;

for (def m in virtualboxws.vms($s)) {
    if ($m.name == "<inaccessible>") {
        continue;
    }
    def i as virtualboxws.VmInfo init virtualboxws.info($s, $m.uuid);
    io.printf("%-20s %-10s %d CPU %5d MiB\n", $i.name, $i.state, $i.cpus, $i.memoryMb);
}
```

States are named as `VBoxManage` names them (`poweroff`, `running`,
`saved`, `aborted`, ...), so code shared with the `virtualbox` deck compares
the same strings.

## Power

```jennifer
virtualboxws.start($s, "web");             # headless, waits until it runs
virtualboxws.acpiShutdown($s, "web");      # ask the guest to shut down
virtualboxws.powerOff($s, "web");          # or pull the plug, and wait
```

`startWith($s, "web", "gui")` opens a window on the host's desktop (the
service must run in that desktop session). `pause`, `resume`, `reset` and
`saveState` do what the VirtualBox menu does. Each locks the machine for a
moment through a session of its own and unlocks it before returning, also
when it fails.

## Snapshots and clones

```jennifer
use io;
use strings;

virtualboxws.takeSnapshot($s, "web", "before-upgrade", "kernel 6.8");
for (def snap in virtualboxws.snapshots($s, "web")) {
    io.printf("%s%s\n", strings.replicate("  ", $snap.depth), $snap.name);
}
virtualboxws.restoreSnapshot($s, "web", "before-upgrade");
```

Restoring needs the machine powered off. `clone` copies a machine with its
disks into a new registered machine; `linkedClone` makes a clone on
difference disks from a snapshot, fast and small but tied to that snapshot.
Both return the clone's UUID. On VirtualBox 7.1 the clone gets the
original's platform (x86 or ARM).

## Appliances

```jennifer
virtualboxws.importAs($s, "/srv/images/debian-12.ova", "build-1");
virtualboxws.exportOva($s, "build-1", "/srv/out/build-1.ova");
```

The paths are on the VirtualBox host. `importOva` keeps the names the
appliance gives and returns the new machines' UUIDs; `importAs` renames
the first machine and otherwise imports everything as suggested, as
`VBoxManage import --vmname` does. `exportOva` writes OVF 2.0: one `.ova`
archive, or an `.ovf` descriptor with the disks beside it.

## The guest

```jennifer
virtualboxws.unsetGuestProperty($s, "web", "/VirtualBox/GuestInfo/Net/0/V4/IP");
virtualboxws.start($s, "web");
def ip as string init virtualboxws.waitForIp($s, "web", 0, 180000);
```

The Guest Additions publish the guest's addresses as guest properties;
`waitForIp` polls the one for a guest interface (from 0) until it is set.
The property can survive a hard power-off, hence the `unsetGuestProperty`
before `start`. `guestProperty`, `setGuestProperty` and
`unsetGuestProperty` work on any key.
