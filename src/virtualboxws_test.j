# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * White-box tests: jennifer test src/virtualboxws_test.j
 *
 * No test needs VirtualBox. A fake web service on 127.0.0.1 (`startFake` in
 * the core overlay) answers each SOAP method from a script and records every
 * request; the replies follow the WSDL the VirtualBox 7.0.6 / 7.1.4 sources
 * generate (`websrv-wsdl.xsl`) and the faults `vboxweb.cpp` raises. The topic
 * overlays are fragments spliced in here, not standalone suites.
 */
use testing;
use httpd;
use encoding;

include "topics/core_test.j";
include "topics/machines_test.j";
include "topics/snapshots_test.j";
include "topics/guest_test.j";
