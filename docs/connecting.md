<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Connecting

## The web service

`vboxwebsrv` ships with VirtualBox but is off by default. On the host, as
the user whose machines it serves:

```sh
VBoxManage setproperty websrvauthlibrary default   # check users with PAM
vboxwebsrv --host 0.0.0.0 --port 18083 --timeout 300 --background
```

It listens on port 18083, plain http. For anything but this machine, give
it a certificate (`--ssl --keyfile ... --cacert ...`) or put a TLS proxy in
front: `logon` sends the password, and every request after it carries the
session's references.

## Endpoint and TLS

```jennifer
use fs;
import "http.j" as http;

def c as virtualboxws.Config init virtualboxws.endpoint("https://vmhost:18083/");
$c = virtualboxws.withTls($c, http.TlsOptions{caCert: fs.readBytes("/etc/vbox/ca.pem")});
```

`endpoint` refuses a URL with a login part, a query or a fragment, and
plain `http` to anything but `127.0.0.1`, `localhost` and `[::1]`.
`withPlainHttp` allows it, for a network you trust. `caCert` trusts a
private CA or the service's own self-signed certificate; `skipVerify` turns
the check off and lets anyone in the middle read the password.

## Sessions

`logon` returns a `Session`, `logoff` ends it. The service ends a session
nobody used for its `--timeout` (300 s by default); the next call then fails
with `errorCode` `INVALID_OBJECT`, and `logoff` on it is no error. Log on
again for long pauses.

Every object the deck obtains (a machine, a lock session, a console, a
progress object) is released before its function returns, also when it
fails, so a long-lived session does not pile up objects on the service.
References from `call` are yours to release with `releaseRef`; `logoff`
frees whatever is left.

## Deadlines

An ordinary request is abandoned after `DEFAULT_TIMEOUT_MS` (one minute);
the deadline covers connecting, sending and reading. A start, power-off,
snapshot, clone, import or export is followed through its `IProgress` for up
to `DEFAULT_LONG_TIMEOUT_MS` (one hour), asking the service to wait a second
at a time; past the deadline the operation is cancelled and the call fails.
A reply over `DEFAULT_MAX_BYTES` (1 MiB) is refused: parsing one costs the
interpreter several times its size in memory (about 40 MiB at the cap).
Raise it with `withMaxBytes` for a host with tens of thousands of machines.

```jennifer
def c as virtualboxws.Config init virtualboxws.withLongTimeout(
    virtualboxws.endpoint("https://vmhost:18083/"), 4 * 3600000);
```

## Other methods

`call` sends any method of the web service's WSDL. Arguments map each
parameter to its values (one for a plain parameter, any number for an
array), in the WSDL's order; `_this` is the object. The result maps each
reply element to its values.

```jennifer
use io;

def r as map of string to list of string init virtualboxws.call($s, "IVirtualBox_getHomeFolder",
    {"_this": [$s.vbox]});
io.printf("%s\n", $r["returnval"][0]);
```
