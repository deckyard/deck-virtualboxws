<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/virtualboxws

Oracle VirtualBox 7 from a Jennifer program over VirtualBox's SOAP web
service, `vboxwebsrv`: for a VirtualBox host the program reaches over the
network and cannot run programs on. Where the program can run `VBoxManage`
(locally or over `ssh`), the [`@deckyard/virtualbox`](https://github.com/deckyard/deck-virtualbox)
deck does more; the two decks name their functions and fields alike, so
code moves between them with few changes.

- **Machines**: the registered and the running machines, one machine's
  details, its state.
- **Power**: start (headless, with a window, separate), power off, ACPI
  shutdown, pause, resume, reset, save state.
- **Snapshots, clones, appliances**: take, list, restore, delete; full and
  linked clones; OVA / OVF import (renaming the machine) and export.
- **The guest**: guest properties and the IP address it reports.

`virtualboxws.call` reaches every other method of the web service.

## Conventions

Snippets assume this import, and add the `use` lines they need:

```jennifer
import "@deckyard/virtualboxws/" as virtualboxws;
```

The trailing slash resolves to the entry module. Every call takes the
`Session` that `logon` returns:

```jennifer
use io;
use os;

def s as virtualboxws.Session init virtualboxws.logon(
    virtualboxws.endpoint("https://vmhost:18083/"), "admin", os.getEnv("VBOX_PASSWORD"));
io.printf("VirtualBox %s\n", $s.version);
virtualboxws.logoff($s);
```

A machine is named by its name or its UUID. Paths (appliances) are paths on
the VirtualBox host. The deck needs the `net` capability.

## Errors

Every failure but a reached `maxBytes` (see below) is a `virtualboxws.VirtualboxwsError` (kind `"virtualboxws"`),
its message starting with `virtualboxws: `. Its `reason` says which case it
is, so no code needs to read the message:

- an argument the deck refuses before sending anything: an unusable URL,
  plain `http` to another machine without `withPlainHttp`, an empty name, a
  control character, a number out of range;
- the service cannot be reached (`reason` `"unreachable"`), answers past the
  deadline (`"timeout"`), an HTTP
  error (`"http"`, with `status`) or something that is not SOAP (`"reply"`);
- `logon` is refused, or VirtualBox is older than 7;
- VirtualBox refuses a call, or a long operation fails or passes its
  deadline (it is then cancelled). The message carries VirtualBox's text and
  its result code: `virtualboxws: findMachine web: Could not find a
  registered machine named 'web' (VBOX_E_OBJECT_NOT_FOUND)`.
  `reason` is `"fault"` for a refused call and `"operation"` for a failed
  long operation (`"timeout"` past its deadline), `code` holds the code
  (`virtualboxws.errorCode(e)` returns it too); `INVALID_OBJECT` means the
  service no longer knows the session (it ended an idle one).

A reply over `maxBytes` is the one exception: an `Error` of kind `"limit"`,
the kind every library uses for a reached cap, with the same `virtualboxws: `
message.

```jennifer
use io;

try {
    virtualboxws.start($s, "web");
} catch (e) {
    if ($e.kind == "virtualboxws" and $e.code == "VBOX_E_INVALID_OBJECT_STATE") {
        io.printf("web is already running\n");
    } else {
        io.printf("%s\n", $e.message);
    }
}
```
