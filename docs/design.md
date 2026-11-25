<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

`@deckyard/virtualboxws` drives Oracle™ VirtualBox™ 7 through its SOAP web
service, `vboxwebsrv`, for a host that can be reached over the network but
where running programs is not wanted: logon and logoff, machines, power,
snapshots, clones, OVA import and export, and guest properties. `call`
reaches any other method of the Main API.

Not in scope:

- **Running `VBoxManage`.** That is the separate `@deckyard/virtualbox` deck,
  which also covers remote hosts over `ssh`. Capabilities are per deck, so
  the two stay apart; they share function names and shapes by convention
  (state names as VBoxManage™ prints them), not by code.
- **Guest control.** Running programs in the guest and copying files are not
  offered here.
- **VirtualBox before 7.** Older majors are refused.
- **`jennifer-tiny`.** It has no network driver.

## Decisions

- **SOAP built by hand over `http` and `xml`.** The service is SOAP 1.1,
  document/literal, with `SOAPAction: ""`. The request element is
  `Iface_method` in VirtualBox's namespace, parameters are unqualified
  children named as in VirtualBox's interface definition (`_this` is the
  object), an array is repeated elements. The wire format follows the 7.0.6
  and 7.1.4 sources (the WSDL generator and the web service itself).
- **References are released.** `logon` returns a managed-object reference for
  `IVirtualBox`; every reference a function obtains is released when it is
  done, also on error, and lock sessions are taken per operation and
  unlocked afterwards. `releaseRef` and `logoff` are exported for callers
  using `call`.
- **Long operations.** A method that returns `IProgress` is polled one second
  at a time until it completes or its deadline passes, then cancelled; a
  failed operation reports its own error text and result code.
- **One version difference.** Only `IVirtualBox_createMachine` differs
  between 7.0 and 7.1 (7.1 adds a platform architecture); `clone` reads the
  platform from the source machine to fill it in.
- **`importAs` mirrors `VBoxManage import --vmname`.** It reads the
  appliance description, enables every entry, replaces the name and sets the
  final values.
- **Deadlines around the whole exchange.** Each request runs in a task
  bounded by `task.waitTimeout`; ordinary calls get `DEFAULT_TIMEOUT_MS`
  (60 s), long operations `DEFAULT_LONG_TIMEOUT_MS` (1 hour).
- **Topics layout.** `src/virtualboxws.j` includes core, machines, snapshots
  and guest, each with its overlay.

## Errors

- Every error of kind `"virtualboxws"` is a `VirtualboxwsError`: `reason`
  is `"fault"` (a SOAP fault), `"http"` (an HTTP error without a fault),
  `"timeout"` (no answer within the deadline, or a long operation not done
  by it), `"unreachable"` (no connection or no complete reply), `"reply"`
  (not the expected SOAP), `"operation"` (a long operation failed) or `""`
  (a check before the call); `code` is the fault's `VBOX_E_*` or COM `E_*`
  name, a `0x` code, or `INVALID_OBJECT` for a reference the service no
  longer knows; `status` is the HTTP status.
- `errorCode` returns the `code` field. Logon refusal, existence checks and
  the guest-property wait read fields, never the deck's own messages.
- A reply over `maxBytes` is kind `"limit"`; a cancelled task stays
  `"cancelled"`.
- A service that cannot be reached (refused, reset, unreachable, DNS, TLS,
  a close before any reply) is the `http` module's `net.NetError`, kind
  `"net"`, passed on unchanged so its `reason`, `sent` and `replied` stay
  readable. Other transport failures, such as a reply cut short, are a
  `VirtualboxwsError` with reason `"unreachable"`.

## Security and limits

- Plain `http` is accepted for this machine only (`127.0.0.1`, `localhost`,
  `[::1]`; `DEFAULT_URL` is `http://localhost:18083/`). Another host needs
  `https` (`withTls`) or an explicit `withPlainHttp`, since the logon
  password would otherwise cross the network in clear.
- Replies are capped at `DEFAULT_MAX_BYTES` (1 MiB, `withMaxBytes`).
- Parameters are encoded with `xml`; a control character XML cannot carry is
  refused before sending. References must have the service's
  `%016x-%016x` shape; arguments are limited in length.
- Text from the service in an error message is cut and cleaned of control
  and bidirectional characters.
- The service ends a session after its idle timeout (300 s by default on the
  server side).

## Testing and validation

- `src/virtualboxws_test.j` includes the four topic overlays (36 tests). A
  loopback fake built on `httpd` answers by method and object reference from
  short specs (values, faults, invalid-object faults, raw HTTP replies,
  delays) and records every request, so tests assert both what was sent and
  that every reference was released.
- No live VirtualBox was used; the wire format comes from the 7.0.6 and
  7.1.4 sources.

## Known limitations and open questions

- Check against a real `vboxwebsrv` before 1.0.
- The service is off by default and rarely deployed; most remote setups are
  served by `@deckyard/virtualbox` over `ssh`.
- Telling the task deadline from an `http` read timeout still relies on the
  runtime's message text, since only the former leaves the task running.

## Dependencies on the interpreter

- Floor `jennifer >=0.28.0` (the calls 0.29.0 removes are replaced by their 0.28.0 forms); the default binary (capability `net`). The
  tests use the UTF-8 codec of `encoding.decode` and `strings.replicate`,
  new in 0.27.0.
- The bundled `http` and `uri` modules, the `xml` library, tasks with
  `task.waitTimeout`, `task.cancel` and `task.discard`.
- Kind `"limit"` for reached caps (M28.54) and `"cancelled"` for a cancelled
  task; thrown structs classified by kind (the error-struct work of M28.51
  to M28.57); transport failures as `net.NetError` (M28.65).
