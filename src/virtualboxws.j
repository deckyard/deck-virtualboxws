# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0
# pragma-jennifer-capability: net

/**
 * Oracle VirtualBox 7 through its SOAP web service, `vboxwebsrv`: machines
 * and their details, power, snapshots, full and linked clones, OVA / OVF
 * import and export, and guest properties, on a host the program reaches
 * over HTTP(S) instead of running `VBoxManage` (the `@deckyard/virtualbox`
 * deck). Its functions are named and shaped like that deck's.
 *
 * A `Session` from `logon` holds the web session; `logoff` ends it and frees
 * everything it held. Every object reference a call obtains is released
 * before the call returns, also on error. Long operations (start, power off,
 * snapshots, clones, import, export) are waited for with a deadline and
 * cancelled when they pass it. Plain `http` is refused except on this
 * machine unless asked for: `logon` sends the password. Every failure is a
 * `VirtualboxwsError` (kind `"virtualboxws"`), with the `VBOX_E_*` code where
 * VirtualBox gives one, except a reply over `maxBytes` (kind `"limit"`), a
 * cancelled task, and a service that cannot be reached: the `net.NetError`
 * (kind `"net"`) of the `http` module.
 *
 * | topic | covers |
 * | --- | --- |
 * | `core` | `Config`, `Session`, logon and logoff, SOAP, errors, progress, `call` |
 * | `machines` | machines, their details, power |
 * | `snapshots` | snapshots, clones, appliances |
 * | `guest` | guest properties and the guest's IP |
 *
 * @module virtualboxws
 * @see https://www.virtualbox.org/sdkref/
 * @example
 *   def s as virtualboxws.Session init virtualboxws.logon(
 *       virtualboxws.endpoint("https://vmhost:18083/"), "admin", $password);
 *   virtualboxws.start($s, "web");
 *   io.printf("%s\n", virtualboxws.waitForIp($s, "web", 0, 120000));
 *   virtualboxws.logoff($s);
 */
use convert;
use io;
use lists;
use maps;
use regex;
use strings;
use task;
use time;
use xml;

import "http.j" as http;
import "uri.j" as uri;

include "topics/core.j";
include "topics/machines.j";
include "topics/snapshots.j";
include "topics/guest.j";
