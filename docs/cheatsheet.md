<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# virtualboxws cheatsheet

Every export of `@deckyard/virtualboxws`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/virtualboxws/" as virtualboxws;
```

Every failure is a `VirtualboxwsError` (kind `"virtualboxws"`), except a
cancelled task (kind `"cancelled"`). A `c` argument is a
`Config`, an `s` a `Session`, a `vm` a machine's name or UUID.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `DEFAULT_URL` | `"http://localhost:18083/"` | the web service on this machine, with its defaults |
| `DEFAULT_TIMEOUT_MS` | `60000` | how long an ordinary request may take |
| `DEFAULT_LONG_TIMEOUT_MS` | `3600000` | how long a start, power-off, snapshot, clone, import or export may take |
| `DEFAULT_MAX_BYTES` | `1048576` | the largest reply read; a full reply takes about 40 MiB to parse |
| `MIN_MAJOR` | `7` | the oldest VirtualBox major version `logon` accepts |

## Connecting

| Function | Returns | Does |
|---|---|---|
| `virtualboxws.endpoint(url)` | `Config` | the service at a URL; plain `http` only to this machine |
| `virtualboxws.withTls(c, tls)` | `Config` | certificate options (`caCert`, `skipVerify`) for `https` |
| `virtualboxws.withPlainHttp(c)` | `Config` | allow plain `http` to another machine (the password in clear) |
| `virtualboxws.withTimeout(c, ms)` | `Config` | the deadline of an ordinary request, 1000 to 86400000 ms |
| `virtualboxws.withLongTimeout(c, ms)` | `Config` | the deadline of the long operations |
| `virtualboxws.withMaxBytes(c, most)` | `Config` | the largest reply, 65536 to 67108864 bytes |
| `virtualboxws.logon(c, username, password)` | `Session` | log on; refuse VirtualBox older than 7 |
| `virtualboxws.logoff(s)` | `null` | end the session; the service frees everything it held |
| `virtualboxws.call(s, method, args)` | `map of string to list of string` | any other web-service method |
| `virtualboxws.releaseRef(s, ref)` | `null` | release a reference `call` returned |
| `virtualboxws.errorCode(e)` | `string` | a `VirtualboxwsError`'s `code`: `VBOX_E_*` / `E_*` / `0x...` / `INVALID_OBJECT` (read `$e.code` directly) |

## Machines and power

| Function | Returns | Does |
|---|---|---|
| `virtualboxws.vms(s)` | `list of Vm` | every registered machine |
| `virtualboxws.runningVms(s)` | `list of Vm` | the running ones (running, paused, starting, ...) |
| `virtualboxws.hasVm(s, vm)` | `bool` | whether a machine is registered |
| `virtualboxws.info(s, vm)` | `VmInfo` | state, type, memory, processors, snapshots |
| `virtualboxws.state(s, vm)` | `string` | `poweroff`, `running`, `paused`, `saved`, ... as VBoxManage names them |
| `virtualboxws.start(s, vm)` | `null` | start without a window and wait |
| `virtualboxws.startWith(s, vm, mode)` | `null` | start `headless`, `gui` or `separate` |
| `virtualboxws.powerOff(s, vm)` | `null` | pull the plug and wait |
| `virtualboxws.acpiShutdown(s, vm)` | `null` | press the power button |
| `virtualboxws.pause(s, vm)` | `null` | pause |
| `virtualboxws.resume(s, vm)` | `null` | resume |
| `virtualboxws.reset(s, vm)` | `null` | press reset |
| `virtualboxws.saveState(s, vm)` | `null` | save the state to disk, stop, and wait |

## Snapshots, clones, appliances

| Function | Returns | Does |
|---|---|---|
| `virtualboxws.snapshots(s, vm)` | `list of Snapshot` | the snapshot tree, parents first |
| `virtualboxws.takeSnapshot(s, vm, name, description)` | `string` | take one and wait; its UUID |
| `virtualboxws.restoreSnapshot(s, vm, name)` | `null` | go back to one (machine off) |
| `virtualboxws.deleteSnapshot(s, vm, name)` | `null` | delete one |
| `virtualboxws.clone(s, vm, newName)` | `string` | a full, registered copy; its UUID |
| `virtualboxws.linkedClone(s, vm, snapshot, newName)` | `string` | a copy on difference disks from a snapshot; its UUID |
| `virtualboxws.importOva(s, path)` | `list of string` | import an `.ova` / `.ovf` on the host; the machines' UUIDs |
| `virtualboxws.importAs(s, path, name)` | `list of string` | the same, naming the first machine |
| `virtualboxws.exportOva(s, vm, path)` | `null` | export to an `.ova` / `.ovf` on the host |

## The guest

| Function | Returns | Does |
|---|---|---|
| `virtualboxws.guestProperty(s, vm, key)` | `string` | a guest property, `""` when unset |
| `virtualboxws.setGuestProperty(s, vm, key, value)` | `null` | set one |
| `virtualboxws.unsetGuestProperty(s, vm, key)` | `null` | remove one |
| `virtualboxws.guestIp(s, vm, nic)` | `string` | the IPv4 address of guest interface `nic` (from 0), `""` if none yet |
| `virtualboxws.waitForIp(s, vm, nic, timeoutMs)` | `string` | wait for that address |

## Types

### `Config`

| Field | Meaning |
|---|---|
| `url as string` | the service's URL |
| `tls as http.TlsOptions` | certificate checks for `https` |
| `allowPlainHttp as bool` | plain `http` to another machine allowed |
| `timeoutMs as int` | the deadline of an ordinary request |
| `longTimeoutMs as int` | the deadline of the long operations |
| `maxBytes as int` | the largest reply read |

### `Session`

| Field | Meaning |
|---|---|
| `config as Config` | how the service is reached |
| `vbox as string` | the session's `IVirtualBox` reference |
| `version as string` | VirtualBox's version, such as `7.1.4` |
| `major as int` | its major version |
| `minor as int` | its minor version |

### `Vm`

| Field | Meaning |
|---|---|
| `name as string` | the machine's name, `<inaccessible>` if VirtualBox cannot read it |
| `uuid as string` | its UUID |

### `VmInfo`

| Field | Meaning |
|---|---|
| `name as string` | the machine's name |
| `uuid as string` | its UUID |
| `osType as string` | its guest OS type id |
| `state as string` | `poweroff`, `running`, ... |
| `memoryMb as int` | memory in MiB |
| `cpus as int` | processors |
| `description as string` | its description |
| `configFile as string` | its `.vbox` file on the host |
| `sessionState as string` | `Unlocked`, `Locked`, `Spawning`, `Unlocking` |
| `currentSnapshot as string` | the current snapshot's name |
| `snapshotCount as int` | how many snapshots it has |

### `Snapshot`

| Field | Meaning |
|---|---|
| `name as string` | its name |
| `uuid as string` | its UUID |
| `description as string` | its description |
| `depth as int` | 0 for a first snapshot, 1 below it, ... |
| `current as bool` | the machine runs from it |

### `VirtualboxwsError`

Every error of kind `"virtualboxws"`.

| Field | Meaning |
|---|---|
| `kind as string` | always `"virtualboxws"` |
| `message as string` | `virtualboxws: ` and what went wrong |
| `reason as string` | `"fault"`, `"http"`, `"timeout"`, `"unreachable"`, `"reply"` (not the expected SOAP), `"operation"` (a long operation failed), `""` otherwise |
| `code as string` | the fault's or operation's code: `VBOX_E_*` / `E_*` / `0x...` / `INVALID_OBJECT`, `""` if none |
| `status as int` | the reply's HTTP status, 0 if there was none |
